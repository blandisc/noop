import Foundation
import StrandTraining

// MARK: - Strength CSV import (FER-328 · E8)
//
// Pure, Foundation-only reader for three dialects (Strong, Hevy, Cénit). Detects by COLUMN SET,
// never by position; normalizes BOM / UTF-16 / `;`. Persistence (`saveSessions`) lives in
// CenitStore; name reconciliation reuses `WorkoutExerciseReconciler`. No network.

/// Pure CSV → history importer for Strong / Hevy / Cénit strength exports.
public enum StrengthCSVImporter {

    public enum Dialect: String, Sendable, Equatable, CaseIterable {
        case strong
        case hevy
        case cenit
    }

    public enum ImportError: Error, Equatable, Sendable {
        /// Strong export without `Weight (kg|lbs)` and no caller-supplied unit.
        case unitRequired
        /// Header columns don't match any known dialect.
        case unknownHeader
        /// Text is empty or has no header row.
        case emptyInput
    }

    /// Why a data row (or one of its sets) was skipped — never fatal for the rest of the file.
    public struct RowIssue: Equatable, Sendable {
        public let row: Int          // 1-based data row (header = 0)
        public let reason: String
        public init(row: Int, reason: String) { self.row = row; self.reason = reason }
    }

    /// One logged set as read from the CSV (exercise still a free-text name — reconcile later).
    public struct ImportedSet: Equatable, Sendable {
        public var exerciseName: String
        public var setIndex: Int
        public var kind: SetKind
        public var mode: SetMode
        public var weightKg: Double?
        public var reps: Int?
        public var timeS: Double?
        public var distanceM: Double?
        public var rpe: Double?
        public var restTakenS: Int?
        public var notes: String?

        public init(exerciseName: String, setIndex: Int, kind: SetKind, mode: SetMode = .standard,
                    weightKg: Double? = nil, reps: Int? = nil, timeS: Double? = nil,
                    distanceM: Double? = nil, rpe: Double? = nil, restTakenS: Int? = nil,
                    notes: String? = nil) {
            self.exerciseName = exerciseName; self.setIndex = setIndex; self.kind = kind
            self.mode = mode; self.weightKg = weightKg; self.reps = reps; self.timeS = timeS
            self.distanceM = distanceM; self.rpe = rpe; self.restTakenS = restTakenS
            self.notes = notes
        }
    }

    /// One workout session grouped from one-row-per-set CSV rows.
    public struct ImportedSession: Equatable, Sendable {
        /// Deterministic id: `"\(source)-\(startTs)"`.
        public var id: String
        public var source: String          // "strong" | "hevy" | "cenit"
        public var startTs: Int
        public var endTs: Int?
        public var title: String
        public var notes: String?
        public var sets: [ImportedSet]
        /// `true` when at least one kept set carries an in-range RPE (drives session prefill).
        public var hasPerSetRPE: Bool

        public init(id: String, source: String, startTs: Int, endTs: Int?, title: String,
                    notes: String?, sets: [ImportedSet], hasPerSetRPE: Bool) {
            self.id = id; self.source = source; self.startTs = startTs; self.endTs = endTs
            self.title = title; self.notes = notes; self.sets = sets; self.hasPerSetRPE = hasPerSetRPE
        }
    }

    /// An imported session that overlaps an already-stored one from another origin (±30 min).
    public struct PossibleDuplicate: Equatable, Sendable {
        public var session: ImportedSession
        public var existingId: String
        public var existingSource: String?
        public var existingTitle: String?
        public var existingStartTs: Int
        public init(session: ImportedSession, existingId: String, existingSource: String?,
                    existingTitle: String?, existingStartTs: Int) {
            self.session = session; self.existingId = existingId
            self.existingSource = existingSource; self.existingTitle = existingTitle
            self.existingStartTs = existingStartTs
        }
    }

