#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// StarterTemplatesSheet.swift — «Start from a template» (FER-386).
//
// A light «Instrumento diurno» sheet that lets the user copy a bundled starter routine into «My
// routines». Two states in one sheet (no nested NavigationStack — FER-171): the grouped LIST, and a
// single template's PREVIEW with the «Add to my routines» action. Everything is offline: the
// templates are bundled data (`StarterTemplates`) and the exercises resolve from the seed catalog.
// Adding writes a normal `Routine` via the existing save path, so the copy edits like any routine.
//
// Presented like the routine builder: from `EntrenarView` as a `.sheet`, with the theme passed in
// explicitly (it doesn't cross the sheet boundary — FER-190) and `onAdded` to reload the hub.

struct StarterTemplatesSheet: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Called after a template is copied, so the hub reloads «My routines» and the new one shows.
    var onAdded: () async -> Void

    /// When set, the preview offers «Empezar» as the PRIMARY action (start a one-off guided session now,
    /// without saving), with «Add to my routines» demoted to secondary. The planner's «do it now»
    /// suggestion passes this so a contextual lighter session can be started on the spot (FER-560); the
    /// library / plan-builder entry points leave it nil, keeping «Add to my routines» as the only action.
    /// The caller stashes (name, slots) and starts AFTER this sheet dismisses, so two sheets never stack.
    var onStart: ((String, [StrengthSessionModel.PlanSlot]) -> Void)?

    /// nil = the grouped list; non-nil = that template's preview.
    @State private var selected: StarterTemplate?
    @State private var saving = false

    /// `initialSelection` opens the sheet straight on a template's preview (the planner's «softer»
    /// suggestion lands here on the mobility routine — FER-554); nil opens the grouped list.
    init(initialSelection: StarterTemplate? = nil,
         onStart: ((String, [StrengthSessionModel.PlanSlot]) -> Void)? = nil,
         onAdded: @escaping () async -> Void) {
        self.onStart = onStart
        self.onAdded = onAdded
        _selected = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let t = selected { preview(t) } else { listContent }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    // MARK: - List (grouped by program)

    private var listContent: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start from a template")
                    .font(StrandFont.title1).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Begin with a proven base and edit it to taste.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(StarterTemplate.Group.allCases, id: \.self) { group in
                let templates = StarterTemplates.inGroup(group)
                if !templates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(groupName(group)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(templates) { t in
                                templateRow(t)
                                if t.id != templates.last?.id { divider }
                            }
                        }
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                            .strokeBorder(theme.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func templateRow(_ t: StarterTemplate) -> some View {
        Button { withAnimation(.snappy) { selected = t } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(templateName(t.id)).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text("\(exerciseCountText(t.exerciseCount)) · \(String(localized: templateBlurb(t.id)))")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 14).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Preview this template"))
    }

    // MARK: - Preview (one template + the «add» action)

    private func preview(_ t: StarterTemplate) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            Button { withAnimation(.snappy) { selected = nil } } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Templates").font(StrandFont.subhead)
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back to templates"))

            VStack(alignment: .leading, spacing: 3) {
                Text(groupName(t.group)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(templateName(t.id)).font(StrandFont.title1).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(exerciseCountText(t.exerciseCount)) · \(String(localized: templateBlurb(t.id)))")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(t.slots.enumerated()), id: \.offset) { index, slot in
                    slotRow(slot)
                    if index != t.slots.count - 1 { divider }
                }
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))

            VStack(spacing: 10) {
                if let onStart {
                    // «Do it now» context (the planner's softer suggestion): start the session now is primary;
                    // saving it for later is the quiet secondary.
                    Button { start(t, via: onStart) } label: {
                        Text("Empezar")
                            .font(StrandFont.headline).foregroundStyle(theme.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button { add(t) } label: {
                        Text("Add to my routines")
                            .font(StrandFont.headline).foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .opacity(saving ? 0.6 : 1)
                } else {
                    Button { add(t) } label: {
                        Text("Add to my routines")
                            .font(StrandFont.headline).foregroundStyle(theme.paper)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .opacity(saving ? 0.6 : 1)

                    Text("It's copied into «My routines». You can edit it like any routine.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)
        }
    }

    private func slotRow(_ slot: StarterTemplate.Slot) -> some View {
        let exercise = ExerciseCatalog.byID(slot.exerciseId)
        let name = exercise.map(StrengthDisplay.name) ?? String(localized: "Exercise")
        return HStack(spacing: 10) {
            Text(name).font(StrandFont.body).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(schemeText(slot)).font(StrandFont.subhead).monospacedDigit().foregroundStyle(theme.inkSecondary)
            Text(restChipText(slot.restSeconds))
                .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(theme.paper, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
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
            try? await repo.saveRoutine(routine, exercises: exercises)
            await onAdded()
            dismiss()
        }
    }

    // MARK: - Start now (FER-560) — a one-off guided session, no save

    /// Build the template into guided-session slots and hand them to the caller, then dismiss. The caller
    /// starts the session AFTER this sheet is gone (so the session sheet never stacks on this one — FER-171).
    private func start(_ t: StarterTemplate, via onStart: (String, [StrengthSessionModel.PlanSlot]) -> Void) {
        let name = String(localized: templateName(t.id))
        let now = Int(Date().timeIntervalSince1970)
        let (_, exercises) = t.makeRoutine(name: name, now: now)
        let slots = exercises.map {
            StrengthSessionModel.PlanSlot(re: $0, exercise: ExerciseCatalog.byID($0.exerciseId), lastSets: [])
        }
        onStart(name, slots)
        dismiss()
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

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
