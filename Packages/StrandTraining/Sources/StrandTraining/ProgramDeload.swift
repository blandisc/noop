import Foundation

// ProgramDeload.swift — la regla PURA de la semana ligera (ola 1 · E10, FER-329).
//
// Vive aquí, en StrandTraining (puro, Foundation-only), y no en la pantalla, porque es una REGLA DEL
// ENTRENAMIENTO: si mañana la semana ligera deja de ser «la mitad de las series», cambia UNA vez.
// Mismo criterio y misma frontera que `SetVariants` (E6): devuelve kilos CRUDOS a propósito —
// StrandTraining no puede importar `PlateMath` ni `ProgressionMath` (viven en StrandAnalytics, que no
// depende de StrandTraining; ver docs/ARCHITECTURE.md), así que el redondeo a «lo que de verdad puedes
// armar con tus discos» y el valor de `deloadFraction` ENTRAN por parámetro desde la capa app. Esa
// inyección es justamente lo que mantiene UNA sola familia de «bajar»: no hay una segunda copia del
// 7,5 % aquí que pueda desincronizarse de la del deload reactivo.
//
// Ciencia — CONVENCIÓN, NO RECETA. No existe un porcentaje publicado como «el correcto»:
// - Bell et al. 2023, *Sports Medicine – Open* 9:87 (DOI 10.1186/s40798-023-00633-0) — consenso Delphi:
//   la descarga puede ser pre-planeada Y autorregulada (100 % de acuerdo), se baja volumen por
//   series/reps/días (100 %) y la intensidad «podría mantenerse alta» (81 %). SIN porcentajes.
// - Bell et al. 2024, *Sports Medicine – Open* (PMC10948666) — encuesta de práctica real: 78,9 % baja
//   series, 83,7 % baja intensidad, cada 5,6 ± 2,3 semanas, durante 6,4 ± 1,7 días.
// Por eso el default del producto (D-Q3) es `volumeOnly` — series a la mitad y el peso IGUAL, que es lo
// más alineado con el consenso — y bajar también el peso es una OPCIÓN, no la norma. Nada de esto es
// una prescripción ni promete un resultado. (Citas verificadas por /biomecanico, gate-biomecanico-1 · 2026-09-02.)
public enum ProgramDeload {

    /// Fracción de series de trabajo que sobrevive a la semana ligera: **0,5 (la mitad, mínimo 1)**.
    /// Calibration default — convención de gimnasio, no ley (ver cabecera).
    public static let ligeraSeriesFactor = 0.5

    /// Cuántas series de trabajo se hacen en la semana ligera a partir de las planeadas.
    /// Trunca hacia abajo y nunca deja el ejercicio en cero: 4→2, 3→1, 5→2, 1→1.
    public static func lightWorkSetCount(_ planned: Int) -> Int {
        max(1, Int((Double(planned) * ligeraSeriesFactor).rounded(.down)))
    }

    /// Transforma la receta de UN ejercicio para servirla ligera. **Nunca escribe en `routineSet`**: el
    /// caller aplica esto EN MEMORIA sobre la semilla de la sesión viva, así que el plan guardado del
    /// usuario queda intacto (test byte a byte en CenitStore).
    ///
    /// - `volumeOnly` (default del producto): se quedan las primeras `lightWorkSetCount(n)` series de
    ///   trabajo; el peso NO se toca.
    /// - `volumeAndLoad`: lo mismo, y además el peso baja `deloadFraction` — el MISMO 7,5 % del deload
    ///   reactivo (`ProgressionMath.deloadFraction`), que el caller inyecta. `snap` redondea a un peso
    ///   construible (`PlateMath.snap` en la app); por defecto es la identidad, que es lo correcto para
    ///   un test puro que solo mide la aritmética.
    /// - `none`: identidad.
    ///
    /// Los calentamientos pasan intactos —en número y en peso— y las series que sobreviven conservan su
    /// `position` original: la lista queda con huecos a propósito, porque quien la consume lee por orden
    /// y por `kind`, y renumerar aquí inventaría un plan que nadie guardó.
    public static func apply(rule: DeloadRule, to sets: [RoutineSet],
                             deloadFraction: Double,
                             snap: (Double) -> Double = { $0 }) -> [RoutineSet] {
        guard rule != .none else { return sets }
        let workCount = sets.filter { $0.kind == .work }.count
        guard workCount > 0 else { return sets }
        let keep = lightWorkSetCount(workCount)
        var seen = 0
        var out: [RoutineSet] = []
        out.reserveCapacity(sets.count)
        for set in sets {
            guard set.kind == .work else { out.append(set); continue }
            seen += 1
            guard seen <= keep else { continue }
            var light = set
            if rule == .volumeAndLoad, let kg = light.weightKg, kg > 0 {
                light.weightKg = snap(kg * (1 - deloadFraction))
            }
            out.append(light)
        }
        return out
    }

    /// La MISMA regla sobre un ejercicio completo — la forma en que la capa app la llama.
    ///
    /// Existe porque `RoutineSet` tiene DOS formas en disco: la receta explícita (`sets`) y la legada,
    /// donde `sets` está vacío y el plan se abanica desde `targetSets`/`targetReps` (`plannedSets`).
    /// Aplicar la regla solo sobre `sets` dejaba a una rutina legada SIN semana ligera, en silencio.
    /// Normalizar aquí —una vez, en el motor probado— es lo que impide que cada call site tenga que
    /// acordarse de esa segunda forma.
    ///
    /// Devuelve el ejercicio con la receta ya materializada y `targetSets` coherente con ella. Es una
    /// COPIA en memoria para la sesión del día: nadie debe persistirla (el plan guardado no cambia).
    public static func apply(rule: DeloadRule, to exercise: RoutineExercise,
                             deloadFraction: Double,
                             snap: (Double) -> Double = { $0 }) -> RoutineExercise {
        guard rule != .none else { return exercise }
        let light = apply(rule: rule, to: exercise.plannedSets,
                          deloadFraction: deloadFraction, snap: snap)
        var out = exercise
        out.sets = light
        out.targetSets = max(1, light.filter { $0.kind == .work }.count)
        return out
    }
}
