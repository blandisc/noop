import XCTest
import BiometricStreams
@testable import StrandAnalytics

final class CircadianEngineTests: XCTestCase {

    /// Build a 24-point hourly profile from a known cosine: mesor + amp·cos(2π(h − acro)/24).
    private func profile(mesor: Double, amp: Double, acrophase: Double) -> [CircadianEngine.ActivityBin] {
        (0..<24).map { h in
            let v = mesor + amp * cos(2.0 * Double.pi * (Double(h) - acrophase) / 24.0)
            return CircadianEngine.ActivityBin(hour: Double(h), activity: v)
        }
    }

    // MARK: - Cosinor recovers a known acrophase + amplitude (pure-math determinism)

    func testCosinorRecoversInjectedParameters() {
        let fit = CircadianEngine.cosinor(profile(mesor: 50, amp: 30, acrophase: 15))!
        XCTAssertEqual(fit.mesor, 50, accuracy: 1e-6)
        XCTAssertEqual(fit.amplitude, 30, accuracy: 1e-6)
        XCTAssertEqual(fit.acrophaseHours, 15, accuracy: 1e-6)
    }

    func testCosinorAcrophaseWrapsIntoDay() {
        let fit = CircadianEngine.cosinor(profile(mesor: 10, amp: 5, acrophase: 23))!
        XCTAssertEqual(fit.acrophaseHours, 23, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(fit.acrophaseHours, 0)
        XCTAssertLessThan(fit.acrophaseHours, 24)
    }

    func testCosinorRejectsTooFewPoints() {
        XCTAssertNil(CircadianEngine.cosinor([.init(hour: 1, activity: 1), .init(hour: 2, activity: 2)]))
    }

    // MARK: - Phase estimate confidence

    func testStrongRhythmEnoughDaysIsSolid() {
        let bins = profile(mesor: 50, amp: 30, acrophase: 15)
        let est = CircadianEngine.estimatePhase(bins: bins, daysObserved: 20, habitualWakeHour: 7)!
        XCTAssertEqual(est.confidence, .solid)
        // Acrophase 15:00 → derived temp-min ≈ 15 − 9.5 = 05:30 (population offset, Mitchell 2017).
        XCTAssertEqual(est.tempMinHour, 5.5, accuracy: 1e-6)
        // Ideal temp-min = wake 7 − 2.5 = 04:30; estimated 05:30 is +60 min raw, −37 baseline ≈ +23 → owl.
        XCTAssertEqual(est.offsetVsScheduleMinutes, 23, accuracy: 0.1)
        XCTAssertTrue(est.note.contains("night-owl"))
    }

    // MARK: - Baseline-bias centering (FER-704 finding → FER-712)

    func testBaselineOffsetIsAboutThirtySevenMinutes() {
        // (14.617 − 9.5) − (7 − 2.5) = 0.617 h ≈ 37 min, derived purely from the population anchors.
        XCTAssertEqual(CircadianEngine.baselineOffsetMinutes, 37, accuracy: 0.1)
    }

    func testAveragePhenotypeReadsZeroOffset() {
        // An average phenotype (activity acrophase 14:37, wake 07:00) must read ≈ 0 (no lean), not a
        // false night-owl — the whole point of centering the baseline bias.
        let bins = profile(mesor: 50, amp: 30, acrophase: 14.617)
        let est = CircadianEngine.estimatePhase(bins: bins, daysObserved: 20, habitualWakeHour: 7)!
        XCTAssertEqual(est.offsetVsScheduleMinutes, 0, accuracy: 0.5)
        XCTAssertTrue(est.note.contains("well-aligned"))
    }

    func testSuggestedBedtimeSitsBeforeIdealWake() {
        // tempMin 05:30 → ideal wake 05:30+2.5 = 08:00 → bedtime 08:00 − 8 h = 00:00.
        XCTAssertEqual(CircadianEngine.suggestedBedtime(tempMinHour: 5.5), 0.0, accuracy: 1e-6)
        // A lark (earlier tempMin) gets an earlier suggested bedtime.
        let lark = CircadianEngine.suggestedBedtime(tempMinHour: 3.0)   // wake 05:30 → bed 21:30
        XCTAssertEqual(lark, 21.5, accuracy: 1e-6)
    }

    // MARK: - Hourly activity-profile builder

    /// Synthesize a day whose per-hour motion intensity follows mesor + amp·cos(2π(h−acro)/24): two samples
    /// per local hour whose x-delta equals the target intensity (so hourMotionIntensity == target).
    private func syntheticDay(dayIndex: Int, mesor: Double, amp: Double,
                              acrophase: Double, tzOffsetSeconds: Int = 0) -> CircadianEngine.DayGravity {
        var samples: [GravitySample] = []
        let base = dayIndex * 86_400 - tzOffsetSeconds   // so local hour == h regardless of tz
        for h in 0..<24 {
            let target = mesor + amp * cos(2.0 * Double.pi * (Double(h) - acrophase) / 24.0)
            let t = base + h * 3600
            samples.append(GravitySample(ts: t, x: 0, y: 0, z: 0))
            samples.append(GravitySample(ts: t + 1, x: target, y: 0, z: 0))
        }
        return CircadianEngine.DayGravity(samples: samples, tzOffsetSeconds: tzOffsetSeconds)
    }

    func testActivityBinsRecoverInjectedAcrophase() {
        let days = (0..<14).map { syntheticDay(dayIndex: $0, mesor: 50, amp: 30, acrophase: 15) }
        let (bins, daysObserved) = CircadianEngine.activityBins(days)
        XCTAssertEqual(daysObserved, 14)
        XCTAssertEqual(bins.count, 24)
        let est = CircadianEngine.estimatePhase(bins: bins, daysObserved: daysObserved, habitualWakeHour: 7)!
        XCTAssertEqual(est.acrophaseHours, 15, accuracy: 0.5)
    }

    func testActivityBinsUseLocalHour() {
        // Same UTC ts, two different tz offsets → the sample lands in different local-hour bins.
        let s = [GravitySample(ts: 3 * 3600, x: 0, y: 0, z: 0),
                 GravitySample(ts: 3 * 3600 + 1, x: 10, y: 0, z: 0)]
        let utc = CircadianEngine.activityBins([.init(samples: s, tzOffsetSeconds: 0)]).bins
        let plus1 = CircadianEngine.activityBins([.init(samples: s, tzOffsetSeconds: 3600)]).bins
        XCTAssertEqual(utc.first?.hour, 3)
        XCTAssertEqual(plus1.first?.hour, 4)
    }

    // MARK: - FER-868: hourlyMotionProfile ⟺ activityBins equivalence (the persistable split)

    /// The engine now persists per-day hourly profiles (`act_hNN`) and pools them later; the pooled
    /// result must be EXACTLY what the monolithic gravity path produces. Fixtures cover empty hours,
    /// an hour with samples but zero motion, and a tz shift.
    func testActivityBinsEquivalenceViaHourlyProfiles() {
        var days: [CircadianEngine.DayGravity] = (0..<10).map {
            syntheticDay(dayIndex: $0, mesor: 40, amp: 25, acrophase: 14, tzOffsetSeconds: -6 * 3600)
        }
        // A sparse day: only hours 2 and 9 observed; hour 2 has samples but ZERO motion.
        let sparse = [GravitySample(ts: 100 * 86_400 + 2 * 3600, x: 1, y: 1, z: 1),
                      GravitySample(ts: 100 * 86_400 + 2 * 3600 + 5, x: 1, y: 1, z: 1),
                      GravitySample(ts: 100 * 86_400 + 9 * 3600, x: 0, y: 0, z: 0),
                      GravitySample(ts: 100 * 86_400 + 9 * 3600 + 5, x: 7, y: 0, z: 0)]
        days.append(.init(samples: sparse, tzOffsetSeconds: 0))
        // A day whose samples straddle a positive-tz midnight (local hour wraps).
        let wrap = [GravitySample(ts: 200 * 86_400 - 1800, x: 0, y: 0, z: 0),
                    GravitySample(ts: 200 * 86_400 - 1790, x: 3, y: 0, z: 0)]
        days.append(.init(samples: wrap, tzOffsetSeconds: 3600))
        days.append(.init(samples: [], tzOffsetSeconds: 0))   // fully-empty day

        let direct = CircadianEngine.activityBins(days)
        let viaProfiles = CircadianEngine.activityBins(
            hourlyProfiles: days.map { CircadianEngine.hourlyMotionProfile($0.samples, tzOffsetSeconds: $0.tzOffsetSeconds) })
        XCTAssertEqual(direct.bins, viaProfiles.bins)
        XCTAssertEqual(direct.daysObserved, viaProfiles.daysObserved)
    }

    func testHourlyMotionProfileSemantics() {
        // nil = hour unobserved; present 0.0 = observed but still (single sample → zero delta).
        let s = [GravitySample(ts: 5 * 3600 + 10, x: 1, y: 0, z: 0),          // hour 5: one sample → 0.0
                 GravitySample(ts: 8 * 3600, x: 0, y: 0, z: 0),
                 GravitySample(ts: 8 * 3600 + 1, x: 4, y: 3, z: 0)]           // hour 8: delta L2 = 5
        let p = CircadianEngine.hourlyMotionProfile(s, tzOffsetSeconds: 0)
        XCTAssertEqual(p.count, 24)
        XCTAssertNil(p[0])
        XCTAssertEqual(p[5], 0.0)
        XCTAssertEqual(p[8]!, 5.0, accuracy: 1e-9)
        // tz shift relocates the local hour.
        let shifted = CircadianEngine.hourlyMotionProfile(s, tzOffsetSeconds: 3600)
        XCTAssertNil(shifted[8])
        XCTAssertEqual(shifted[9]!, 5.0, accuracy: 1e-9)
    }

    func testActivityBinsEmptyInputIsNoFit() {
        let (bins, days) = CircadianEngine.activityBins([])
        XCTAssertTrue(bins.isEmpty)
        XCTAssertEqual(days, 0)
        XCTAssertNil(CircadianEngine.estimatePhase(bins: bins, daysObserved: days, habitualWakeHour: 7))
    }

    func testThinDataIsWideOrUnreadable() {
        let bins = profile(mesor: 50, amp: 30, acrophase: 15)
        let est = CircadianEngine.estimatePhase(bins: bins, daysObserved: 4, habitualWakeHour: 7)!
        XCTAssertEqual(est.confidence, .unreadable)
        XCTAssertTrue(est.note.lowercased().contains("hard to read"))
    }

    func testArrhythmicProfileIsUnreadable() {
        // Near-flat activity (amplitude ≈ 0) → arrhythmic → unreadable even with many days.
        let bins = profile(mesor: 50, amp: 0.5, acrophase: 15)
        let est = CircadianEngine.estimatePhase(bins: bins, daysObserved: 30, habitualWakeHour: 7)!
        XCTAssertEqual(est.confidence, .unreadable)
    }

    func testObservedTempMinOverridesDerived() {
        let bins = profile(mesor: 50, amp: 30, acrophase: 15)
        let est = CircadianEngine.estimatePhase(
            bins: bins, daysObserved: 20, habitualWakeHour: 7, observedTempMinHour: 4.5)!
        XCTAssertEqual(est.tempMinHour, 4.5, accuracy: 1e-9)
    }

    // MARK: - Jet-lag / shift planner: direction + light rule + no supplements

    func testEastwardAdvancePlanUsesMorningLight() {
        // +3 h required = advance the clock earlier (eastward).
        let plan = CircadianEngine.planShift(shiftHours: 3, currentSleepHour: 23, currentWakeHour: 7)
        XCTAssertEqual(plan.direction, .advance)
        XCTAssertEqual(plan.estimatedDays, 3)            // 3 h at ≤1 h/day
        XCTAssertEqual(plan.days.count, 3)
        // Final day: window pulled 3 h earlier → sleep 20:00, wake 04:00.
        let last = plan.days.last!
        XCTAssertEqual(last.targetSleepHour, 20, accuracy: 1e-9)
        XCTAssertEqual(last.targetWakeHour, 4, accuracy: 1e-9)
        // Morning light begins at the new wake.
        XCTAssertEqual(last.brightLightStartHour, 4, accuracy: 1e-9)
        XCTAssertTrue(last.guidance.contains("bright light early"))
    }

    func testWestwardDelayPlanUsesEveningLight() {
        // −2 h required = delay the clock later (westward).
        let plan = CircadianEngine.planShift(shiftHours: -2, currentSleepHour: 23, currentWakeHour: 7)
        XCTAssertEqual(plan.direction, .delay)
        XCTAssertEqual(plan.estimatedDays, 2)
        let last = plan.days.last!
        // Window pushed 2 h later → sleep 01:00, wake 09:00.
        XCTAssertEqual(last.targetSleepHour, 1, accuracy: 1e-9)
        XCTAssertEqual(last.targetWakeHour, 9, accuracy: 1e-9)
        XCTAssertTrue(last.guidance.contains("bright light in the evening"))
    }

    func testNoShiftNeededReturnsNonePlan() {
        let plan = CircadianEngine.planShift(shiftHours: 0.2, currentSleepHour: 23, currentWakeHour: 7)
        XCTAssertEqual(plan.direction, .none)
        XCTAssertTrue(plan.days.isEmpty)
    }

    func testPlanNeverMentionsSupplements() {
        let banned = ["melatonin", "supplement", "pill", "drug", "caffeine pill", "medication"]
        for shift in [3.0, -3.0, 6.0, -1.0] {
            let plan = CircadianEngine.planShift(shiftHours: shift, currentSleepHour: 23, currentWakeHour: 7)
            var text = plan.note.lowercased()
            for d in plan.days { text += " " + d.guidance.lowercased() }
            for b in banned { XCTAssertFalse(text.contains(b), "plan mentioned banned \(b)") }
        }
    }

    func testSteppedAtOneHourPerDay() {
        // 6 h shift → 6 stepped days.
        let plan = CircadianEngine.planShift(shiftHours: 6, currentSleepHour: 23, currentWakeHour: 7)
        XCTAssertEqual(plan.estimatedDays, 6)
        XCTAssertEqual(plan.days.count, 6)
    }

    // MARK: - Clock formatting parity helper

    func testClockFormatting() {
        XCTAssertEqual(CircadianEngine.clock(20.0), "20:00")
        XCTAssertEqual(CircadianEngine.clock(23.5), "23:30")
        XCTAssertEqual(CircadianEngine.clock(-1.0), "23:00")   // wraps
        XCTAssertEqual(CircadianEngine.clock(7.25), "07:15")
    }
}
