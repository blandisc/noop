import Foundation
import Combine
import StrandAnalytics

/// The data-source mode (combined / WHOOP-only / Apple-Health-only) — a single user preference,
/// UserDefaults-backed (single-user, on-device), mirroring `ProfileStore` / `BehaviorStore` / `GoalStore`.
/// Capture is independent of this (FER-484): the mode only filters what the dashboard and baseline READ,
/// never what gets written. Default `.combined`, so existing users keep the historical behavior.
@MainActor
final class SourceModeStore: ObservableObject {
    @Published var mode: DataSourceMode { didSet { d.set(mode.rawValue, forKey: K.mode) } }

    private let d = UserDefaults.standard
    private enum K { static let mode = "sources.dataSourceMode" }

    init() {
        mode = DataSourceMode(rawValue: d.string(forKey: K.mode) ?? "") ?? .combined
    }
}
