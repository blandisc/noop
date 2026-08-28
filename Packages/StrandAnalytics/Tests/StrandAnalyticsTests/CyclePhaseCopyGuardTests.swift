import XCTest

// CyclePhaseCopyGuardTests.swift — the guard against «Fase del ciclo»'s copy drifting into a hard
// medical claim (FER-184).
//
// `Cenit/Screens/CyclePhaseView.swift` says, in its own header comment, that the phase reading is a
// rough, hedged estimate — never a contraceptive method, a fertility/ovulation predictor, or a
// diagnosis. This test reads that SOURCE FILE AS TEXT (the same technique
// `HealthKitReadPredicateGuardTests` uses for `HealthKitBridge.swift`) and enforces the contract two
// ways: the required hedges/negations must survive verbatim, and no positive hard-claim phrasing may
// ever sneak in — regardless of how the surrounding sentences get reworded. It lives here, in the
// Foundation-only StrandAnalytics package, rather than in CenitUnitTests, so it runs in the fast
// `swift test` loop with no simulator/app build needed.
//
// FER-184 also rewrote every "band" mention in the sheet to "Apple Watch" (Cénit never shipped a
// strap; the copy used to imply one) and added the real Apple Watch coverage limits (Series 8+/Ultra,
// worn to bed, ~5 nights to start) to the learning/no-signal states. Both are guarded here too.
final class CyclePhaseCopyGuardTests: XCTestCase {

    /// `<repo>/Cenit/Screens/CyclePhaseView.swift`, derived from this file's own location so the test
    /// survives being run from a worktree or a different checkout.
    private var viewSource: String {
        get throws {
            let repoRoot = URL(fileURLWithPath: #filePath)   // …/StrandAnalyticsTests/<this file>.swift
                .deletingLastPathComponent()                  // …/StrandAnalyticsTests
                .deletingLastPathComponent()                  // …/Tests
                .deletingLastPathComponent()                  // …/StrandAnalytics
                .deletingLastPathComponent()                  // …/Packages
                .deletingLastPathComponent()                  // …/<repo>
            let url = repoRoot.appendingPathComponent("Cenit/Screens/CyclePhaseView.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: - Required hedges (must survive any copy rewrite)

    /// The four "what it doesn't do" negations, the "probably"/"approximate" softeners on the reading
    /// itself, and the 1-3 day confirmation lag — all load-bearing, all must stay word for word.
    func testRequiredHedgesArePresent() throws {
        let source = try viewSource
        let requiredHedges = [
            "not a contraceptive method",
            "doesn't predict your fertile days or your ovulation",
            "doesn't diagnose pregnancy or any health condition",
            "doesn't tell you which day your next period starts",
            "probably",
            "approximate",
            "one to three days",
        ]
        for hedge in requiredHedges {
            XCTAssertTrue(source.localizedCaseInsensitiveContains(hedge),
                          "Missing required hedge: \"\(hedge)\". CyclePhaseView must keep every hard-claim denial word for word.")
        }
    }

    // MARK: - No hard claim frame

    /// Phrases that would turn the hedged estimate into a positive fertility/contraception/diagnosis
    /// claim. None of these may ever appear, no matter how the surrounding copy gets reworded — this
    /// is distinct from the required hedges above, which use the SAME root words (fertile, ovulation,
    /// contraceptive) but only inside a negation.
    func testNoHardClaimPhrasing() throws {
        let source = try viewSource.lowercased()
        let forbidden = [
            "fertile window", "fertility window", "ovulation day", "predicts ovulation",
            "predicts your fertile", "birth control", "contraceptive alternative",
            "family planning", "when you'll ovulate", "diagnoses", "diagnosis of",
            "medical diagnosis", "safe days", "unsafe days", "conceive", "pregnancy test",
        ]
        for phrase in forbidden {
            XCTAssertFalse(source.contains(phrase),
                           "Forbidden hard-claim phrase found: \"\(phrase)\". Fase del ciclo must never read as a fertility/contraception/diagnosis claim.")
        }
    }

    // MARK: - FER-184: no band left in the copy

    /// FER-184 moved the input from a discontinued strap to the Apple Watch's own wrist temperature.
    /// Every "band" mention — copy AND comments — must be gone: this is the honesty bug the issue
    /// exists to fix (naming hardware no Cénit user was ever sold).
    func testNoBandMentionsRemain() throws {
        let source = try viewSource
        let bandWord = try NSRegularExpression(pattern: "\\bband\\b", options: .caseInsensitive)
        let range = NSRange(source.startIndex..., in: source)
        let count = bandWord.numberOfMatches(in: source, range: range)
        XCTAssertEqual(count, 0,
                       "Found \(count) \"band\" mention(s) in CyclePhaseView.swift; FER-184 requires all of them rewritten to Apple Watch.")
    }

    // MARK: - FER-184: Apple coverage limits stated

    /// The learning and no-signal states must set the real Apple Watch expectation (model, worn-to-bed,
    /// warm-up nights) instead of leaving the user to wonder why nothing is happening.
    func testAppleCoverageLimitsArePresent() throws {
        let source = try viewSource
        for phrase in ["Series 8", "Ultra", "5 nights", "worn to bed"] {
            XCTAssertTrue(source.contains(phrase),
                          "Missing Apple coverage limit \"\(phrase)\": the learning/no-signal copy must state the real Apple Watch requirements (FER-184).")
        }
    }

    // MARK: - No sex gate

    /// The experiment must not gate on a binary-sex profile field — the copy speaks to whoever turns
    /// it on, not to a sex assumption read from onboarding.
    func testDoesNotGateOnSex() throws {
        let source = try viewSource
        XCTAssertFalse(source.localizedCaseInsensitiveContains("profile.sex"),
                       "CyclePhaseView must not read a sex field to gate the experiment (FER-184: no binary-sex gate).")
    }
}
