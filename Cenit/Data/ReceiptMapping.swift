#if os(iOS)
import Foundation
import StrandDesign
import StrandAnalytics
import StrandTraining
import BiometricStreams

// ReceiptMapping.swift — pure StrengthSummary → ThermalReceipt mapper for the workout receipt printer.
// No view code. Deterministic (stable order #, barcode seed) so the same session always reprints the
// same face. Mirrors TicketMapping's shape/idioms.

enum ReceiptMapping {

    /// Map a finished strength session onto the thermal-ticket model.
    /// - Parameters:
    ///   - hrr: Screen-computed HRR-60s drop (bpm) + arrow direction; nil omits the row entirely.
    ///   - age: Years for HR-zone edges; nil → 35 (honest fallback when profile is unset).
    static func receipt(
        summary: StrengthSummary,
        sessionId: String,
        sets: [SetEntry],
        exerciseNames: [String: String],
        hr: [HRSample],
        age: Double?,
        hrr: (bpm: Int, risingIsGood: Bool)?,
        system: UnitSystem
    ) -> ThermalReceipt {
        let orderN = orderNumber(for: sessionId)
        let end = Date(timeIntervalSince1970: TimeInterval(summary.endTs))
        let type = ticketType(from: summary.routineName)
        let workSets = sets.filter { $0.kind == .work && $0.done }
        let idsByName = invertNames(exerciseNames)
        let zoneSet = HRZones.zones(age: age ?? 35)

        let items: [ThermalReceipt.Item] = summary.exercises.map { line in
            let ids = idsByName[line.name] ?? []
            let exWork = workSets.filter { ids.contains($0.exerciseId) }
            let topReps = topReps(from: exWork)
            let volume = exerciseVolume(exWork)
            let zone = dominantZone(sets: exWork, hr: hr, zoneSet: zoneSet)
            return ThermalReceipt.Item(
                zone: zone,
                name: line.name,
                isRecord: summary.prs.contains { $0.exercise == line.name },
                detail: detailString(setCount: line.setCount, topReps: topReps,
                                     topWeightKg: line.topWeightKg, system: system),
                price: groupedVolume(volume, system: system)
            )
        }

        let (totalValue, totalUnit) = volumeParts(summary.volumeKg, system: system)

        return ThermalReceipt(
            kind: String(format: String(localized: "recibo.tipo.fmt", defaultValue: "STRENGTH · %@"), type),
            orderLine: String(format: String(localized: "recibo.orden.fmt", defaultValue: "ORDER:#%@ · %@"), orderN, orderDateTime(end)),
            items: items,
            totalCaption: String(format: String(localized: "recibo.total.caption.fmt", defaultValue: "%lld exercises · %lld sets"), summary.exercises.count, summary.setCount),
            total: "\(totalValue) \(totalUnit)",
            zones: zoneSlices(hr: hr, zoneSet: zoneSet),
            summary: summaryRows(summary: summary, hrr: hrr),
            footerCode: "CENIT · \(orderN) · \(year(end))",
            footerTag: String(localized: "recibo.tagline", defaultValue: "your effort, in ink."),
            barcodeSeed: sessionId,
            recordBadge: String(localized: "recibo.record", defaultValue: "RECORD")
        )
    }

    // MARK: - Reconstruct a summary for a REPRINT (saved-tickets grid)

