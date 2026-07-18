import XCTest
@testable import StrandAnalytics
import BiometricStreams
import CenitStore

final class AnalyticsEngineTests: XCTestCase {

    func testVersion() {
        XCTAssertEqual(StrandAnalytics.version, "0.1.0")
    }

    func testDayStringUTC() {
        // 2021-01-01 00:00:00 UTC == 1609459200.
        XCTAssertEqual(AnalyticsEngine.dayString(1_609_459_200), "2021-01-01")
    }

    /// Build a still, low-HR night ending on a known UTC day.
    private func night(endDay: String, hours: Int) -> (start: Int, end: Int,
                                                       hr: [HRSample], rr: [RRInterval],
                                                       gravity: [GravitySample]) {
        // Pick an end timestamp on `endDay` at 06:00 UTC.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd"
        let dayMidnight = Int(fmt.date(from: endDay)!.timeIntervalSince1970)
        let end = dayMidnight + 6 * 3600
        let start = end - hours * 3600

        var hr: [HRSample] = []
        var rr: [RRInterval] = []
        var grav: [GravitySample] = []
        for t in start..<end {
            hr.append(HRSample(ts: t, bpm: 50))
            grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still
        }
        // RR every 2 s at ~1200 ms with tiny oscillation (avoids ectopic rejection).
        var toggle = false
        for t in stride(from: start, to: end, by: 2) {
            rr.append(RRInterval(ts: t, rrMs: toggle ? 1205 : 1195))
            toggle.toggle()
        }
        return (start, end, hr, rr, grav)
    }

    func testAnalyzeDayProducesSleepMetric() {
        let day = "2021-06-15"
        let n = night(endDay: day, hours: 7)
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity, profile: profile)

