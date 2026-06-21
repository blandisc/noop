import XCTest
@testable import StrandAnalytics

final class EventTitleCleanerTests: XCTestCase {

    func testStripsStackedPrefixesAndCutsAtDoubleSlash() {
        XCTAssertEqual(
            EventTitleCleaner.clean("RE: FW: Revisión de diseño NOOP // Detalle de Estrés (Sala 4B)"),
            "Revisión de diseño NOOP")
    }

    func testStripsBracketTagAndCutsAtEmDash() {
        XCTAssertEqual(
            EventTitleCleaner.clean("[EXT] Weekly Business Review — Growth × Eng — Q3 OKR planning (pre-read!)"),
            "Weekly Business Review")
    }

    func testCutsAtParenAndStripsEmoji() {
        XCTAssertEqual(EventTitleCleaner.clean("Gym 🏋️ (no molestar)"), "Gym")
    }

    func testStripsTrailingEmojiOnly() {
        XCTAssertEqual(EventTitleCleaner.clean("Comida 🌮"), "Comida")
    }

    // Conservative: a single "/" is NOT a cut delimiter (would drop a person's name), only "//".
    func testKeepsSingleSlashName() {
        XCTAssertEqual(EventTitleCleaner.clean("1:1 Fernando / Aby Yépez 🗓️"), "1:1 Fernando / Aby Yépez")
    }

    func testStripsCanceledPrefix() {
        XCTAssertEqual(EventTitleCleaner.clean("Canceled: 1:1 Ana"), "1:1 Ana")
    }

    func testDropsTrailingMeetingLink() {
        XCTAssertEqual(EventTitleCleaner.clean("Daily Standup @ Google Meet"), "Daily Standup")
    }

    // If cleaning would empty the title, fall back to the trimmed original (never return "").
    func testFallsBackToOriginalWhenCleanedEmpty() {
        XCTAssertEqual(EventTitleCleaner.clean("RE:"), "RE:")
        XCTAssertEqual(EventTitleCleaner.clean("   "), "")
    }

    // A clean title passes through untouched.
    func testCleanTitleUnchanged() {
        XCTAssertEqual(EventTitleCleaner.clean("Comida"), "Comida")
    }
}
