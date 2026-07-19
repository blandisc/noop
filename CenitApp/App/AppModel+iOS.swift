#if os(iOS)
import Foundation

extension AppModel {
    /// Execute any actions queued by App Intents while the app was suspended (mark moment, buzz).
    /// Call when the app becomes active.
    func drainPendingIntents() {
        for entry in PendingIntents.drain() {
            switch entry.action {
            case .markMoment: markMoment(at: entry.date)
            case .buzz:       buzz(loops: 1)
            }
        }
    }
}
#endif