    public struct ImportedStrengthHistory: Equatable, Sendable {
        public var sessions: [ImportedSession]
        public var skipped: [RowIssue]
        /// Cross-origin overlaps at ±30 min. Default **out** of the import (N5); UI toggles force-in.
        public var possibleDuplicates: [PossibleDuplicate]
        /// The weight unit this file actually carries — Strong's own header/user pick, `.kg` for
        /// Hevy/Cénit (always normalized to kg on parse). QA D7 / E9: the screen's «Weight unit» row
        /// reads this instead of assuming kg.
        public var declaredUnit: WorkoutWeightUnit?

        public init(sessions: [ImportedSession], skipped: [RowIssue] = [],
                    possibleDuplicates: [PossibleDuplicate] = [], declaredUnit: WorkoutWeightUnit? = nil) {
            self.sessions = sessions; self.skipped = skipped
            self.possibleDuplicates = possibleDuplicates
            self.declaredUnit = declaredUnit
        }
    }

    /// Window used for «Posibles duplicados» (N5 / C8).
    public static let duplicateWindowSeconds: Int = 30 * 60

    // MARK: - Detect

    /// Detect dialect by the **set of column names** (never position). Returns `nil` for unknown.
    public static func detectDialect(header: String) -> Dialect? {
        let cols = Set(normalizedHeaderColumns(header))
        guard !cols.isEmpty else { return nil }
        if isHevy(cols) { return .hevy }
        if isStrong(cols) { return .strong }
        if isCenit(cols) { return .cenit }
        return nil
    }

    // MARK: - Parse

    /// Parse `text` as `dialect`. For Strong without a unit in the header, `weightUnit` is mandatory
    /// (`throw .unitRequired`). Hevy/Cénit ignore `weightUnit` (unit is in the header / always kg).
    public static func parse(text: String, dialect: Dialect,
                             weightUnit: WorkoutWeightUnit? = nil) throws -> ImportedStrengthHistory {
        let normalized = normalizeText(text)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyInput
        }
        let rows = CSV.parse(normalized)
        guard let headerRow = rows.first else { throw ImportError.emptyInput }
        let columns = headerRow.map { normalizeColumnName($0) }
        let colSet = Set(columns)