    /// Rebuild a minimal `StrengthSummary` from a stored session so a saved ticket can reprint the full
    /// receipt. Honest for a reprint: **no PRs** (records aren't re-derived here, so no record tags) and
    /// no comparison — just the itemized core the ticket needs. `strain`/`avgHr`/`energyKcal` come straight
    /// from the stored session; the per-exercise lines are grouped from the session's work sets.
    static func summary(session: StrengthSession, sets: [SetEntry],
                        exerciseNames: [String: String], routineName: String) -> StrengthSummary {
        let work = sets.filter { $0.kind == .work && $0.done }
        let end = session.endTs ?? session.startTs
        let volume = work.reduce(0.0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }

        var order: [String] = []
        var byEx: [String: [SetEntry]] = [:]
        for s in work.sorted(by: { $0.position < $1.position }) {
            if byEx[s.exerciseId] == nil { order.append(s.exerciseId) }
            byEx[s.exerciseId, default: []].append(s)
        }
        let exercises: [StrengthSummary.ExerciseLine] = order.map { id in
            let es = byEx[id] ?? []
            return StrengthSummary.ExerciseLine(
                name: exerciseNames[id] ?? String(localized: "Exercise"),
                setCount: es.count,
                topWeightKg: es.compactMap(\.weightKg).max(),
                topTimeS: es.compactMap(\.timeS).max().map { Int($0.rounded()) },
                topDistanceM: es.compactMap(\.distanceM).max(),
                trend: nil
            )
        }
        return StrengthSummary(
            routineName: routineName,
            endTs: end,
            durationS: max(0, end - session.startTs),
            volumeKg: volume,
            setCount: work.count,
            strain: session.strain,
            avgHr: session.avgHr,
            costBand: nil,
            costTomorrowPct: nil,
            energyKcal: session.energyKcal,
            energySource: session.energySource,
            prs: [],
            muscles: [],
            isFirstTime: false,
            comparison: nil,
            exercises: exercises
        )
    }

    // MARK: - Order · date · type

