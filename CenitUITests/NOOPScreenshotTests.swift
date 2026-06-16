import XCTest

/// Captures a screenshot of every main screen in NOOP and saves PNGs to docs/fixtures/.
/// The HTML screen map at docs/screen-map.html loads these as thumbnails.
///
/// Run (no simulator pre-launch needed — xcodebuild boots one):
///   GIT_CONFIG=/dev/null xcodebuild test \
///     -project Cenit.xcodeproj -scheme Cenit \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     CODE_SIGNING_ALLOWED=NO \
///     -only-testing CenitUITests/NOOPScreenshotTests
///
/// Maintenance: when you add/remove/rename a state in a *View.swift, add/update the
/// corresponding case here and re-run to regenerate the fixtures in the same PR.
final class NOOPScreenshotTests: XCTestCase {

    var app: XCUIApplication!

    // Output dir for PNG fixtures.
    // The test runner process is sandboxed in a way that blocks writes to arbitrary Mac paths,
    // so we write to the app's shared container (always writable) and print the path so
    // a post-test copy step can move files to docs/fixtures/.
    static let outputDir: URL = {
        // Prefer a path passed via TEST_RUNNER_NOOP_FIXTURES (if it propagates)
        if let p = ProcessInfo.processInfo.environment["NOOP_FIXTURES"], !p.isEmpty {
            let dir = URL(fileURLWithPath: p)
            if (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
                || FileManager.default.fileExists(atPath: p) {
                return dir
            }
        }
        // Fallback: use the tmp directory (always writable in any process)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("noop-fixtures")
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
        continueAfterFailure = true

        // ── Main tabs ─────────────────────────────────────────────────────────
        wait(1);  snap("today")
        tap(tab: "Trends"); wait(2); snap("trends")
        tap(tab: "Live");   wait(2); snap("live")
        tap(tab: "Sleep");  wait(2); snap("sleep")
        tap(tab: "More");   wait(1) // list — not captured as its own screen

        // ── Screens inside the More list ──────────────────────────────────────
        // "Explore" (MetricExplorer) is last: it sometimes crashes the app on exit.
        // Putting it last means all other screens are captured even if Explore crashes.
        let moreScreens: [(cell: String, id: String)] = [
            ("Intelligence", "intelligence"),
            ("Coach",        "coach"),
            ("Insights",     "insights"),
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
            ("Explore",      "explore"),   // last — may crash app on exit
        ]

        for (cell, id) in moreScreens {
            // Re-launch if the app crashed or backgrounded during a previous screen
            if app.state != .runningForeground {
                app.launch()
                guard app.tabBars.firstMatch.waitForExistence(timeout: 8) else {
                    XCTFail("App failed to relaunch for '\(cell)'"); continue
                }
                wait(1)
            }
            returnToMoreList()
            // Use cells to avoid ambiguity when the label appears in multiple elements
            let row = app.cells.containing(.staticText, identifier: cell).firstMatch
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
        guard app.state == .runningForeground else { return }
        // Pop back through any pushed views (max 3 levels)
        for _ in 0..<3 {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap(); wait(1)
        }
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
        if let data = shot.image.pngData() {
            do {
                try data.write(to: fileURL)
                print("FIXTURE_WRITTEN: \(fileURL.path)")
            } catch {
                print("FIXTURE_WRITE_FAILED: \(fileURL.path) — \(error)")
            }
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = id
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
