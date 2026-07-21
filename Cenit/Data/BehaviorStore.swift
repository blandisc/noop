import Foundation
import Combine

/// On-device behavior prefs (UserDefaults-backed, single-user).
@MainActor
final class BehaviorStore: ObservableObject {

    // MARK: Illness early-warning
    @Published var illnessWatch: Bool { didSet { d.set(illnessWatch, forKey: K.illness) } }

    private let d = UserDefaults.standard
    private enum K {
        // Band-era automation keys retired with FER-1003; orphaned UserDefaults values left on purpose.
        static let illness = "behavior.illnessWatch"
    }

    init() {
        illnessWatch = d.object(forKey: K.illness) as? Bool ?? false
    }
}