        switch dialect {
        case .hevy:
            guard isHevy(colSet) else { throw ImportError.unknownHeader }
            var result = try parseHevy(rows: rows, columns: columns)
            result.declaredUnit = .kg
            return result
        case .strong:
            guard isStrong(colSet) else { throw ImportError.unknownHeader }
            let unit = strongUnit(from: colSet) ?? weightUnit
            guard let unit else { throw ImportError.unitRequired }
            var result = try parseStrong(rows: rows, columns: columns, unit: unit)
            result.declaredUnit = unit
            return result
        case .cenit:
            guard isCenit(colSet) else { throw ImportError.unknownHeader }
            var result = try parseCenit(rows: rows, columns: columns)
            result.declaredUnit = .kg
            return result
        }
    }

    /// Convenience: detect then parse. Throws `.unknownHeader` when detection fails.
    public static func parse(text: String, weightUnit: WorkoutWeightUnit? = nil) throws -> ImportedStrengthHistory {
        let normalized = normalizeText(text)
        let firstLine = normalized.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard let dialect = detectDialect(header: firstLine) else { throw ImportError.unknownHeader }
        return try parse(text: normalized, dialect: dialect, weightUnit: weightUnit)
    }

    /// Decode raw file bytes (UTF-8 / UTF-16 LE/BE with or without BOM) then parse. QA D3 / E9.
    public static func parse(data: Data, dialect: Dialect? = nil,
                             weightUnit: WorkoutWeightUnit? = nil) throws -> ImportedStrengthHistory {
        let text = try decodeCSVData(data)
        if let dialect {
            return try parse(text: text, dialect: dialect, weightUnit: weightUnit)
        }
        return try parse(text: text, weightUnit: weightUnit)
    }

    /// Highest numeric value in Strong's `Weight` column before unit conversion — drives the
    /// «315 → 143 kg» hint when the file omits the unit and the UI must ask (E9).
    public static func strongMaxWeightRaw(text: String) -> Double? {
        let normalized = normalizeText(text)
        let rows = CSV.parse(normalized)
        guard let header = rows.first else { return nil }
        let cols = header.map { normalizeColumnName($0) }
        guard isStrong(Set(cols)) else { return nil }
        // Prefer an explicit unit column name; legacy Strong uses plain `Weight`.
        let weightKeys = ["weight (kg)", "weight (lbs)", "weight (lb)", "weight"]
        guard let wi = cols.firstIndex(where: { weightKeys.contains($0) }) else { return nil }
        var maxV: Double?
        for row in rows.dropFirst() {
            guard wi < row.count else { continue }
            let raw = row[wi].trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let v = Double(raw), v > 0 else { continue }
            maxV = max(maxV ?? v, v)
        }
        return maxV
    }

    // MARK: - Duplicates (pure)

    /// Annotate cross-origin overlaps within ±`duplicateWindowSeconds`. Exact id matches are NOT
    /// listed here — those are «ya estaban» via `existingSessionIds`.
    public static func annotateDuplicates(
        _ history: ImportedStrengthHistory,
        existing: [(id: String, source: String?, title: String?, startTs: Int)]
    ) -> ImportedStrengthHistory {
        var dups: [PossibleDuplicate] = []
        for session in history.sessions {
            for ex in existing {
                if ex.id == session.id { continue }
                let sameSource = (ex.source ?? "") == session.source
                if sameSource { continue }
                if abs(ex.startTs - session.startTs) <= duplicateWindowSeconds {
                    dups.append(PossibleDuplicate(
                        session: session, existingId: ex.id, existingSource: ex.source,
                        existingTitle: ex.title, existingStartTs: ex.startTs))
                    break
                }
            }
        }
        var out = history
        out.possibleDuplicates = dups
        return out
    }

    // MARK: - Materialize → StrengthSession + SetEntry (no strain math)

    /// Build a `StrengthSession` + `SetEntry`s from an imported session after names are mapped to
    /// catalog ids. `sessionRpe` / `.prefill` ONLY when the CSV brought per-set RPE (director note);
    /// without RPE both stay nil — nothing is invented. `strain` / `strainSource` stay nil here: the
    /// app save path decides them (`.rpe` when effort is present, else nil without pulse).
    public static func materialize(
        _ session: ImportedSession,
        exerciseIdByName: (String) -> String?
    ) -> (StrengthSession, [SetEntry])? {
        var entries: [SetEntry] = []
        var position = 0
        for set in session.sets {
            guard let exerciseId = exerciseIdByName(set.exerciseName) else { continue }
            entries.append(SetEntry(
                sessionId: session.id, exerciseId: exerciseId, position: position,
                kind: set.kind, weightKg: set.weightKg, reps: set.reps, timeS: set.timeS,
                distanceM: set.distanceM, done: true, ts: session.startTs, rpe: set.rpe,
                restTakenS: set.restTakenS, mode: set.mode))
            position += 1
        }
        guard !entries.isEmpty else { return nil }

        let prefill: Double? = session.hasPerSetRPE ? SessionRPE.prefill(sets: entries) : nil
        let strength = StrengthSession(
            id: session.id, routineId: nil, startTs: session.startTs, endTs: session.endTs,
            deviceId: nil, strain: nil, avgHr: nil, notes: session.notes,
            strainSource: nil, sessionRpe: prefill,
            sessionRpeSource: prefill == nil ? nil : .prefill,
            source: session.source, title: session.title)
        return (strength, entries)
    }
}

// MARK: - Dialect column sets

private extension StrengthCSVImporter {
    static func isHevy(_ cols: Set<String>) -> Bool {
        cols.contains("exercise_title")
            && cols.contains("set_type")
            && (cols.contains("weight_kg") || cols.contains("weight_lbs"))
    }

    static func isStrong(_ cols: Set<String>) -> Bool {
        cols.contains("exercise name")
            && cols.contains("set order")
            && cols.contains("workout name")
    }

    static func isCenit(_ cols: Set<String>) -> Bool {
        // Own export: `exercise` + `set_kind` + `weight_kg` (and usually `set_mode` / `rest_taken_s`).
        cols.contains("exercise") && cols.contains("set_kind") && cols.contains("weight_kg")
            && cols.contains("set_index")
            && !cols.contains("exercise_title")
            && !cols.contains("exercise name")
    }

