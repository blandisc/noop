#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics
import WhoopProtocol
import WhoopStore

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
    let onPick: (Double?) -> Void
    let onClose: () -> Void

    /// The scale offered (canvas pass 2026-07-15, owner trim): 6 stops — 7,5/8,5 dropped, 9,5 kept —
    /// so the whole scale fits ONE row, no slide.
    private static let scale: [Double] = [6, 7, 8, 9, 9.5, 10]

    @State private var selected: Double

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.RPETarget,
         onPick: @escaping (Double?) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.onPick = onPick; self.onClose = onClose
        // r21 (auditoría UX #8b): un RPE legado fuera de la escala visible (7,5/8,5 del modelo
        // viejo) se ancla al escalón más cercano — antes la hoja abría sin píldora seleccionada.
        let raw = target.currentRPE ?? 8
        _selected = State(initialValue: Self.scale.min(by: { abs($0 - raw) < abs($1 - raw) }) ?? 8)
    }

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
        .background(theme.paper.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                // Canvas pass 2026-07-15: it's a TITLE, not a label — Grotesk bold with real air above.
                Text("RPE").font(InstrumentoType.grotesk(22, weight: .bold)).foregroundStyle(theme.ink)
                Spacer()
                Button(action: onClose) {
                    StrandIcon.close.image.font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkSecondary)
                }
                .accessibilityLabel(Text("Close"))
            }
            Text("Set \(target.setNumber) · \(LiveStrengthSheet.formatDecimalComma(target.weightKg)) kg × \(target.reps) reps")
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, CenitMetrics.sectionGap)
        .padding(.bottom, 8)
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

    private var scale: some View {
        // Canvas pass 2026-07-15: the whole scale visible at once — ONE row of six (7,5/8,5 dropped),
        // tiles ≥56pt (HIG), rounded-rect.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                  spacing: CenitMetrics.gap) {
            ForEach(Self.scale, id: \.self) { value in
                let sel = value == selected
                Button {
                    withAnimation(StrandMotion.interactive) { selected = value }
                } label: {
                    Text(LiveStrengthSheet.formatDecimalComma(value))
                        // r26: el numeral RPE también habla Grotesk (era el último en StrandFont.number).
                        .font(InstrumentoType.groteskNumber(17, weight: sel ? .bold : .regular))
                        .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                            if sel { shape.fill(theme.dataEffort) }
                            else { shape.strokeBorder(theme.hairlineStrong, lineWidth: 1) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? [.isSelected] : [])
            }
        }
    }

    private var okButton: some View {
        VStack(spacing: 8) {
            Button {
                onPick(selected)
            } label: {
                Text("Ok ✓")
                    .font(InstrumentoType.grotesk(17, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(theme.verdictDeep, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("RPE is optional · tap the set's RPE cell")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.top, 12)
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
    @FocusState private var focused: Bool

    init(theme: InstrumentoTheme, target: LiveStrengthSheet.NoteTarget, initialScope: Scope,
         exerciseText: String, setText: String, history: [ExerciseNote]?,
         onSave: @escaping (Scope, String) -> Void, onClose: @escaping () -> Void) {
        self.theme = theme; self.target = target; self.initialScope = initialScope
        self.exerciseText = exerciseText; self.setText = setText; self.history = history
        self.onSave = onSave; self.onClose = onClose
        _scope = State(initialValue: initialScope)
        _text = State(initialValue: initialScope == .exercise ? exerciseText : setText)
    }

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
        .padding(.top, 32)   // r12 (owner): más aire aún — el grabber respira lejos del título
        .padding(.bottom, CenitMetrics.screenPadding)
        .background(theme.paper.ignoresSafeArea())
        .onChange(of: scope) { _, newScope in
            text = newScope == .exercise ? exerciseText : setText
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // r10: voz de hoja hermana — título Grotesk como RPE/Progresión.
                Text("Note · \(target.exerciseName)")
                    .font(InstrumentoType.grotesk(20, weight: .semibold)).foregroundStyle(theme.ink)
                    .lineLimit(2)
                Text(scope == .exercise
                     ? "Saved in this exercise's history"
                     : "Saved for this set only")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            Button { onSave(scope, text) } label: {
                Text("Save").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.verdictDeep)
            }
            .buttonStyle(.plain)
        }
    }

    private var scopeToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save to:").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            HStack(spacing: 3) {
                scopeOption(.exercise, label: String(localized: "This exercise"))
                scopeOption(.set, label: String(format: String(localized: "Only set %d"), target.setNumber))
            }
            .padding(3)
            .background(theme.trackWarm, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        }
    }

    private func scopeOption(_ value: Scope, label: String) -> some View {
        let selected = scope == value
        return Button {
            withAnimation(StrandMotion.interactive) { scope = value }
        } label: {
            Text(label)
                .font(StrandFont.caption.weight(.bold))
                .foregroundStyle(selected ? theme.paper : theme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected { RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous).fill(theme.ink) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Jot something for next time: how it felt, technique, a load tweak…")
                    .font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                    .padding(.horizontal, 13).padding(.vertical, 13)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(StrandFont.body)
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .tint(theme.dataStrain)
                .focused($focused)
                .padding(9)
        }
        .frame(minHeight: 100)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.dataStrain, lineWidth: 1.5))
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

    /// Same-muscle shortlist when the field is empty; a name search over the whole library otherwise. The
    /// current exercise is always excluded (you don't replace it with itself).
    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            guard let m = primaryMuscle else { return [] }
            return Array(all.filter { $0.id != run.exerciseId && $0.primaryMuscles.contains(m) }.prefix(12))
        }
        return Array(all.filter { $0.id != run.exerciseId && StrengthDisplay.name($0).lowercased().contains(q) }.prefix(20))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    searchField
                    if !filtered.isEmpty {
                        if query.isEmpty, let m = primaryMuscle {
                            (Text("Suggested · ") + Text(MuscleAtlas.name(m)))
                                .instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.top, 4)
                        }
                        ForEach(filtered) { row($0) }
                    } else if loaded {
                        Text(query.isEmpty ? "No alternatives for this muscle: search the library."
                                           : "No matches.")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.paper)
            .navigationTitle(Text("Change \(run.name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }.foregroundStyle(theme.ink)
                }
            }
        }
        .task {
            guard !loaded else { return }
            async let exercisesTask = repo.allExercises()
            async let currentTask = repo.resolvedExercise(run.exerciseId)
            all = await exercisesTask
            primaryMuscle = await currentTask?.primaryMuscles.first
            loaded = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            StrandIcon.search.image.font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkTertiary)
            TextField("Search the library…", text: $query)
                .font(StrandFont.body).foregroundStyle(theme.ink).tint(theme.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func row(_ ex: Exercise) -> some View {
        HStack(spacing: 12) {
            SessionRunThumb(exerciseId: ex.id)
            VStack(alignment: .leading, spacing: 1) {
                Text(StrengthDisplay.name(ex)).font(StrandFont.body).foregroundStyle(theme.ink)
                if let m = ex.primaryMuscles.first {
                    Text(MuscleAtlas.name(m)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            Spacer(minLength: 8)
            Button { onUse(ex) } label: {
                Text("Use").font(StrandFont.caption).foregroundStyle(theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Use \(StrengthDisplay.name(ex))"))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }
}


#endif
