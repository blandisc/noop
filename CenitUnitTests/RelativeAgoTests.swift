import XCTest
@testable import Cenit

/// Unit tests for `relativeAgo`, the pure helper behind the "History synced N ago" sync-status
/// line. Verifies the bucketing — just-now / minutes / hours / days, the integer division, and the
/// future-time clamp — value-for-value with the Android RelativeAgoTest (ed6a31d). The wording
/// lives in `Localizable.xcstrings` (the app is es-only, so `relativeAgo` resolves to Spanish at
/// runtime), so each expectation asserts against the same `String(localized:)` template the helper
/// uses rather than a hard-coded English literal — that keeps the test green in any UI language.
final class RelativeAgoTests: XCTestCase {

    private let now: TimeInterval = 1_781_000_000

    private func ago(_ sec: TimeInterval) -> String { relativeAgo(now - sec, now: now) }

    func testUnderAMinuteIsJustNow() {
        XCTAssertEqual(ago(0), String(localized: "just now"))
        XCTAssertEqual(ago(59), String(localized: "just now"))
    }

    func testMinutes() {
        XCTAssertEqual(ago(60), String(localized: "\(1) min ago"))
        XCTAssertEqual(ago(5 * 60), String(localized: "\(5) min ago"))
        XCTAssertEqual(ago(59 * 60), String(localized: "\(59) min ago"))
    }

    func testHours() {
        XCTAssertEqual(ago(3600), String(localized: "\(1) h ago"))
        XCTAssertEqual(ago(23 * 3600), String(localized: "\(23) h ago"))
    }

    func testDays() {
        XCTAssertEqual(ago(86_400), String(localized: "\(1) d ago"))
        XCTAssertEqual(ago(3 * 86_400), String(localized: "\(3) d ago"))
    }

    func testFutureTimestampClampsToJustNow() {
        // Strap-clock skew could put lastSyncedAt slightly in the future; never render negative.
        XCTAssertEqual(relativeAgo(now + 500, now: now), String(localized: "just now"))
    }
}