    static func strongUnit(from cols: Set<String>) -> WorkoutWeightUnit? {
        if cols.contains("weight (kg)") { return .kg }
        if cols.contains("weight (lbs)") || cols.contains("weight (lb)") { return .lb }
        return nil
    }
}

// MARK: - Hevy

private extension StrengthCSVImporter {
    static func parseHevy(rows: [[String]], columns: [String]) throws -> ImportedStrengthHistory {
        let idx = ColumnIndex(columns)
        let unit: WorkoutWeightUnit = columns.contains("weight_lbs") ? .lb : .kg
        let distanceIsMiles = columns.contains("distance_miles")

        var skipped: [RowIssue] = []
        // key = title + startTs
        var order: [String] = []
        var buckets: [String: DraftSession] = [:]

        for (i, row) in rows.dropFirst().enumerated() {
            let rowNum = i + 1
            let title = idx.string("title", in: row)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let startRaw = idx.string("start_time", in: row) ?? ""
            guard let start = parseHevyDate(startRaw) else {
                skipped.append(RowIssue(row: rowNum, reason: "unparseable start_time"))
                continue
            }
            let startTs = Int(start.timeIntervalSince1970)
            let endTs = (idx.string("end_time", in: row)).flatMap(parseHevyDate).map { Int($0.timeIntervalSince1970) }
            let description = emptyToNil(idx.string("description", in: row))
            let exercise = idx.string("exercise_title", in: row)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if exercise.isEmpty {
                skipped.append(RowIssue(row: rowNum, reason: "empty exercise_title"))
                continue
            }

            let setTypeRaw = (idx.string("set_type", in: row) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let mapped = mapHevySetType(setTypeRaw) else {
                skipped.append(RowIssue(row: rowNum, reason: "unknown set_type \(setTypeRaw)"))
                continue
            }
            let (kind, mode, forceRPE10) = mapped

            let setIndex = (idx.int("set_index", in: row) ?? 0) + 1  // Hevy is 0-based; we store 1-based
            let weightCol = unit == .lb ? "weight_lbs" : "weight_kg"
            let weightRaw = idx.double(weightCol, in: row)
            let weightKg = weightRaw.map { roundKg(unit.toKilograms($0)) }
            if let w = weightKg, w < 0 {
                skipped.append(RowIssue(row: rowNum, reason: "negative weight"))
                continue
            }
            let reps = idx.int("reps", in: row)
            if let r = reps, r < 0 {
                skipped.append(RowIssue(row: rowNum, reason: "negative reps"))
                continue
            }
            // reps == 0 → skip the set (edge 6)
            if reps == 0 {
                skipped.append(RowIssue(row: rowNum, reason: "zero reps"))
                continue
            }

            let distanceRaw = distanceIsMiles
                ? idx.double("distance_miles", in: row)
                : idx.double("distance_km", in: row)
            let distanceM = distanceRaw.map { distanceIsMiles ? $0 * 1609.344 : $0 * 1000 }
            let timeS = idx.double("duration_seconds", in: row)
            var rpe = sanitizeRPE(idx.double("rpe", in: row))
            if forceRPE10 { rpe = 10 }
            let notes = emptyToNil(idx.string("exercise_notes", in: row))

            let key = "hevy-\(startTs)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = DraftSession(id: key, source: "hevy", startTs: startTs, endTs: endTs,
                                            title: title.isEmpty ? "Hevy" : title, notes: description)
            } else if buckets[key]?.endTs == nil {
                buckets[key]?.endTs = endTs
            }

            buckets[key]?.sets.append(ImportedSet(
                exerciseName: exercise, setIndex: setIndex, kind: kind, mode: mode,
                weightKg: weightKg, reps: reps, timeS: timeS, distanceM: distanceM,
                rpe: rpe, notes: notes))
        }

