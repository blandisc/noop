import XCTest
@testable import Cenit

/// Pins the FER-406 trigger fix: after a completed backfill the on-device recompute must fire
/// (event-driven), coalesce the morning burst of completions into ONE pass, and respect the FER-177
/// guard (never run while a backfill/import is writing). Both seams are pure/instance-free so they
/// verify headless, the way the repo pins `Repository.mergeDaily` / `BLEManager.syncSessionOutcome`.
final class BackfillRecomputeTests: XCTestCase {

    /// Thread-safe run counter for the async debounce tests.
    private actor Counter {
        private(set) var count = 0
        func inc() { count += 1 }
    }

    // MARK: - Guard (FER-177): recompute only while the strap/import is quiet

    func testGuardBlocksWhileBackfilling() {
        XCTAssertFalse(AppModel.mayRecomputeAfterBackfill(backfilling: true, hasActiveImport: false),
                       "must not run the heavy pass while a backfill is writing on the main actor")
    }

    func testGuardBlocksWhileImporting() {
        XCTAssertFalse(AppModel.mayRecomputeAfterBackfill(backfilling: false, hasActiveImport: true))
    }

    func testGuardBlocksWhileBoth() {
        XCTAssertFalse(AppModel.mayRecomputeAfterBackfill(backfilling: true, hasActiveImport: true))
    }

    func testGuardAllowsWhenQuiet() {
        XCTAssertTrue(AppModel.mayRecomputeAfterBackfill(backfilling: false, hasActiveImport: false),
                      "a settled strap with no import must let the recompute run")
    }

    // MARK: - Debounce coalescing (the ~6 completions/60 s morning burst → ONE pass)

    /// A burst of cancel-and-reschedule calls (exactly what `scheduleRecomputeAfterBackfill` does on each
    /// completion) must collapse to a SINGLE action run — not one per completion.
    func testDebounceCoalescesBurstIntoOneRun() async {
        let counter = Counter()
        var task: Task<Void, Never>?
        for _ in 0..<6 {
            task?.cancel()                                              // each completion replaces the prior
            task = AppModel.debounced(after: 40_000_000) { await counter.inc() }   // 40 ms
        }
        await task?.value
        let n = await counter.count
        XCTAssertEqual(n, 1, "a 6-completion burst must run analyzeRecent exactly once, not 6×")
    }

    /// A single completion runs the action once after the delay.
    func testDebounceRunsOnceAfterDelay() async {
        let counter = Counter()
        let task = AppModel.debounced(after: 20_000_000) { await counter.inc() }
        await task.value
        let n = await counter.count
        XCTAssertEqual(n, 1)
    }

    /// Cancelling before the delay elapses (teardown / app background) must skip the action entirely.
    func testDebounceCancelledBeforeDelayDoesNotRun() async {
        let counter = Counter()
        let task = AppModel.debounced(after: 60_000_000) { await counter.inc() }
        task.cancel()
        _ = await task.value
        let n = await counter.count
        XCTAssertEqual(n, 0, "a cancelled debounce (teardown) must not run the recompute")
    }
}
