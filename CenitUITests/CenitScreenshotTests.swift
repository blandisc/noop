import XCTest

/// Captures a screenshot of every main screen in Cénit and saves PNGs to docs/fixtures/.
/// `Tools/build-appmap.py` picks a subset of them (its `SHOT_SRC` table) for the state wall
/// at docs/appmap/ — that wall is the reason these captures exist.
///
/// Run (no simulator pre-launch needed — xcodebuild boots one):
///   GIT_CONFIG=/dev/null xcodebuild test \
///     -project Cenit.xcodeproj -scheme Cenit \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///     CODE_SIGNING_ALLOWED=NO \
///     -only-testing CenitUITests/CenitScreenshotTests
/// or just `Tools/capture-screens.sh`, which also copies the PNGs into docs/fixtures/.
///
/// Maintenance: when you add/remove/rename a state in a *View.swift, add/update the
/// corresponding case here and re-run to regenerate the fixtures in the same PR. If the new
/// state belongs on the wall, add its entry to `SHOT_SRC` too — otherwise the PNG is captured
/// and never seen.
///
/// ## Two rules that keep this suite from rotting (learned the hard way)
///
/// 1. **Navigate with `nav(_:)`, not by tapping labels.** Every screen here is reachable through
///    `ScreenshotNav` (`noop.nav.<key>`, DEBUG-only), which sets the tab + pushes the stack
///    directly. Tapping localized text was how this suite broke: the string catalog's source
///    language is English (keys ARE the English literals), so `buttons["Entrenar"]` matched only
///    when the host simulator happened to run in Spanish, and renamed copy («Editar semana» →
///    «Edit routines and week») silently stopped matching anything. Worse, taps guarded by
///    `if exists` no-oped and the test still "passed" — snapping the WRONG screen into a fixture.
///    `nav(_:)` cannot land on the wrong screen, so a bad key fails loudly instead.
/// 2. **The language is pinned** (`baseArgs`). Unpinned, the same test produced a different UI per
///    machine. Spanish is the product's copy (es-MX) and the only coherent choice: the tab keys
///    «Tendencias» and «Patrones» have no English translation, so an English run renders a
///    mixed-language bar.
///
/// The native tab bar is hidden app-wide (`.toolbar(.hidden, for: .tabBar)`) in favour of the
/// custom `InstrumentTabBar` (FER-163/FER-490) — `app.tabBars` is EMPTY. Never query it.
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

    /// Launch arguments shared by every capture: skip onboarding / terms / the restore nudge, and
    /// PIN the language so the captured UI is identical on every machine (see rule 2).
    private static let baseArgs = [
        "-AppleLanguages",               "(es)",
        "-AppleLocale",                  "es_MX",
        "-noop.onboarded",               "YES",
        // Debe igualar `Terms.currentVersion` (Cenit/App/Terms.swift): con "1.0" desde FER-1003 el
        // arnés capturaba la puerta de Términos en vez de la pantalla (FER-118 · F lo cazó).
        "-noop.acceptedTermsVersion",    "2.0",
        "-noop.didOfferRestore",         "YES",
    ]

    /// A fresh app pinned to `baseArgs`, optionally seeded with a `ScreenshotFixtures` state.
    private func makeApp(fixture: String? = nil) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments = Self.baseArgs + (fixture.map { ["-noop.fixture", $0] } ?? [])
        return a
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = makeApp()

        // Dismiss any system permission alert (HealthKit, Bluetooth) without blocking
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            for label in ["Don't Allow", "No permitir", "Allow", "Permitir", "OK"] {
                let btn = alert.buttons[label]
                if btn.exists { btn.tap(); return true }
            }
            return false
        }

        app.launch()
        // NOT `app.tabBars` — the native bar is hidden (see the class note), so waiting on it just
        // burned the full timeout on every test.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "app never reached the foreground")
    }

    // MARK: - Today (verdict states)

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

    // MARK: - Entrenar (seeded plan + routines)

    /// FER-939 · the Entrenar hub's PLANNED state (open hero + discs + «LA SESIÓN DE HOY» + TU PLAN +
    /// Constancia). The `primed` fixture also seeds the demo plan (`seedTrainingPlan`), so the tab
    /// renders the full layout. Two frames: top + one swipe (plan/consistency/foot).
    func test_entrenar_hub() throws {
        let a = launchSeeded()
        nav("train", app: a, settle: 3)   // EntrenarLanding runs its own async load()
        snap("entrenar_hub", app: a)
        a.swipeUp(); wait(1)
        snap("entrenar_hub_2", app: a)
    }

    /// FER-939 follow-up · «Tu Plan» (WeeklyPlanEditorView) with the seeded demo plan: hero, LA SEMANA
    /// (one row per day), weekly volume, MIS RUTINAS.
    func test_tu_plan() throws {
        let a = launchSeeded()
        nav("weeklyplan", app: a, settle: 3)
        snap("tu_plan", app: a)
        a.swipeUp(); wait(1)
        snap("tu_plan_2", app: a)
    }

    /// «Mis entrenamientos» (WorkoutHistoryScreen) with the seeded demo plan+sessions.
    /// Three frames: the screen is long.
    func test_mis_entrenamientos() throws {
        let a = launchSeeded()
        nav("workouthistory", app: a, settle: 3)
        snap("mis_entrenamientos", app: a)
        a.swipeUp(); wait(1)
        snap("mis_entrenamientos_2", app: a)
        a.swipeUp(); wait(1)
        snap("mis_entrenamientos_3", app: a)
    }

    /// «Biblioteca de ejercicios» (ExerciseLibraryScreen).
    func test_biblioteca() throws {
        let a = launchSeeded()
        nav("library", app: a, settle: 4)   // catalog load
        snap("biblioteca", app: a)
        a.swipeUp(); wait(1)
        snap("biblioteca_2", app: a)
    }

    /// El flujo de Entrenar con datos sembrados (fixture `train`): hub poblado → rutina de hoy →
    /// sesión guiada. Navegación defensiva: snapea lo que alcanza sin fallar duro. Éste es el único
    /// test que TOCA la UI (el punto es ejercitar el flujo real, no sólo llegar a la pantalla); sus
    /// labels son deterministas porque el idioma va fijado en `baseArgs`.
    func test_train_flow() throws {
        continueAfterFailure = true
        let a = makeApp(fixture: "train")
        a.launch()
        XCTAssertTrue(a.wait(for: .runningForeground, timeout: 15))
        wait(7)   // las rutinas se siembran async en el store

        nav("train", app: a, settle: 3)
        snap("train-hub", app: a)

        // Rutina de hoy ANTES de la sesión: la sesión de fuerza es un cover propiedad de AppModel, y
        // cerrarlo solo lo MINIMIZA a la píldora flotante (RootTabView) — el hub queda en estado «sesión
        // activa» y la tarjeta de rutina en reposo ya no se puede capturar después. Por eso la sesión va
        // al final. Se navega por nav(), no tocando «Empuje», para no depender del copy del fixture.
        nav("routineToday", app: a, settle: 3)
        snap("train-rutina", app: a)

        // Sesión guiada de fuerza: «Empezar» desde el hub. Este sí es un tap real por label — el punto
        // del test es ejercitar el flujo de verdad, y el idioma va fijado en `baseArgs`.
        nav("train", app: a, settle: 3)
        let empezar = a.buttons["Empezar"].firstMatch
        if empezar.waitForExistence(timeout: 4) {
            empezar.tap(); wait(3)
            snap("train-sesion", app: a)
        } else {
            XCTFail("«Empezar» no existe en el hub de Entrenar — ¿cambió el copy o el fixture `train`?")
        }
    }

    // MARK: - All screens (empty/default state)

    /// Sweeps the 5-tab shell (FER-182: Hoy · Tendencias · Patrones · Entrenar · Ajustes) plus every
    /// secondary screen, all via `nav(_:)`.
    ///
    /// Not swept: `sleep` — Sueño is no longer a standalone screen, its `noop.nav` key is an ALIAS of
    /// the Cuerpo tab (see `RootTabView`), so capturing it would just duplicate `trends.png`.
    /// `docs/fixtures/sleep.png` is therefore an orphan of the old shell, as are health/insights/
    /// intelligence/live/stress. «En vivo» is likewise no longer a tab (it opens as a cover from
    /// Today's «beat by beat»).
    func test_captureAllScreens() throws {
        continueAfterFailure = true

        let screens: [(key: String, id: String)] = [
            ("today",       "today"),
            ("body",        "trends"),      // Cuerpo (snapshot histórico «trends»)
            ("coach",       "coach"),
            // Entrenar hub → the active-session tools.
            ("breathe",     "breathing"),
            ("intervals",   "interval"),
            // Ajustes + the screens that open from Cuerpo's footer.
            ("settings",    "settings"),
            ("compare",     "compare"),
            ("workouts",    "workouts"),
            ("applehealth", "apple-health"),
            ("datasources", "data-sources"),
            ("automations", "automations"),
            ("support",     "support"),
            ("explore",     "explore"),     // last (FER-171 fixed the old exit crash)
        ]

        for (key, id) in screens {
            guard app.state == .runningForeground else {
                XCTFail("App dropped out of the foreground before '\(id)'"); return
            }
            nav(key, app: app)
            snap(id)
        }
    }

    // MARK: - Componentes (FER-315 · catálogo del sistema de diseño)

    /// El núcleo de piezas de `CenitDesign` que la galería expone (grupo «Componentes» del muro).
    /// DEBE seguir a `ComponentGallery.entries` (Cenit/App/ComponentGallery.swift, la fuente que
    /// renderiza) y a `COMPONENTS` en `Tools/build-appmap.py` (que las agrupa por familia). Es
    /// black-box: el test no puede importar el módulo de la app, así que la lista vive aquí también.
    private static let componentNames = [
        "LiquidGlassButton",
        "LiquidMetricTile",
        "LiquidCajita",
        "EntrenarTile",
        "EntrenarModulo",
        "LiquidChipSeleccion",
        "LiquidOrigenChip",
        "LiquidOrigenBadge",
        "EntrenarChipHerramienta",
        "LiquidStatePill",
        "LiquidListRow",
        "LiquidChecklistRow",
        "EntrenarFilaEjercicio",
        "LiquidRangeSelector",
        "EntrenarStepper",
        "LiquidCampoBusqueda",
        "LiquidTabBar",
        "LiquidMenu",
        "LiquidSheetHeader",
        "LiquidSectionHeader",
        "LiquidAviso",
        "ConfirmCard",
        "LiquidInputCard",
        "LiquidPatternBlock",
        "LiquidTrendChart",
        "Sparkline",
    ]

    /// Captura un PNG por pieza: cada una se monta a pantalla completa vía `-noop.component <Nombre>`
    /// (ver `ComponentGalleryHost`). Un solo test, un relanzamiento por pieza — igual disciplina que
    /// los estados de Hoy, para que una permission-alert en una no bloquee a las demás.
    func test_components() throws {
        for name in Self.componentNames {
            let a = XCUIApplication()
            a.launchArguments = Self.baseArgs + ["-noop.component", name]
            a.launch()
            XCTAssertTrue(a.wait(for: .runningForeground, timeout: 15), "app never foregrounded for \(name)")
            wait(2)   // sin coreografía de entrada aquí (la galería tapa la raíz), pero deja asentar el layout
            snap("component_\(name)", app: a)
            a.terminate()
        }
    }

    // MARK: - Today detail (top → bottom scroll for design review)

    private func captureToday(state: String) {
        let a = makeApp(fixture: state == "empty" ? nil : state)
        a.launch()
        XCTAssertTrue(a.wait(for: .runningForeground, timeout: 15))

        // Seeding writes to the store asynchronously; and the empty state is not faster: its hero
        // enters with the same ~2.8 s choreography (FER-41), so at 2 s the frame was still white
        // (FER-118 · F). Same wait for every state.
        wait(5)

        // Frame 1 = top (the frame `SHOT_SRC` maps onto the state wall; the rest are scroll context)
        let prefix = state == "empty" ? "today" : "today_\(state)"
        snap(prefix, app: a)
        for i in 2...4 {
            a.swipeUp(); wait(1)
            snap("\(prefix)_\(i)", app: a)
        }
    }

    // MARK: - Helpers

    /// Launches the `primed` fixture (dashboard + demo training plan, both seeded async).
    private func launchSeeded() -> XCUIApplication {
        let a = makeApp(fixture: "primed")
        a.launch()
        XCTAssertTrue(a.wait(for: .runningForeground, timeout: 15))
        wait(6)   // seeding (dashboard + plan) is async
        return a
    }

    /// Drives `ScreenshotNav` (`CenitApp/App/ScreenshotNav.swift`) by posting the Darwin notification
    /// it observes. The Darwin notify center is system-wide on the simulator, so the runner process
    /// can steer the app under test without touching a single pixel — no localized labels, no
    /// coordinates, no `app.tabBars` (hidden). A key the app doesn't observe is a silent no-op, so
    /// keep this in sync with `DebugNavWatcher.screens`.
    private func nav(_ screen: String, app a: XCUIApplication? = nil, settle: TimeInterval = 2) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("noop.nav.\(screen)" as CFString),
            nil, nil, true)
        wait(settle)
        let target = a ?? self.app!
        XCTAssertEqual(target.state, .runningForeground,
                       "app left the foreground while navigating to '\(screen)'")
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