        return finish(order: order, buckets: buckets, skipped: skipped)
    }

    /// `nil` = skip (unknown). Empty/`normal` → work; `warmup` → warmup; `failure` → work+RPE10;
    /// `dropset`/`drop_set` → work+drop.
    static func mapHevySetType(_ raw: String) -> (SetKind, SetMode, forceRPE10: Bool)? {
        switch raw {
        case "", "normal":           return (.work, .standard, false)
        case "warmup", "warm-up":    return (.warmup, .standard, false)
        case "failure":              return (.work, .standard, true)
        case "dropset", "drop_set", "drop set": return (.work, .drop, false)
        default:                     return nil
        }
    }
}

// MARK: - Strong

private extension StrengthCSVImporter {
    static func parseStrong(rows: [[String]], columns: [String],
                            unit: WorkoutWeightUnit) throws -> ImportedStrengthHistory {
        let idx = ColumnIndex(columns)
        let weightKey = columns.first(where: {
            let n = normalizeColumnName($0)
            return n == "weight" || n == "weight (kg)" || n == "weight (lbs)" || n == "weight (lb)"
        }).map(normalizeColumnName) ?? "weight"

        var skipped: [RowIssue] = []
        var order: [String] = []
        var buckets: [String: DraftSession] = [:]

        for (i, row) in rows.dropFirst().enumerated() {
            let rowNum = i + 1
            let dateRaw = idx.string("date", in: row) ?? ""
            guard let start = parseStrongDate(dateRaw) else {
                skipped.append(RowIssue(row: rowNum, reason: "unparseable Date"))
                continue
            }
            let startTs = Int(start.timeIntervalSince1970)
            let title = idx.string("workout name", in: row)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let exercise = idx.string("exercise name", in: row)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if exercise.isEmpty {
                skipped.append(RowIssue(row: rowNum, reason: "empty Exercise Name"))
                continue
            }

            let orderRaw = (idx.string("set order", in: row) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: SetKind
            let setIndex: Int
            if orderRaw.uppercased() == "W" {
                kind = .warmup
                setIndex = 0
            } else if let n = Int(orderRaw), n > 0 {
                kind = .work
                setIndex = n
            } else {
                skipped.append(RowIssue(row: rowNum, reason: "unknown Set Order \(orderRaw)"))
                continue
            }

            let weightRaw = idx.double(weightKey, in: row)
            let weightKg = weightRaw.map { roundKg(unit.toKilograms($0)) }
            if let w = weightKg, w < 0 {
                skipped.append(RowIssue(row: rowNum, reason: "negative weight"))
                continue
            }
            let reps = idx.int("reps", in: row)
            if reps == 0 {
                skipped.append(RowIssue(row: rowNum, reason: "zero reps"))
                continue
            }
            let distanceM = idx.double("distance", in: row)  // Strong exports meters
            let timeS = idx.double("seconds", in: row)
            let rpe = sanitizeRPE(idx.double("rpe", in: row))
            let notes = emptyToNil(idx.string("notes", in: row))
            let workoutNotes = emptyToNil(idx.string("workout notes", in: row))
            let durationS = parseStrongDuration(idx.string("duration", in: row) ?? "")
            let endTs = durationS.map { startTs + $0 }

            let key = "strong-\(startTs)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = DraftSession(id: key, source: "strong", startTs: startTs, endTs: endTs,
                                            title: title.isEmpty ? "Strong" : title, notes: workoutNotes)
            } else if buckets[key]?.endTs == nil, let endTs {
                buckets[key]?.endTs = endTs
            }

            buckets[key]?.sets.append(ImportedSet(
                exerciseName: exercise, setIndex: max(setIndex, 1), kind: kind, mode: .standard,
                weightKg: weightKg, reps: reps, timeS: timeS, distanceM: distanceM,
                rpe: rpe, notes: notes))
        }

        return finish(order: order, buckets: buckets, skipped: skipped)
    }
}

// MARK: - Cénit

