import Foundation
import WhoopStore

// MARK: - DietPlan → WhoopStore.DietPlanRow (FER-370)
//
// WhoopStore persists a plan as an OPAQUE JSON payload — it never decodes the nested
// structure. This bridge (StrandImport depends on WhoopStore, not the reverse) re-encodes a
// validated `DietPlan` into the canonical `noop.diet.v1` JSON and packs it, with the
// denormalized listing columns, into a `DietPlanRow`. Canonical = sorted keys, so the stored
// payload is stable and a round-trip (`parse(makeDietPlanRow(plan).payloadJSON) == plan`) holds.

public extension DietPlanImporter {

    /// Build the persistable row for a validated plan. `id` is the app-generated plan id (UUID),
    /// `createdAt` unix seconds — both supplied by the caller (mirrors `experiment`).
    func makeDietPlanRow(_ plan: DietPlan, id: String, createdAt: Int) throws -> DietPlanRow {
        DietPlanRow(
            id: id,
            name: plan.name,
            language: plan.language.rawValue,
            cycle: plan.cycle.rawValue,
            payloadJSON: try Self.canonicalJSON(plan),
            createdAt: createdAt)
    }

    /// Canonical `noop.diet.v1` JSON for a validated plan: deterministic key order so the stored
    /// payload is stable across encodes.
    static func canonicalJSON(_ plan: DietPlan) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(plan), as: UTF8.self)
    }
}
