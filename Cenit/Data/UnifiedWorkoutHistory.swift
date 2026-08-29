import Foundation
import StrandTraining   // StrengthSession
import CenitStore       // WorkoutRow

// MARK: - UnifiedWorkoutHistory (FER-202 · épico «Entrenar en vidrio»)
//
// La proyección de SOLO LECTURA que funde el historial de fuerza de Cénit (`StrengthSession`) con la
// actividad de Apple Health / bitácora (`WorkoutRow`) en UNA línea de tiempo filtrable. Pura, sin
// persistencia, sin red, on-device: el merge/dedup/filtro pasa en tiempo de lectura sobre arreglos que
// el caller ya cargó de `Repository`. No sabe de UI ni de repo.
//
// El único invariante delicado es el DEDUP del «eco»: cuando el espejo del Apple Watch está activo, el
// reloj guarda el HKWorkout de fuerza bajo OTRO `HKSource` (otro bundle id) que sí llega como
// `apple-health`; sin de-duplicar, la misma sesión se contaría dos veces. Solo el eco de APPLE cuenta:
// las filas `manual` / `detected` / `whoop` NUNCA se de-duplican (son datos que el usuario metió o que
// otra fuente aportó, no un eco de una sesión rica).

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

    /// ¿Esta fila de actividad es el ECO de una sesión de fuerza ya registrada en Cénit?
    /// Gate DURO de origen: solo `apple`. `manual`/`detected`/`whoop` regresan `false` siempre
    /// (nunca se de-duplican). Heurística: origen Apple + deporte tipo-fuerza + solape temporal
    /// half-open con una sesión COMPLETADA (mismo criterio de solape que `WorkoutDetailScreen.loadVolume`).
    static func isStrengthEcho(_ row: WorkoutRow, sessions: [StrengthSession]) -> Bool {
        guard WorkoutSource.classify(row.source) == .apple else { return false }
        let sport = row.sport.lowercased()
        let looksStrength = sport.contains("strength") || sport.contains("weight")
            || sport.contains("lift") || sport.contains("functional")
        guard looksStrength else { return false }
        return sessions.contains { sess in
            let sEnd = sess.endTs ?? sess.startTs
            return sess.startTs < row.endTs && row.startTs < sEnd   // solape half-open
        }
    }

    /// Funde las sesiones de fuerza COMPLETADAS (`endTs != nil`) + las filas de actividad en una línea
    /// de tiempo, más reciente primero, descartando el eco de Apple de una sesión ya registrada. Pura.
    /// Una sesión de fuerza EN CURSO es estado vivo, no historial — se excluye.
    static func merge(sessions: [StrengthSession], rows: [WorkoutRow]) -> [HistoryEntry] {
        let completed = sessions.filter { $0.endTs != nil }
        var out: [HistoryEntry] = completed.map { .strength($0) }
        for row in rows where !isStrengthEcho(row, sessions: completed) {
            out.append(.cardio(row))
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
    /// Solo filas de cardio; la fuerza no es un «deporte» aquí (tiene su propio segmento).
    static func sports(_ entries: [HistoryEntry]) -> [String] {
        var counts: [String: Int] = [:]
        for case .cardio(let row) in entries { counts[row.sport, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .map(\.key)
    }
}