private extension StrengthCSVImporter {
    static func parseCenit(rows: [[String]], columns: [String]) throws -> ImportedStrengthHistory {
        let idx = ColumnIndex(columns)
        var skipped: [RowIssue] = []
        var order: [String] = []
        var buckets: [String: DraftSession] = [:]

        for (i, row) in rows.dropFirst().enumerated() {
            let rowNum = i + 1
            let dateRaw = idx.string("date", in: row) ?? ""
            guard let start = parseCenitDate(dateRaw) else {
                skipped.append(RowIssue(row: rowNum, reason: "unparseable date"))
                continue
            }
            let startTs = Int(start.timeIntervalSince1970)
            let exercise = idx.string("exercise", in: row)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if exercise.isEmpty {
                skipped.append(RowIssue(row: rowNum, reason: "empty exercise"))
                continue
            }
            let setIndex = idx.int("set_index", in: row) ?? 1
            let kindRaw = (idx.string("set_kind", in: row) ?? "work").lowercased()
            let kind: SetKind = kindRaw == "warmup" ? .warmup : .work
            let mode = parseSetMode(idx.string("set_mode", in: row))
            let weightKg = idx.double("weight_kg", in: row).map(roundKg)
            let reps = idx.int("reps", in: row)
            let timeS = idx.double("time_s", in: row)
            let distanceM = idx.double("distance_m", in: row)
            let rpe = sanitizeRPE(idx.double("rpe", in: row))
            let restTakenS = idx.int("rest_taken_s", in: row)
            let notes = emptyToNil(idx.string("notes", in: row))
            let routine = emptyToNil(idx.string("routine", in: row))

            let key = "cenit-\(startTs)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = DraftSession(id: key, source: "cenit", startTs: startTs, endTs: nil,
                                            title: routine ?? "Cénit", notes: nil)
            }
            buckets[key]?.sets.append(ImportedSet(
                exerciseName: exercise, setIndex: setIndex, kind: kind, mode: mode,
                weightKg: weightKg, reps: reps, timeS: timeS, distanceM: distanceM,
                rpe: rpe, restTakenS: restTakenS, notes: notes))
        }

        return finish(order: order, buckets: buckets, skipped: skipped)
    }

    /// Accepts lowercase (what `StrengthCSV` writes) and uppercase; blank / `standard` → `.standard`.
    static func parseSetMode(_ raw: String?) -> SetMode {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch v {
        case "", "standard", "normal": return .standard
        case "amrap": return .amrap
        case "drop": return .drop
        default: return .standard
        }
    }
}

// MARK: - Shared draft → history

private extension StrengthCSVImporter {
    struct DraftSession {
        var id: String
        var source: String
        var startTs: Int
        var endTs: Int?
        var title: String
        var notes: String?
        var sets: [ImportedSet] = []
    }

    static func finish(order: [String], buckets: [String: DraftSession],
                       skipped: [RowIssue]) -> ImportedStrengthHistory {
        var sessions: [ImportedSession] = []
        var moreSkipped = skipped
        for key in order {
            guard var draft = buckets[key], !draft.sets.isEmpty else {
                moreSkipped.append(RowIssue(row: 0, reason: "session without valid sets (\(key))"))
                continue
            }
            let hasRPE = draft.sets.contains { $0.rpe != nil }
            sessions.append(ImportedSession(
                id: draft.id, source: draft.source, startTs: draft.startTs, endTs: draft.endTs,
                title: draft.title, notes: draft.notes, sets: draft.sets, hasPerSetRPE: hasRPE))
        }
        return ImportedStrengthHistory(sessions: sessions, skipped: moreSkipped)
    }
}

// MARK: - Dates, duration, RPE, text

