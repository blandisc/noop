// FER-95 · E14 — «Empezar» from the home-screen `TrainTodayWidget` / `WeekWidget`.
//
// Lives in `HomeWidgets/`, NOT `CenitWidgets/Shared/`: `Shared/` also compiles into the APP target
// (`project.yml`), and `RestActivityIntents.swift` already documents the bug two intents with the
// same identifier in two bundles caused (FER-844 — `appintentsd` resolved the lock-screen auth policy
// from the app-side record and forced Face ID on every tap). Putting this intent only where the
// `CenitWidgets` extension compiles avoids repeating that defect, with no `project.yml` change needed.
//
// Unlike the six `RestActivityIntents` (`openAppWhenRun = false`, deliberately staying in the
// extension process so a locked phone never demands Face ID for a rest nudge), this one sets
// `openAppWhenRun = true` on purpose: tapping «Empezar» on the home screen SHOULD open Cénit — the
// guided session is a full-screen experience the extension can't render. `perform()` only queues the
// request (`StartRoutineBridge`, mirroring `RestActivityBridge`'s inbox pattern); the app drains it on
// activation and turns it into `TabRouter.startTodayTraining()` — the exact path the Daily Brief's own
// «Empezar» already uses, so today's guided session opens in one tap, not two.

#if canImport(AppIntents)
import AppIntents

struct StartTodayRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Start today's routine"
    static var openAppWhenRun = true
    static var description = IntentDescription("Opens Cénit in today's guided routine.")

    init() {}

    func perform() async throws -> some IntentResult {
        StartRoutineBridge.request()
        return .result()
    }
}
#endif
