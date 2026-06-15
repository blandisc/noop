import XCTest

/// Captures a screenshot of every main screen in NOOP and saves PNGs to docs/fixtures/.
/// The HTML screen map at docs/screen-map.html loads these as thumbnails.
///
/// Run (no simulator pre-launch needed — xcodebuild boots one):
///   GIT_CONFIG=/dev/null xcodebuild test \
///     -project Strand.xcodeproj -scheme NOOPiOS \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     CODE_SIGNING_ALLOWED=NO \
///     -only-testing NOOPiOSUITests/NOOPScreenshotTests
///
/// Maintenance: when you add/remove/rename a state in a *View.swift, add/update the
/// corresponding case here and re-run to regenerate the fixtures in the same PR.
final class NOOPScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    // docs/fixtures/ relative to repo root (SRCROOT is set by Xcode in both unit and UI test runners)
    static let outputDir: URL = {
        let root: URL
        if let s = ProcessInfo.processInfo.environment["SRCROOT"], !s.isEmpty {
            root = URL(fileURLWithPath: s)
        } else {
            // Fallback for manual runs: write next to the test file
            let home = ProcessInfo.processInfo.environment["HOME"] ?? NSTemporaryDirectory()
            root = URL(fileURLWithPath: home).appendingPathComponent("code/noop")
        }
        let dir = root.appendingPathComponent("docs/fixtures")
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
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 8)
    }

    // MARK: - Today (three verdict states)

    /// Each state is its OWN test so a permission alert in one doesn't block the others.
    /// Run on an ERASED simulator for a clean store: `xcrun simctl erase <udid>`.
    func test_today_empty()    throws { captureToday(state: "empty") }
    func test_today_primed()   throws { captureToday(state: "primed") }
    func test_today_strained() throws { captureToday(state: "strained") }

    // MARK: - All screens (empty/default state)

    func test_captureAllScreens() throws {
        // ── Main tabs ─────────────────────────────────────────────────────────
        wait(1);  snap("today")
        tap(tab: "Trends"); wait(2); snap("trends")
        tap(tab: "Live");   wait(2); snap("live")
        tap(tab: "Sleep");  wait(2); snap("sleep")
        tap(tab: "More");   wait(1) // list — not captured as its own screen

        // ── Screens inside the More list ──────────────────────────────────────
        let moreScreens: [(cell: String, id: String)] = [
            ("Intelligence", "intelligence"),
            ("Coach",        "coach"),
            ("Insights",     "insights"),
            ("Explore",      "explore"),
            ("Compare",      "compare"),
            ("Workouts",     "workouts"),
            ("Health",       "health"),
            ("Stress",       "stress"),
            ("Breathe",      "breathing"),
            ("Intervals",    "interval"),
            ("Apple Health", "apple-health"),
            ("Data Sources", "data-sources"),
            ("Automations",  "automations"),
            ("Settings",     "settings"),
            ("Support",      "support"),
        ]

        for (cell, id) in moreScreens {
            returnToMoreList()
            let row = app.staticTexts[cell]
            guard row.waitForExistence(timeout: 3) else {
                XCTFail("Cell '\(cell)' not found"); continue
            }
            row.tap()
            wait(2)
            snap(id)
        }
    }

    // MARK: - Today detail (top → bottom scroll for design review)

    private func captureToday(state: String) {
        let a = XCUIApplication()
        a.launchArguments = [
            "-noop.onboarded",               "YES",
            "-noop.acceptedTermsVersion",    "1.0",
            "-noop.lastSeenChangelogVersion","1.80",
            "-noop.didOfferRestore",         "YES",
        ]
        if state != "empty" { a.launchArguments += ["-noop.fixture", state] }
        a.launch()
        _ = a.tabBars.firstMatch.waitForExistence(timeout: 8)

        // Seeding writes to the store asynchronously; give it extra time on non-empty states.
        wait(state == "empty" ? 2 : 5)

        // Frame 1 = top (used as the primary fixture thumbnail in screen-map.html)
        let prefix = state == "empty" ? "today" : "today_\(state)"
        snap(prefix, app: a)
        for i in 2...4 {
            a.swipeUp(); wait(1)
            snap("\(prefix)_\(i)", app: a)
        }
    }

    // MARK: - Helpers

    private func tap(tab: String) { app.tabBars.buttons[tab].tap() }

    private func returnToMoreList() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable { back.tap(); wait(1) }
        if !app.navigationBars["More"].exists { tap(tab: "More"); wait(1) }
    }

    private func wait(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func snap(_ id: String, app: XCUIApplication? = nil) {
        let target = app ?? self.app!
        let shot = XCUIScreen.main.screenshot()
        _ = target // suppress unused warning
        let fileURL = Self.outputDir.appendingPathComponent("\(id).png")
        try? shot.image.pngData()?.write(to: fileURL)
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = id
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
