#if DEBUG && os(iOS)
import SwiftUI
import StrandTraining

/// **Canvas de revisión de la «Serie activa»** (Acto II · épico FER-928) — monta `LiveStrengthSheet`
/// con una sesión de fuerza en vivo sembrada a mano, para revisar en el canvas de Xcode el modelo
/// riel + acordeón y los estados nuevos del épico sin correr el harness ni el simulador.
///
/// Qué se ve de entrada (riel + acordeón, FER-929): el primer ejercicio ya HECHO (`doneRow`), el
/// segundo ACTIVO y expandido (acordeón abierto), el tercero POR VENIR (`comingRow`), y el nodo «＋»
/// al final del riel (FER-935). Los estados interactivos se activan tocando en el Live preview:
///  · **Modo mover «SOLTAR AQUÍ»** (FER-933) — «···» del activo → «Reordenar», o long-press una fila.
///  · **Descanso completo verde** (FER-934) — registra las series del activo hasta que arranca el
///    descanso, luego «Modo foco» para verlo a pantalla completa.
///
/// La sesión se construye con `StrengthSessionModel.make` (puro) en vez de `startStrengthSession`,
/// para NO disparar los efectos de una sesión real (stream de HR, persistencia, buzz, Apple Watch).
private struct SerieActivaPreviewCell: View {
    @StateObject private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        Group {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session)
                    .environmentObject(model.repo)
                    .environmentObject(model)
                    .environmentObject(TabRouter())
                    .environment(model.live)
                    .preferredColorScheme(.light)
                    .frame(width: 393, height: 852)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1))
            } else {
                ProgressView().frame(width: 393, height: 852)
            }
        }
        .task {
            guard !seeded else { return }
            seeded = true
            seedLiveSession()
        }
    }

    private func seedLiveSession() {
        func rex(_ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double) -> RoutineExercise {
            let planned = (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) }
            return RoutineExercise(routineId: "preview", exerciseId: eid, position: pos,
                                   targetSets: sets, targetReps: reps, targetWeightKg: kg,
                                   restMode: .fixed, restSeconds: 90, sets: planned)
        }
        // Mismos ejercicios reales del catálogo que el fixture del plan (Día A — Empuje).
        let res = [
            rex("Barbell_Bench_Press_-_Medium_Grip", 0, sets: 4, reps: 8, kg: 80),
            rex("Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
            rex("Dumbbell_Lying_One-Arm_Rear_Lateral_Raise", 2, sets: 3, reps: 12, kg: 8),
        ]
        let slots = res.map {
            StrengthSessionModel.PlanSlot(re: $0, exercise: ExerciseCatalog.byID($0.exerciseId), lastSets: [])
        }
        let session = StrengthSessionModel.make(routineId: "preview", routineName: "Día A — Empuje",
                                                slots: slots, startTs: Int(Date().timeIntervalSince1970))
        // Ej0 completo → doneRow; ej1 activo → acordeón abierto; ej2 → comingRow.
        for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
        session.currentIndex = 1
        model.strengthSession = session
    }
}

#Preview("Serie activa · riel + acordeón") {
    SerieActivaPreviewCell()
}
#endif
