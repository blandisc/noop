import XCTest
import HealthKit
@testable import Cenit

/// FER-1004 — the structural guard against Cénit re-reading its own write-back.
///
/// Cénit mirrors derived metrics INTO Apple Health: `writeBack` saves resting HR, HRV, SpO2 and
/// respiratory rate plus the staged hypnogram, and `saveStrengthWorkout` saves an `HKWorkout` per
/// strength session. Every READ therefore has to exclude this app's own source, or the next sync
/// pulls those samples straight back in as if Apple had measured them.
///
/// Two things went wrong when it did:
///   1. The Apple baselines that `DailyStressModel` z-scores against
///      were fed the band's own numbers — and `writeBack` mirrors the band's RMSSD under Apple's
///      *SDNN* identifier, so the value coming back was mislabelled on top of being foreign. Same
///      contamination class as FER-519/623/629/631/632/633/635/639/640/670/882, reached through
///      the mirror instead of the merge.
///   2. `mapWorkouts` labels everything it receives `source: "apple-health"` unconditionally, so
///      each strength session came back as a second, Apple-branded copy of a workout the app
///      already owned.
///
/// That failure mode has now recurred eleven times through the merge path, always the same way:
/// someone adds a new read and forgets the guard. A comment cannot prevent a twelfth. This test
/// reads the source file and fails the build if a raw date-only read predicate reappears anywhere
/// outside `readPredicate`, which is the only sanctioned way to build one.
final class HealthKitReadPredicateGuardTests: XCTestCase {

