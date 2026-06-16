import XCTest
@testable import NOOP

/// Pins `BLEManager.plausibleDataRange` — the validation that stops the "On the band" sync diagnostic
/// from showing GET_DATA_RANGE garbage (FER-150). The bug it guards: the old raw u32 scan kept any word
/// in a fixed nov-2023 → mar-2030 window, so the WHOOP 4.0's unstable RTC produced future dates
/// ("2029-10-11") and collapsed single-point ranges ("mar 15, 2025 → mar 15, 2025"). The validated
/// version returns a window ONLY when it's plausible (in the past, oldest < newest), else nil → "—".
final class DataRangePlausibilityTests: XCTestCase {

    /// A GET_DATA_RANGE frame: a 7-byte header (ignored — the scan starts at frame[7]) followed by the
    /// given values as u32 LE words, exactly how the strap packs them in the response body.
    private func frame(words: [Int]) -> [UInt8] {
        var bytes: [UInt8] = [0, 0, 0, 0, 0, 0, 0]   // [type, seq, cmd, …] header, contents irrelevant
        for w in words {
            bytes.append(UInt8(w & 0xFF))
            bytes.append(UInt8((w >> 8) & 0xFF))
            bytes.append(UInt8((w >> 16) & 0xFF))
            bytes.append(UInt8((w >> 24) & 0xFF))
        }
        return bytes
    }

    private let now = 1_750_000_000   // 2025-06-15, the fixed "now" for these deterministic cases
    private let day = 86_400

    // MARK: - the happy path

    func testTwoDistinctPastTimestampsBoundTheWindow() {
        let oldest = now - 30 * day, newest = now - day
        let r = BLEManager.plausibleDataRange(from: frame(words: [newest, oldest]), now: now)
        XCTAssertEqual(r?.oldest, oldest)
        XCTAssertEqual(r?.newest, newest)
    }

    func testManyWordsTakesMinAndMax() {
        let words = [now - 5 * day, now - 100 * day, now - day, now - 50 * day]
        let r = BLEManager.plausibleDataRange(from: frame(words: words), now: now)
        XCTAssertEqual(r?.oldest, now - 100 * day)
        XCTAssertEqual(r?.newest, now - day)
    }

    // MARK: - FER-150 criterion: no collapsed single-point ranges

    func testSinglePlausibleWordIsRejectedAsCollapsed() {
        // Exactly the observed bug shape: only one word survives → oldest == newest → not real history.
        XCTAssertNil(BLEManager.plausibleDataRange(from: frame(words: [now - day]), now: now))
    }

    func testRepeatedSameValueIsCollapsed() {
        XCTAssertNil(BLEManager.plausibleDataRange(from: frame(words: [now - day, now - day]), now: now))
    }

    // MARK: - FER-150 criterion: no future dates

    func testFutureWordsAreFiltered() {
        // "2029-10-11"-style junk sits above the ceiling and must not bound the window. Here only one
        // genuine past word remains after filtering → collapsed → nil (no garbage window shown).
        let future = 1_855_000_000   // ≈ 2028
        XCTAssertNil(BLEManager.plausibleDataRange(from: frame(words: [future, now - day]), now: now))
    }

    func testFuturePlusTwoPastWordsKeepsOnlyThePast() {
        let future = 1_855_000_000
        let r = BLEManager.plausibleDataRange(from: frame(words: [future, now - 2 * day, now - 10 * day]), now: now)
        XCTAssertEqual(r?.oldest, now - 10 * day)
        XCTAssertEqual(r?.newest, now - 2 * day)
    }

    func testWordWithinSkewToleranceIsAccepted() {
        // A newest a few hours ahead of `now` (benign RTC skew) still counts — only year-scale future is junk.
        let r = BLEManager.plausibleDataRange(from: frame(words: [now + 3600, now - day]), now: now)
        XCTAssertEqual(r?.newest, now + 3600)
        XCTAssertEqual(r?.oldest, now - day)
    }

    // MARK: - non-timestamp noise

    func testWordsBelowEarliestAreIgnored() {
        // Small u32s (counters, ids) are below the unix floor and must not be read as dates.
        XCTAssertNil(BLEManager.plausibleDataRange(from: frame(words: [42, 1000, now - day]), now: now))
    }

    func testEmptyAndShortFramesReturnNil() {
        XCTAssertNil(BLEManager.plausibleDataRange(from: [0, 0, 0], now: now))
        XCTAssertNil(BLEManager.plausibleDataRange(from: [], now: now))
        XCTAssertNil(BLEManager.plausibleDataRange(from: frame(words: []), now: now))
    }
}
