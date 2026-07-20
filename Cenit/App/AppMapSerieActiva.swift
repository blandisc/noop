#if DEBUG && os(iOS)
import SwiftUI
import StrandTraining

/// **Canvas de revisión de la «Serie activa»** (Acto II · épico FER-928) — monta `LiveStrengthSheet`
/// con una sesión de fuerza en vivo sembrada a mano, para revisar en el canvas de Xcode el modelo
/// riel + acordeón y los estados nuevos del épico sin correr el harness ni el simulador.
///
/// Dos escenarios (dos #Preview):
///  · **Riel + acordeón** — 1 hecho, 1 activo (tarjeta flotante), 1 por venir, nodo «＋».
///  · **Superserie A1/A2** — un par en superserie a media vuelta (A1 con su primera serie hecha,
///    foco en A2), más un ejercicio de pierna para ver los puntos de categoría conviviendo.
///    Verifica en vivo: round-robin A1→A2→A1 al registrar, descanso solo al cerrar la vuelta,
///    reorden en modo mover con el par pegado, y el par terminado.
///
/// La sesión se construye con `StrengthSessionModel.make` (puro) en vez de `startStrengthSession`,
/// para NO disparar los efectos de una sesión real (stream de HR, persistencia, buzz, Apple Watch).
private struct SerieActivaPreviewCell: View {
    enum Scenario { case plan, superserie, serieNueva }
    var scenario: Scenario = .plan

    @State private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        Group {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session)
                    .environmentObject(model.repo)
                    .environment(model)
                    .environmentObject(TabRouter())
                    // Sin este coordinador, abrir «Agregar ejercicio» (ExerciseLibraryScreen lo exige
                    // como @EnvironmentObject) CRASHEA el preview — el app real lo inyecta en Root.
                    .environmentObject(MediaDownloadCoordinator())
                    .environment(\.locale, Locale(identifier: "es-MX"))
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

    private func rex(_ eid: String, _ pos: Int, sets: Int, reps: Int, kg: Double,
                     superset: Int? = nil) -> RoutineExercise {
        let planned = (0..<sets).map { RoutineSet(position: $0, reps: reps, weightKg: kg) }
        return RoutineExercise(routineId: "preview", exerciseId: eid, position: pos,
                               targetSets: sets, targetReps: reps, targetWeightKg: kg,
                               restMode: .fixed, restSeconds: 90,
                               supersetGroup: superset, sets: planned)
    }

    private func seedLiveSession() {
        let res: [RoutineExercise]
        switch scenario {
        case .plan:
            // Mismos ejercicios reales del catálogo que el fixture del plan (Día A — Empuje).
            res = [
                rex("Barbell_Bench_Press_-_Medium_Grip", 0, sets: 4, reps: 8, kg: 80),
                rex("Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
                rex("Dumbbell_Lying_One-Arm_Rear_Lateral_Raise", 2, sets: 3, reps: 12, kg: 8),
            ]
        case .serieNueva:
            // Cacería de la «fila gorda»: 3 series hechas + una CUARTA recién agregada pendiente —
            // el estado exacto donde el dueño ve la fila inflada tras «+ Serie».
            res = [
                rex("Barbell_Bench_Press_-_Medium_Grip", 0, sets: 3, reps: 8, kg: 80),
                rex("Incline_Dumbbell_Press", 1, sets: 3, reps: 10, kg: 26),
            ]
        case .superserie:
            // Par A1/A2 (curl + jalón agrupados) entre un empuje hecho y una pierna por venir —
            // mezcla de familias para ver los puntos de categoría conviviendo.
            res = [
                rex("Barbell_Bench_Press_-_Medium_Grip", 0, sets: 3, reps: 8, kg: 80),
                rex("Barbell_Curl", 1, sets: 3, reps: 10, kg: 30, superset: 1),
                rex("Close-Grip_Front_Lat_Pulldown", 2, sets: 3, reps: 10, kg: 55, superset: 1),
                rex("Barbell_Full_Squat", 3, sets: 3, reps: 8, kg: 100),
            ]
        }
        let slots = res.map { re in
            // «La última vez»: una entrada previa por ejercicio (un pelín por debajo del plan) para que
            // el modo foco y las celdas ANTERIOR tengan historia que enseñar.
            let prev = SetEntry(sessionId: "preview-prev", exerciseId: re.exerciseId, position: 0,
                                kind: .work, weightKg: (re.targetWeightKg ?? 20) - 2.5,
                                reps: max(1, (re.targetReps ?? 8) - 1), done: true, ts: 0)
            return StrengthSessionModel.PlanSlot(re: re, exercise: ExerciseCatalog.byID(re.exerciseId),
                                                 lastSets: [prev])
        }
        let name = scenario == .plan ? "Día A — Empuje" : "Full body — Superserie"
        let session = StrengthSessionModel.make(routineId: "preview", routineName: name,
                                                slots: slots, startTs: Int(Date().timeIntervalSince1970))
        switch scenario {
        case .plan:
            // Ej0 completo → doneRow; ej1 activo → tarjeta flotante; ej2 → comingRow.
            for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
            session.currentIndex = 1
        case .serieNueva:
            for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
            session.addSet(exercise: 0)   // la 4ª, recién copiada, pendiente
            session.currentIndex = 0
        case .superserie:
            // Empuje hecho; A1 registró su primera serie; el foco round-robin quedó en A2.
            for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
            session.runs[1].sets[0].done = true
            session.runs[1].currentSet = 1
            session.currentIndex = 2
        }
        model.strengthSession = session
    }
}

#Preview("Serie activa · riel + acordeón") {
    SerieActivaPreviewCell(scenario: .plan)
}
#Preview("Serie activa · superserie A1/A2") {
    SerieActivaPreviewCell(scenario: .superserie)
}
#Preview("Serie activa · serie recién agregada") {
    SerieActivaPreviewCell(scenario: .serieNueva)
}
#endif
