import XCTest

/// Captures a screenshot of every main screen in NOOP and saves PNGs to ~/Desktop/noop-screenshots/.
/// Run via: xcodebuild test -scheme NOOPiOS -destination '...' -only-testing NOOPiOSUITests
final class NOOPScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    static let outputDir: URL = {
        // HOME env var is the Mac user home when the test runner executes on the host
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: home).appendingPathComponent("Desktop/noop-screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Skip onboarding, terms acceptance, What's New sheet, and restore nudge
        app.launchArguments += [
            "-noop.onboarded",               "YES",
            "-noop.acceptedTermsVersion",    "1.0",
            "-noop.lastSeenChangelogVersion","1.80",
            "-noop.didOfferRestore",         "YES",
        ]

        // Dismiss any system permission alert (HealthKit, Bluetooth) without blocking
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for label in ["Don't Allow", "Allow", "OK"] {
                let btn = alert.buttons[label]
                if btn.exists { btn.tap(); return true }
            }
            return false
        }

        app.launch()
        // Wait for the UI to settle after launch
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
    }

    // MARK: - Main test

    func test_captureAllScreens() throws {
        // ── Main tabs ─────────────────────────────────────────────────────────
        wait(1)
        snap("01_Today")

        tap(tab: "Trends");  wait(2); snap("02_Trends")
        tap(tab: "Live");    wait(2); snap("03_Live")
        tap(tab: "Sleep");   wait(2); snap("04_Sleep")
        tap(tab: "More");    wait(1); snap("05_More_list")

        // ── Screens inside the More list ──────────────────────────────────────
        let moreScreens: [(cell: String, file: String)] = [
            ("Intelligence",  "06_Intelligence"),
            ("Coach",         "07_Coach"),
            ("Insights",      "08_Insights"),
            ("Explore",       "09_MetricExplorer"),
            ("Compare",       "10_Compare"),
            ("Workouts",      "11_Workouts"),
            ("Health",        "12_Health"),
            ("Stress",        "13_Stress"),
            ("Breathe",       "14_Breathe"),
            ("Intervals",     "15_IntervalTimer"),
            ("Apple Health",  "16_AppleHealth"),
            ("Data Sources",  "17_DataSources"),
            ("Automations",   "18_Automations"),
            ("Settings",      "19_Settings"),
            ("Support",       "20_Support"),
        ]

        for (cell, file) in moreScreens {
            returnToMoreList()
            let row = app.staticTexts[cell]
            guard row.waitForExistence(timeout: 3) else {
                XCTFail("Cell '\(cell)' not found"); continue
            }
            row.tap()
            wait(2)
            app.swipeUp() // scroll to capture more content if any
            wait(1)
            snap(file)
        }
    }

    // MARK: - Helpers

    private func tap(tab: String) {
        app.tabBars.buttons[tab].tap()
    }

    private func returnToMoreList() {
        // If we're inside a pushed screen, pop back; then tap More
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists && backButton.isHittable {
            backButton.tap()
            wait(1)
        }
        if !app.navigationBars["More"].exists {
            tap(tab: "More")
            wait(1)
        }
    }

    private func wait(_ seconds: UInt32) {
        Thread.sleep(forTimeInterval: TimeInterval(seconds))
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()

        // Save to ~/Desktop/noop-screenshots/<name>.png
        let fileURL = Self.outputDir.appendingPathComponent("\(name).png")
        try? shot.image.pngData()?.write(to: fileURL)

        // Also attach to the Xcode test report
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
