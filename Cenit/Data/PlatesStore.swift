import Foundation
import Combine
import StrandAnalytics

/// The user's barbell + the plate denominations they own (FER-720 · 3a), UserDefaults-backed
/// (single-user, on-device), mirroring `GoalStore`. Not analytics history, so no database table. The
/// plate-math itself (per-side loading, warm-up ramp) lives in `StrandAnalytics.PlateMath`; this store
/// only holds the user's editable inventory and hands it over as `PlateStock`s.
@MainActor
final class PlatesStore: ObservableObject {

    /// The bar weight (kg). Defaults to the standard 20 kg Olympic bar.
    @Published var barKg: Double {
        didSet { d.set(barKg, forKey: K.bar) }
    }

    /// The plate denominations (kg) the user owns, largest first. We don't track pair counts — a home
    /// or gym rack effectively has "enough" of each denomination it stocks — so `PlateMath` gets a
    /// generous pair count per owned denomination.
    @Published var ownedKg: [Double] {
        didSet { d.set(ownedKg, forKey: K.owned) }
    }

    /// The denominations offered in the editor to toggle on/off — the standard metric set.
    static let selectableKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    private let d = UserDefaults.standard
    private enum K {
        static let bar = "plates.barKg"
        static let owned = "plates.ownedKg"
    }

    init() {
        let storedBar = d.object(forKey: K.bar) as? Double
        barKg = storedBar ?? PlateMath.defaultBarKg
        if let raw = d.array(forKey: K.owned) as? [Double], !raw.isEmpty {
            ownedKg = raw.sorted(by: >)
        } else {
            ownedKg = PlateMath.defaultInventory.map(\.kg)   // tops at 20 kg (see PlateMath)
        }
    }

    /// The owned denominations as `PlateMath` stock (generous pair count, since we don't track pairs).
    var inventory: [PlateMath.PlateStock] {
        ownedKg.sorted(by: >).map { PlateMath.PlateStock(kg: $0, pairs: 20) }
    }

    /// Toggle whether the user owns a denomination.
    func toggle(_ kg: Double) {
        if let i = ownedKg.firstIndex(of: kg) { ownedKg.remove(at: i) }
        else { ownedKg = (ownedKg + [kg]).sorted(by: >) }
    }

    func owns(_ kg: Double) -> Bool { ownedKg.contains(kg) }
}
