import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-8 · Veredicto v4 Fase 5 — the illness sentinel (temp∧resp) now carries STREAK memory, exposed
/// on `Read.sentinel`. The streak is COPY only: it never changes the verdict (the existing frozen
/// Preparedness suites stay green unedited — that is the bit-identical-vote guarantee). These tests
/// pin the state machine, calendar contiguity, and the reset semantics.
final class PreparednessSentinelStreakTests: XCTestCase {

    // MARK: Fixtures (mirror PreparednessV3InputsTests)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    /// 20 calm nights (June 1–20): normal autonomic, temp 0, resp ~14 → sentinel quiet, baselines mature.
    private func baseline() -> [DailyMetric] {
        (1...20).map { i in
            dm(String(format: "2026-06-%02d", i),
               hrv: 52 + Double(i % 5), rhr: 54 + i % 3, resp: 13 + Double(i % 3), temp: 0.0)
        }
    }

    // Event nights (autonomic + sleep stay normal, so ONLY the sentinel signals move):
    private func corroborated(_ day: String) -> DailyMetric { dm(day, resp: 18, temp: 0.9) } // temp∧resp out
    private func watchingTemp(_ day: String)  -> DailyMetric { dm(day, resp: 14, temp: 0.9) } // temp only
    private func watchingResp(_ day: String)  -> DailyMetric { dm(day, resp: 18, temp: 0.0) } // resp only
    private func quiet(_ day: String)         -> DailyMetric { dm(day, resp: 14, temp: 0.0) }

    private func sentinel(_ days: [DailyMetric], asOf: String) -> Preparedness.SentinelRead? {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                                    nocturnalRestingHr: [:], cyclePhase: nil, nocturnalRmssd: nil)).sentinel
    }

    private var noHyst: Preparedness.Config {
        var c = Preparedness.Config(); c.hysteresisDays = 1; return c
    }

    private func verdict(_ days: [DailyMetric], asOf: String,
                         config: Preparedness.Config = .default) -> Preparedness.Verdict {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: nil, asOf: asOf,
                                    nocturnalRestingHr: [:], cyclePhase: nil, nocturnalRmssd: nil),
                              config: config).verdict
    }

    // MARK: CA2 — corroborated streak

    func testCA2_corroboratedStreak3() throws {
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22"), corroborated("2026-06-23")]
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-23"))
        XCTAssertEqual(s.state, .corroborated)
        XCTAssertEqual(s.streakNights, 3)
        XCTAssertTrue(s.tempOut && s.respOut)
    }

    // MARK: CA3 — a single signal never votes, even in a streak (with the numeric fixture)

    func testCA3_watchingTempDoesNotVote() throws {
        let event = [watchingTemp("2026-06-21"), watchingTemp("2026-06-22"), watchingTemp("2026-06-23")]
        let days = baseline() + event
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-23"))
        XCTAssertEqual(s.state, .watchingOneSignal)
        XCTAssertEqual(s.watchingSignal, .temp)
        XCTAssertEqual(s.streakNights, 3)
        // Sanity: the verdict is identical to those three nights being quiet (watching never votes).
        let quietDays = baseline() + [quiet("2026-06-21"), quiet("2026-06-22"), quiet("2026-06-23")]
        XCTAssertEqual(verdict(days, asOf: "2026-06-23"), verdict(quietDays, asOf: "2026-06-23"))
    }

    // MARK: CA4 — corroborated → watching resets to 1

    func testCA4_corroboratedThenWatching() throws {
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22"), watchingTemp("2026-06-23")]
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-23"))
        XCTAssertEqual(s.state, .watchingOneSignal)
        XCTAssertEqual(s.streakNights, 1)
    }

    // MARK: CA5 — signal flip resets to 1

    func testCA5_signalFlip() throws {
        let days = baseline() + [watchingTemp("2026-06-21"), watchingResp("2026-06-22")]
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-22"))
        XCTAssertEqual(s.state, .watchingOneSignal)
        XCTAssertEqual(s.watchingSignal, .resp)
        XCTAssertEqual(s.streakNights, 1)
    }

    // MARK: CA6 — a CALENDAR gap ends the streak (not index adjacency)

    func testCA6_calendarGapBreaks() throws {
        // 06-21 and 06-24 corroborated, with 22 & 23 ABSENT (not nil rows) — the common production case.
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-24")]
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-24"))
        XCTAssertEqual(s.state, .corroborated)
        XCTAssertEqual(s.streakNights, 1)   // 3-day jump breaks; index adjacency would wrongly give 2
    }

    // MARK: CA7 — quiet → streak 0

    func testCA7_quietStreakZero() throws {
        let s = try XCTUnwrap(sentinel(baseline(), asOf: "2026-06-20"))
        XCTAssertEqual(s.state, .quiet)
        XCTAssertEqual(s.streakNights, 0)
    }

    // MARK: CA8 — a quiet night resets the streak

    func testCA8_quietResets() throws {
        let days = baseline() + [corroborated("2026-06-21"), quiet("2026-06-22"), corroborated("2026-06-23")]
        let s = try XCTUnwrap(sentinel(days, asOf: "2026-06-23"))
        XCTAssertEqual(s.streakNights, 1)   // the quiet 06-22 breaks the run
    }

    // MARK: CA1 sanity — streak length does NOT change the vote

    func testStreakLengthDoesNotVote() {
        // Under no hysteresis (so the raw day shows), a corroborated night votes ONCE (→ caution)
        // whether it's night 1 or night 3 of a streak — the streak adds no vote.
        let three = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22"), corroborated("2026-06-23")]
        let one = baseline() + [corroborated("2026-06-21")]
        XCTAssertEqual(verdict(three, asOf: "2026-06-23", config: noHyst), .caution)
        XCTAssertEqual(verdict(one, asOf: "2026-06-21", config: noHyst), .caution)
    }

    // MARK: CA10 — deterministic

    func testDeterministic() {
        let days = baseline() + [corroborated("2026-06-21"), corroborated("2026-06-22")]
        XCTAssertEqual(sentinel(days, asOf: "2026-06-22"), sentinel(days, asOf: "2026-06-22"))
    }

    // MARK: nil when the asOf night has neither temp nor resp

    func testNilWhenNoTempNorResp() {
        let days = baseline() + [dm("2026-06-21", resp: nil, temp: nil)]
        XCTAssertNil(sentinel(days, asOf: "2026-06-21"))
    }
}
