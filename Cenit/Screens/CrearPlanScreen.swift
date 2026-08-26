#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// CrearPlanScreen.swift — «Tres caminos» (FER-137, sobre el handoff «Entrenar, reconstruido» v2).
//
// La puerta única de creación: el chip «Crear plan» de la landing y el CTA «Crear mi plan» del
// primer uso empujan aquí, en vez de saltar directo a una plantilla o al importador. Tres filas,
// tres caminos, todos offline:
//   PLANTILLAS   — tocar un grupo COPIA todas sus rutinas Y arma la semana (los días libres se
//                  llenan en orden lunes→domingo; un día ya asignado no se toca — FER-137 no pisa
//                  un plan que el usuario ya armó a mano).
//   DESDE CERO   — «Nueva rutina» empuja la Biblioteca en su flujo de creación (existente).
//   IMPORTAR     — «Importar de tu IA» abre `WorkoutImportView` (existente) como hoja.
//
// Empuja sobre la MISMA pila que `EntrenarView` (vía `.navigationDestination(isPresented:)`, igual
// que «＋ Nueva rutina»/«? Trucos»), así que el tema y el repositorio ya viajan por el entorno —
// solo la hoja de importar necesita reinyectarlos (una hoja no cruza el entorno de su padre).
struct CrearPlanScreen: View {
    /// Empuja el editor de una rutina recién creada — el mismo closure que la landing ya recibe de
    /// `RootTabView` (FER-952: el flujo unificado biblioteca → editor).
    var openRoutine: (String) -> Void
    /// Recarga el estado del hub (rutinas, semana) tras crear o importar.
    var onChange: () async -> Void
    /// Corre cuando una plantilla queda aplicada, para que la landing muestre el aviso de éxito.
    var onApplied: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository

