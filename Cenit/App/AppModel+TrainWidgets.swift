import Foundation

/// FER-95 · E14 — «fuera de la app»: los dos widgets de pantalla de inicio + el recordatorio del día que
/// toca entrenar. Ver el `.sink` sobre `repo.$dashboard` en `AppModel.init()` que llama a este método.
extension AppModel {

    /// Fetches the split/routines/sessions ONCE and hands them to `TrainWidgetPublisher` (the App-Group
    /// snapshot + widget reload) and `TrainingDayReminder` (the notification plan) — one dashboard
    /// publish costs one store trip, and the two can't drift because they read the SAME split.
    @MainActor
    func publishTrainOutsideApp() async {
        guard let store = await repo.storeHandle() else { return }
        let sched = (try? await store.routineSchedule()) ?? []
        let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let routines = await repo.routines()
        let routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let sessions = await repo.recentSessions(limit: 200)

        TrainWidgetPublisher.publish(split: split, routineNames: routineNames, sessions: sessions,
                                     sessionLive: strengthSession != nil, prep: repo.todayPreparedness,
                                     fullyLoaded: repo.fullyLoaded,
                                     healthConnected: healthBridge?.auth == .authorized)
        await TrainingDayReminder.reschedule(split: split, routineNames: routineNames)
    }
}
