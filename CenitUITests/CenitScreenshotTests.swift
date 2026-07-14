import XCTest

/// Captures a screenshot of every main screen in NOOP and saves PNGs to docs/fixtures/.
/// The HTML screen map at docs/screen-map.html loads these as thumbnails.
///
/// Run (no simulator pre-launch needed — xcodebuild boots one):
///   GIT_CONFIG=/dev/null xcodebuild test \
///     -project Cenit.xcodeproj -scheme Cenit \
///     -destination 'platform=iOS Simulator,name=iPhone 16' \
///     CODE_SIGNING_ALLOWED=NO \
///     -only-testing CenitUITests/CenitScreenshotTests
///
/// Maintenance: when you add/remove/rename a state in a *View.swift, add/update the
/// corresponding case here and re-run to regenerate the fixtures in the same PR.
final class CenitScreenshotTests: XCTestCase {

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
    func test_today_empty()       throws { captureToday(state: "empty") }
    func test_today_primed()      throws { captureToday(state: "primed") }
    func test_today_strained()    throws { captureToday(state: "strained") }
    func test_today_balanced()    throws { captureToday(state: "balanced") }
    func test_today_rundown()     throws { captureToday(state: "rundown") }
    /// Numeral en TINTA + «Not enough context for a verdict»: hay número de hoy, sin historia.
    func test_today_insufficient() throws { captureToday(state: "insufficient") }
    /// FER-711 · the `··` calibrating state (numeral never lies): a strap seen, base not yet seeded.
    func test_today_calibrating() throws { captureToday(state: "calibrating") }
    /// FER-286 · «Downloading / your night is on its way»: offload en curso, sin recovery de hoy aún.
    func test_today_downloading() throws { captureToday(state: "downloading") }

    /// FER-939 · the Entrenar hub's PLANNED state (open hero + discs + «LA SESIÓN DE HOY» + TU PLAN +
    /// Constancia). The `primed` fixture also seeds the demo plan (`seedTrainingPlan`), so the tab
    /// renders the full layout. Two frames: top + one swipe (plan/consistency/foot).
    func test_entrenar_hub() throws {
        let a = XCUIApplication()
        a.launchArguments = [
            "-noop.onboarded",               "YES",
            "-noop.acceptedTermsVersion",    "1.0",
            "-noop.lastSeenChangelogVersion","1.80",
            "-noop.didOfferRestore",         "YES",
            "-noop.fixture",                 "primed",
        ]
        a.launch()
        wait(6)   // seeding (dashboard + plan) is async
        // The dock is the custom InstrumentTabBar (FER-490) — not a native TabBar, so query the
        // localized button label directly.
        let entrenar = a.buttons["Entrenar"].firstMatch
        if entrenar.waitForExistence(timeout: 6) { entrenar.tap() }
        else { a.staticTexts["Entrenar"].firstMatch.tap() }
        wait(3)   // EntrenarLanding's own async load()
        snap("entrenar_hub", app: a)
        a.swipeUp(); wait(1)
        snap("entrenar_hub_2", app: a)
    }

    // MARK: - All screens (empty/default state)

    func test_captureAllScreens() throws {
        continueAfterFailure = true

        // 5-tab shell (FER-182): Hoy · Cuerpo · Coach · Entrenar · Ajustes. Tab labels are the
        // English `tabItem` titles (the hidden native bar still exposes them to XCUI). En vivo is no
        // longer a tab — it opens as a cover from Today's "beat by beat", so it's not swept here.
        wait(1);  snap("today")
        tap(tab: "Body"); wait(2); snap("trends")   // Cuerpo (snapshot histórico «trends»)

        // Coach.
        captureHub(tab: "Coach", screens: [
            ("Coach",        "coach"),
        ])

        // Entrenar hub → the active-session tools.
        captureHub(tab: "Train", screens: [
            ("Breathe",   "breathing"),
            ("Intervals", "interval"),
        ])

        // Ajustes → Settings + the temporary «Más» orphans. "Explore" (MetricExplorer) is kept last
        // (it used to crash on exit via a nested NavigationStack — fixed in FER-171).
        captureHub(tab: "Settings", screens: [
            ("Settings",     "settings"),
            ("Sleep",        "sleep"),
            ("Compare",      "compare"),
            ("Workouts",     "workouts"),
            ("Apple Health", "apple-health"),
            ("Data Sources", "data-sources"),
            ("Automations",  "automations"),
            ("Support",      "support"),
            ("Explore",      "explore"),   // last (FER-171 fixed the old exit crash)
        ])
    }

    /// Walks a hub tab's list, tapping each row and snapping the pushed screen. Relaunches defensively
    /// if the app dropped out of the foreground on a previous screen.
    private func captureHub(tab: String, screens: [(cell: String, id: String)]) {
        for (cell, id) in screens {
            if app.state != .runningForeground {
                app.launch()
                guard app.tabBars.firstMatch.waitForExistence(timeout: 8) else {
                    XCTFail("App failed to relaunch for '\(cell)'"); continue
                }
                wait(1)
            }
            returnToHub(tab)
            // Use cells to avoid ambiguity when the label appears in multiple elements
            let row = app.cells.containing(.staticText, identifier: cell).firstMatch
            guard row.waitForExistence(timeout: 3) else {
                XCTFail("Cell '\(cell)' not found in '\(tab)'"); continue
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

    private func returnToHub(_ tab: String) {
        guard app.state == .runningForeground else { return }
        // Pop back through any pushed views (max 3 levels)
        for _ in 0..<3 {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap(); wait(1)
        }
        tap(tab: tab); wait(1)
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
