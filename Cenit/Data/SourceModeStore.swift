import Foundation
import Combine
import StrandAnalytics

/// The data-source mode (combined / WHOOP-only / Apple-Health-only) — a single user preference,
/// UserDefaults-backed (single-user, on-device), mirroring `ProfileStore` / `BehaviorStore` / `GoalStore`.
/// Capture is independent of this (FER-484): the mode only filters what the dashboard and baseline READ,
/// never what gets written. Default `.combined`, so existing users keep the historical behavior.
@MainActor
final class SourceModeStore: ObservableObject {
    /// B (FER-1003): PINEADO a `.appleHealthOnly`. Cénit es Apple-only — el app ya no lee la banda. Se
    /// ignora el valor persistido y cualquier intento de cambiarlo (el picker de fuentes se retira en la
    /// ola de superficies). La partición de banda (`strap` / `strap-noop`) queda DORMIDA en la DB, excluida
    /// por el modo, NUNCA borrada — así un backup/restore preserva la historia y no hay «recovery zombi»
    /// (los días viejos de banda no le ganan al Apple porque `DataSourcePolicy` los saca del merge).
    @Published var mode: DataSourceMode = .appleHealthOnly {
        didSet { if mode != .appleHealthOnly { mode = .appleHealthOnly } }   // rechaza cualquier cambio
    }

    init() {}   // deliberadamente ignora el `sources.dataSourceMode` persistido: el modo es constante
}