        XCTAssertEqual(result.daily.day, day)
        XCTAssertEqual(result.sleepSessions.count, 1)
        XCTAssertNotNil(result.daily.totalSleepMin)
        XCTAssertGreaterThan(result.daily.totalSleepMin!, 0)
        XCTAssertEqual(result.daily.restingHr, 50)
        XCTAssertNotNil(result.daily.avgHrv)
        XCTAssertEqual(result.daily.avgHrv!, 10.0, accuracy: 1.0)  // RMSSD of ±5 ms oscillation
        // CachedSleepSession rows mirror the detected sessions and carry stage JSON.
        XCTAssertEqual(result.cachedSleep.count, 1)
        XCTAssertNotNil(result.cachedSleep[0].stagesJSON)
        XCTAssertEqual(result.cachedSleep[0].restingHr, 50)
    }

    func testAnalyzeDayColdStartRecoveryNil() {
        // No baselines supplied → recovery is nil (cold-start gate).
        let day = "2021-06-16"
        let n = night(endDay: day, hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(age: 30))
        XCTAssertNil(result.daily.recovery)
        XCTAssertNil(result.recovery)
    }

    func testAnalyzeDayWithBaselinesProducesRecovery() {
        let day = "2021-06-17"
        let n = night(endDay: day, hours: 7)
        // Trusted HRV + RHR baselines around the values this night will produce.
        let hrvBase = Baselines.foldHistory(Array(repeating: 10.0, count: 14), cfg: Baselines.hrvCfg)
        let rhrBase = Baselines.foldHistory(Array(repeating: 50.0, count: 14), cfg: Baselines.restingHRCfg)
        XCTAssertTrue(hrvBase.usable)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(age: 30),
            baselines: AnalyticsEngine.ProfileBaselines(hrv: hrvBase, restingHR: rhrBase))
        XCTAssertNotNil(result.recovery)
        XCTAssertEqual(result.daily.recovery, result.recovery)
        XCTAssertGreaterThanOrEqual(result.recovery!, 0)
        XCTAssertLessThanOrEqual(result.recovery!, 100)
    }

    func testAnalyzeDayNoMatchingNight() {
        // A night ending on a different day → no sleep attributed to `day`.
        let n = night(endDay: "2021-06-18", hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: "2021-06-19", hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(age: 30))
        XCTAssertEqual(result.sleepSessions.count, 0)
        XCTAssertNil(result.daily.totalSleepMin)
        XCTAssertEqual(result.daily.exerciseCount, 0)
    }

    // MARK: - Frequency-domain HRV (FER-702, additive)

    func testAnalyzeDayComputesSpectralBands() {
        // A full 7 h night (span ≫ 250 s) yields a non-nil Bands with HF present, LF present, and the
        // superset invariant totalPower >= hf. The RR modulates at 0.25 Hz (HF band) by construction.
        let day = "2021-06-15"
        let n = night(endDay: day, hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male"))
        let bands = result.spectralBands
        XCTAssertNotNil(bands, "a full night must produce a spectrum")
        XCTAssertGreaterThan(bands!.hf, 0)
        XCTAssertNotNil(bands!.lf, "span ≫ 250 s → LF present")
        XCTAssertGreaterThanOrEqual(bands!.totalPower, bands!.hf)
    }

    func testAnalyzeDayNoNightNoSpectralBands() {
        // No matched sleep session → no session R-R → nil spectrum (never fabricated).
        let n = night(endDay: "2021-06-18", hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: "2021-06-19", hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(age: 30))
        XCTAssertNil(result.spectralBands)
    }

    func testSpectralComputeIsAdditiveToAvgHrv() {
        // The spectral pass reads the SAME session R-R as avgHrv but must not perturb it: avgHrv is
        // still the RMSSD of the ±5 ms oscillation, unchanged from testAnalyzeDayProducesSleepMetric.
        let day = "2021-06-15"
        let n = night(endDay: day, hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
            profile: UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male"))
        XCTAssertNotNil(result.daily.avgHrv)
        XCTAssertEqual(result.daily.avgHrv!, 10.0, accuracy: 1.0)
        XCTAssertNotNil(result.spectralBands)  // both derived from the same night, coherently
    }

    func testAnalyzeDayDailyMetricRoundTripsThroughCodable() throws {
        // The produced DailyMetric must encode/decode (it's the CenitStore cache shape).
        let day = "2021-06-20"
        let n = night(endDay: day, hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity, profile: UserProfile(age: 30))
        let data = try JSONEncoder().encode(result.daily)
        let decoded = try JSONDecoder().decode(DailyMetric.self, from: data)
        XCTAssertEqual(decoded, result.daily)
    }

    func testAnalyzeDayPopulatesParityFields() throws {
        // The Android-parity computations must land on the DailyMetric when the streams are
        // supplied: RSA respiration from RR, daily steps from the cumulative @57 counter,
        // whole-day HR-only calories, and the wear-gated skin-temp deviation (usable baseline).
        let day = "2021-06-21"
        let n = night(endDay: day, hours: 7)
        // RSA-modulated RR replacing the square-wave fixture: mean 1200 ms (HR 50), ±40 ms at
        // 0.25 Hz — a planted 15 breaths/min the estimator must recover.
        var rr: [RRInterval] = []
        var tSec = 0.0
        while tSec < Double(n.end - n.start) {
            let rrMs = 1200.0 + 40.0 * sin(2.0 * Double.pi * 0.25 * tSec)
            tSec += rrMs / 1000.0
            rr.append(RRInterval(ts: n.start + Int(tSec), rrMs: Int(rrMs)))
        }
        // Worn in-bed skin temp at 34 °C across the whole night (raw = °C × 128, Swift scale).
        let skin = (0..<(n.end - n.start)).map { SkinTempSample(ts: n.start + $0, raw: 4352) }
        // Step counter: morning movement after wake, inside the same UTC day → 250 steps.
        let steps = [StepSample(ts: n.end + 600, counter: 100),
                     StepSample(ts: n.end + 1200, counter: 350)]
        let skinBase = Baselines.foldHistory([33.5, 33.4, 33.6, 33.5],
                                             cfg: Baselines.metricCfg["skin_temp"]!)
        XCTAssertTrue(skinBase.usable)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: rr, gravity: n.gravity, steps: steps, skinTemp: skin,
            profile: UserProfile(age: 30),
            baselines: AnalyticsEngine.ProfileBaselines(skinTemp: skinBase))
        XCTAssertEqual(result.sleepSessions.count, 1)
        XCTAssertEqual(result.daily.steps, 250)
        XCTAssertGreaterThan(try XCTUnwrap(result.daily.activeKcalEst), 0)
        // RSA respiration recovered from the in-bed RR (≈15 bpm planted, ±3 tolerance).
        XCTAssertEqual(try XCTUnwrap(result.daily.respRateBpm), 15.0, accuracy: 3.0)
        // Wear-gated nightly mean (34 °C plateau) + a positive deviation vs the ~33.5 °C baseline.
        XCTAssertEqual(try XCTUnwrap(result.nightlySkinTempC), 34.0, accuracy: 1e-9)
        XCTAssertGreaterThan(try XCTUnwrap(result.daily.skinTempDevC), 0.2)
    }

    func testAnalyzeDayWithoutNewStreamsLeavesParityFieldsNil() {
        // Pure-function contract: callers that don't supply steps/skinTemp (all pre-existing
        // call sites and tests) get nil steps + nil skinTempDevC — never a fabricated value.
        let day = "2021-06-22"
        let n = night(endDay: day, hours: 7)
        let result = AnalyticsEngine.analyzeDay(
            day: day, hr: n.hr, rr: n.rr, gravity: n.gravity, profile: UserProfile(age: 30))
        XCTAssertNil(result.daily.steps)
        XCTAssertNil(result.daily.skinTempDevC)
        XCTAssertNil(result.nightlySkinTempC)
    }

    func testAnalyzeDayIsDeterministicAcrossConcurrentRecompute() {
        // FER-177: the periodic engine snapshots its inputs up front and skips re-running when nothing
        // changed, so a refresh landing mid-pass can't drift a day's scores. The analytics core is what
        // underwrites that — `analyzeDay` is a PURE function with no shared mutable state, so the SAME
        // inputs always yield the SAME scores. Proven here by scoring one night, scoring an UNRELATED
        // night with a DIFFERENT profile/baseline in between (modelling a concurrent recompute), then
        // re-scoring the first night and asserting every persisted field is bit-for-bit identical.
        let day = "2021-07-02"
        let n = night(endDay: day, hours: 7)
        let hrvBase = Baselines.foldHistory(Array(repeating: 10.0, count: 14), cfg: Baselines.hrvCfg)
        let rhrBase = Baselines.foldHistory(Array(repeating: 50.0, count: 14), cfg: Baselines.restingHRCfg)
        let baselines = AnalyticsEngine.ProfileBaselines(hrv: hrvBase, restingHR: rhrBase)
        let profile = UserProfile(age: 30)

        let first = AnalyticsEngine.analyzeDay(day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
                                               profile: profile, baselines: baselines)
        XCTAssertNotNil(first.recovery)   // a meaningful (non-cold-start) score, so the check has teeth

        // Interleave an unrelated computation with different inputs — a stand-in for the concurrent
        // refresh the engine guards against. If any global state leaked, it would taint the re-run below.
        let other = night(endDay: "2021-07-03", hours: 8)
        _ = AnalyticsEngine.analyzeDay(
            day: "2021-07-03", hr: other.hr, rr: other.rr, gravity: other.gravity,
            profile: UserProfile(age: 45),
            baselines: AnalyticsEngine.ProfileBaselines(
                hrv: Baselines.foldHistory(Array(repeating: 80.0, count: 14), cfg: Baselines.hrvCfg),
                restingHR: Baselines.foldHistory(Array(repeating: 70.0, count: 14), cfg: Baselines.restingHRCfg)))

        let again = AnalyticsEngine.analyzeDay(day: day, hr: n.hr, rr: n.rr, gravity: n.gravity,
                                               profile: profile, baselines: baselines)

        XCTAssertEqual(first.daily, again.daily)   // DailyMetric is Equatable — every persisted field
        XCTAssertEqual(first.recovery, again.recovery)
        XCTAssertEqual(first.strain, again.strain)
        XCTAssertEqual(first.sleepSessions.count, again.sleepSessions.count)
        XCTAssertEqual(first.workouts.count, again.workouts.count)
    }

    // MARK: - Local civil-day attribution (FER-226)

    func testDayRangeMatchesDayStringAtBoundaries() {
        let day = "2024-06-15"
        for tz in [0, -21600, 19800] {
            guard let range = AnalyticsEngine.dayRange(day, tzOffsetSeconds: tz) else {
                XCTFail("dayRange should parse \(day) for tz=\(tz)")
                continue
            }
            let dayStart = range.lowerBound
            let timestamps = [
                dayStart - 1,
                dayStart,
                dayStart + 43_200,
                dayStart + 86_399,
                dayStart + 86_400,
            ]
            for ts in timestamps {
                let numeric = range.contains(ts)
                let stringMatch = AnalyticsEngine.dayString(ts, tzOffsetSeconds: tz) == day
                XCTAssertEqual(numeric, stringMatch,
                               "mismatch at ts=\(ts) tz=\(tz): dayRange.contains=\(numeric) dayString==day=\(stringMatch)")
            }
        }
    }

    func testDayStringLocalNegativeOffsetCrossesMidnight() {
        // 2026-06-18 01:30:00 UTC is still 2026-06-17 19:30 in México (UTC−6) — the exact incident.
        let ts = utcTimestamp("2026-06-18 01:30:00")
        XCTAssertEqual(AnalyticsEngine.dayString(ts), "2026-06-18")                          // default = UTC
        XCTAssertEqual(AnalyticsEngine.dayString(ts, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        // A positive offset (e.g. UTC+10) rolls an early-UTC instant forward into the next civil day.
        XCTAssertEqual(AnalyticsEngine.dayString(utcTimestamp("2026-06-17 16:00:00"),
                                                 tzOffsetSeconds: 10 * 3600), "2026-06-18")
    }

    func testLocalMidnightNegativeOffset() {
        // Local midnight of 2026-06-17 in México (UTC−6) is 2026-06-17 06:00:00 UTC.
        let ts = utcTimestamp("2026-06-18 01:30:00")   // evening of the 17th, local MX
        let mid = AnalyticsEngine.localMidnight(ts, tzOffsetSeconds: -6 * 3600)
        XCTAssertEqual(mid, utcTimestamp("2026-06-17 06:00:00"))
        // It floors to local midnight: the instant maps to the 17th, one second earlier to the 16th.
        XCTAssertEqual(AnalyticsEngine.dayString(mid, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        XCTAssertEqual(AnalyticsEngine.dayString(mid - 1, tzOffsetSeconds: -6 * 3600), "2026-06-16")
        // Default offset 0 floors to UTC midnight — unchanged behaviour for pure callers.
        XCTAssertEqual(AnalyticsEngine.localMidnight(ts), utcTimestamp("2026-06-18 00:00:00"))
    }

    func testAnalyzeDayAttributesEveningStepsToLocalDay() {
        // Two cumulative step samples this evening: 2026-06-17 ~19:30 local MX = 2026-06-18 ~01:30 UTC.
        let t0 = utcTimestamp("2026-06-18 01:30:00")
        let steps = [StepSample(ts: t0, counter: 100), StepSample(ts: t0 + 600, counter: 350)]
        let profile = UserProfile(age: 30)
        // With the device on MX (−6h) the 250 steps count for the LOCAL day 2026-06-17…
        let local = AnalyticsEngine.analyzeDay(day: "2026-06-17", steps: steps,
                                               profile: profile, tzOffsetSeconds: -6 * 3600)
        XCTAssertEqual(local.daily.steps, 250)
        // …whereas the old UTC dating (default offset 0) drops them from 2026-06-17 — those samples
        // fall on 2026-06-18 in UTC, so the day's total is empty. That mis-attribution is the bug.
        let utc = AnalyticsEngine.analyzeDay(day: "2026-06-17", steps: steps, profile: profile)
        XCTAssertNil(utc.daily.steps)
    }

    func testInProgressDayStrainExcludesYesterday() {
        // The in-progress day (offset 0) reads a ~42h night window that, just after midnight, is ALL of
        // yesterday. The Esfuerzo del día must NOT surface yesterday's strain as today's (FER-341): with
        // `strainCivilDayOnly`, strain counts only the device's local civil `day`.
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")
        let tz = -6 * 3600
        // Yesterday's workout: 12 min @ 175 bpm ending ~23:00 local MX (2026-06-19) = ~05:00 UTC.
        let yStart = utcTimestamp("2026-06-20 04:48:00")            // 2026-06-19 22:48 local MX
        var hr = (0..<720).map { HRSample(ts: yStart + $0, bpm: 175) }
        // Today so far: 2 min @ 60 bpm at 00:10 local MX (2026-06-20) = 06:10 UTC.
        let tStart = utcTimestamp("2026-06-20 06:10:00")            // 2026-06-20 00:10 local MX
        hr += (0..<120).map { HRSample(ts: tStart + $0, bpm: 60) }
        // The two blocks straddle the local civil-day boundary.
        XCTAssertEqual(AnalyticsEngine.dayString(yStart, tzOffsetSeconds: tz), "2026-06-19")
        XCTAssertEqual(AnalyticsEngine.dayString(tStart, tzOffsetSeconds: tz), "2026-06-20")

        // Full window (a past complete day, default): strain scores the workout → non-nil.
        let full = AnalyticsEngine.analyzeDay(day: "2026-06-20", hr: hr, profile: profile,
                                              tzOffsetSeconds: tz)
        XCTAssertNotNil(full.strain, "the full ~42h window includes yesterday's workout")
        // In-progress day: strain restricted to today's own civil day — only 2 min of resting HR, too
        // little to score → nil. So `repo.today?.strain` is nil and the tile reads «—», not yesterday's.
        let inProgress = AnalyticsEngine.analyzeDay(day: "2026-06-20", hr: hr, profile: profile,
                                                    tzOffsetSeconds: tz, strainCivilDayOnly: true)
        XCTAssertNil(inProgress.strain, "the in-progress day must not surface yesterday's strain")
    }

    func testInProgressDayStrainCountsTodaysOwnActivity() {
        // The civil-day flag doesn't blanket-zero today: a real workout TODAY still scores.
        let profile = UserProfile(weightKg: 75, heightCm: 178, age: 30, sex: "male")
        let tz = -6 * 3600
        let tStart = utcTimestamp("2026-06-20 18:00:00")            // 2026-06-20 12:00 local MX
        let hr = (0..<900).map { HRSample(ts: tStart + $0, bpm: 170) }   // 15-min hard block, all today
        XCTAssertEqual(AnalyticsEngine.dayString(tStart, tzOffsetSeconds: tz), "2026-06-20")
        let inProgress = AnalyticsEngine.analyzeDay(day: "2026-06-20", hr: hr, profile: profile,
                                                    tzOffsetSeconds: tz, strainCivilDayOnly: true)
        XCTAssertNotNil(inProgress.strain, "today's own activity still scores under the civil-day flag")
    }

    func testFutureLocalDaysToPruneSelectsOnlyFutureUnwrittenRows() {
        let today = "2026-06-17"
        let written: Set<String> = ["2026-06-15", "2026-06-16", "2026-06-17"]   // re-grouped local days
        // (a) The future-in-local phantom row (the 18th) IS selected for prune…
        let stored = ["2026-06-15", "2026-06-16", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: stored, today: today, written: written),
                       ["2026-06-18"])
        // (b) …a today/past row is never selected — even a PAST day NOT in `written` (raw pruned, not
        // recomputable) is kept: no data loss. Only the future row is pruned.
        let withUnrecomputedPast = ["2026-04-01", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: withUnrecomputedPast, today: today,
                                                              written: written), ["2026-06-18"])
        // (c) A future row that WAS written this run is not pruned (defensive belt-and-suspenders).
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: ["2026-06-18"], today: today,
                                                              written: ["2026-06-18"]), [])
    }

    /// Unix-seconds for a `yyyy-MM-dd HH:mm:ss` wall-clock string interpreted in UTC.
    private func utcTimestamp(_ s: String) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return Int(f.date(from: s)!.timeIntervalSince1970)
    }
}
