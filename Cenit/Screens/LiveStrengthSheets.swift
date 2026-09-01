#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics
import CenitStore
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// The «Change {exercise}» sheet (FER-894 · «Cómo llego a Cambiar»): a search field over the library plus a
/// shortlist of alternatives for the SAME primary muscle as the exercise being replaced. Picking «Use» swaps
/// it into the live run, keeping the sets already done. Self-contained so the session stays lean; it only
/// reads the catalog (`allExercises` / `resolvedExercise`) — the actual swap is the caller's `onUse`.
// MARK: - RPE sheet (FER-930)
//
// Estilo Hevy, aprobado en el preview v3 del handoff: número héroe grande + descriptor + una escala
// horizontal de pills (6…10, medios pasos) + «Ok ✓» verde. Tocar la celda RPE de una serie abre esto;
// el RPE es SIEMPRE opcional — no hay ningún estado que lo exija para marcar la serie.

struct RPESheet: View {
    let theme: InstrumentoTheme
    let target: LiveStrengthSheet.RPETarget
    /// Peso YA formateado en la unidad del usuario («82,5 kg» / «180 lb») — la hoja no conoce unidades (FER-952).
    let weightLabel: String
    let onPick: (Double?) -> Void
    let onClose: () -> Void

    /// The scale offered (canvas pass 2026-07-15, owner trim): 6 stops — 7,5/8,5 dropped, 9,5 kept —
    /// so the whole scale fits ONE row, no slide.
    private static let scale: [Double] = [6, 7, 8, 9, 9.5, 10]