private extension StrengthCSVImporter {
    /// Strong: `yyyy-MM-dd HH:mm:ss` in the account's local zone (no offset in the file).
    static func parseStrongDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: trimmed) { return d }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: trimmed)
    }

    /// Hevy: `d MMM yyyy, HH:mm` with month in the account language. Table covers en/es/pt/fr/de.
    static func parseHevyDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // "15 Sep 2025, 07:48" / "15 septiembre 2025, 07:48" / "30 juin 2026, 18:21"
        let pattern = #"^(\d{1,2})\s+(\S+)\s+(\d{4}),?\s+(\d{1,2}):(\d{2})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges == 6,
              let dayR = Range(match.range(at: 1), in: trimmed),
              let monR = Range(match.range(at: 2), in: trimmed),
              let yearR = Range(match.range(at: 3), in: trimmed),
              let hourR = Range(match.range(at: 4), in: trimmed),
              let minR = Range(match.range(at: 5), in: trimmed),
              let day = Int(trimmed[dayR]),
              let year = Int(trimmed[yearR]),
              let hour = Int(trimmed[hourR]),
              let minute = Int(trimmed[minR])
        else { return nil }

        var monthToken = String(trimmed[monR]).lowercased()
        if monthToken.hasSuffix(".") { monthToken.removeLast() }
        guard let month = hevyMonths[monthToken] else { return nil }

        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return Calendar.current.date(from: comps)
    }

    static let hevyMonths: [String: Int] = {
        var m: [String: Int] = [:]
        let pairs: [(Int, [String])] = [
            (1,  ["jan", "january", "ene", "enero", "janv", "janvier", "januar", "janeiro"]),
            (2,  ["feb", "february", "feb", "febrero", "févr", "fevr", "février", "fevrier", "februar", "fevereiro"]),
            (3,  ["mar", "march", "marzo", "mars", "märz", "marz", "março", "marco"]),
            (4,  ["apr", "april", "abr", "abril", "avr", "avril", "april"]),
            (5,  ["may", "mayo", "mai", "maio"]),
            (6,  ["jun", "june", "junio", "juin", "juni", "junho"]),
            (7,  ["jul", "july", "julio", "juil", "juillet", "juli", "julho"]),
            (8,  ["aug", "august", "ago", "agosto", "août", "aout", "august"]),
            (9,  ["sep", "sept", "september", "septiembre", "set", "setiembre", "septembre", "setembro"]),
            (10, ["oct", "october", "octubre", "octobre", "oktober", "outubro"]),
            (11, ["nov", "november", "noviembre", "novembre", "novembro"]),
            (12, ["dec", "december", "dic", "diciembre", "déc", "décembre", "decembre", "dez", "dezember", "dezembro"]),
        ]
        for (num, names) in pairs {
            for n in names { m[n] = num }
        }
        return m
    }()

    static func parseCenitDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let d = iso.date(from: trimmed) { return d }
        return parseStrongDate(trimmed)
    }

    /// Strong Duration: `35m`, `1h 5m`, `1h5m`, or `MM:SS` / `H:MM:SS`.
    static func parseStrongDuration(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        if s.contains("h") || s.contains("m") {
            var total = 0
            let hRe = try? NSRegularExpression(pattern: #"(\d+)\s*h"#)
            let mRe = try? NSRegularExpression(pattern: #"(\d+)\s*m"#)
            let range = NSRange(s.startIndex..., in: s)
            if let m = hRe?.firstMatch(in: s, range: range), let r = Range(m.range(at: 1), in: s),
               let h = Int(s[r]) { total += h * 3600 }
            if let m = mRe?.firstMatch(in: s, range: range), let r = Range(m.range(at: 1), in: s),
               let mins = Int(s[r]) { total += mins * 60 }
            return total > 0 ? total : nil
        }
        let parts = s.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]           // MM:SS (or H:MM when short workouts)
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    /// RPE outside 6…10 → `nil` (never clamp). Matches CONSOLIDACION E12.
    static func sanitizeRPE(_ value: Double?) -> Double? {
        guard let v = value else { return nil }
        return (v >= 6 && v <= 10) ? v : nil
    }

    static func roundKg(_ kg: Double) -> Double {
        (kg * 100).rounded() / 100
    }

    static func emptyToNil(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Decode CSV file bytes: UTF-8 BOM, UTF-16 LE/BE BOM, then plain UTF-8 / UTF-16 fallbacks (E9).
    static func decodeCSVData(_ data: Data) throws -> String {
        if data.isEmpty { throw ImportError.emptyInput }
        // UTF-8 BOM EF BB BF — strip then decode the rest as UTF-8.
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            guard let s = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw ImportError.emptyInput
            }
            return s
        }
        // UTF-16 LE BOM FF FE / BE BOM FE FF — include BOM so String drops it.
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            guard let s = String(data: data, encoding: .utf16LittleEndian) else {
                throw ImportError.emptyInput
            }
            return s
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            guard let s = String(data: data, encoding: .utf16BigEndian) else {
                throw ImportError.emptyInput
            }
            return s
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if let s = String(data: data, encoding: .utf16BigEndian) { return s }
        throw ImportError.emptyInput
    }

    /// Strip UTF-8 BOM; decode UTF-16 LE/BE when a BOM is present; prefer `;` when it dominates.
    static func normalizeText(_ text: String) -> String {
        var s = text
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        // CRLF (RFC 4180, Excel, Windows) is ONE `Character` in Swift, so a char-by-char scanner that
        // tests "\r" and "\n" separately never sees a line break and the whole file collapses into a
        // single header row — zero sessions, zero issues (gate /qa FER-328 D1). Normalize once here.
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        // UTF-16 BOM as decoded by String sometimes appears as the replacement for raw bytes —
        // callers typically already decoded; handle the common UTF-8 BOM above.
        // Semicolon-delimited (Excel locales): rewrite the first line's separator if needed is
        // handled inside CSV.parse via delimiter sniff on the header.
        return s
    }

    static func normalizedHeaderColumns(_ header: String) -> [String] {
        let line = header.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        let delim: Character = line.filter { $0 == ";" }.count > line.filter { $0 == "," }.count ? ";" : ","
        return CSV.parseLine(line, delimiter: delim).map(normalizeColumnName)
    }

    static func normalizeColumnName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .lowercased()
    }
}

