#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import Inject   // recarga en caliente (dev-only, inerte en Release)

// StarterTemplatesSheet.swift — «Start from a template» (FER-386).
//
// A light Liquid Glass · El Eje sheet that lets the user copy a bundled starter routine into «My
// routines». Two states in one sheet (no nested NavigationStack — FER-171): the grouped LIST, and a
// single template's PREVIEW with the «Add to my routines» action. Everything is offline: the
// templates are bundled data (`StarterTemplates`) and the exercises resolve from the seed catalog.
// Adding writes a normal `Routine` via the existing save path, so the copy edits like any routine.
//
// FER-251: optional `grupo` acota la hoja a UN programa (lista SUS rutinas + preview + CTA
// «Usar este plan» que crea el grupo entero y agenda días libres). Sin `grupo` (nil) el
// comportamiento es el catálogo completo de siempre — cero regresión para WeeklyPlanEditor y co.
//
// Presented like the routine builder: from `EntrenarView` as a `.sheet`, with the theme passed in
// explicitly (it doesn't cross the sheet boundary — FER-190) and `onAdded` to reload the hub.

struct StarterTemplatesSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Called after a template is copied (or a group is applied), so the hub reloads.
    var onAdded: () async -> Void
    /// Optional: fired after a successful group apply (toast / dismiss parent), never on single-add.
    var onApplied: (() -> Void)?
    /// nil = catálogo completo; non-nil = solo ese grupo (FER-251).
    var grupo: StarterTemplate.Group?

    /// nil = the grouped list; non-nil = that template's preview.
    @State private var selected: StarterTemplate?
    @State private var saving = false
    @State private var saveError = false
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Catálogo completo (`grupo == nil`) o acotado a un programa. En modo grupo abre SIEMPRE con
    /// la primera rutina en preview (ronda 2 del gate FER-251: el CTA «Usar este plan» nunca es
    /// alcanzable sin ejercicios visibles — el preview aprobado por el dueño llega abierto).
    init(grupo: StarterTemplate.Group? = nil,
         onApplied: (() -> Void)? = nil,
         onAdded: @escaping () async -> Void) {
        self.grupo = grupo
        self.onApplied = onApplied
        self.onAdded = onAdded
        if let grupo {
            _selected = State(initialValue: StarterTemplates.inGroup(grupo).first)
        }
    }

    private var isGroupMode: Bool { grupo != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                if let t = selected {
                    preview(t)
                } else {
                    listContent
                }
                if isGroupMode {
                    useThisPlanFooter
                }
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s300)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-200 (Anillo 2, épico FER-195): fondo de vidrio El Eje — se CONSERVA el chrome actual
        // (título Grotesk a mano + preview in-place). Esta hoja no tiene botón de salida hoy (solo
        // swipe-dismiss + «Add to my routines»); meter `EntrenarHojaCabecera` AÑADIRÍA un control
        // (REGLA SUPREMA) — se ignora deliberadamente y se flagea en el reporte.
        .entrenarHojaFondo(tono: .neutro)
        // FER-969 / FER-280·2c: write failure → `.saveErrorToast` (misma receta, un solo dialecto).
        .saveErrorToast(isPresented: $saveError)
        .enableInjection()
    }

    // MARK: - List (grouped by program, or one group in FER-251 mode)

    private var listContent: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            if !isGroupMode {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    Text("Templates").liquidKicker().foregroundStyle(LiquidColor.tinta500)
                    Text("Start from a template")
                        .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Begin with a proven base and edit it to taste. Everything works offline.")
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, LiquidSpace.s050)
                }
            } else if let grupo {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    Text("Templates").liquidKicker().foregroundStyle(LiquidColor.tinta500)
                    Text(groupName(grupo))
                        .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(routineCountText(StarterTemplates.inGroup(grupo).count))
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, LiquidSpace.s050)
                }
            }

            ForEach(visibleGroups, id: \.self) { group in
                let templates = StarterTemplates.inGroup(group)
                if !templates.isEmpty {
                    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                        if !isGroupMode {
                            Text(groupName(group)).liquidKicker().foregroundStyle(LiquidColor.tinta500)
                        }
                        EntrenarModulo(tono: .neutro, intensidad: LiquidTonoMetrics.intensidadDefault, insets: EdgeInsets()) {
                            VStack(alignment: .leading, spacing: .zero) {
                                ForEach(templates) { t in
                                    templateRow(t)
                                    if t.id != templates.last?.id { divider }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleGroups: [StarterTemplate.Group] {
        if let grupo { return [grupo] }
        return Array(StarterTemplate.Group.allCases)
    }

    private func templateRow(_ t: StarterTemplate) -> some View {
        Button { withAnimation(LiquidMotion.toque) { selected = t } } label: {
            HStack(spacing: LiquidSpace.s300) {
                VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                    Text(templateName(t.id)).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                    Text("\(exerciseCountText(t.exerciseCount)) · \(String(localized: templateBlurb(t.id)))")
                        .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: LiquidSpace.s200)
                CenitIcon.disclosure.image
                    .font(LiquidType.iconSF(size: 15)).foregroundStyle(LiquidColor.tinta500)
            }
            .padding(.horizontal, LiquidSpace.s400).frame(minHeight: LiquidSpace.s1400).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Preview this template"))
    }

    // MARK: - Preview (one template + add / use-plan action)

    private func preview(_ t: StarterTemplate) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            // En modo grupo con 1 rutina no hay lista detrás; el back solo tiene sentido si hay
            // más de una (o catálogo completo).
            if !isGroupMode || (grupo.map { StarterTemplates.inGroup($0).count } ?? 0) > 1 {
                Button { withAnimation(LiquidMotion.toque) { selected = nil } } label: {
                    HStack(spacing: LiquidSpace.s100) {
                        CenitIcon.back.image.font(LiquidType.iconSF(size: 15))
                        Text(isGroupMode ? groupName(t.group) : LocalizedStringKey("Templates"))
                            .font(LiquidType.cuerpo)
                    }
                    .foregroundStyle(LiquidColor.tinta700)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back to templates"))
            }

            VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                Text(groupName(t.group)).liquidKicker().foregroundStyle(LiquidColor.tinta500)
                Text(templateName(t.id))
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(exerciseCountText(t.exerciseCount)) · \(String(localized: templateBlurb(t.id)))")
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EntrenarModulo(tono: .neutro, intensidad: LiquidTonoMetrics.intensidadDefault, insets: EdgeInsets()) {
                VStack(alignment: .leading, spacing: .zero) {
                    ForEach(Array(t.slots.enumerated()), id: \.offset) { index, slot in
                        slotRow(slot)
                        if index != t.slots.count - 1 { divider }
                    }
                }
            }

            if !isGroupMode {
                VStack(spacing: LiquidSpace.s250) {
                    CenitCTAButton("Add to my routines") { add(t) }
                        .disabled(saving)

                    Text("It's copied into «My routines». You can edit it like any routine.")
                        .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, LiquidSpace.s050)
            }
        }
    }

    /// CTA de modo grupo (FER-251): aplica el programa entero + agenda, no una sola rutina.
    private var useThisPlanFooter: some View {
        VStack(spacing: LiquidSpace.s250) {
            CenitCTAButton("Use this plan") { applyTemplateGroup() }
                .disabled(saving)
                .accessibilityHint(Text("Choosing a template creates its routines and your week is set; you can always edit it later, day by day."))

            Text("Choosing a template creates its routines and your week is set; you can always edit it later, day by day.")
                .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, LiquidSpace.s050)
    }

    private func slotRow(_ slot: StarterTemplate.Slot) -> some View {
        let exercise = ExerciseCatalog.byID(slot.exerciseId)
        let name = exercise.map(StrengthDisplay.name) ?? String(localized: "Exercise")
        return HStack(spacing: LiquidSpace.s250) {
            Text(name).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LiquidSpace.s200)
            Text(schemeText(slot)).font(LiquidType.cuerpo).monospacedDigit().foregroundStyle(LiquidColor.tinta700)
            Text(restChipText(slot.restSeconds))
                .font(LiquidType.caption).monospacedDigit().foregroundStyle(LiquidColor.tinta500)
                .padding(.horizontal, LiquidSpace.s175).padding(.vertical, LiquidSpace.s050)
                .background(LiquidColor.papelTarjeta, in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous)
                    .strokeBorder(LiquidColor.tinta10, lineWidth: 1))
        }
        .padding(.horizontal, LiquidSpace.s400).padding(.vertical, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(name), \(schemeText(slot)), rest \(restAccessibility(slot.restSeconds))"))
    }

    // MARK: - Add (copy → save → reload → dismiss)

    private func add(_ t: StarterTemplate) {
        guard !saving else { return }
        saving = true
        let name = String(localized: templateName(t.id))
        let now = Int(Date().timeIntervalSince1970)
        let (routine, exercises) = t.makeRoutine(name: name, now: now)
        Task {
            do {
                try await repo.saveRoutine(routine, exercises: exercises)
                await onAdded()
                dismiss()
            } catch {
                saving = false
                saveError = true
            }
        }
    }

    // MARK: - Apply group (FER-251 · misma lógica que CrearPlanScreen.applyTemplateGroup)

    /// Días lunes→domingo (Calendar weekday: 1 = domingo … 7 = sábado).
    private static let mondayFirstWeekdays = [2, 3, 4, 5, 6, 7, 1]

    /// Copia CADA rutina del grupo y asigna cada una al primer día LIBRE — nunca pisa un día ya
    /// asignado. Si falla el guardado: banner inline, la hoja NO se cierra, nada a medias.
    private func applyTemplateGroup() {
        guard let group = grupo, !saving else { return }
        saving = true
        Task {
            guard let store = await repo.storeHandle() else {
                saving = false; saveError = true; return
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
                await onAdded()
                onApplied?()
                dismiss()
            } catch {
                saving = false
                saveError = true
            }
        }
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(LiquidColor.tinta10) }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

    private func routineCountText(_ n: Int) -> String {
        n == 1 ? String(localized: "1 routine") : String(localized: "\(n) routines")
    }

    /// "4 × 6" for rep work; "4 sets" when a template prescribes no rep target.
    private func schemeText(_ slot: StarterTemplate.Slot) -> String {
        if let reps = slot.reps { return "\(slot.sets) × \(reps)" }
        return String(localized: "\(slot.sets) sets")
    }

    private func restChipText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func restAccessibility(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return String(localized: "\(seconds / 60) min") }
        return String(localized: "\(seconds) seconds")
    }

    // MARK: - Display names (localized via the string catalog)

    private func groupName(_ g: StarterTemplate.Group) -> LocalizedStringKey {
        switch g {
        case .pushPullLegs: return "Push Pull Legs"
        case .fullBody:     return "Full body"
        case .upperLower:   return "Upper / Lower"
        case .home:         return "At home"
        case .mobility:     return "Mobility"
        }
    }

    // Unique source strings on purpose: a bare "Push"/"Legs" would collide with other catalog keys
    // (e.g. the recovery band's «Push»), so template names carry a distinguishing word.
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

    private func templateBlurb(_ id: String) -> LocalizedStringResource {
        switch id {
        case "ppl-push":  return "chest, shoulders, triceps"
        case "ppl-pull":  return "back, biceps"
        case "ppl-legs":  return "quads, glutes, hamstrings"
        case "full-body": return "the whole body"
        case "upper":     return "chest, back, arms"
        case "lower":     return "full legs"
        case "home":      return "no equipment"
        case "mobility":  return "a gentle 20-minute reset"
        default:          return "strength"
        }
    }
}
#endif
