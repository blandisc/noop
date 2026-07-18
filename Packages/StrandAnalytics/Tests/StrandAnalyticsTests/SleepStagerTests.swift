import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class SleepStagerTests: XCTestCase {

    // MARK: - Cole–Kripke

    func testColeKripkeAllStillIsSleep() {
        // Zero activity → SI = 0 < 1 for every epoch → all sleep.
        let flags = SleepStager.coleKripke([Double](repeating: 0, count: 20))
        XCTAssertTrue(flags.allSatisfy { $0 })
    }

    func testColeKripkeHighActivityIsWake() {
        // A large clipped count at the center weight (230) → SI ≥ 1 → wake.
        // rescaled count of 300 (the clip) at A0: 0.001 * 230 * 300 = 69 ≥ 1.
        var counts = [Double](repeating: 0, count: 9)
        counts[4] = 300
        let flags = SleepStager.coleKripke(counts)
        XCTAssertFalse(flags[4])  // center epoch is wake
    }

    func testRescaleCountsDivideAndClip() {
        XCTAssertEqual(SleepStager.rescaleCounts([200]), [2.0])
        XCTAssertEqual(SleepStager.rescaleCounts([50000]), [300.0])  // clipped
    }

    // MARK: - Gravity stillness spine

    /// Build a still gravity stream (constant orientation) at 1 Hz.
    private func stillGravity(start: Int, durationS: Int) -> [GravitySample] {
        (0..<durationS).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1.0) }
    }

    /// Build an active gravity stream (oscillating) at 1 Hz.
    private func activeGravity(start: Int, durationS: Int) -> [GravitySample] {
        (0..<durationS).map { i -> GravitySample in
            let phase = Double(i % 2) * 0.5  // 0.5 g jumps per sample → clearly moving
            return GravitySample(ts: start + i, x: phase, y: 0, z: 1.0)
        }
    }

    private func hrStream(start: Int, durationS: Int, bpm: Int) -> [HRSample] {
        (0..<durationS).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    /// Unix start at `hourUTC:00:00` on a fixed reference day. With the detector's default
    /// tzOffset=0, local hour == UTC hour, so this lets a test place a window's center in or
    /// out of the daytime band [11,20) deterministically.
    private func startAtHour(_ hourUTC: Int) -> Int {
        // 2026-06-10 00:00:00 UTC (an arbitrary fixed midnight) + hourUTC hours.
        let refMidnight = 1_749_513_600
        return refMidnight + hourUTC * 3_600
    }
    /// Window anchored at a clear NIGHT hour (center stays out of [11,20) for short windows).
    private func nightStart(_ hourUTC: Int) -> Int { startAtHour(hourUTC) }
    /// Window anchored at a DAYTIME hour (center lands in [11,20) for the durations tested).
    private func daytimeStart(_ hourUTC: Int) -> Int { startAtHour(hourUTC) }

    func testDetectSleepFindsStillNight() {
        // 90 min still + low HR (50 bpm) → one sleep session.
        // Anchored at 02:00 UTC (center 02:45) so the window is OVERNIGHT at the default
        // tzOffset=0 and never trips the daytime false-sleep guard (#90) — a plain still
        // night must always register regardless of the guard.
        let start = nightStart(02)
        let dur = 90 * 60
        let grav = stillGravity(start: start, durationS: dur)
        let hr = hrStream(start: start, durationS: dur, bpm: 50)
        let sessions = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertEqual(sessions.count, 1)
        let s = sessions[0]
        XCTAssertEqual(s.start, start)
        XCTAssertGreaterThan(s.efficiency, 0.5)
        XCTAssertEqual(s.restingHR, 50)
    }

    func testDetectSleepRejectsShortBout() {
        // Only 30 min still — below MIN_SLEEP_MIN (60) → no session.
        let start = 2_000_000
        let grav = stillGravity(start: start, durationS: 30 * 60)
        let hr = hrStream(start: start, durationS: 30 * 60, bpm: 50)
        XCTAssertTrue(SleepStager.detectSleep(hr: hr, gravity: grav).isEmpty)
    }

    func testDetectSleepEmptyGravity() {
        XCTAssertTrue(SleepStager.detectSleep(gravity: []).isEmpty)
    }

    func testDetectSleepHRConfirmationRejectsHighHR() {
        // Still gravity but HR is well above the day median*1.05. The daytime is
        // long (4 h) and low-HR (55) so the day median stays ~55; the still 90-min
        // "night" runs at 120 bpm, which exceeds 55*1.05 → the run is HR-rejected.
        let start = 3_000_000
        let sleepDur = 90 * 60
        let dayDur = 4 * 60 * 60
        let dayGrav = activeGravity(start: start, durationS: dayDur)
        let dayHR = hrStream(start: start, durationS: dayDur, bpm: 55)
        let nightGrav = stillGravity(start: start + dayDur, durationS: sleepDur)
        let nightHR = hrStream(start: start + dayDur, durationS: sleepDur, bpm: 120)
        let sessions = SleepStager.detectSleep(hr: dayHR + nightHR, gravity: dayGrav + nightGrav)
        // The still run's mean HR (120) >> median(55)*1.05 → rejected.
        XCTAssertTrue(sessions.isEmpty)
    }

    // MARK: - Daytime false-sleep guard (#90)

    /// A 70-min still, LOW-HR daytime window is rejected: even though its HR dips, it is
    /// shorter than the daytime minimum (90 min), so it's the dominant false-positive a
    /// sedentary daytime stretch produces. The preceding active block lifts the day HR
    /// baseline so the HR test would otherwise PASS — proving the rejection is the duration
    /// gate, not the HR gate.
    func testDaytimeShortLowHRWindowRejected() {
        let dayStart = daytimeStart(10)           // 10:00 active context
        let dayDur = 3 * 60 * 60                   // 3 h awake, moving, HR 72
        let dayGrav = activeGravity(start: dayStart, durationS: dayDur)
        let dayHR = hrStream(start: dayStart, durationS: dayDur, bpm: 72)

        let napStart = dayStart + dayDur           // 13:00, center 13:35 → daytime band
        let napDur = 70 * 60                        // 70 min < 90 min daytime minimum
        let napGrav = stillGravity(start: napStart, durationS: napDur)
        let napHR = hrStream(start: napStart, durationS: napDur, bpm: 50)

        let sessions = SleepStager.detectSleep(hr: dayHR + napHR, gravity: dayGrav + napGrav)
        XCTAssertTrue(sessions.isEmpty, "a 70-min daytime still window must be rejected by the guard")
    }

    /// A 120-min still, genuine-dip daytime nap STILL registers: ≥ 90 min AND its resting HR
    /// (50) sits clearly below the day HR baseline (~72), the cardiac signature of a real nap.
    /// The guard must not suppress legitimate daytime sleep.
    func testDaytimeQualityNapRegisters() {
        let dayStart = daytimeStart(10)            // 10:00 active context, HR 72
        let dayDur = 3 * 60 * 60
        let dayGrav = activeGravity(start: dayStart, durationS: dayDur)
        let dayHR = hrStream(start: dayStart, durationS: dayDur, bpm: 72)

        let napStart = dayStart + dayDur            // 13:00, center 14:00 → daytime band
        let napDur = 120 * 60                        // 120 min ≥ 90 min daytime minimum
        let napGrav = stillGravity(start: napStart, durationS: napDur)
        let napHR = hrStream(start: napStart, durationS: napDur, bpm: 50)

        let sessions = SleepStager.detectSleep(hr: dayHR + napHR, gravity: dayGrav + napGrav)
        XCTAssertEqual(sessions.count, 1, "a 120-min daytime nap with a real HR dip must register")
        // The run begins at/just after the active→still transition (the rolling stillness window
        // shifts the boundary by a few minutes), and its center is firmly in the daytime band.
        XCTAssertGreaterThanOrEqual(sessions[0].start, napStart)
        XCTAssertLessThan(sessions[0].start, napStart + 10 * 60)
        XCTAssertEqual(sessions[0].restingHR, 50)
    }

    /// A 70-min still, low-HR OVERNIGHT window registers unchanged: its center (≈03:35) is
    /// outside the daytime band, so the guard never applies and only the base 60-min minimum
    /// gates it. This pins that the guard leaves overnight detection exactly as it was.
    func testOvernightShortWindowUnchanged() {
        let dayStart = nightStart(00)               // 00:00 active context so a baseline exists
        let dayDur = 3 * 60 * 60                     // moving, HR 72
        let dayGrav = activeGravity(start: dayStart, durationS: dayDur)
        let dayHR = hrStream(start: dayStart, durationS: dayDur, bpm: 72)

        let sleepStartTs = dayStart + dayDur         // 03:00, center 03:35 → overnight
        let sleepDur = 70 * 60                         // 70 min > 60 min base minimum
        let sleepGrav = stillGravity(start: sleepStartTs, durationS: sleepDur)
        let sleepHR = hrStream(start: sleepStartTs, durationS: sleepDur, bpm: 50)

        let sessions = SleepStager.detectSleep(hr: dayHR + sleepHR, gravity: dayGrav + sleepGrav)
        XCTAssertEqual(sessions.count, 1, "a 70-min overnight still window must register unchanged")
        // Begins at/just after the active→still transition; center stays out of the daytime band.
        XCTAssertGreaterThanOrEqual(sessions[0].start, sleepStartTs)
        XCTAssertLessThan(sessions[0].start, sleepStartTs + 10 * 60)
    }

    /// The guard is offset-aware: the SAME absolute window that is overnight at tzOffset=0
    /// becomes daytime under a +10 h offset and is then held to the stricter bar. With no
    /// preceding awake block there is no HR baseline, so the daytime path rejects it (it can't
    /// confirm a real dip) — while at offset 0 the identical 70-min still window registers.
    func testTzOffsetShiftsWindowIntoDaytimeBand() {
        let start = nightStart(02)                   // 02:00 UTC, center 02:35
        let dur = 70 * 60
        let grav = stillGravity(start: start, durationS: dur)
        let hr = hrStream(start: start, durationS: dur, bpm: 50)

        // offset 0: overnight → registers.
        XCTAssertEqual(SleepStager.detectSleep(hr: hr, gravity: grav).count, 1)
        // +10 h: local center ≈ 12:35 → daytime band → stricter bar; no awake baseline → rejected.
        let shifted = SleepStager.detectSleep(hr: hr, gravity: grav, tzOffsetSeconds: 10 * 3_600)
        XCTAssertTrue(shifted.isEmpty, "a +10h offset pushes the window into the daytime band → rejected")
    }

    /// Guards against the index-out-of-range crash class from the prior attempt: no candidate
    /// at all (single still day, no HR) must return [] cleanly, not trap on empty median /
    /// first/last accesses inside the daytime path.
    func testDaytimeGuardEmptyInputsNoCrash() {
        // A still daytime stretch with NO HR at all → baseline nil → daytime path returns false
        // without touching any HR array; must not crash and must yield no sessions.
        let start = daytimeStart(13)
        let grav = stillGravity(start: start, durationS: 120 * 60)
        XCTAssertTrue(SleepStager.detectSleep(gravity: grav).isEmpty)
        // And the pure band/guard helpers tolerate a degenerate zero-length period.
        let p = SleepStager.Period(stage: "sleep", start: start, end: start)
        _ = SleepStager.isDaytimeCenter(p, tzOffsetSeconds: 0)
        XCTAssertFalse(SleepStager.passesDaytimeGuard(p, restingHR: nil, baseline: nil))
    }

    // MARK: - Sparse-gravity robustness (#308 / FER-662)

    /// Still gravity emitted in `clumps` bursts of `clumpMin` minutes each, separated by
    /// `gapMin`-minute gaps with NO gravity samples (the un-unlocked WHOOP 5.0 backfill shape).
    private func clumpedStillGravity(start: Int, clumps: Int, clumpMin: Int, gapMin: Int) -> [GravitySample] {
        var out: [GravitySample] = []
        var t = start
        for _ in 0..<clumps {
            out += stillGravity(start: t, durationS: clumpMin * 60)
            t += clumpMin * 60 + gapMin * 60   // advance past the clump AND the empty gap
        }
        return out
    }

    func testSparseGravityBridgesFragmentedNight() {
        // 3 still clumps of 25 min split by 40-min gravity gaps (no gravity), HR continuous 50 bpm
        // over the whole ~155-min overnight span. The gravity-only spine breaks at each >20-min gap
        // into three sub-60-min fragments and drops them all → 0 sessions. The sparse path keeps the
        // run open across a pure gravity gap while HR stays in the sleep band → one continuous night.
        let start = nightStart(02)
        let grav = clumpedStillGravity(start: start, clumps: 3, clumpMin: 25, gapMin: 40)
        let spanS = (25 * 3 + 40 * 2) * 60
        let hr = hrStream(start: start, durationS: spanS, bpm: 50)
        XCTAssertTrue(SleepStager.isGravitySparse(grav, hr: hr), "clumped gravity must read as sparse")
        let sessions = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertEqual(sessions.count, 1, "the fragmented night must be re-stitched into one session")
        XCTAssertGreaterThan(sessions[0].end - sessions[0].start, 150 * 60)
    }

    func testDenseNightNotFlaggedSparseAndUnchanged() {
        // Invariant: a dense 1 Hz night is never reclassified sparse, and detection is unchanged.
        let start = nightStart(02)
        let dur = 90 * 60
        let grav = stillGravity(start: start, durationS: dur)
        let hr = hrStream(start: start, durationS: dur, bpm: 50)
        XCTAssertFalse(SleepStager.isGravitySparse(grav, hr: hr))
        XCTAssertEqual(SleepStager.detectSleep(hr: hr, gravity: grav).count, 1)
    }

    func testIsGravitySparseNoHRIsDense() {
        // A 4.0 night with absent/degenerate HR is never reclassified sparse (dense path kept).
        let start = nightStart(02)
        let clumped = clumpedStillGravity(start: start, clumps: 3, clumpMin: 25, gapMin: 40)
        XCTAssertFalse(SleepStager.isGravitySparse(clumped, hr: []), "no HR → dense path, never sparse")
        XCTAssertFalse(SleepStager.isGravitySparse(clumped, hr: [HRSample(ts: start, bpm: 50)]))
    }

    func testBuildRunsAndBridgeAreNoOpWhenDense() {
        // The sparse override in buildRuns and bridgeSparseSleep must be inert when sparse == false:
        // the clumped gravity splits into three sleep runs exactly as the original did.
        let start = nightStart(02)
        let grav = clumpedStillGravity(start: start, clumps: 3, clumpMin: 25, gapMin: 40)
        let deltas = SleepStager.gravityDeltas(grav)
        let flags = SleepStager.classifyStill(grav, deltas)
        let dense = SleepStager.buildRuns(grav, flags)                       // old signature
        let denseExplicit = SleepStager.buildRuns(grav, flags, sparse: false, hr: [], baseline: nil)
        XCTAssertEqual(dense.count, 3, "dense buildRuns splits the clumps into three runs")
        XCTAssertEqual(denseExplicit.count, dense.count)
        // bridgeSparseSleep is a no-op when not sparse.
        XCTAssertEqual(SleepStager.bridgeSparseSleep(dense, sparse: false, hr: [], baseline: nil).count, 3)
        // ...and with sparse + in-band HR it stitches the three sleep runs into one.
        let hr = hrStream(start: start, durationS: (25 * 3 + 40 * 2) * 60, bpm: 50)
        XCTAssertEqual(SleepStager.bridgeSparseSleep(dense, sparse: true, hr: hr, baseline: 50).count, 1)
    }

    // MARK: - 16 h physiological span cap (#547 / FER-662)

    /// Still gravity/HR every `stepS` seconds over a long span — coarse enough to keep the fixture
    /// small, dense enough (`stepS` ≪ maxGapMin) that the night is NOT flagged sparse.
    private func longStill(start: Int, hours: Int, stepS: Int, bpm: Int) -> ([GravitySample], [HRSample]) {
        let dur = hours * 3_600
        let grav = stride(from: 0, to: dur, by: stepS).map { GravitySample(ts: start + $0, x: 0, y: 0, z: 1.0) }
        let hr = stride(from: 0, to: dur, by: stepS).map { HRSample(ts: start + $0, bpm: bpm) }
        return (grav, hr)
    }

    func testOverlongBlockDroppedButUnderCapKept() {
        // A single 17 h still block is a bad-clock artefact → dropped; a 15 h block is a long but
        // plausible night → kept. Anchored at 20:00 so both centers stay overnight (out of [11,20)).
        let (g17, h17) = longStill(start: startAtHour(20), hours: 17, stepS: 20, bpm: 50)
        XCTAssertTrue(SleepStager.detectSleep(hr: h17, gravity: g17).isEmpty, "17 h > 16 h cap → dropped")
        let (g15, h15) = longStill(start: startAtHour(20), hours: 15, stepS: 20, bpm: 50)
        XCTAssertEqual(SleepStager.detectSleep(hr: h15, gravity: g15).count, 1, "15 h < 16 h cap → kept")
    }

    // MARK: - Off-wrist backstop (#500 / FER-662)

    func testOffWristFractionUnionsSpans() {
        // A run [0, 1000] with an HR hole (no samples in (100, 900]) → one ~900 s gap span, plus an
        // overlapping WRIST_OFF event [800, 1000]; the union is counted once (not double).
        let p = SleepStager.Period(stage: "sleep", start: 0, end: 1000)
        // HR present only at the edges (dense enough stream span to pass the density gate).
        let hr = (0...100).map { HRSample(ts: $0, bpm: 50) } + (901...1000).map { HRSample(ts: $0, bpm: 50) }
        let frac = SleepStager.offWristFraction(p, hr: hr, wristOff: [(start: 800, end: 1000)])
        // The interior HR gap is (100, 901] ≈ 800 s ≥ offWristHRGapMin(1200 s)? No — 800 s < 1200 s,
        // so the HR-gap proxy contributes nothing; only the explicit 200 s wrist-off event counts.
        XCTAssertEqual(frac, 200.0 / 1000.0, accuracy: 1e-9)
    }

    func testAllDayOffWristDroppedShortTailKept() {
        // Overnight still gravity 3 h. When HR is present only for the first 30 min (off-wrist the
        // rest), off-wrist coverage ≈ 83% ≥ 50% → dropped. When HR covers the first 2.5 h (30-min
        // off-wrist tail), coverage ≈ 17% < 50% → kept.
        let start = nightStart(01)
        let dur = 3 * 60 * 60
        let grav = stillGravity(start: start, durationS: dur)
        let hrShort = hrStream(start: start, durationS: 30 * 60, bpm: 50)       // off-wrist 2.5 h
        XCTAssertTrue(SleepStager.detectSleep(hr: hrShort, gravity: grav).isEmpty, "≈83% off-wrist → dropped")
        let hrLong = hrStream(start: start, durationS: 150 * 60, bpm: 50)       // off-wrist 0.5 h
        XCTAssertEqual(SleepStager.detectSleep(hr: hrLong, gravity: grav).count, 1, "≈17% off-wrist → kept")
    }

    // MARK: - Morning-stillness guard + band-state (#531 / FER-662)

    func testMorningStillnessGuardHRBar() {
        // A daytime block beginning within the morning window of an overnight wake must clear the
        // STRONGER 0.90× re-onset bar, not the ordinary 0.95×. baseline 60: 0.90×=54, 0.95×=57.
        let p = SleepStager.Period(stage: "sleep", start: 1_000, end: 1_000 + 120 * 60)  // 120 min ≥ daytime min
        let wakeEnd = 1_000 - 10 * 60   // block starts 10 min after the overnight wake (within 180 min)
        // resting 56 clears the ordinary daytime bar (≤57) but NOT the stronger morning bar (≤54) → reject.
        XCTAssertFalse(SleepStager.passesMorningStillnessGuard(
            p, restingHR: 56, baseline: 60, morningWakeEnd: wakeEnd))
        // resting 53 clears the stronger bar → keep.
        XCTAssertTrue(SleepStager.passesMorningStillnessGuard(
            p, restingHR: 53, baseline: 60, morningWakeEnd: wakeEnd))
        // With no overnight wake anchor, it's the ordinary daytime guard: 56 ≤ 57 → keep.
        XCTAssertTrue(SleepStager.passesMorningStillnessGuard(
            p, restingHR: 56, baseline: 60, morningWakeEnd: nil))
    }

    func testMorningStillnessBandStateRescue() {
        // A borderline morning block (resting 56, fails the 0.90× HR bar) is RESCUED when the strap's
        // own band sleep_state reads predominantly "asleep" (≥60% state==2) over the block.
        let p = SleepStager.Period(stage: "sleep", start: 1_000, end: 1_000 + 120 * 60)
        let wakeEnd = 1_000 - 10 * 60
        let asleepState = stride(from: 1_000, through: 1_000 + 120 * 60, by: 60)
            .map { (ts: $0, state: SleepStager.bandStateAsleep) }             // 100% asleep
        XCTAssertTrue(SleepStager.passesMorningStillnessGuard(
            p, restingHR: 56, baseline: 60, morningWakeEnd: wakeEnd, bandSleepState: asleepState),
            "band-state asleep must rescue a borderline morning re-onset")
        // Empty band state → no anchor → falls back to the HR bar → still rejected.
        XCTAssertFalse(SleepStager.passesMorningStillnessGuard(
            p, restingHR: 56, baseline: 60, morningWakeEnd: wakeEnd, bandSleepState: []))
    }

    func testBandStateConfirmsAsleepThreshold() {
        let p = SleepStager.Period(stage: "sleep", start: 0, end: 100)
        XCTAssertFalse(SleepStager.bandStateConfirmsAsleep(p, bandSleepState: []), "no band state → false")
        // 6 of 10 asleep (0.6) meets the ≥0.6 threshold.
        let sixtyPct = (0..<10).map { (ts: $0 * 10, state: $0 < 6 ? SleepStager.bandStateAsleep : 1) }
        XCTAssertTrue(SleepStager.bandStateConfirmsAsleep(p, bandSleepState: sixtyPct))
        // 5 of 10 (0.5) falls short.
        let fiftyPct = (0..<10).map { (ts: $0 * 10, state: $0 < 5 ? SleepStager.bandStateAsleep : 1) }
        XCTAssertFalse(SleepStager.bandStateConfirmsAsleep(p, bandSleepState: fiftyPct))
    }

    // MARK: - Night-tail continuation (#353 / FER-662)

    func testIsOvernightOnset() {
        XCTAssertTrue(SleepStager.isOvernightOnset(startAtHour(2), tzOffsetSeconds: 0))    // 02:00 → overnight
        XCTAssertFalse(SleepStager.isOvernightOnset(startAtHour(13), tzOffsetSeconds: 0))  // 13:00 → daytime
    }

    func testNightTailPastDaytimeBandKept() {
        // An overnight sleep (02:00) that continues, after a brief 15-min wake, into a daytime-centered
        // tail (11:00, center ~11:45) is KEPT as the night's tail — not rejected as a nap — because it
        // directly continues an overnight chain. The tail's HR sits at the day baseline, so it would
        // FAIL the ordinary daytime guard: only the night-tail exemption saves it. An identical tail
        // with no preceding overnight chain is rejected.
        let step = 10
        let sleepStart = startAtHour(02)
        let sleepDur = 8 * 3_600 + 45 * 60           // 02:00 → 10:45
        let wakeStart = sleepStart + sleepDur         // 10:45
        let wakeDur = 15 * 60                          // 15-min real wake (class change splits the runs)
        let tailStart = wakeStart + wakeDur           // 11:00
        let tailDur = 90 * 60                          // 90 min, center ~11:45 → daytime band

        func stillG(_ s: Int, _ d: Int) -> [GravitySample] {
            stride(from: 0, to: d, by: step).map { GravitySample(ts: s + $0, x: 0, y: 0, z: 1.0) }
        }
        func activeG(_ s: Int, _ d: Int) -> [GravitySample] {
            stride(from: 0, to: d, by: step).enumerated().map { (i, o) in
                GravitySample(ts: s + o, x: Double(i % 2) * 0.5, y: 0, z: 1.0)
            }
        }
        func hrG(_ s: Int, _ d: Int, _ bpm: Int) -> [HRSample] {
            stride(from: 0, to: d, by: step).map { HRSample(ts: s + $0, bpm: bpm) }
        }

        let grav = stillG(sleepStart, sleepDur) + activeG(wakeStart, wakeDur) + stillG(tailStart, tailDur)
        // Night 50, wake 90, tail 50 (= day baseline ⇒ fails the 0.95× daytime dip bar).
        let hr = hrG(sleepStart, sleepDur, 50) + hrG(wakeStart, wakeDur, 90) + hrG(tailStart, tailDur, 50)

        let withChain = SleepStager.detectSleep(hr: hr, gravity: grav)
        XCTAssertEqual(withChain.count, 2, "overnight sleep + its daytime tail both register")
        XCTAssertTrue(withChain.contains { $0.start >= tailStart && $0.start < tailStart + 10 * 60 },
                      "the daytime tail is kept as the night's continuation")

        // The SAME tail in isolation (no overnight chain) faces the full daytime guard and is rejected.
        let tailOnlyGrav = stillG(tailStart, tailDur)
        let tailOnlyHR = hrG(tailStart, tailDur, 50)
        XCTAssertTrue(SleepStager.detectSleep(hr: tailOnlyHR, gravity: tailOnlyGrav).isEmpty,
                      "an isolated daytime still block at day-baseline HR is rejected")
    }

    // MARK: - Staging output integrity

    func testStagesTileSessionExactly() {
        let start = 4_000_000
        let dur = 90 * 60
        let grav = stillGravity(start: start, durationS: dur)
        let hr = hrStream(start: start, durationS: dur, bpm: 50)
        let s = SleepStager.detectSleep(hr: hr, gravity: grav)[0]
        XCTAssertFalse(s.stages.isEmpty)
        // Segments must be contiguous and span exactly [start, end].
        XCTAssertEqual(s.stages.first!.start, s.start)
        XCTAssertEqual(s.stages.last!.end, s.end)
        for i in 0..<(s.stages.count - 1) {
            XCTAssertEqual(s.stages[i].end, s.stages[i + 1].start)
        }
        // Every stage label is one of the four valid classes.
        for seg in s.stages {
            XCTAssertTrue(["wake", "light", "deep", "rem"].contains(seg.stage))
        }
    }

    func testEfficiencyComputation() {
        // A 1000 s session with 100 s of wake → efficiency = 0.9.
        let stages = [
            StageSegment(start: 0, end: 100, stage: "wake"),
            StageSegment(start: 100, end: 1000, stage: "light"),
        ]
        let eff = SleepStager.efficiency(start: 0, end: 1000, stages: stages)
        XCTAssertEqual(eff, 0.9, accuracy: 1e-9)
    }

    // MARK: - Hypnogram metrics

    func testHypnogramMetricsAASM() {
        // SOL 60 s, then light 540 s, deep 300 s, wake 60 s (disturbance), rem 240 s.
        let stages = [
            StageSegment(start: 0, end: 60, stage: "wake"),       // pre-onset latency
            StageSegment(start: 60, end: 600, stage: "light"),    // 540 s
            StageSegment(start: 600, end: 900, stage: "deep"),    // 300 s
            StageSegment(start: 900, end: 960, stage: "wake"),    // WASO 60 s
            StageSegment(start: 960, end: 1200, stage: "rem"),    // 240 s
        ]
        let session = SleepSession(start: 0, end: 1200, efficiency: 0.95,
                                   stages: stages, restingHR: 50, avgHRV: 60)
        let m = SleepStager.hypnogramMetrics(session)
        XCTAssertEqual(m.tibS, 1200, accuracy: 1e-9)
        XCTAssertEqual(m.tstS, 540 + 300 + 240, accuracy: 1e-9)  // 1080
        XCTAssertEqual(m.solS, 60, accuracy: 1e-9)
        XCTAssertEqual(m.wasoS, 60, accuracy: 1e-9)
        XCTAssertEqual(m.disturbances, 1)
        XCTAssertEqual(m.deepMin, 5.0, accuracy: 1e-9)
        XCTAssertEqual(m.remMin, 4.0, accuracy: 1e-9)
        XCTAssertEqual(m.lightMin, 9.0, accuracy: 1e-9)
        // Percentages sum to ~100.
        XCTAssertEqual(m.deepPct + m.remPct + m.lightPct, 100.0, accuracy: 1e-6)
    }

    func testHypnogramREMLatency() {
        let stages = [
            StageSegment(start: 0, end: 300, stage: "light"),   // onset at 0
            StageSegment(start: 300, end: 600, stage: "rem"),   // first REM at 300
        ]
        let session = SleepSession(start: 0, end: 600, efficiency: 1.0,
                                   stages: stages, restingHR: nil, avgHRV: nil)
        let m = SleepStager.hypnogramMetrics(session)
        XCTAssertEqual(m.remLatencyS, 300, accuracy: 1e-9)
    }

    // MARK: - Respiration helper

    func testRespRateFromSyntheticBreathing() {
        // Synthesize a clean 0.25 Hz breathing wave (15 br/min) over 60 s at 1 Hz.
        let n = 60
        let resp = (0..<n).map { i -> Double in sin(2 * Double.pi * 0.25 * Double(i)) * 10 + 100 }
        let (rate, rrv) = SleepStager.respRateAndRRV(resp)
        XCTAssertFalse(rate.isNaN)
        XCTAssertEqual(rate, 15.0, accuracy: 2.0)  // ~15 breaths/min
        XCTAssertGreaterThanOrEqual(rrv, 0)
    }

    func testRespRateTooFewSamples() {
        let (rate, rrv) = SleepStager.respRateAndRRV([1, 2, 3])
        XCTAssertTrue(rate.isNaN)
        XCTAssertTrue(rrv.isNaN)
    }

    // MARK: - Stage-gated nightly HRV

    func testSessionAvgHRVExcludesWakeWindows() {
        // 5 tumbling 5-min windows: the outer two are light sleep (RMSSD ~5 ms), the
        // inner three are wake (RMSSD ~40 ms). Without a hypnogram the median is dragged
        // up by the three wake windows; gating on the hypnogram drops them and the night's
        // HRV reflects only the sleep windows — a more reproducible parasympathetic read.
        var rr: [RRInterval] = []
        func fill(start: Int, lo: Int, hi: Int) {
            for i in 0..<30 { rr.append(RRInterval(ts: start + i, rrMs: i % 2 == 0 ? lo : hi)) }
        }
        fill(start: 0,    lo: 800, hi: 805)   // window 0 — sleep
        fill(start: 300,  lo: 800, hi: 840)   // window 1 — wake
        fill(start: 600,  lo: 800, hi: 840)   // window 2 — wake
        fill(start: 900,  lo: 800, hi: 840)   // window 3 — wake
        fill(start: 1200, lo: 800, hi: 805)   // window 4 — sleep
        let stages = [
            StageSegment(start: 0, end: 300, stage: "light"),
            StageSegment(start: 300, end: 1200, stage: "wake"),
            StageSegment(start: 1200, end: 1500, stage: "light"),
        ]
        let withoutStages = SleepStager.sessionAvgHRV(start: 0, end: 1500, rr: rr)!
        let withStages = SleepStager.sessionAvgHRV(start: 0, end: 1500, rr: rr, stages: stages)!
        XCTAssertEqual(withoutStages, 40, accuracy: 1.0, "all-windows median is dominated by the 3 wake windows")
        XCTAssertEqual(withStages, 5, accuracy: 1.0, "excluding wake leaves only the sleep windows")
        XCTAssertEqual(SleepStager.stageAt(450, stages), "wake")
        XCTAssertEqual(SleepStager.stageAt(150, stages), "light")
    }

    // MARK: - Resting-HR hardening wired to the production path (FER-674 / FER-854)

    /// The production nightly resting-HR (`sessionRestingHR` → AnalyticsEngine → recovery) must
    /// reject a sparse dropout bin and a sub-physiological artefact bin, exactly like the shipped
    /// `RecoveryScorer.restingHR` gate — so an off-wrist minute can't fabricate an impossible RHR
    /// that then contaminates the HRV→RHR→Charge chain.
    func testSessionRestingHRRejectsSparseAndSubPhysiologicalBins() {
        let windowS = 5 * 60
        // Bin 0: a dense, genuine resting floor at 50 bpm.
        var hr = (0..<windowS).map { HRSample(ts: $0, bpm: 50) }
        // Bin 1: a 3-sample dropout at an impossible 10 bpm — must NOT win the floor.
        hr += [HRSample(ts: windowS + 1, bpm: 10),
               HRSample(ts: windowS + 2, bpm: 10),
               HRSample(ts: windowS + 3, bpm: 10)]
        let rhr = SleepStager.sessionRestingHR(start: 0, end: 2 * windowS, hr: hr)
        XCTAssertEqual(rhr, 50, "the sparse sub-25 bpm bin must be rejected; the 50 bpm floor wins")
    }

    /// A dense but genuinely sub-physiological bin (mean < 25 bpm) is still rejected by the floor,
    /// and with no qualifying bin the whole-segment fallback also stays ≥ the floor or returns nil.
    func testSessionRestingHRSubPhysiologicalFallbackIsNil() {
        let windowS = 5 * 60
        // A full window of an impossible 12 bpm (dense enough to pass the sample gate, but below
        // the 25 bpm physiological floor) — no bin qualifies, and the fallback mean is also < 25.
        let hr = (0..<windowS).map { HRSample(ts: $0, bpm: 12) }
        XCTAssertNil(SleepStager.sessionRestingHR(start: 0, end: windowS, hr: hr),
                     "a sub-physiological segment must not fabricate an RHR")
    }
}
