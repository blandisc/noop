#if os(iOS)
import Foundation
import StrandDesign
import StrandTraining

// TicketMapping.swift — pure StrengthSession → MiniTicket mapper for the thermal-receipt grid.
// No view code. Keeps ticket fields deterministic (stable order #, bars) so the same session always
// reprints the same face.

enum TicketMapping {

    /// Map one completed strength session to a compact saved-ticket cell.
    /// - Parameters:
    ///   - index: Caller's grid/list position (unused for fields; `isToday` is date-derived).
    ///   - routineName: Resolved routine name, if any — keyword-matched for ticket type.
    ///   - volumeKg: Work volume in kg for this session (0 when unknown).
    static func miniTicket(for session: StrengthSession, index: Int,
                           routineName: String?, volumeKg: Double, system: UnitSystem) -> MiniTicket {
        _ = index
        let (value, unit) = volumeParts(volumeKg, system: system)
        let date = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        return MiniTicket(
            id: session.id,
            orderText: orderText(for: session.id),
            dateText: shortDate(date),
            isToday: Calendar.current.isDateInToday(date),
            type: ticketType(from: routineName),
            // No cheap per-session PR signal on StrengthSession / sessionVolumes — never fabricate.
            isRecord: false,
            value: value,
            unit: unit,
            bars: bars(from: session.id),
            todayBadge: String(localized: "recibo.hoy", defaultValue: "TODAY")
        )
    }

    // MARK: - Order · date · type

    /// Stable 4-digit order from session id — deterministic FNV fold (not `hashValue`, which is
    /// randomized per process in Swift and would reprint a different # each launch).
    private static func orderText(for sessionId: String) -> String {
        let n = Int(stableHash(sessionId) % 10_000)
        return String(format: String(localized: "recibo.orden.corta.fmt", defaultValue: "CÉNIT · #%04d"), n)
    }

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_03
        for u in s.unicodeScalars {
            h = (h ^ UInt64(u.value)) &* 1_099_511_628_211
        }
        return h
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    private static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date).uppercased()
    }

    /// Keyword match on the routine name only.
    /// Simplification: we do **not** call `RoutineClassifier` (would need each exercise's primary
    /// muscles per session — out of scope / too expensive for this list path). Fallback: "FUERZA".
    /// El match se queda en el idioma del usuario (compara contra SU nombre de rutina); lo que
    /// se traduce es el rótulo pintado (FER-112).
    private static func ticketType(from routineName: String?) -> String {
        guard let raw = routineName?.lowercased(), !raw.isEmpty else { return RecipeLabels.fuerza }
        if raw.contains("empuje") || raw.contains("push") { return RecipeLabels.empuje }
        if raw.contains("tirón") || raw.contains("tiron")
            || raw.contains("jalón") || raw.contains("jalon")
            || raw.contains("pull") { return RecipeLabels.tiron }
        if raw.contains("pierna") || raw.contains("legs") { return RecipeLabels.pierna }
        return RecipeLabels.fuerza
    }

    // MARK: - Volume (value + unit split)

    /// Same conversion/grouping as `StrengthHistoryFormat.volume`, but split for MiniTicket fields.
    private static func volumeParts(_ kg: Double, system: UnitSystem) -> (value: String, unit: String) {
        let converted = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let num = f.string(from: NSNumber(value: converted.rounded()))
            ?? "\(Int(converted.rounded()))"
        return (num, UnitFormatter.massUnit(system))
    }

    // MARK: - Decorative bars (deterministic)

    /// Four 0…1 bar heights from a stable FNV-1a-style fold over the session id. Never random.
    private static func bars(from sessionId: String) -> [Double] {
        let h = stableHash(sessionId)
        return (0..<4).map { i in
            var x = h &+ UInt64(i) &* 0x9E37_79B9_7F4A_7C15
            x = x &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            // Top 32 bits → 0…1
            return Double(x >> 32) / Double(UInt32.max)
        }
    }
}
#endif
