#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// CrearPlanScreen.swift — «Tres caminos» (FER-137, sobre el handoff «Entrenar, reconstruido» v2).
//
// La puerta única de creación: tres caminos, todos offline:
//   PLANTILLAS   — tocar un grupo abre `StarterTemplatesSheet(grupo:)` (preview + «Usar este plan»).
//                  FER-251: NUNCA más un tap ciego que escriba rutinas + agenda.
//   DESDE CERO   — «Nueva rutina» empuja la Biblioteca en su flujo de creación (existente).
//   IMPORTAR     — «Importar de tu IA» abre `WorkoutImportView` (existente) como hoja.
//
// Empuja sobre la MISMA pila que `EntrenarView` (vía `.navigationDestination(isPresented:)`, igual
// que «＋ Nueva rutina»/«? Trucos»), así que el tema y el repositorio ya viajan por el entorno —
// solo las hojas necesitan reinyectarlos (una hoja no cruza el entorno de su padre).
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

    @State private var saveError = false
    @State private var showLibrary = false
    @State private var showImport = false
    /// FER-251: hoja de preview de un grupo (mismo path que los chips del primer uso).
    @State private var showGroupPreview = false
    @State private var previewGroup: StarterTemplate.Group?
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // FER-200 (Anillo 2): `EntrenarHojaCabecera(.cerrar)` absorbe el `BackButton` a mano
                // Y el héroe (kicker + «Three paths») — mismas cadenas ya localizadas, sin copy
                // nueva. Salida `.cerrar`: solo cierra (`dismiss`), no guarda ni descarta trabajo.
                EntrenarHojaCabecera(
                    titulo: String(localized: "Three paths"),
                    subtitulo: String(localized: "Create your plan"),
                    tono: .neutro, salida: .cerrar, onSalir: { dismiss() })
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
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje — sin `NavigationStack` propio
        // (push vía `navigationDestination`); la cabecera de familia ya resolvió la salida.
        .entrenarHojaFondo(tono: .neutro)
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
        .sheet(isPresented: $showGroupPreview, onDismiss: { previewGroup = nil }) {
            StarterTemplatesSheet(grupo: previewGroup, onApplied: {
                onApplied()
                dismiss()
            }) { await onChange() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .enableInjection()
    }

    // MARK: - «Plantillas» — un grupo por fila → preview → «Usar este plan» (FER-251)

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
        return Button {
            previewGroup = group
            showGroupPreview = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(groupName(group)).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                    Text(routineCountText(templates.count))
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
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Show the plan"))
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

    // MARK: - Data

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
