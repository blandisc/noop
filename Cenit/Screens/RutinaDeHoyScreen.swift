#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - «Rutina de hoy» — a routine's plan, as a deep-link (FER-343)
//
// Reached from «Tu plan» (tap a routine) and DEBUG screenshot-nav — NOT the «Empezar» happy path anymore
// (the landing starts today's session in one tap, FER-«Pulir» F1). So this is now a «view this routine's
// plan» screen: exercises + target scheme + rest rule, with a «Start workout» for that routine. The
// recovery band that used to live here is gone (F6) — the autoregulation line shows on the landing hero
// and the running session header, not duplicated here.
//
// The guided, set-by-set session is FER-347: «Empezar» builds the routine's plan (with each exercise's
// «la última vez» prefill) and opens the guided session sheet (owned by AppModel).

struct RutinaDeHoyScreen: View {
    /// Which routine to show; nil = today's pick (the most recent), used by DEBUG screenshot-nav.
    var routineId: String?

    var body: some View {
        RutinaDeHoyContent(routineId: routineId)
            .instrumentoTheme(.base)
    }
}

private struct RutinaDeHoyContent: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var model: AppModel
    @Environment(\.instrumentoTheme) private var theme
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var routineId: String?

    @State private var loaded = false
    @State private var routine: Routine?
    @State private var rows: [PlanRow] = []
    /// The exercise whose detail sheet is open (FER-517); nil = none.
    @State private var detailExercise: Exercise?
    /// Drives the routine builder sheet for editing this routine (FER-557).
    @State private var builderTarget: BuilderTarget?

    private var imperial: Bool { UnitSystem(rawValue: unitSystemRaw) == .imperial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                if loaded {
                    plan
                    if !rows.isEmpty { startButton }
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // Edit this routine (FER-557): a trailing «Edit» opens the existing builder; saving reloads the
        // plan in place. Hidden with no resolved routine, or while a guided session is live (editing a
        // routine under a running session is ambiguous).
        .toolbar {
            if loaded, let r = routine, model.strengthSession == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { builderTarget = .edit(r) }
                        .foregroundStyle(theme.ink)
                        .accessibilityLabel(Text("Edit routine"))
                        .accessibilityHint(Text("Opens the routine editor"))
                }
            }
        }
        .sheet(item: $builderTarget) { target in
            RoutineBuilderScreen(routine: target.routine) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's routine").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(routine?.name ?? "Routine")
                .font(StrandFont.title1).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The plan

    private var plan: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if rows.isEmpty {
                Text("This routine has no exercises yet.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        planRow(row)
                        if row.id != rows.last?.id { Divider().overlay(theme.hairline) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func planRow(_ row: PlanRow) -> some View {
        // Tapping an exercise opens its detail (Progreso + Records, FER-517) — only when the slot
        // resolves to a real exercise, so an unknown id is never a dead tap.
        if let ex = row.exercise {
            Button { detailExercise = ex } label: { planRowContent(row, tappable: true) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the exercise"))
        } else {
            planRowContent(row, tappable: false)
        }
    }

    private func planRowContent(_ row: PlanRow, tappable: Bool) -> some View {
        HStack(spacing: 12) {
            ExerciseThumbnail(side: 54)   // reserved media slot (FER-751); FER-722 fills it
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(StrandFont.body).foregroundStyle(theme.ink)
                if let muscles = row.musclesText {
                    Text(muscles).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(schemeText(row.re))
                    .font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                restChip(row.re)
            }
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func restChip(_ re: RoutineExercise) -> some View {
        Text(restText(re))
            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(theme.paper, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Start the guided session (FER-347)

    private var startButton: some View {
        StrandCTAButton(model.strengthSession != nil ? "Resume workout" : "Start workout",
                        systemImage: model.strengthSession != nil ? "play.fill" : "figure.strengthtraining.functional") { start() }
            .padding(.top, 4)
    }

    private func start() {
        // A session already running → just resume it (don't rebuild over logged sets).
        if model.strengthSession != nil { model.resumeStrengthSession(); return }
        guard let r = routine else { return }
        let slots = rows.map {
            StrengthSessionModel.PlanSlot(re: $0.re, exercise: $0.exercise, lastSets: $0.lastSets)
        }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: slots)
    }

    // MARK: - Formatting

    private func schemeText(_ re: RoutineExercise) -> String {
        var s: String
        if let reps = re.targetReps {
            s = "\(re.targetSets) × \(reps)"
        } else {
            s = String(localized: "\(re.targetSets) sets")
        }
        if let w = re.targetWeightKg, w > 0 { s += " · \(weightText(w))" }
        return s
    }

    private func weightText(_ kg: Double) -> String {
        if imperial { return "\(numText(UnitFormatter.kgToPounds(kg))) lb" }
        return "\(numText(kg)) kg"
    }

    /// Plate weights read cleaner without a trailing «.0» (60 kg, not 60.0 kg) but keep one decimal for
    /// half-plates (2.5 kg) — so this intentionally differs from `UnitFormatter.massFromKilograms`, which
    /// always shows one decimal. Don't fold it into that helper without bringing back the «.0».
    private func numText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    private func restText(_ re: RoutineExercise) -> String {
        switch re.restMode {
        case .heartRate: return String(localized: "rest by HR")
        case .fixed:
            let s = re.restSeconds
            if s >= 60 && s % 60 == 0 { return String(localized: "\(s / 60) min rest") }
            return String(localized: "\(s)s rest")
        }
    }

    // MARK: - Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let all = (try? await store.routines()) ?? []
        let target = routineId.flatMap { id in all.first { $0.id == id } } ?? all.first
        guard let r = target else { loaded = true; return }
        let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
        // Resolve names + type: bundled catalog first, then user-created exercises, then apply the user's
        // measurement-type override (FER-541) so the guided session's Foco matches the override.
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
        routine = r
        var built: [PlanRow] = []
        for re in exs {
            let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
            // Recent work sets power the «la última vez» prefill in the guided session (FER-347).
            let last = (try? await store.lastWorkSets(exerciseId: re.exerciseId, limit: 4)) ?? []
            built.append(PlanRow(re: re, exercise: ex, lastSets: last))
        }
        rows = built
        loaded = true
    }
}

/// One row of the plan: a routine slot plus its resolved exercise (nil if it can't be found).
private struct PlanRow: Identifiable {
    let re: RoutineExercise
    let exercise: Exercise?
    /// Recent work sets (newest first) for the guided session's «la última vez» prefill (FER-347).
    var lastSets: [SetEntry] = []
    var id: String { re.id }
    var name: String { exercise.map(StrengthDisplay.name) ?? String(localized: "Exercise") }
    /// Up to two primary muscles in the device language (catalog stores them as English keys).
    var musclesText: String? {
        guard let m = exercise?.primaryMuscles, !m.isEmpty else { return nil }
        return m.prefix(2).map(StrengthDisplay.muscle).joined(separator: " · ")
    }
}
#endif
