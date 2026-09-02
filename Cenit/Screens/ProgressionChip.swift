import SwiftUI
import CenitDesign
import StrandTraining

/// ↗ +2,5 kg cada 2 — active progression plan chip under an exercise name (RoutineEditor / Builder).
struct ProgressionChip: View {
    let re: RoutineExercise
    let system: UnitSystem
    let theme: InstrumentoTheme
    /// El incremento que sale de TUS discos, para cuando el ejercicio no guarda uno a mano.
    let derivedIncrementKg: Double
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        // FER-89: construido sobre `EntrenarChip` (E2) — encaja 1:1 con `.progression` (icono
        // `arrow.up.right`, tono de avance positivo). Antes el icono (`CenitIcon.up`, «arrow.up»
        // liso) y el texto vivían en el hue de dato de recuperación — mal aplicado a un chip de
        // progresión (auditoría FER-89); la migración corrige el tono de paso.
        // `theme` queda sin uso en el cuerpo (EntrenarChip lee el environment de tema
        // solo), pero se conserva en la firma: el call site de `RoutineEditorScreen.swift:375` (E7,
        // fuera de esta fase) sigue pasándolo tal cual.
        EntrenarChip(.progression, verbatim: Self.summary(re, system: system, derived: derivedIncrementKg),
                    action: action)
            .disabled(disabled)
    }

    /// «+2,5 kg cada 2 ✓» — el plan activo, SIEMPRE con su incremento.
    ///
    /// Antes, sin `progressionIncrementKg` explícito decía «Progresión · activa» a secas. Pero ese nil no
    /// significa «sin configurar»: significa que el incremento se DERIVA de tus discos en vez de estar
    /// guardado a mano. El chip acababa distinguiendo «explícito vs. derivado» —una diferencia interna que
    /// no le importa a nadie— y dejando de decir el dato justo en el caso más común, el del valor por
    /// defecto (bug Fer 2026-07-18). Ahora cae al mínimo derivado: si va a subir 2,5 kg, lo dice.
    static func summary(_ re: RoutineExercise, system: UnitSystem, derived: Double) -> String {
        let inc = re.progressionIncrementKg ?? derived
        let unit = StrengthDisplay.weightUnit(system).lowercased()
        return "+\(StrengthDisplay.incrementNumber(inc, system: system)) \(unit) "
            + String(localized: "every \(re.progressionSessions)") + " ✓"
    }
}

#if DEBUG
#Preview("ProgressionChip") {
    let re = RoutineExercise(
        routineId: "preview",
        exerciseId: "bench",
        position: 0,
        targetSets: 3,
        progressionEnabled: true,
        progressionSessions: 2,
        progressionIncrementKg: 2.5
    )
    ProgressionChip(
        re: re,
        system: .metric,
        theme: .base,
        derivedIncrementKg: 2.5,
        action: {}
    )
    .padding()
    .background(LiquidColor.fondoAlto)
}
#endif