    /// `<repo>/CenitApp/Health/HealthKitBridge.swift`, derived from this file's own location so the
    /// test survives being run from a worktree or a different checkout.
    private var bridgeSource: String {
        get throws {
            let repoRoot = URL(fileURLWithPath: #filePath)   // …/CenitUnitTests/<this file>.swift
                .deletingLastPathComponent()                 // …/CenitUnitTests
                .deletingLastPathComponent()                 // …/<repo>
            let url = repoRoot.appendingPathComponent("CenitApp/Health/HealthKitBridge.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: - Behaviour

    /// The helper must AND the date window with the NEGATION of "samples from this app".
    func testReadPredicateExcludesThisAppsOwnSamples() throws {
        let p = HealthKitBridge.readPredicate(start: Date(timeIntervalSince1970: 0),
                                              end: Date(timeIntervalSince1970: 86_400))
        let root = try XCTUnwrap(p as? NSCompoundPredicate,
                                 "readPredicate must return a compound predicate, not a bare date one.")
        XCTAssertEqual(root.compoundPredicateType, .and)
        XCTAssertEqual(root.subpredicates.count, 2, "Expected exactly [date, NOT(our source)].")

        let negations = root.subpredicates
            .compactMap { $0 as? NSCompoundPredicate }
            .filter { $0.compoundPredicateType == .not }
        XCTAssertEqual(negations.count, 1,
                       "readPredicate must carry exactly one NOT subpredicate — the source exclusion.")
        XCTAssertEqual(try XCTUnwrap(negations.first).subpredicates.count, 1)
    }

    /// Two different windows must still each be scoped — the exclusion is not built once and cached.
    func testExclusionIsPresentForEveryWindow() throws {
        for days in [1, 14, 30] {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end)!
            let p = try XCTUnwrap(HealthKitBridge.readPredicate(start: start, end: end) as? NSCompoundPredicate)
            let hasNegation = p.subpredicates
                .compactMap { $0 as? NSCompoundPredicate }
                .contains { $0.compoundPredicateType == .not }
            XCTAssertTrue(hasNegation, "\(days)-day window lost its source exclusion.")
        }
    }

    // MARK: - Structural guard

    /// Code with comments stripped and ALL whitespace removed.
    ///
    /// Both steps are load-bearing, and the second one was a real hole: counting the raw literal
    /// `"HKQuery.predicateForSamples(withStart"` missed the identical call wrapped across two lines —
    /// which is this file's own formatting style (see the `HKSampleQuery(...)` calls). A guard that a
    /// line break defeats is not a guard. Normalising first makes the count formatting-independent.
    private func normalisedCode(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                // Drop trailing `//` comments (and whole comment lines) so prose mentioning the API
                // — including this test's own doc comments over in the bridge — never counts as code.
                guard let slashes = line.range(of: "//") else { return line }
                return line[line.startIndex..<slashes.lowerBound]
            }
            .joined()
            .filter { !$0.isWhitespace }
    }

    /// The one that actually holds the line: a raw `predicateForSamples` may appear EXACTLY once in
    /// the file — inside `readPredicate` itself. A second occurrence means someone added a read that
    /// bypasses the guard, and this test names it before it ships.
    func testNoRawDatePredicateOutsideTheHelper() throws {
        let code = normalisedCode(try bridgeSource)
        let occurrences = code.components(separatedBy: "HKQuery.predicateForSamples(").count - 1
        XCTAssertEqual(occurrences, 1, """
            HealthKitBridge must build read predicates ONLY through `readPredicate(start:end:options:)`, \
            which excludes this app's own samples (FER-1004). Found \(occurrences) raw \
            `HKQuery.predicateForSamples(` call(s) in code; exactly 1 is allowed (the helper itself). \
            If you added a HealthKit read, route it through the helper.

            NOTE this guard watches `predicateForSamples` only. Two reads sit outside it by design and \
            are NOT covered: `mostRecentQuantity` (predicate: nil — body mass / height, which Cénit \
            never writes) and the per-workout `predicateForObjects(from: w)` (already scoped by a \
            workout the helper filtered). If Cénit ever starts mirroring body mass, the first one \
            becomes a contamination path this test will not catch.
            """)
        XCTAssertTrue(try bridgeSource.contains("nonisolated static func readPredicate(start: Date, end: Date"),
                      "`readPredicate` was renamed or removed — this guard is now blind. Update it.")
    }

    /// The guard must survive this file's own formatting. `HealthKitBridge` wraps long calls across
    /// lines routinely, so a counter that only matches the single-line form would go blind exactly
    /// where a real bypass is most likely to land. Proves the normalisation actually normalises.
    func testGuardSeesAWrappedCallTheSameAsASingleLineOne() {
        let singleLine = "let p = HKQuery.predicateForSamples(withStart: a, end: b, options: [])"
        let wrapped = """
            let p = HKQuery.predicateForSamples(
                withStart: a, end: b, options: [])
            """
        let commentedOut = "// HKQuery.predicateForSamples(withStart: a, end: b, options: [])"

        XCTAssertEqual(normalisedCode(singleLine).components(separatedBy: "HKQuery.predicateForSamples(").count - 1, 1)
        XCTAssertEqual(normalisedCode(wrapped).components(separatedBy: "HKQuery.predicateForSamples(").count - 1, 1,
                       "A wrapped call must count the same as a single-line one — that was the hole.")
        XCTAssertEqual(normalisedCode(commentedOut).components(separatedBy: "HKQuery.predicateForSamples(").count - 1, 0,
                       "Prose about the API must not count as a call.")
    }

    /// Every read site that previously built its own date predicate now goes through the helper.
    /// Covers the four we fixed: quantity aggregates, sleep totals, sleep samples, workouts.
    func testAllKnownReadSitesUseTheHelper() throws {
        let source = try bridgeSource
        let callSites = source.components(separatedBy: "Self.readPredicate(").count - 1
        XCTAssertGreaterThanOrEqual(callSites, 4, """
            Expected at least 4 `Self.readPredicate(` call sites (collect, collectSleep, \
            collectSleepSamples, collectHKWorkouts). Found \(callSites) — did a read lose its guard?
            """)
    }

    /// The write path keeps scoping its DELETEs to our own source. The guard is symmetric: reads
    /// exclude us, writes only ever delete us. Losing this would make write-back delete Apple's data.
    func testWritePathStillScopesDeletesToOurOwnSource() throws {
        let source = try bridgeSource
        let scoped = source.components(separatedBy: "HKQuery.predicateForObjects(from: HKSource.default())").count - 1
        XCTAssertGreaterThanOrEqual(scoped, 3, """
            The write path must keep scoping deletes to `HKSource.default()` — one per delete site \
            (strength workout, quantity mirror, sleep mirror). Found \(scoped).
            """)
    }
}
