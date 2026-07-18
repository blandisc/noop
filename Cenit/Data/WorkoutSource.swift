import Foundation
import CenitStore

/// Locale-aware display formatting shared by the workouts list and the session detail (so the two never
/// drift, and the list doesn't reach into the detail's private statics). Dates/times render in the device
/// locale (es-MX → «mié 18 jun» / 24h per region).
enum WorkoutFormat {
    static func duration(_ s: Double) -> String {
        let total = Int(s.rounded()), h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    static func date(_ ts: Int) -> String { dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
    static func time(_ ts: Int) -> String { timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("j:mm"); return f
    }()
}

/// Origin of a workout row, classified from its stored `source` column. The macOS read model
/// (`WorkoutRow`) carries no `deviceId`, so the row's origin has to be recovered from `source`.
/// Stored values today:
///   - "whoop"        — retired WHOOP CSV import (imported WHOOP session)
///   - "apple_health" / "apple-health" — AppleHealthImport
///   - "manual"       — AppModel.endWorkout (v1.67 live session) AND the retro add/edit sheet
///   - "my-whoop-noop"— IntelligenceEngine detected bouts (source == the computed deviceId, i.e.
///                       it ends in "-noop"). These are re-derived every analyzeRecent run.
///
/// Classification order matters: "-noop" is checked BEFORE "whoop" because the computed id
/// "my-whoop-noop" also contains the substring "whoop".
enum WorkoutSource: Equatable {
    case whoop, apple, detected, manual

    /// Common sports offered when re-labelling a detected bout — short and honest (the user can
    /// fine-tune via Edit afterwards). Shared by the list's swipe action and the detail's menu.
    static let relabelSports = ["Running", "Walking", "Cycling", "Strength Training",
                                "Swimming", "Rowing", "Yoga", "HIIT"]

    static func classify(_ source: String) -> WorkoutSource {
        let s = source.lowercased()
        if s.hasSuffix("-noop") { return .detected }   // BEFORE whoop: "my-whoop-noop" contains "whoop"
        if s == "manual" { return .manual }
        if s.contains("whoop") { return .whoop }
        return .apple
    }

    /// Sport-cell text. Two clean-ups before display:
    ///   - the detector stores the machine token "detected"; show it as a neutral "Activity"
    ///     (we don't claim a sport we didn't actually classify);
    ///   - Apple Health stores the raw HealthKit case name with no spaces
    ///     ("TraditionalStrengthTraining"); split the camel-case so it reads
    ///     "Traditional Strength Training" instead of one run-on, all-caps word. (FER-76)
    static func displaySport(_ sport: String) -> String {
        sport == "detected" ? "Activity" : spacedActivityName(sport)
    }

    /// Insert a space at every camel-case boundary (lower/digit → Upper) so a run-on HealthKit
    /// case name reads as words. Names that already contain a space (WHOOP / manual rows like
    /// "Weight Training") are returned untouched, so this only ever expands the glued Apple names.
    static func spacedActivityName(_ raw: String) -> String {
        guard !raw.contains(" ") else { return raw }
        var out = ""
        var prev: Character?
        for ch in raw {
            if let p = prev, ch.isUppercase, p.isLowercase || p.isNumber { out.append(" ") }
            out.append(ch)
            prev = ch
        }
        return out
    }

    /// SF Symbol for a sport, matched on the lowercased name. Shared by the list and the detail so the
    /// same session shows the same glyph everywhere. Falls back to a neutral mixed-cardio figure.
    static func sfSymbol(for sport: String) -> String {
        let s = sport.lowercased()
        switch true {
        case s.contains("run"):                         return "figure.run"
        case s.contains("walk") || s.contains("hike"):  return "figure.walk"
        case s.contains("cycl") || s.contains("bike") || s.contains("ride"):
                                                         return "figure.outdoor.cycle"
        case s.contains("swim"):                        return "figure.pool.swim"
        case s.contains("row"):                         return "figure.rower"
        case s.contains("yoga"):                        return "figure.yoga"
        case s.contains("strength") || s.contains("weight") || s.contains("lift"):
                                                         return "dumbbell.fill"
        case s.contains("box"):                         return "figure.boxing"
        case s.contains("hiit") || s.contains("functional"):
                                                         return "figure.highintensity.intervaltraining"
        case s.contains("elliptical"):                  return "figure.elliptical"
        case s.contains("ski"):                         return "figure.skiing.downhill"
        case s.contains("tennis"):                      return "figure.tennis"
        case s.contains("golf"):                        return "figure.golf"
        case s.contains("soccer") || s.contains("football"):
                                                         return "figure.soccer"
        case s.contains("basketball"):                  return "figure.basketball"
        case s.contains("dance"):                       return "figure.dance"
        case s.contains("climb"):                       return "figure.climbing"
        case s.contains("pilates"):                     return "figure.pilates"
        case s.contains("meditat"):                     return "figure.mind.and.body"
        default:                                        return "figure.mixed.cardio"
        }
    }

    // MARK: - Dismissed detected bouts (durable across re-detection)
    //
    // The engine wipes + re-derives "detected" rows every run, so deleting a detected row from the
    // table would only hide it until the next analyzeRecent recreates the same (startTs, sport) PK.
    // The durable "this isn't a workout" record is a list of dismissed time spans persisted in
    // UserDefaults (the macOS WorkoutRow lives in the CenitStore Journal file, which this layer must
    // not extend with a new column). A detected row overlapping any dismissed span stays hidden.
    // (#107)

    /// UserDefaults key holding the dismissed spans as "startTs:endTs" strings.
    static let dismissedDefaultsKey = "workouts.dismissedDetected"

    /// Parse "startTs:endTs" spans (UserDefaults string array). Malformed / non-positive-width
    /// entries are dropped so a corrupt value can never hide everything.
    static func parseDismissedSpans(_ raw: [String]) -> [(start: Int, end: Int)] {
        raw.compactMap { s in
            let parts = s.split(separator: ":")
            guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), b > a else { return nil }
            return (a, b)
        }
    }

    /// The "startTs:endTs" token persisted for a dismissed row (caller appends it to the defaults list).
    static func dismissedToken(for row: WorkoutRow) -> String { "\(row.startTs):\(row.endTs)" }

    /// Read-time filter: a DETECTED row overlapping any dismissed span is hidden. Imported / manual
    /// rows are never auto-hidden (the user deletes those outright), so dismissal only applies to the
    /// re-derived detected source. Half-open overlap test: `row.start < span.end && span.start < row.end`.
    static func isDismissed(_ row: WorkoutRow, spans: [(start: Int, end: Int)]) -> Bool {
        classify(row.source) == .detected
            && spans.contains { row.startTs < $0.end && $0.start < row.endTs }
    }

    // MARK: - Building / preserving rows

    /// Carry the captured fields the add/edit sheet does NOT expose (maxHr, strain, distanceM,
    /// zonesJSON, notes) over from the row being edited. A v1.67 live-tracked session has real
    /// captured strain/maxHr; rebuilding the row from the sheet's inputs alone would silently wipe
    /// them on an edit. No-op for a fresh add (`old == nil`).
    static func preservingCaptured(_ row: WorkoutRow, from old: WorkoutRow?) -> WorkoutRow {
        guard let old else { return row }
        return WorkoutRow(startTs: row.startTs, endTs: row.endTs, sport: row.sport,
                          source: row.source, durationS: row.durationS,
                          energyKcal: row.energyKcal, avgHr: row.avgHr,
                          maxHr: old.maxHr, strain: old.strain, distanceM: old.distanceM,
                          zonesJSON: old.zonesJSON, notes: old.notes)
    }

    /// Build a retroactive manual workout (source "manual", persisted under the strap deviceId by the
    /// caller — where v1.67's live sessions live). Returns nil when the input can't make an honest row.
    /// strain/zones stay nil: with no captured HR window an APPROXIMATE strain is never fabricated.
    static func buildManualRow(start: Date, durationMin: Int, sport: String,
                               avgHr: Int?, energyKcal: Double?, now: Date = Date()) -> WorkoutRow? {
        guard durationMin > 0, durationMin <= 24 * 60 else { return nil }
        let trimmed = sport.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, start <= now else { return nil }
        if let hr = avgHr, !(25...250).contains(hr) { return nil }
        if let k = energyKcal, k < 0 || k > 20_000 { return nil }
        let s = Int(start.timeIntervalSince1970)
        guard s > 0 else { return nil }
        return WorkoutRow(startTs: s, endTs: s + durationMin * 60, sport: trimmed, source: "manual",
                          durationS: Double(durationMin) * 60, energyKcal: energyKcal,
                          avgHr: avgHr, maxHr: nil, strain: nil, distanceM: nil,
                          zonesJSON: nil, notes: nil)
    }
}
