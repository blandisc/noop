import Foundation
import CenitStore
import StrandAnalytics

// CircadianPhaseProvider.swift — the app-layer read for FER-712's «Tu reloj corporal» surface. It
// pulls the latest persisted phase record and resolves the coarse UI state (no band / no reading yet /
// a reading) so the screen binds to one value. No science here — CircadianEngine owns every number;
// this only translates the stored `confidence` string back to the enum and packages a display value.

/// A resolved reading for the screen. All numbers come straight from the persisted record.
struct CircadianReading: Equatable {
    let trendOffsetMinutes: Double     // centered offset: <−20 lark, >20 owl, else aligned
    let confidence: CircadianEngine.PhaseConfidence
    let bedtimeHour: Double?           // suggested sleep-window hour (nil if not derivable)
    let daysObserved: Int

    /// The morning-lark / night-owl / aligned tendency, from the centered offset (±20 min threshold).
    var tendency: CircadianTendency {
        if trendOffsetMinutes > 20 { return .owl }
        if trendOffsetMinutes < -20 { return .lark }
        return .aligned
    }
}

enum CircadianTendency: Equatable { case lark, owl, aligned }

/// The coarse state of the body-clock read, for the screen to render.
enum CircadianPhaseRead: Equatable {
    /// The phase signal is the band's accelerometer rhythm; not available on Apple-Health-only.
    case needsBand
    /// No record yet, or the reading is arrhythmic/too-few-days (`unreadable`) — "hard to read".
    case notReadable
    /// A readable phase estimate (wide or solid).
    case reading(CircadianReading)
}

enum CircadianPhaseProvider {

    /// Pure resolution from an already-fetched record. Testable without a store.
    static func resolve(usesWhoop: Bool, record: CircadianPhaseRow?) -> CircadianPhaseRead {
        guard usesWhoop else { return .needsBand }
        guard let r = record,
              let confidence = CircadianEngine.PhaseConfidence(rawValue: r.confidence),
              confidence != .unreadable
        else { return .notReadable }
        return .reading(CircadianReading(trendOffsetMinutes: r.offsetMinutes,
                                         confidence: confidence,
                                         bedtimeHour: r.bedtimeHour,
                                         daysObserved: r.daysObserved))
    }

    /// Load the latest phase from the store and resolve the state. The screen calls this once on open.
    @MainActor
    static func load(from repo: Repository) async -> CircadianPhaseRead {
        guard repo.dataSourceMode.usesWhoop else { return .needsBand }
        let record = await repo.latestCircadianPhase()
        return resolve(usesWhoop: true, record: record)
    }
}