    @State private var selected: Double

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.RPETarget, weightLabel: String,
         onPick: @escaping (Double?) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.weightLabel = weightLabel
        self.onPick = onPick; self.onClose = onClose
        // r21 (auditoría UX #8b): un RPE legado fuera de la escala visible (7,5/8,5 del modelo
        // viejo) se ancla al escalón más cercano — antes la hoja abría sin píldora seleccionada.
        let raw = target.currentRPE ?? 8
        _selected = State(initialValue: Self.scale.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 8)
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        VStack(spacing: 0) {
            header
            // Canvas pass 2026-07-15: sin ScrollView — con el grid 2×4 todo cabe; más aire arriba
            // (sectionGap) para que el héroe no se pegue a la colilla.
            VStack(spacing: 28) {
                hero
                scale
            }
            .padding(.top, CenitMetrics.sectionGap)
            Spacer(minLength: CenitMetrics.gap)
            okButton
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.bottom, CenitMetrics.screenPadding)
        // FER-198 (Ola 2, épico FER-195): el fondo de vidrio El Eje (Ola 1, FER-197) reemplaza el
        // papel plano — misma hoja, mismo gesto de cierre; solo el vestido cambia.
        .entrenarHojaFondo(tono: .ambar)
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    /// FER-198: `EntrenarHojaCabecera` reemplaza el título+`BackButton` a mano — MISMA acción de
    /// cierre (`onClose`, disco `.cerrar`: DESCARTA, no guarda — «Ok ✓» abajo sigue siendo el único
    /// camino que guarda), mismo texto de subtítulo, solo el vestido cambia. El glifo `.llama` es
    /// el mismo que ya tiñe «ESFUERZO» en otras superficies (`LiquidSheetHeader`, ámbar).
    private var header: some View {
        EntrenarHojaCabecera(glifo: .llama, titulo: String(localized: "RPE"),
                             subtitulo: String(localized: "Set \(target.setNumber) · \(weightLabel) × \(target.reps) reps"),
                             tono: .ambar, salida: .cerrar, onSalir: onClose)
            .padding(.top, CenitMetrics.sectionGap)
            .padding(.bottom, CenitMetrics.space2)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            // Canvas pass 2026-07-15 (UI·armonía #1): un solo tamaño de héroe entre hojas hermanas
            // (RPE 84 vs. discos 52 → 64 en ambas).
            Text(LiveStrengthSheet.formatDecimalComma(selected))
                .font(InstrumentoType.groteskSheetHero).tracking(InstrumentoType.groteskSheetHeroTracking)
                .foregroundStyle(theme.ink)
            Text(Self.descriptor(selected)).font(StrandFont.headline).foregroundStyle(theme.ink)
            Text(Self.subtitle(selected)).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// FER-198: `EntrenarFilaEsfuerzo` (Ola 1) reemplaza el `LazyVGrid` de celdas a mano — MISMA
    /// selección (índice tocado → `Self.scale[index]`) y MISMA animación (`StrandMotion.interactive`).
    private var scale: some View {
        EntrenarFilaEsfuerzo(
            opciones: Self.scale.map { LiveStrengthSheet.formatDecimalComma($0) },
            seleccion: Self.scale.firstIndex(of: selected),
            tono: .ambar
        ) { index in
            guard Self.scale.indices.contains(index) else { return }
            withAnimation(StrandMotion.interactive) { selected = Self.scale[index] }
        }
    }

    private var okButton: some View {
        VStack(spacing: CenitMetrics.space2) {
            Button {
                onPick(selected)
            } label: {
                Text("Ok ✓")
                    .font(InstrumentoType.grotesk(17, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    // FER-89: re-vestido con el token del héroe de hoja — EntrenarMetrics.primaryButton
                    // (46) en vez del 52 suelto.
                    .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.primaryButton)
                    .background(theme.verdictDeep, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("RPE is optional · tap the set's RPE cell")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, CenitMetrics.gap)
    }

    /// Descriptors (FER-930 spec §3, es-MX in the xcstrings catalog), no prescriptive coaching.
    private static func descriptor(_ v: Double) -> LocalizedStringKey {
        switch v {
        // r20 (auditoría UX #6b): escala monótona — el 7 decía «Cómodo» y sonaba más fácil que el
        // 6 «Esfuerzo moderado»; intercambiados para que el esfuerzo solo crezca.
        case 6:   return "Comfortable"
        case 7:   return "Moderate effort"
        case 8:   return "Hard effort"
        case 9:   return "Very hard"
        case 9.5: return "Near failure"
        case 10:  return "Maximum"
        default:  return ""   // 7.5 / 8.5: no descriptor of their own, just the subtitle
        }
    }
    private static func subtitle(_ v: Double) -> LocalizedStringKey {
        switch v {
        case 6:   return "You could've done 4+ more reps"
        case 7:   return "~3 more reps"
        case 7.5: return "~2-3 more reps"
        case 8:   return "You had ~2 reps left"
        case 8.5: return "~1-2 more reps"
        case 9:   return "~1 more rep"
        case 9.5: return "Near failure"
        case 10:  return "To failure"
        default:  return ""
        }
    }
}

// MARK: - Note sheet (FER-932)
//
// Preview v3 aprobado del handoff («Nota con color de vuelta»): editor con borde/caret ámbar
// (`dataStrain`), toggle «Guardar en:» exercise/set, «Guardar» verde, historial «NOTAS ANTERIORES»
// separado por hairline (sin tarjeta), omitido si está vacío. Abrir el sheet no toca `restEndsAt`.

struct NoteSheet: View {
    /// Where a note is saved: the whole exercise (default) or just the active set (FER-932 §4).
    enum Scope { case exercise, set }

    let theme: InstrumentoTheme
    let target: LiveStrengthSheet.NoteTarget
    let initialScope: Scope
    let exerciseText: String
    let setText: String
    /// Cross-session history for this exercise, loaded by the caller. nil = still loading.
    let history: [ExerciseNote]?
    let onSave: (Scope, String) -> Void
    let onClose: () -> Void

    @State private var scope: Scope
    @State private var text: String

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.NoteTarget, initialScope: Scope,
         exerciseText: String, setText: String, history: [ExerciseNote]?,
         onSave: @escaping (Scope, String) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.initialScope = initialScope
        self.exerciseText = exerciseText; self.setText = setText; self.history = history
        self.onSave = onSave; self.onClose = onClose
        _scope = State(initialValue: initialScope)
        _text = State(initialValue: initialScope == .exercise ? exerciseText : setText)
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            // r9 (owner): las notas son POR EJERCICIO — el alcance por-serie se retira del UI (el
            // modelo lo conserva por si vuelve).
            editor
            if let history, !history.isEmpty {
                historySection(history)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 32)  // token-exempt: aire del grabber (decisión dueño r12)
        .padding(.bottom, CenitMetrics.screenPadding)
        // FER-198 (Ola 2): fondo de vidrio El Eje — el `TextEditor` sigue SIN envolver (regla dura
        // del épico), solo cambia el marco que lo rodea.
        .entrenarHojaFondo(tono: .ambar)
        .onChange(of: scope) { _, newScope in
            text = newScope == .exercise ? exerciseText : setText
        }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    /// FER-198: `EntrenarHojaCabecera(.guardar(_:))` reemplaza el título+«Save» a mano — MISMO
    /// guardado (`onSave(scope, text)`, sigue siendo el ÚNICO camino que guarda: no hay control de
    /// cerrar aquí, tal como antes — el descarte es el swipe-dismiss nativo del sheet).
    private var header: some View {
        EntrenarHojaCabecera(
            titulo: String(localized: "Note · \(target.exerciseName)"),
            subtitulo: scope == .exercise
                ? String(localized: "Saved in this exercise's history")
                : String(localized: "Saved for this set only"),
            tono: .ambar,
            salida: .guardar(String(localized: "Save")),
            onSalir: { onSave(scope, text) }
        )
    }

    /// FER-198: `EntrenarNotaCampo` (Ola 1) reemplaza el marco a mano del `TextEditor` — el editor
    /// real (binding, tinte, placeholder) es EXACTAMENTE el mismo, solo cambia su vestido.
    private var editor: some View {
        EntrenarNotaCampo(
            texto: $text,
            placeholder: String(localized: "Jot something for next time: how it felt, technique, a load tweak…"),
            tono: .ambar
        )
    }

    private func historySection(_ history: [ExerciseNote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PREVIOUS NOTES").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(history.enumerated()), id: \.element.id) { index, note in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Self.relativeDays(note.ts)).font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(theme.inkTertiary)
                            if note.setPosition != nil {
                                Text("Set \(note.setPosition! + 1)").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                            }
                        }
                        Text(verbatim: note.text).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if index < history.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    /// «Hace N días» relative-day label for a note's `ts` (epoch seconds).
    private static func relativeDays(_ ts: Int) -> String {
        let days = max(0, Int((Date().timeIntervalSince1970 - Double(ts)) / 86400))
        if days == 0 { return String(localized: "Today") }
        if days == 1 { return String(localized: "Yesterday") }
        return String(format: String(localized: "%d days ago"), days)
    }
}

// MARK: - Pure ranking (FER-89) — extracted so it's testable without mounting the View
//
// «orden por uso reciente» (criterio de aceptación): `repo.recentWorkSets(sinceTs:)` ya expande
// exactamente `(exerciseId, startTs)` por serie de trabajo, más reciente primero (un solo JOIN en
// `StrengthStore.workSetsSince`, ya usado por el mapa de fatiga muscular) — se reusa ESE, no
// `recentSessions()` (que no carga `exerciseId` por sesión y forzaría un fetch de sets por sesión
// encima, un N+1 que el spec no pide).
enum ChangeExerciseRanking {
    /// Reduce las filas de uso (ya DESC por `startTs`, como las entrega `workSetsSince`) al timestamp
    /// MÁS RECIENTE por ejercicio — la primera aparición de cada id gana porque la entrada ya viene
    /// ordenada. Código viejo que asumiera orden ASC, o que se quedara con la ÚLTIMA aparición en vez
    /// de la primera, tronaría contra `testMostRecentUseKeepsFirstOccurrence`.
    static func mostRecentUse(_ rows: [(exerciseId: String, startTs: Int)]) -> [String: Int] {
        var out: [String: Int] = [:]
        for r in rows where out[r.exerciseId] == nil { out[r.exerciseId] = r.startTs }
        return out
    }

    /// Ordena por uso reciente, más reciente primero; los nunca-usados (sin entrada en `recency`)
    /// se quedan al final, en su orden relativo original (`sorted` es estable desde Swift 5). Código
    /// viejo que comparara con `<` en vez de `>` invertiría el orden.
    static func sortByRecentUse<T>(_ items: [T], id: (T) -> String, recency: [String: Int]) -> [T] {
        items.sorted { (recency[id($0)] ?? -1) > (recency[id($1)] ?? -1) }
    }
}

struct ChangeExerciseSheet: View {
    let theme: InstrumentoTheme
    let run: StrengthSessionModel.ExerciseRun
    let repo: Repository
    let onUse: (Exercise) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var all: [Exercise] = []
    @State private var primaryMuscle: String?
    @State private var loaded = false
    /// exerciseId → timestamp de su serie de trabajo más reciente (FER-89, orden por uso reciente).
    @State private var recentByExercise: [String: Int] = [:]
    /// exerciseId → mejor marca `.maxWeight` (FER-89, «la mejor marca por ejercicio»). Se llena solo
    /// para los candidatos visibles (`filtered`), no para toda la biblioteca.
    @State private var bestKg: [String: Double] = [:]
    /// Autocontenido (comentario propio del archivo): la hoja no recibe `system:` — igual que
    /// `ExerciseLibraryScreen`, lee su propia unidad para no forzar un cambio de firma en el call
    /// site de E5 (`LiveStrengthSheet.swift:394`, fuera de esta fase).
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var units: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    @State private var showLibrary = false

    /// Same-muscle shortlist when the field is empty; a name search over the whole library otherwise. The
    /// current exercise is always excluded (you don't replace it with itself). FER-89: ahora también
    /// ordenado por uso reciente (antes: solo coincidencia de músculo, sin orden).
    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [Exercise]
        if q.isEmpty {
            guard let m = primaryMuscle else { return [] }
            base = all.filter { $0.id != run.exerciseId && $0.primaryMuscles.contains(m) }
        } else {
            base = all.filter { $0.id != run.exerciseId && StrengthDisplay.name($0).lowercased().contains(q) }
        }
        let ranked = ChangeExerciseRanking.sortByRecentUse(base, id: \.id, recency: recentByExercise)
        return Array(ranked.prefix(q.isEmpty ? 12 : 20))
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    searchField
                    if !filtered.isEmpty {
                        if query.isEmpty, let m = primaryMuscle {
                            (Text("Suggested · ") + Text(MuscleAtlas.name(m)))
                                .instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.top, CenitMetrics.space1)
                        }
                        ForEach(filtered) { row($0) }
                    } else if loaded {
                        Text(query.isEmpty ? "No alternatives for this muscle: search the library."
                                           : "No matches.")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, CenitMetrics.space2)
                    }
                    // FER-89: la puerta nueva — hoy 0 apariciones de `ExerciseLibraryScreen` en este
                    // archivo. Reusa `EntrenarNivel` (ya garantiza el toque de 44 pt + el chevron
                    // «›» + `accessibilityElement(children: .combine)`) en vez de un botón a mano.
                    EntrenarNivel("See full library") { showLibrary = true }
                        .padding(.top, CenitMetrics.space2)
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 16)  // token-exempt: sin token exacto en mapa FER-207 (cardPadding candidato)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(Text("Change \(run.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }.foregroundStyle(theme.ink)
                }
            }
            // FER-89: solo una puerta — el interior de `ExerciseLibraryScreen` no se re-viste aquí
            // (fuera de alcance del spec). Modo BROWSE (sin `onAdd`): abre el detalle al tocar, no
            // sustituye el ejercicio por sí sola — la biblioteca completa es para EXPLORAR, «Use» en
            // esta hoja sigue siendo el único gesto que de verdad cambia el ejercicio de la sesión.
            .navigationDestination(isPresented: $showLibrary) {
                ExerciseLibraryScreen()
                    .instrumentoTheme(theme)
            }
        }
        // FER-198 (Ola 2): fondo de vidrio El Eje EN LA RAÍZ del `NavigationStack` propio — se
        // CONSERVA el stack + su toolbar nativo (el buscador vive en el toolbar), solo se tiñe por
        // debajo (mismo patrón que la propia preview de `EntrenarHojaFondo` «sobre NavigationStack»).
        .entrenarHojaFondo(tono: .neutro)
        .task {
            guard !loaded else { return }
            async let exercisesTask = repo.allExercises()
            async let currentTask = repo.resolvedExercise(run.exerciseId)
            async let recentTask = repo.recentWorkSets(sinceTs: 0)
            all = await exercisesTask
            primaryMuscle = await currentTask?.primaryMuscles.first
            recentByExercise = ChangeExerciseRanking.mostRecentUse(await recentTask)
            loaded = true
            await loadBestMarks()
        }
        .onChange(of: query) { _, _ in Task { await loadBestMarks() } }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    /// La mejor marca `.maxWeight` de cada candidato hoy visible — solo para los que aún no están en
    /// caché, así que reabrir la búsqueda sobre lo ya visto no vuelve a leer la DB.
    private func loadBestMarks() async {
        let ids = filtered.map(\.id).filter { bestKg[$0] == nil }
        guard !ids.isEmpty else { return }
        for id in ids {
            let prs = await repo.personalRecords(exerciseId: id)
            if let best = prs.first(where: { $0.metric == .maxWeight })?.valueKg {
                bestKg[id] = best
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            TextField("Search the library…", text: $query)
                .font(StrandFont.body).foregroundStyle(theme.ink).tint(theme.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13).padding(.vertical, CenitMetrics.rowVPad)  // token-exempt: sin token exacto (horizontal/chip handoff)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// «Pecho · PR 82,5 kg» — músculo + mejor marca combinados en un solo texto (`ExerciseCard.meta`
    /// solo acepta una línea). `Text` compuesto por quien llama, no `LocalizedStringKey`: el peso ya
    /// viene formateado en la unidad del usuario, no es una clave de catálogo.
    private func metaText(for ex: Exercise) -> Text? {
        let muscle = ex.primaryMuscles.first.map { Text(MuscleAtlas.name($0)) }
        let pr = bestKg[ex.id].map { Text(verbatim: String(localized: "PR") + " " + StrengthDisplay.weight($0, system: units)) }
        switch (muscle, pr) {
        case let (m?, p?): return m + Text(verbatim: " · ") + p
        case let (m?, nil): return m
        case let (nil, p?): return p
        case (nil, nil): return nil
        }
    }

    /// FER-89: la identidad (miniatura + nombre + músculo/PR) ahora reusa `ExerciseCard` en vez del
    /// `HStack` a mano de antes. «Use» se queda FUERA de `ExerciseCard` (sin `onTap` en la identidad):
    /// antes tocar el nombre/miniatura no hacía nada — dejarlo inerte conserva ESE comportamiento en
    /// vez de convertir la fila entera en un gesto de «cambiar de ejercicio» que hoy no existe.
    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: CenitMetrics.gap) {
            ExerciseCard(family: nil, name: StrengthDisplay.name(ex), metaText: metaText(for: ex)) {
                SessionRunThumb(exerciseId: ex.id)
            }
            useButton(ex)
        }
        .padding(.vertical, CenitMetrics.space2)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    private func useButton(_ ex: Exercise) -> some View {
        Button { onUse(ex) } label: {
            Text("Use").font(StrandFont.caption).foregroundStyle(theme.ink)
                .padding(.horizontal, CenitMetrics.gap).padding(.vertical, LiquidSpace.s125)
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .frame(minHeight: 44)   // toque 44: la cápsula queda visualmente igual
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Use \(StrengthDisplay.name(ex))"))
    }
}


// MARK: - HR rest reference mapping (FER-506)

/// Maps the persisted domain enum (StrandTraining) onto the rest-math vocabulary (StrandAnalytics), so the
/// math package stays decoupled from the data model. 1-to-1.
extension HRRestReference {
    var restTargetReference: RestTarget.Reference {
        switch self {
        case .restingMargin:   return .restingMargin
        case .peakDrop:        return .peakDrop
        case .karvonenReserve: return .karvonenReserve
        case .fixedBpm:        return .fixedBpm
        }
    }
}

#endif
