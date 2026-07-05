import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class WorkoutDetectorTests: XCTestCase {

    // MARK: - Activity series

    func testActivitySeriesFirstIsZero() {
        let grav = [
            GravitySample(ts: 0, x: 0, y: 0, z: 1),
            GravitySample(ts: 1, x: 0.3, y: 0, z: 1),  // Δ = 0.3
            GravitySample(ts: 2, x: 0.3, y: 0, z: 1),  // Δ = 0
        ]
        let series = WorkoutDetector.activitySeries(grav)
        XCTAssertEqual(series.count, 3)
        XCTAssertEqual(series[0].intensity, 0.0, accuracy: 1e-9)
        XCTAssertEqual(series[1].intensity, 0.3, accuracy: 1e-9)
        XCTAssertEqual(series[2].intensity, 0.0, accuracy: 1e-9)
    }

    func testActivitySeriesEmpty() {
        XCTAssertTrue(WorkoutDetector.activitySeries([]).isEmpty)
    }

    // MARK: - Calories

    func testCaloriesActiveAndRestingMale() {
        // 600 active samples at 150 bpm, male 80 kg 30 y, hrmax 190 → matches Python golden.
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, kj) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        XCTAssertEqual(kcal, 146.972, accuracy: 0.1)
        XCTAssertEqual(kj, kcal * 4.184, accuracy: 1e-6)
    }

    func testCaloriesRestingBelowThreshold() {
        // HR below the 30% HRR active threshold → BMR rate (small per-sample).
        // Threshold = 60 + 0.30*(190-60) = 99. bpm 80 < 99 → resting.
        let hr = (0..<86400).map { HRSample(ts: $0, bpm: 80) }  // a full "day" of resting
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let (kcal, _) = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 190, restingHR: 60)
        // 86400 s at BMR rate ≈ full BMR ≈ 1853.6 kcal/day.
        XCTAssertEqual(kcal, 1853.632, accuracy: 1.0)
    }

    func testCaloriesSexCoefficientsDiffer() {
        let hr = (0..<600).map { HRSample(ts: $0, bpm: 150) }
        let male = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "male"),
            hrmax: 190, restingHR: 60).0
        let female = Calories.estimateBoutCalories(
            hr, profile: UserProfile(weightKg: 70, heightCm: 175, age: 30, sex: "female"),
            hrmax: 190, restingHR: 60).0
        XCTAssertNotEqual(male, female, accuracy: 0.0)
    }

    // MARK: - Detection

    /// A workout: high HR + sustained motion for `durationS`, embedded in a rest day.
    private func workoutDay(workoutStart: Int, workoutDur: Int) -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = workoutStart - 30 * 60
        let dayEnd = workoutStart + workoutDur + 30 * 60
        for t in dayStart..<dayEnd {
            let inWorkout = t >= workoutStart && t < workoutStart + workoutDur
            // Resting periods: HR 55, still gravity. Workout: HR 165, moving gravity.
            hr.append(HRSample(ts: t, bpm: inWorkout ? 165 : 55))
            if inWorkout {
                let phase = Double((t - workoutStart) % 2) * 0.5  // 0.5 g oscillation → moving
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still
            }
        }
        return (hr, grav)
    }

    func testDetectFindsWorkout() {
        let start = 5_000_000
        let dur = 20 * 60  // 20 min
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        let w = sessions[0]
        XCTAssertEqual(w.avgHR, 165, accuracy: 1.0)
        XCTAssertEqual(w.peakHR, 165)
        XCTAssertGreaterThan(w.durationS, Double(15 * 60))
        // Zone breakdown sums to ~100.
        let total = w.zoneTimePct.values.reduce(0, +)
        XCTAssertEqual(total, 100.0, accuracy: 0.5)
        XCTAssertEqual(w.hrmaxSource, "tanaka")  // age supplied, thin observed history
    }

    func testDetectWithProfileEstimatesCalories() {
        let start = 6_000_000
        let dur = 20 * 60
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: dur)
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 30, sex: "male")
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30, profile: profile)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].caloriesKcal)
        XCTAssertGreaterThan(sessions[0].caloriesKcal!, 0)
    }

    func testDetectRejectsShortBout() {
        let start = 7_000_000
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: 3 * 60)  // 3 min < 5
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    func testShortBoutHasNilStrain() {
        // A detected bout shorter than StrainScorer's ~10-min (600-sample) floor reports strain == nil
        // by design (accepted span ~290–598 s). Pinned so the documented behavior can't silently change.
        let start = 9_000_000
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: 7 * 60)  // 7 min → 420 samples < 600
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].strain, "a ~7-min bout is below StrainScorer's 600-sample floor → nil")
    }

    func testLongBoutHasStrain() {
        // The companion: a 20-min bout clears the floor and gets a numeric strain.
        let start = 9_500_000
        let (hr, grav) = workoutDay(workoutStart: start, workoutDur: 20 * 60)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].strain)
    }

    func testDetectEmptyStreams() {
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: [], age: 30).isEmpty)
        let grav = [GravitySample(ts: 0, x: 0, y: 0, z: 1)]
        XCTAssertTrue(WorkoutDetector.detect(hr: [], gravity: grav, age: 30).isEmpty)
    }

    func testDetectRejectsLowIntensityBlip() {
        // Moving + slightly elevated HR but dominated by zone 0/1 (HR just over floor).
        // resting derived ~55, floor = 70. HR 75 is above floor but at ~15% HRR (zone 0).
        let start = 8_000_000
        let dur = 20 * 60
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let dayStart = start - 30 * 60
        let dayEnd = start + dur + 30 * 60
        for t in dayStart..<dayEnd {
            let inBout = t >= start && t < start + dur
            hr.append(HRSample(ts: t, bpm: inBout ? 75 : 55))
            if inBout {
                let phase = Double((t - start) % 2) * 0.5
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))
            }
        }
        // age 30 → hrmax 187, zone math available → z2+ fraction ≈ 0 < 0.50 → rejected.
        XCTAssertTrue(WorkoutDetector.detect(hr: hr, gravity: grav, age: 30).isEmpty)
    }

    // MARK: - Second-pass bridge (#303, FER-660)

    /// Two moving phases of `phaseDur` s each (HR `boutHR`), split by a still-motion gap of
    /// `gapDur` s during which HR holds at `gapHR`. Embedded in a resting day (HR 55, still).
    private func twoPhaseDay(start: Int, phaseDur: Int, gapDur: Int, boutHR: Int, gapHR: Int)
        -> (hr: [HRSample], grav: [GravitySample]) {
        var hr: [HRSample] = []
        var grav: [GravitySample] = []
        let p1End = start + phaseDur
        let gapEnd = p1End + gapDur
        let p2End = gapEnd + phaseDur
        let dayStart = start - 30 * 60
        let dayEnd = p2End + 30 * 60
        for t in dayStart..<dayEnd {
            let moving = (t >= start && t < p1End) || (t >= gapEnd && t < p2End)
            let inGap = t >= p1End && t < gapEnd
            hr.append(HRSample(ts: t, bpm: moving ? boutHR : (inGap ? gapHR : 55)))
            if moving {
                let phase = Double((t - start) % 2) * 0.5   // 0.5 g oscillation → moving
                grav.append(GravitySample(ts: t, x: phase, y: 0, z: 1))
            } else {
                grav.append(GravitySample(ts: t, x: 0, y: 0, z: 1))  // still (gap + rest)
            }
        }
        return (hr, grav)
    }

    func testBridgesRunsAcrossElevatedHRLull() {
        // Two 4-min moving phases split by a 4-min still gap where HR STAYS at 165 (coasting a
        // descent). Gap 240 s ≤ bridgeGapS and mean gap HR > floor → one continuous ~12-min bout.
        // Each 4-min phase alone (240 s < the ~290 s onset floor) would be dropped, so WITHOUT
        // bridging this day yields ZERO workouts — the exact fragmentation #303 fixes.
        let (hr, grav) = twoPhaseDay(start: 10_000_000, phaseDur: 4 * 60, gapDur: 4 * 60,
                                     boutHR: 165, gapHR: 165)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertGreaterThan(sessions[0].durationS, Double(11 * 60))  // spans both phases + the gap
    }

    func testDoesNotBridgeAcrossGenuineRest() {
        // Two 20-min moving phases split by a 4-min still gap where HR FALLS to resting (55): two
        // genuinely separate workouts. The gap is within bridgeGapS, but the HR check sees rest and
        // keeps them apart → two sessions. A naive gap-only bridge would wrongly merge them into one.
        let (hr, grav) = twoPhaseDay(start: 11_000_000, phaseDur: 20 * 60, gapDur: 4 * 60,
                                     boutHR: 165, gapHR: 55)
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 2)
    }

    func testBridgesRunsAcrossSensorDropout() {
        // Same two 4-min phases, but the 4-min gap carries NO HR samples at all (a sensor dropout
        // mid-effort). With no HR to prove rest, the gap is treated as same-effort and bridged →
        // one bout, not zero. Build the day, then strip the HR samples inside the gap window.
        let start = 12_000_000
        let p1End = start + 4 * 60, gapEnd = p1End + 4 * 60
        var (hr, grav) = twoPhaseDay(start: start, phaseDur: 4 * 60, gapDur: 4 * 60,
                                     boutHR: 165, gapHR: 165)
        hr.removeAll { $0.ts >= p1End && $0.ts < gapEnd }   // sensor dropout: no HR in the lull
        let sessions = WorkoutDetector.detect(hr: hr, gravity: grav, age: 30)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertGreaterThan(sessions[0].durationS, Double(11 * 60))
    }

    func testBridgeRunsUnitElevatedVsRest() {
        // Direct unit check of the bridge predicate on synthetic runs.
        let runs = [(0, 100), (300, 400)]   // 200 s gap ≤ bridgeGapS
        let elevated = (101...299).map { (ts: $0, bpm: 150.0) }   // gap HR well above floor 70
        XCTAssertEqual(WorkoutDetector.bridgeRuns(runs, hrSeg: elevated, hrFloor: 70).count, 1)
        let resting = (101...299).map { (ts: $0, bpm: 55.0) }     // gap HR at rest
        XCTAssertEqual(WorkoutDetector.bridgeRuns(runs, hrSeg: resting, hrFloor: 70).count, 2)
        // Gap wider than bridgeGapS is never bridged, even with elevated HR.
        let farRuns = [(0, 100), (500, 600)]   // 400 s gap > bridgeGapS
        let farHR = (101...499).map { (ts: $0, bpm: 150.0) }
        XCTAssertEqual(WorkoutDetector.bridgeRuns(farRuns, hrSeg: farHR, hrFloor: 70).count, 2)
    }
}