// MARK: - Tiny column index + CSV reader

private struct ColumnIndex {
    let map: [String: Int]
    init(_ columns: [String]) {
        var m: [String: Int] = [:]
        for (i, c) in columns.enumerated() {
            let key = StrengthCSVImporterHelpers.normalize(c)
            if m[key] == nil { m[key] = i }
        }
        map = m
    }
    func string(_ name: String, in row: [String]) -> String? {
        guard let i = map[name], i < row.count else { return nil }
        return row[i]
    }
    func double(_ name: String, in row: [String]) -> Double? {
        guard let s = string(name, in: row)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return Double(s.replacingOccurrences(of: ",", with: "."))
    }
    func int(_ name: String, in row: [String]) -> Int? {
        // Guarda de finitud y rango: una celda "nan"/"inf"/"1e999"/gigante en un CSV de terceros
        // hacía de `Int(d)` un trap fatal que tumbaba TODA la importación. Paridad con
        // WorkoutProgram/DietPlan (que ya guardan isFinite). Celda mala → nil (se ignora), no crash.
        guard let d = double(name, in: row), d.isFinite,
              d >= Double(Int.min), d <= Double(Int.max) else { return nil }
        return Int(d)
    }
}

/// Expose normalize to ColumnIndex without leaking it.
private enum StrengthCSVImporterHelpers {
    static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .lowercased()
    }
}

private enum CSV {
    static func parse(_ input: String) -> [[String]] {
        let delim: Character = {
            let header = input.prefix(while: { $0 != "\n" && $0 != "\r" })
            let semis = header.filter { $0 == ";" }.count
            let commas = header.filter { $0 == "," }.count
            return semis > commas ? ";" : ","
        }()
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\""); i += 2; continue
                    }
                    inQuotes = false; i += 1; continue
                }
                field.append(c); i += 1; continue
            }
            switch c {
            case "\"":
                inQuotes = true; i += 1
            case delim:
                row.append(field); field = ""; i += 1
            case "\r":
                if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if !row.isEmpty || !rows.isEmpty { rows.append(row) }
                row = []; i += 1
            case "\n":
                row.append(field); field = ""
                if !row.isEmpty || !rows.isEmpty { rows.append(row) }
                row = []; i += 1
            default:
                field.append(c); i += 1
            }
        }
        if inQuotes || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Drop a trailing empty row produced by a final newline.
        if let last = rows.last, last.count == 1, last[0].isEmpty { rows.removeLast() }
        return rows
    }

    static func parseLine(_ line: String, delimiter: Character) -> [String] {
        parse(String(line) + "\n").first ?? []
    }
}
