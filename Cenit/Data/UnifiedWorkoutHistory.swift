import Foundation
import StrandTraining   // StrengthSession
import CenitStore       // WorkoutRow
import StrandImport     // WorkoutHealthKitDedup (FER-362 · C4)

// MARK: - UnifiedWorkoutHistory (FER-202 · épico «Entrenar en vidrio»)
//
// La proyección de SOLO LECTURA que funde el historial de fuerza de Cénit (`StrengthSession`) con la
// actividad de Apple Health / bitácora (`WorkoutRow`) en UNA línea de tiempo filtrable. Pura, sin
// persistencia, sin red, on-device: el merge/dedup/filtro pasa en tiempo de lectura sobre arreglos que
// el caller ya cargó de `Repository`. No sabe de UI ni de repo.
//
// El DEDUP (eco de Apple + colapso de dos apps de terceros solapadas) vive en
// `StrandImport.WorkoutHealthKitDedup` (FER-362 · C4, ola A) — puro, sin dependencia de CenitStore.
// `merge` solo traduce `WorkoutRow`/`StrengthSession` a las DTOs mínimas del motor y aplica el
// resultado; ver el docstring de ese tipo para el porqué de cada paso. Solo el eco/colapso de APPLE
// cuenta: las filas `manual` / `detected` / `whoop` NUNCA se de-duplican (son datos que el usuario
// metió o que otra fuente aportó, no un eco de una sesión rica).

/// Una entrada de la línea de tiempo: una sesión de fuerza rica de Cénit, o una fila de actividad.
enum HistoryEntry: Equatable {
    case strength(StrengthSession)
    case cardio(WorkoutRow)

    var startTs: Int {
        switch self {
        case .strength(let s): return s.startTs
        case .cardio(let r):   return r.startTs
        }
    }
    var endTs: Int {
        switch self {
        case .strength(let s): return s.endTs ?? s.startTs
        case .cardio(let r):   return r.endTs
        }
    }
    var isStrength: Bool { if case .strength = self { return true }; return false }
}

/// El filtro (interruptor de dialecto): todo, solo fuerza rica de Cénit, o un deporte de actividad.
/// Nota: `.sport` filtra SOLO filas de cardio por nombre de deporte; el chip «Fuerza» de «Por deporte»
/// NO es un `.sport("...")` — el caller conmuta a `.strength` (si no, devolvería 0 sesiones de fuerza).
enum HistoryFilter: Equatable { case all, strength, sport(String) }

enum UnifiedWorkoutHistory {

    /// Funde las sesiones de fuerza COMPLETADAS (`endTs != nil`) + las filas de actividad en una línea
    /// de tiempo, más reciente primero, delegando el dedup a `WorkoutHealthKitDedup.survivingRows`
    /// (echo de Apple + colapso de dos apps de terceros solapadas). Pura. Una sesión de fuerza EN
    /// CURSO es estado vivo, no historial — se excluye.
    static func merge(sessions: [StrengthSession], rows: [WorkoutRow]) -> [HistoryEntry] {
        let completed = sessions.filter { $0.endTs != nil }
        var out: [HistoryEntry] = completed.map { .strength($0) }

        let richIntervals = completed.map {
            WorkoutHealthKitDedup.RichInterval(startTs: $0.startTs, endTs: $0.endTs ?? $0.startTs)
        }
        let engineRows = rows.map {
            WorkoutHealthKitDedup.Workout(startTs: $0.startTs, endTs: $0.endTs, sport: $0.sport,
                                          durationS: $0.durationS, source: $0.source)
        }
        let survivors = WorkoutHealthKitDedup.survivingRows(engineRows, richSessions: richIntervals)

        // `survivingRows` returns the engine's minimal DTO, in the caller's original order, with the
        // dropped elements simply missing — never reordered or duplicated. A single forward walk
        // re-pairs each survivor with its full `WorkoutRow` positionally, so the join is correct even
        // if two input rows happen to share an identical (startTs,endTs,sport,durationS,source).
        var cursor = 0
        for survivor in survivors {
            while cursor < rows.count && engineRows[cursor] != survivor { cursor += 1 }
            guard cursor < rows.count else { break }
            out.append(.cardio(rows[cursor]))
            cursor += 1
        }
        return out.sorted { $0.startTs > $1.startTs }
    }