    private static func orderNumber(for sessionId: String) -> String {
        let n = Int(stableHash(sessionId) % 10_000)
        return String(format: "%04d", n)
    }

    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 14_695_981_039_346_656_03
        for u in s.unicodeScalars {
            h = (h ^ UInt64(u.value)) &* 1_099_511_628_211
        }
        return h
    }

    private static let orderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f
    }()

    private static func orderDateTime(_ date: Date) -> String {
        orderDateFormatter.string(from: date).uppercased()
    }

    private static func year(_ date: Date) -> String {
        let y = Calendar.current.component(.year, from: date)
        return "\(y)"
    }

    /// Keyword match on the routine name — same idea as `TicketMapping.ticketType`.
    ///
    /// El MATCH se queda en español (y en inglés): compara contra el nombre que el usuario
    /// escribió en su rutina, así que traducirlo rompería la clasificación. Lo que se traduce es
    /// el rótulo que se PINTA, que es cosa distinta (FER-112).
    private static func ticketType(from routineName: String?) -> String {
        guard let raw = routineName?.lowercased(), !raw.isEmpty else { return RecipeLabels.fuerza }
        if raw.contains("empuje") || raw.contains("push") { return RecipeLabels.empuje }
        if raw.contains("tirón") || raw.contains("tiron")
            || raw.contains("jalón") || raw.contains("jalon")
            || raw.contains("pull") { return RecipeLabels.tiron }
        if raw.contains("pierna") || raw.contains("legs") { return RecipeLabels.pierna }
        return RecipeLabels.fuerza
    }

    // MARK: - Per-exercise detail / volume / zone

    private static func invertNames(_ names: [String: String]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (id, name) in names {
            out[name, default: []].append(id)
        }
        return out
    }

    /// Work set with the max weight; its reps. Nil when no weighted work set has reps.
    private static func topReps(from work: [SetEntry]) -> Int? {
        guard !work.isEmpty else { return nil }
        let best = work.max { a, b in
            (a.weightKg ?? 0) < (b.weightKg ?? 0)
        }
        return best?.reps
    }

    /// Σ weightKg × reps over work sets (kg-reps volume).
    private static func exerciseVolume(_ work: [SetEntry]) -> Double {
        work.reduce(0.0) { acc, s in
            acc + (s.weightKg ?? 0) * Double(s.reps ?? 0)
        }
    }

    private static func detailString(setCount: Int, topReps: Int?, topWeightKg: Double?,
                                     system: UnitSystem) -> String {
        let repsPart = topReps.map(String.init) ?? "—"
        var s = "\(setCount)×\(repsPart)"
        if let kg = topWeightKg {
            s += " · \(massString(kg, system: system))"
        }
        return s
    }

    // 2026-07-19: tercera copia del formateador de peso, también desfasada en imperial (conservaba el
    // decimal donde `StrengthDisplay` redondea a entero). El recibo imprimía un número y las pantallas
    // otro para la misma serie. Ahora enruta por la única fuente.
    private static func massString(_ kg: Double, system: UnitSystem) -> String {
        StrengthDisplay.weight(kg, system: system)
    }

    /// Grouped volume number only (no unit) — the ticket's "price" column.
    private static func groupedVolume(_ kg: Double, system: UnitSystem) -> String {
        volumeParts(kg, system: system).value
    }

    private static func volumeParts(_ kg: Double, system: UnitSystem) -> (value: String, unit: String) {
        let converted = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let num = f.string(from: NSNumber(value: converted.rounded()))
            ?? "\(Int(converted.rounded()))"
        return (num, UnitFormatter.massUnit(system))
    }

    /// Modal HR zone for an exercise's set window (±60 s). Zone 2 when HR is empty or uncovered.
    private static func dominantZone(sets: [SetEntry], hr: [HRSample], zoneSet: HRZoneSet) -> Int {
        guard !hr.isEmpty, !sets.isEmpty else { return 2 }
        let minTs = (sets.map(\.ts).min() ?? 0) - 60
        let maxTs = (sets.map(\.ts).max() ?? 0) + 60
        let window = hr.filter { $0.ts >= minTs && $0.ts <= maxTs }
        guard !window.isEmpty else { return 2 }

        var counts: [Int: Int] = [:]
        for sample in window {
            let z = zoneSet.zoneNumber(forBPM: Double(sample.bpm))
            // Zone 0 = below Z1 — fold into Z1 so the leading dot still has a Cénit color.
            let bucket = z <= 0 ? 1 : min(z, 5)
            counts[bucket, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? 2
    }

    // MARK: - Zones (session time-in-zone)

    private static func zoneSlices(hr: [HRSample], zoneSet: HRZoneSet) -> [ThermalReceipt.ZoneSlice] {
        guard !hr.isEmpty else { return [] }
        let tiz = HRZones.timeInZone(hr, zoneSet: zoneSet)
        var seconds: [(zone: Int, s: Double)] = []
        for z in 2...5 {
            let sec = tiz.seconds(inZone: z)
            if sec > 0 { seconds.append((z, sec)) }
        }
        let sum = seconds.reduce(0.0) { $0 + $1.s }
        guard sum > 0 else { return [] }

        return seconds.compactMap { item in
            let fraction = item.s / sum
            let pct = Int((fraction * 100).rounded())
            guard pct > 0 else { return nil }
            return ThermalReceipt.ZoneSlice(
                zone: item.zone,
                fraction: fraction,
                label: "Z\(item.zone) \(pct)%"
            )
        }
    }

    // MARK: - Summary rows

    private static func summaryRows(
        summary: StrengthSummary,
        hrr: (bpm: Int, risingIsGood: Bool)?
    ) -> [ThermalReceipt.SummaryRow] {
        var rows: [ThermalReceipt.SummaryRow] = [
            .init(key: String(localized: "recibo.duracion", defaultValue: "DURATION"), value: durationHMS(summary.durationS))
        ]
        if let strain = summary.strain, strain > 0 {
            let v = strain.formatted(.number.precision(.fractionLength(1)))
            rows.append(.init(key: String(localized: "recibo.esfuerzo", defaultValue: "EFFORT"), value: "\(v) / 21"))
        }
        if let avg = summary.avgHr {
            rows.append(.init(key: String(localized: "recibo.fcmedia", defaultValue: "AVG HR"), value: "\(avg) bpm"))
        }
        if let kcal = summary.energyKcal {
            rows.append(.init(key: String(localized: "recibo.calorias", defaultValue: "CALORIES"), value: "\(Int(kcal.rounded())) kcal"))
        }
        if let hrr {
            let arrow = hrr.risingIsGood ? "↑" : "↓"
            rows.append(.init(key: "RECUPERACIÓN 60s",
                              value: "\(hrr.bpm) bpm \(arrow)", pink: true))
        }
        return rows
    }

    private static func durationHMS(_ total: Int) -> String {
        let s = max(0, total)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }
}
#endif
