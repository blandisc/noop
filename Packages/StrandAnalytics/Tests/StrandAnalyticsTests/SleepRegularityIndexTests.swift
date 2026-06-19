import XCTest
@testable import StrandAnalytics
import WhoopStore

/// FER-214 — the real Sleep Regularity Index (Phillips 2017 / Windred 2024): concordance of the
/// asleep/awake state with the instant 24 h later, over a window of nights.
final class SleepRegularityIndexTests: XCTestCase {

    private let base = 1_700_000_000   // arbitrary unix anchor; only the night-to-night pattern matters

    private func iv(day: Int, startH: Double, durH: Double) -> SleepRegularityIndex.AsleepInterval {
        let s = base + day * 86_400 + Int(startH * 3600)
        return .init(start: s, end: s + Int(durH * 3600))
    }

    // MARK: a perfectly repeated schedule → SRI ≈ 100

    func test_regularSchedule_nearHundred() {
        let nights = (0..<10).map { iv(day: $0, startH: 23, durH: 8) }   // 23:00–07:00 every night
        let sri = SleepRegularityIndex.compute(asleepIntervals: nights)
        XCTAssertNotNil(sri)
        XCTAssertGreaterThan(sri!, 98)
    }

    // MARK: alternating bedtimes → much lower, and below the regular case

    func test_irregularSchedule_low() {
        let nights = (0..<10).map { iv(day: $0, startH: $0 % 2 == 0 ? 22 : 26, durH: 7) }  // 10pm vs 2am
        let sri = SleepRegularityIndex.compute(asleepIntervals: nights)
        let regular = SleepRegularityIndex.compute(asleepIntervals: (0..<10).map { iv(day: $0, startH: 22, durH: 7) })!
        XCTAssertNotNil(sri)
        XCTAssertLessThan(sri!, 80)
        XCTAssertLessThan(sri!, regular)
    }

    // MARK: a single shifted night dips below regular but stays high

    func test_oneShiftedNight_penalizedButHigh() {
        let nights = (0..<10).map { iv(day: $0, startH: $0 == 5 ? 26 : 23, durH: 8) }
        let sri = SleepRegularityIndex.compute(asleepIntervals: nights)!
        let regular = SleepRegularityIndex.compute(asleepIntervals: (0..<10).map { iv(day: $0, startH: 23, durH: 8) })!
        XCTAssertLessThan(sri, regular)
        XCTAssertGreaterThan(sri, 85)
    }

    // MARK: coverage gate

    func test_belowMinNights_nil() {
        let nights = (0..<6).map { iv(day: $0, startH: 23, durH: 8) }   // 6 < minNights (7)
        XCTAssertNil(SleepRegularityIndex.compute(asleepIntervals: nights))
        XCTAssertNil(SleepRegularityIndex.compute(asleepIntervals: []))
    }

    // MARK: a missing night drops out of the pairing (doesn't tank a regular sleeper, doesn't crash)

    func test_missingNight_skipsGap() {
        let nights = (0..<11).filter { $0 != 5 }.map { iv(day: $0, startH: 23, durH: 8) }  // day 5 missing
        let sri = SleepRegularityIndex.compute(asleepIntervals: nights)
        XCTAssertNotNil(sri)
        XCTAssertGreaterThan(sri!, 90)
    }

    // MARK: decodeStages round-trips with encodeStages; imported dict / junk → nil

    func test_decodeStages_roundTrip() {
        let segs = [StageSegment(start: 100, end: 200, stage: "deep"),
                    StageSegment(start: 200, end: 300, stage: "wake")]
        let json = AnalyticsEngine.encodeStages(segs)
        XCTAssertEqual(AnalyticsEngine.decodeStages(json), segs)
        XCTAssertNil(AnalyticsEngine.decodeStages("{\"light\":120,\"deep\":80}"))  // imported totals dict
        XCTAssertNil(AnalyticsEngine.decodeStages(nil))
        XCTAssertNil(AnalyticsEngine.decodeStages("[]"))
    }

    // MARK: a nap is excluded so it can't tank the SRI (FER-298)
    //
    // fromSessions applies the "main night" gate (≥ 3 h, SleepMainNight): a short daytime sleep is
    // near anti-phase to the nocturnal sleep (Phillips 2017 / Windred 2024 measure the MAIN sleep
    // period) and would drag the 24 h concordance down. Fixed vector: 8 steady nights + one 2 h nap →
    // the same SRI as the 8 nights alone.

    func test_fromSessions_napExcluded() {
        func session(day: Int, startH: Double, durH: Double) -> CachedSleepSession {
            let start = base + day * 86_400 + Int(startH * 3600)
            return .init(startTs: start, endTs: start + Int(durH * 3600), efficiency: nil,
                         restingHr: nil, avgHrv: nil, stagesJSON: nil)
        }
        let nights = (0..<8).map { session(day: $0, startH: 23, durH: 8) }   // 23:00–07:00 every night
        let nap = session(day: 3, startH: 15, durH: 2)                       // 2 h afternoon nap

        let withoutNap = SleepRegularityIndex.fromSessions(nights)
        let withNap = SleepRegularityIndex.fromSessions(nights + [nap])
        XCTAssertNotNil(withNap)
        XCTAssertEqual(withNap!, withoutNap!, accuracy: 1e-6, "the 2 h nap must not change the SRI")
        XCTAssertGreaterThan(withNap!, 98, "a steady schedule stays steady despite the nap")
    }

    // MARK: the builder prefers a real SRI over the duration proxy

    func test_builder_sriOverridesProxy() {
        // nightlySleepHours all 7 → the proxy would be 1.0 (CV 0); the real SRI/100 must win.
        let withSRI = VitalityInputsBuilder.build(.init(
            chronoAge: 40, nightlySleepHours: [7, 7, 7], sleepRegularity: 0.42))
        XCTAssertEqual(withSRI.sleepConsistency, 0.42)

        let withoutSRI = VitalityInputsBuilder.build(.init(
            chronoAge: 40, nightlySleepHours: [7, 7, 7]))
        XCTAssertEqual(withoutSRI.sleepConsistency, VitalityEngine.sleepConsistency(nightlyHours: [7, 7, 7]))
    }

    // MARK: fromSessions maps the persisted hypnogram (fine) + bare [start,end] (coarse) the same way

    func test_fromSessions_fineAndCoarseMix() {
        // 8 nights on one schedule: even nights carry a real hypnogram, odd nights only [start, end].
        var sessions: [CachedSleepSession] = []
        for i in 0..<8 {
            let start = base + i * 86_400 + 23 * 3600, end = start + 8 * 3600
            let json = i % 2 == 0
                ? AnalyticsEngine.encodeStages([StageSegment(start: start, end: end, stage: "light")])
                : nil
            sessions.append(.init(startTs: start, endTs: end, efficiency: nil,
                                  restingHr: nil, avgHrv: nil, stagesJSON: json))
        }
        let sri = SleepRegularityIndex.fromSessions(sessions)
        XCTAssertNotNil(sri)
        XCTAssertGreaterThan(sri!, 98)   // identical schedule across fine + coarse → still ~100
    }
}