    @State private var applyingGroup: StarterTemplate.Group?
    @State private var saveError = false
    @State private var showLibrary = false
    @State private var showImport = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Text("Create your plan").entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
                    .padding(.top, EntrenarMetrics.heroKickerTop)
                Text("Three paths")
                    .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, EntrenarMetrics.heroTitleTop)
                Text("Ready-made templates, your own routine, or the plan you already have in your AI")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, EntrenarMetrics.heroSubTop)
                plantillasSection.padding(.top, CenitMetrics.sectionGap)
                desdeCeroSection.padding(.top, CenitMetrics.sectionGap)
                Text("Choosing a template creates its routines and your week is set; you can always edit it later, day by day.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, CenitMetrics.space2)
            }
            .padding(.top, CenitMetrics.screenTop)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // FER-988: ocultar la barra mata el gesto de volver; esto lo devuelve.
        .keepsSwipeBack()
        .saveErrorToast(isPresented: $saveError)
        .navigationDestination(isPresented: $showLibrary) {
            ExerciseLibraryScreen(createFlow: true) { picks in createRoutine(picks) }
        }
        .sheet(isPresented: $showImport) {
            WorkoutImportView { await onChange() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .enableInjection()
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            BackButton(role: .back, theme: theme) { dismiss() }
                .padding(.leading, -2)
            Spacer()
        }
    }

    // MARK: - «Plantillas» — un grupo por fila, copia todas sus rutinas y arma la semana

    private var plantillasSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentoSectionBand("Templates") {
                Text("catalog routines").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(nonEmptyGroups.enumerated()), id: \.element) { index, group in
                    plantillaRow(group)
                    if index != nonEmptyGroups.count - 1 { divider }
                }
            }
        }
    }

    private var nonEmptyGroups: [StarterTemplate.Group] {
        StarterTemplate.Group.allCases.filter { !StarterTemplates.inGroup($0).isEmpty }
    }

    private func plantillaRow(_ group: StarterTemplate.Group) -> some View {
        let templates = StarterTemplates.inGroup(group)
        return Button { applyTemplateGroup(group) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(groupName(group)).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                    Text("\(routineCountText(templates.count)) · \(String(localized: "Ready to edit"))")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    ForEach(Array(templates.enumerated()), id: \.offset) { _, t in
                        EntrenarFamilyDot(templateFamily(t).tint(theme))
                    }
                }
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            // token-exempt: 56 pt, la misma fila de plantilla que `StarterTemplatesSheet.templateRow`.
            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(applyingGroup != nil)
        .opacity(applyingGroup != nil && applyingGroup != group ? StrandOpacity.dim : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - «Desde cero» — nueva rutina o importar de tu IA

    private var desdeCeroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            InstrumentoSectionBand("From scratch")
            doorRow(title: "New routine",
                   subtitle: String(localized: "Choose exercises from the library (\(ExerciseCatalog.all.count) in the catalog)")) {
                showLibrary = true
            }
            divider
            doorRow(title: "Import from your AI",
                   subtitle: String(localized: "Paste the plan you built with your LLM · noop.workout.v1")) {
                showImport = true
            }
        }
    }

    private func doorRow(title: LocalizedStringKey, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    private func routineCountText(_ n: Int) -> String {
        // «1 rutina», no «1 rutinas» (revisión Grok r1): el grupo Movilidad trae una sola.
        n == 1 ? String(localized: "1 routine") : String(localized: "\(n) routines")
    }

    /// El tinte de identidad de una plantilla, derivado de sus ejercicios (`RoutineClassifier`,
    /// FER-775) — el mismo criterio que colorea las rutinas ya guardadas, así que la copia se ve
    /// igual antes y después de tocar la fila.
    private func templateFamily(_ t: StarterTemplate) -> EntrenarFamily {
        let muscles = t.slots.compactMap { ExerciseCatalog.byID($0.exerciseId)?.primaryMuscles }
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: muscles) ?? .fullBody
        return EntrenarFamily(rawValue: region.rawValue) ?? .fullBody
    }

    private func groupName(_ g: StarterTemplate.Group) -> LocalizedStringKey {
        switch g {
        case .pushPullLegs: return "Push Pull Legs"
        case .fullBody:     return "Full body"
        case .upperLower:   return "Upper / Lower"
        case .home:         return "At home"
        case .mobility:     return "Mobility"
        }
    }

    // Mismo vocabulario que `StarterTemplatesSheet.templateName` (claves únicas a propósito: un
    // «Push» pelón colisionaría con otras claves del catálogo).
    private func templateName(_ id: String) -> LocalizedStringResource {
        switch id {
        case "ppl-push":  return "Push day"
        case "ppl-pull":  return "Pull day"
        case "ppl-legs":  return "Leg day"
        case "full-body": return "Full body"
        case "upper":     return "Upper body"
        case "lower":     return "Lower body"
        case "home":      return "At home"
        case "mobility":  return "Mobility & light cardio"
        default:          return "Routine"
        }
    }

    // MARK: - Data

    /// Días de la semana en orden lunes→domingo (convención `Calendar.component(.weekday)`,
    /// 1 = domingo … 7 = sábado), para llenar la semana en un orden legible.
    private static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]

    /// Copia CADA rutina del grupo (`StarterTemplate.makeRoutine`, ya probado en `StrandTraining`)
    /// y asigna cada una al primer día LIBRE de la semana — nunca pisa un día que el usuario ya
    /// asignó a mano, así que tocar «Plantillas» nunca destruye trabajo previo, solo lo completa.
    private func applyTemplateGroup(_ group: StarterTemplate.Group) {
        guard applyingGroup == nil else { return }
        applyingGroup = group
        Task {
            guard let store = await repo.storeHandle() else {
                applyingGroup = nil; saveError = true; return
            }
            do {
                let existing = (try? await store.routineSchedule()) ?? []
                let taken = Set(existing.map(\.weekday))
                var freeWeekdays = Self.mondayFirstWeekdays.filter { !taken.contains($0) }
                let now = Int(Date().timeIntervalSince1970)
                for t in StarterTemplates.inGroup(group) {
                    let name = String(localized: templateName(t.id))
                    let (routine, exercises) = t.makeRoutine(name: name, now: now)
                    try await repo.saveRoutine(routine, exercises: exercises)
                    if !freeWeekdays.isEmpty {
                        try? await store.setRoutineSchedule(weekday: freeWeekdays.removeFirst(), routineId: routine.id)
                    }
                }
                await onChange()
                onApplied()
                dismiss()
            } catch {
                applyingGroup = nil
                saveError = true
            }
        }
    }

    /// «＋ Nueva rutina»: mismo flujo unificado que la landing (FER-952) — la Biblioteca entrega los
    /// ejercicios, aquí se materializa la rutina con los valores por omisión del builder (3×8) y se
    /// empuja al editor para nombrarla y afinarla.
    private func createRoutine(_ picks: [Exercise]) {
        guard !picks.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(name: String(localized: "New routine"), createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises = picks.enumerated().map { idx, ex -> RoutineExercise in
            let usesReps = ex.type == .weightReps || ex.type == .bodyweight
            let reps: Int? = usesReps ? 8 : nil
            let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
            return RoutineExercise(routineId: r.id, exerciseId: ex.id, position: idx,
                                   targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
        }
        Task {
            do {
                try await repo.saveRoutine(r, exercises: exercises)
                await onChange()
                try? await Task.sleep(nanoseconds: 550_000_000)
                openRoutine(r.id)
            } catch {
                saveError = true
            }
        }
    }
}
#endif
