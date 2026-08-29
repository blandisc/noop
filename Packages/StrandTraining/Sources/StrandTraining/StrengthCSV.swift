import Foundation

/// CSV export of the strength-training history (FER-224) — one of the 3 "must-have" gaps against
/// Hevy. Pure, Foundation-only generator: it never touches GRDB or the catalog directly. The caller
/// (app layer) resolves ids to display data — routine name, exercise name, notes text — and streams
/// `Row`s in, session by session, so the whole history never has to sit in memory as one array.
public enum StrengthCSV {

    /// Column order is part of the contract with the user (they'll open this in Excel/Numbers/Sheets).
    public static let header =
        "date,routine,exercise,set_index,set_kind,weight_kg,reps,time_s,distance_m,rpe,rest_taken_s,notes"

    /// One exported row: a single logged set, already resolved to the names/values the user reads
    /// (never a raw id) so this file is useful standalone.
    public struct Row: Equatable {
        public let date: Date
        public let routineName: String?
        public let exerciseName: String
        /// 1-based position of this set within its session (matches what the app shows as "serie N").
        public let setIndex: Int
        public let setKind: SetKind
        public let weightKg: Double?
        public let reps: Int?
        public let timeS: Double?
        public let distanceM: Double?
        public let rpe: Double?
        public let restTakenS: Int?
        public let notes: String?

        public init(date: Date, routineName: String?, exerciseName: String, setIndex: Int,
                    setKind: SetKind, weightKg: Double?, reps: Int?, timeS: Double?,
                    distanceM: Double?, rpe: Double?, restTakenS: Int?, notes: String?) {
            self.date = date; self.routineName = routineName; self.exerciseName = exerciseName
            self.setIndex = setIndex; self.setKind = setKind; self.weightKg = weightKg
            self.reps = reps; self.timeS = timeS; self.distanceM = distanceM; self.rpe = rpe
            self.restTakenS = restTakenS; self.notes = notes
        }
    }

    /// One CSV data line (no trailing newline) for a single logged set. A fresh `ISO8601DateFormatter`
    /// per call (not a shared `static let`) — it's a mutable `Foundation` object and this generator
    /// must stay `Sendable`-clean; formatting one line is cheap next to a DB round trip.
    public static func line(for row: Row) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var fields: [String] = []
        fields.append(dateFormatter.string(from: row.date))
        fields.append(escape(row.routineName ?? ""))
        fields.append(escape(row.exerciseName))
        fields.append(String(row.setIndex))
        fields.append(row.setKind.rawValue)
        fields.append(row.weightKg.map(numberString) ?? "")
        fields.append(row.reps.map(String.init) ?? "")
        fields.append(row.timeS.map(numberString) ?? "")
        fields.append(row.distanceM.map(numberString) ?? "")
        fields.append(row.rpe.map(numberString) ?? "")
        fields.append(row.restTakenS.map(String.init) ?? "")
        fields.append(escape(row.notes ?? ""))
        return fields.joined(separator: ",")
    }

    /// Appends one CSV line per row (each followed by `\n`) to `output`. Streams — the caller passes
    /// one session's rows at a time instead of materializing the entire history as a single array, so
    /// memory stays bounded by one session's set count, not the whole history.
    public static func appendRows(_ rows: some Sequence<Row>, to output: inout String) {
        for row in rows {
            output += line(for: row)
            output += "\n"
        }
    }

    /// RFC 4180-ish CSV field escaping: quote the field and double any embedded quotes whenever it
    /// contains a comma, a double quote, or a line break — the three characters that would otherwise
    /// split or corrupt the column.
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Trims a trailing ".0" from whole numbers (e.g. weight "60" instead of "60.0") while keeping
    /// fractional precision (e.g. "62.5") — matches how the app already displays these values.
    private static func numberString(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
}
