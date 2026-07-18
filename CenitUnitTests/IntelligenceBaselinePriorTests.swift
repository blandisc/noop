import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// Pins the FER-60 Apple Health baseline prior: the pure helpers that fold Apple Health nights UNDER
/// the strap layers (lowest precedence, capped) so a brand-new strap user crosses
/// `Baselines.minNightsSeed` and recovery lights up from night 1 — without ever letting Apple Health
/// override the strap. Pure logic, mirroring the JournalLogicTests merge-precedence style.
final class IntelligenceBaselinePriorTests: XCTestCase {

    /// Minimal DailyMetric carrying just the fields the prior reads.
    private func dm(_ day: String, hrv: Double? = nil, rhr: Int? = nil, resp: Double? = nil) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, respRateBpm: resp)
    }

    // MARK: - applePriorDays (the cap)

    func testApplePriorDaysSelectsMostRecentNightsWithHrv() {
        // 10 Apple nights, day-ascending (the store read order). The cap keeps the newest 7.
        let rows = (1...10).map { dm(String(format: "2026-06-%02d", $0), hrv: 50 + Double($0)) }
        let days = IntelligenceEngine.applePriorDays(rows, maxNights: 7)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.contains("2026-06-10"))         // newest kept
        XCTAssertTrue(days.contains("2026-06-04"))         // boundary kept
        XCTAssertFalse(days.contains("2026-06-03"))        // older than the 7 most recent
        XCTAssertFalse(days.contains("2026-06-01"))
    }

    func testApplePriorDaysIgnoresNilHrvNights() {
        // Nights without a usable HRV don't count toward the cap (robust to gaps).
        let rows = [dm("2026-06-01", hrv: 55), dm("2026-06-02", hrv: nil), dm("2026-06-03", hrv: 60),
                    dm("2026-06-04", hrv: nil), dm("2026-06-05", hrv: 58)]
        let days = IntelligenceEngine.applePriorDays(rows, maxNights: 7)
        XCTAssertEqual(days, ["2026-06-01", "2026-06-03", "2026-06-05"])
    }

    func testApplePriorDaysCapNeverExceedsMaxNights() {
        let rows = (1...20).map { dm(String(format: "2026-06-%02d", $0), hrv: 55) }
        XCTAssertEqual(IntelligenceEngine.applePriorDays(rows, maxNights: 7).count, 7)
    }

    // MARK: - foldApplePrior (the precedence)

    func testStrapValueWinsOnCollision() {
        // Apple must never overwrite a day the strap already has.
        let strap: [String: Double?] = ["2026-06-10": 48.0]
        let apple: [String: Double?] = ["2026-06-10": 99.0, "2026-06-09": 60.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-10", "2026-06-09"])
        XCTAssertEqual(out["2026-06-10"] ?? nil, 48.0)     // strap wins
        XCTAssertEqual(out["2026-06-09"] ?? nil, 60.0)     // apple fills the uncovered day
        XCTAssertEqual(out.count, 2)
    }

    func testApplePriorOnlyFillsDaysInPriorDays() {
        // A day outside the capped set is left out even when the strap doesn't cover it.
        let strap: [String: Double?] = [:]
        let apple: [String: Double?] = ["2026-06-09": 60.0, "2026-06-08": 58.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-09"])
        XCTAssertEqual(out["2026-06-09"] ?? nil, 60.0)
        XCTAssertNil(out["2026-06-08"] ?? nil)             // not in priorDays → excluded
        XCTAssertEqual(out.count, 1)
    }

    func testPresentNilDayIsNotFilledByApple() {
        // The strap "owns" a night it recorded even if its HRV is nil — same `== nil` idiom as the
        // imported/computed merge: a present key (value nil) is NOT absent, so Apple must not fill it.
        var strap: [String: Double?] = [:]
        strap.updateValue(nil, forKey: "2026-06-10")       // key present, value nil
        let apple: [String: Double?] = ["2026-06-10": 55.0]
        let out = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                    priorDays: ["2026-06-10"])
        XCTAssertEqual(out.count, 1)
        XCTAssertNil(out["2026-06-10"] ?? nil)             // still nil, not 55
    }

    // MARK: - End-to-end mechanism (pure): prior → provisional baseline → recovery scores

    func testApplePriorSeedsProvisionalUsableBaselineThatScores() {
        // One strap night alone can't clear minNightsSeed (4). A 6-night Apple prior seeds the gap.
        let strap: [String: Double?] = ["2026-06-13": 52.0]
        let apple: [String: Double?] = ["2026-06-07": 60, "2026-06-08": 58, "2026-06-09": 61,
                                        "2026-06-10": 59, "2026-06-11": 57, "2026-06-12": 62]
        let merged = IntelligenceEngine.foldApplePrior(into: strap, apple: apple,
                                                       priorDays: Set(apple.keys))
        XCTAssertEqual(merged.count, 7)

        // Fold chronologically (lexicographic ISO day == chronological) → baseline crosses the gate.
        let seq = merged.keys.sorted().map { merged[$0]! }
        let state = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertTrue(state.usable, "7 seeded nights must clear the seed gate")
        XCTAssertEqual(state.status, .provisional, "capped prior stays provisional, not trusted")

        // Recovery now lights up (was nil under 4 nights), shrunk by the provisional confidence.
        let score = RecoveryScorer.recovery(
            hrv: 52, rhr: 55, resp: nil,
            hrvBaseline: RecoveryScorer.DriverBaseline(state),
            rhrBaseline: nil, respBaseline: nil, sleepPerf: nil,
            hrvBaselineUsable: state.usable)
        XCTAssertNotNil(score, "recovery lights up once the baseline is seeded")
    }

    // MARK: - strapOnlyHistory (FER-519): Apple SDNN must never enter the RMSSD baseline

    func testStrapOnlyHistoryExcludesAppleOnlyDaysAndIsIdentityWhenEmpty() {
        // hist holds two strap nights and one Apple-only night (band-less, its avgHrv is SDNN).
        let hist = [dm("2026-06-09", hrv: 80), dm("2026-06-10", hrv: 45), dm("2026-06-11", hrv: 46)]
        let appleOnly: Set<String> = ["2026-06-09"]

        let strap = IntelligenceEngine.strapOnlyHistory(hist, appleHealthDays: appleOnly)
        XCTAssertEqual(strap.map(\.day), ["2026-06-10", "2026-06-11"], "Apple-only day dropped")
        XCTAssertFalse(strap.contains { $0.day == "2026-06-09" })

        // Regression zero: no Apple-only days ⇒ identity (the strap-only / whoopOnly user is untouched).
        XCTAssertEqual(IntelligenceEngine.strapOnlyHistory(hist, appleHealthDays: []).map(\.day),
                       hist.map(\.day))
    }

    func testAppleOnlyDaysDoNotMoveTheRmssdBaseline() {
        // Strap RMSSD nights (~45 ms) interleaved with Apple-only SDNN nights (~80 ms — a different,
        // higher-scale construct). The fix must fold the strap-only slice; folding `hist` raw would drag
        // the RMSSD center toward the SDNN values.
        let strapNights = [dm("2026-06-10", hrv: 45), dm("2026-06-11", hrv: 46),
                           dm("2026-06-12", hrv: 44), dm("2026-06-13", hrv: 45)]
        let appleOnlyNights = [dm("2026-06-06", hrv: 80), dm("2026-06-07", hrv: 82),
                               dm("2026-06-08", hrv: 78), dm("2026-06-09", hrv: 81)]
        let hist = appleOnlyNights + strapNights            // chronological (oldest→newest)
        let appleOnly = Set(appleOnlyNights.map(\.day))

        let cleanFold = Baselines.foldHistory(
            IntelligenceEngine.strapOnlyHistory(hist, appleHealthDays: appleOnly).map { $0.avgHrv },
            cfg: Baselines.hrvCfg)
        // A user who never had any Apple-only days — the regression-zero reference.
        let referenceFold = Baselines.foldHistory(strapNights.map { $0.avgHrv }, cfg: Baselines.hrvCfg)
        // The buggy path: fold everything, Apple SDNN included.
        let contaminatedFold = Baselines.foldHistory(hist.map { $0.avgHrv }, cfg: Baselines.hrvCfg)

        XCTAssertEqual(cleanFold.baseline, referenceFold.baseline, accuracy: 1e-9,
                       "excluding Apple-only days == never having had them (regression zero)")
        XCTAssertEqual(cleanFold.nValid, 4, "only the 4 strap nights feed the RMSSD baseline")
        XCTAssertGreaterThan(contaminatedFold.baseline, cleanFold.baseline + 0.5,
                             "without the fix, Apple SDNN drags the RMSSD center upward — the bug")
    }

    func testRespPriorStaysCappedAfterAppleOnlyDaysAreExcluded() {
        // FER-634: RHR is no longer seeded from Apple (band sleep-nadir vs Apple awake differ ~10–13 bpm);
        // RESPIRATION is the sole remaining metric that keeps the Apple prior (breaths/min during sleep,
        // same metric across sources). The cap-bypass half of the bug still applies to resp: when Apple-only
        // days sit in `hist`, they're already PRESENT in histRespByDay (non-nil), so foldApplePrior's
        // `== nil` gate skips them → ALL of them enter, uncapped. Excluding them first (strapOnlyHistory)
        // restores the FER-60 cap for respiration.
        let strapNight = dm("2026-06-20", resp: 14)
        let appleOnlyNights = (1...10).map { dm(String(format: "2026-06-%02d", $0), resp: 16) }
        let hist = appleOnlyNights + [strapNight]
        let appleOnly = Set(appleOnlyNights.map(\.day))

        // BUGGY (no exclusion): every Apple resp day is present in the strap dict → foldApplePrior adds
        // nothing → all 11 days enter the baseline, the 7-night cap bypassed.
        var buggyResp: [String: Double?] = [:]
        for d in hist { buggyResp[d.day] = d.respRateBpm }
        let appleResp = Dictionary(uniqueKeysWithValues: appleOnlyNights.map { ($0.day, Optional($0.respRateBpm!)) })
        let priorDays = IntelligenceEngine.applePriorDays(appleOnlyNights, maxNights: IntelligenceEngine.applePriorMaxNights)
        // applePriorDays gates on avgHrv; these rows have no HRV, so the prior set is empty — but they're
        // all already present in buggyResp regardless, which is exactly the leak.
        let buggyFolded = IntelligenceEngine.foldApplePrior(into: buggyResp, apple: appleResp, priorDays: priorDays)
        XCTAssertEqual(buggyFolded.count, 11, "without the fix, all Apple-only resp days leak in uncapped")

        // FIXED: exclude Apple-only days first, then the capped prior governs how many re-enter.
        let strap = IntelligenceEngine.strapOnlyHistory(hist, appleHealthDays: appleOnly)
        var fixedResp: [String: Double?] = [:]
        for d in strap { fixedResp[d.day] = d.respRateBpm }
        XCTAssertEqual(fixedResp.count, 1, "only the strap night seeds resp before the prior")
        // With the prior set capped to 7, at most 7 Apple days could re-enter (here the prior set is
        // HRV-gated; the invariant is that the strap dict no longer pre-contains the Apple days).
        let cappedPrior = Set(appleOnlyNights.suffix(IntelligenceEngine.applePriorMaxNights).map(\.day))
        let fixedFolded = IntelligenceEngine.foldApplePrior(into: fixedResp, apple: appleResp, priorDays: cappedPrior)
        XCTAssertLessThanOrEqual(fixedFolded.count, 1 + IntelligenceEngine.applePriorMaxNights,
                                 "the strap night + at most applePriorMaxNights capped Apple days")
        XCTAssertEqual(fixedFolded.count, 8, "1 strap + 7 capped Apple resp days (cap restored)")
    }
}