    /// Aplica el filtro de puerta/segmento a una línea de tiempo ya fundida.
    static func filter(_ entries: [HistoryEntry], _ f: HistoryFilter) -> [HistoryEntry] {
        switch f {
        case .all:
            return entries
        case .strength:
            return entries.filter { $0.isStrength }
        case .sport(let name):
            return entries.filter {
                if case .cardio(let row) = $0 { return row.sport == name }
                return false
            }
        }
    }

    /// Los deportes presentes en la actividad (para «Por deporte»), ordenados por frecuencia desc.
    /// Solo filas de cardio; la fuerza no es un "deporte" aquí (tiene su propio segmento). FER-362 ·
    /// C4: una fila de fuerza CERRADA de origen Apple (Strong/Hevy/Apple Fitness) tampoco cuenta como
    /// su propio "deporte" — vive bajo el paraguas «Fuerza», sin importar si `fuerzaEntries` acaba
    /// admitiéndola (la guardia de plausibilidad no aplica aquí: no es ni deporte ni fuerza).
    static func sports(_ entries: [HistoryEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for case .cardio(let row) in entries where !isClosedStrengthApple(row) {
            counts[row.sport, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map(\.key)
    }

    // MARK: - FER-362 · C4: fuerza de terceros honesta

    /// El dialecto «Fuerza»: toda sesión rica dentro de 90 días + — si `showThirdParty` — la fuerza de
    /// terceros que Apple Salud ya trae (Strong/Hevy/Apple Fitness), sobreviviente del dedup de
    /// `merge` y admitida por `isAdmissibleThirdPartyStrength`. `merged` ya viene ordenado
    /// más-reciente-primero (`merge`); `filter` es estable, así que el resultado hereda el orden sin
    /// re-ordenar. `now` es un parámetro (no `Date()`) para que la función siga pura y testeable.
    static func fuerzaEntries(_ merged: [HistoryEntry], now: Int, showThirdParty: Bool) -> [HistoryEntry] {
        let cutoff = now - 90 * 86_400
        return merged.filter { entry in
            guard entry.startTs >= cutoff else { return false }
            switch entry {
            case .strength:
                return true
            case .cardio(let row):
                return showThirdParty && isAdmissibleThirdPartyStrength(row)
            }
        }
    }

    /// ¿Esta fila de actividad es fuerza CERRADA de origen Apple (Strong/Hevy/Apple Fitness ya en
    /// Apple Salud)? Puerta ESTRUCTURAL: no depende de plausibilidad, así que también decide si la
    /// fila cuenta como su propio "deporte" en `sports` (no debe — vive bajo el paraguas «Fuerza»).
    static func isClosedStrengthApple(_ row: WorkoutRow) -> Bool {
        WorkoutSource.classify(row.source) == .apple && WorkoutHealthKitDedup.isClosedStrength(row.sport)
    }

    /// ¿Esta fila de actividad ENTRA a «Fuerza» como fuerza de terceros? Apple + deporte CERRADO +
    /// guardia de plausibilidad — la puerta que `fuerzaEntries` usa para admitir un `.cardio`, y la
    /// MISMA que cuenta la fila «Fuerza» de «Por deporte» (`WorkoutHistoryScreen.porDeporteSection`),
    /// para que las dos superficies nunca discrepen.
    static func isAdmissibleThirdPartyStrength(_ row: WorkoutRow) -> Bool {
        isClosedStrengthApple(row) && isPlausibleStrengthEnvelope(row)
    }

    /// La guardia de plausibilidad de un sobre de fuerza de terceros: un `HKWorkout` corrupto/basura
    /// no se disfraza de sesión real. Rango humano — los mismos límites que
    /// `WorkoutSource.buildManualRow` usa para una entrada manual — y solo aplica a estos sobres de
    /// fuerza (el cardio normal no pasa por esta guardia). Una fuera de rango se DESCARTA, nunca se
    /// recorta: silenciar un dato falso es mejor que mostrar uno.
    private static func isPlausibleStrengthEnvelope(_ row: WorkoutRow) -> Bool {
        guard row.endTs > row.startTs, row.endTs - row.startTs <= 24 * 3_600 else { return false }
        if let k = row.energyKcal, !(0.0...20_000.0).contains(k) { return false }
        if let hr = row.avgHr, !(25...250).contains(hr) { return false }
        return true
    }
}
