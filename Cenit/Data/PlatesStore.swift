import Foundation
import Combine
import StrandAnalytics

/// The user's barbell + the plate denominations they own (FER-720 · 3a), UserDefaults-backed
/// (single-user, on-device), mirroring `GoalStore`. Not analytics history, so no database table. The
/// plate-math itself (per-side loading, warm-up ramp) lives in `StrandAnalytics.PlateMath`; this store
/// only holds the user's editable inventory and hands it over as `PlateStock`s. Pair counts are tracked
/// per denomination so `PlateMath` can report an honest shortfall when the rack can't hit the target.
@MainActor
final class PlatesStore: ObservableObject {

    /// The bar weight (kg). Defaults to the standard 20 kg Olympic bar.
    @Published var barKg: Double {
        didSet { d.set(barKg, forKey: K.bar) }
    }

    /// Pair count per plate denomination (kg → pairs). `0` means not owned; `1` = one pair (one plate
    /// per side), `2` = two pairs, etc. Persisted to UserDefaults; drives `inventory` for `PlateMath`.
    @Published private(set) var pairs: [Double: Int] {
        didSet { persistPairs() }
    }

    /// The denominations offered in the editor — the standard metric set.
    static let selectableKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// r22 (owner): ejercicios con calentamiento ACTIVADO — insertar la rampa una vez lo recuerda y
    /// cada sesión futura del ejercicio nace con sus «C»; quitar la última «C» en sesión lo apaga.
    /// UserDefaults como el resto del store (preferencia de usuario, no historial).
    @Published private(set) var warmupExerciseIds: Set<String> {
        didSet { d.set(Array(warmupExerciseIds), forKey: K.warmupIds) }
    }

    func setWarmupAlways(_ exerciseId: String, _ on: Bool) {
        if on { warmupExerciseIds.insert(exerciseId) } else { warmupExerciseIds.remove(exerciseId) }
    }

    private let d = UserDefaults.standard
    private enum K {
        static let bar = "plates.barKg"
        /// Legacy boolean inventory (`[Double]` of owned denominations). Migrated once into `pairsKey`.
        static let owned = "plates.ownedKg"
        /// Per-denomination pair counts as `[[kg, pairs], …]`.
        static let pairsKey = "plates.pairsByKg"
        /// r22: exercise ids whose warm-up ramp auto-inserts at session start.
        static let warmupIds = "plates.warmupExerciseIds"
    }

    init() {
        let storedBar = d.object(forKey: K.bar) as? Double
        barKg = storedBar ?? PlateMath.defaultBarKg
        warmupExerciseIds = Set(d.stringArray(forKey: K.warmupIds) ?? [])

        if let loaded = Self.loadPairs(from: d) {
            pairs = loaded
        } else if let raw = d.array(forKey: K.owned) as? [Double], !raw.isEmpty {
            // One-shot migration from the legacy boolean list: each owned denomination → 2 pairs
            // (a reasonable "some pairs" default so users don't lose their setup).
            var migrated: [Double: Int] = Dictionary(uniqueKeysWithValues: Self.selectableKg.map { ($0, 0) })
            for kg in raw {
                if let key = Self.selectableKg.first(where: { abs($0 - kg) < 0.001 }) {
                    migrated[key] = 2
                }
            }
            pairs = migrated
            // didSet is not called during init — write the migrated payload so this path runs once.
            d.set(Self.encodePairs(migrated), forKey: K.pairsKey)
        } else {
            // Fresh install: seed from `PlateMath.defaultInventory` (pairs already tracked there).
            var defaults: [Double: Int] = Dictionary(uniqueKeysWithValues: Self.selectableKg.map { ($0, 0) })
            for stock in PlateMath.defaultInventory { defaults[stock.kg] = stock.pairs }
            pairs = defaults
        }
    }

    /// The owned denominations as `PlateMath` stock, using the real per-denomination pair counts.
    var inventory: [PlateMath.PlateStock] {
        pairs
            .filter { $0.value > 0 }
            .sorted { $0.key > $1.key }
            .map { PlateMath.PlateStock(kg: $0.key, pairs: $0.value) }
    }

    /// How many pairs the user owns of this denomination (`0` = not owned).
    func pairs(for kg: Double) -> Int { pairs[kg] ?? 0 }

    /// Set the pair count for a denomination. Floors at 0.
    func setPairs(_ count: Int, for kg: Double) {
        let c = max(0, count)
        var next = pairs
        next[kg] = c
        pairs = next
    }
}

// MARK: - Persistence helpers

private extension PlatesStore {
    /// Encode as `[[kg, pairs], …]` so Double keys survive UserDefaults round-trips cleanly.
    static func encodePairs(_ pairs: [Double: Int]) -> [[Double]] {
        selectableKg.map { [$0, Double(pairs[$0] ?? 0)] }
    }

    /// Load pair counts. UserDefaults nests numbers as `NSNumber`, so cast element-by-element
    /// rather than `as? [[Double]]` (which often fails for nested arrays).
    static func loadPairs(from d: UserDefaults) -> [Double: Int]? {
        guard let arr = d.array(forKey: K.pairsKey), !arr.isEmpty else { return nil }
        var result: [Double: Int] = Dictionary(uniqueKeysWithValues: selectableKg.map { ($0, 0) })
        var found = false
        for item in arr {
            guard let row = item as? [Any], row.count >= 2,
                  let kgRaw = doubleValue(row[0]),
                  let count = intValue(row[1]),
                  let key = selectableKg.first(where: { abs($0 - kgRaw) < 0.001 }) else { continue }
            result[key] = max(0, count)
            found = true
        }
        return found ? result : nil
    }

    static func doubleValue(_ any: Any) -> Double? {
        if let v = any as? Double { return v }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static func intValue(_ any: Any) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v.rounded()) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }

    func persistPairs() {
        d.set(Self.encodePairs(pairs), forKey: K.pairsKey)
    }
}
