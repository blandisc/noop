#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - «Rutina de hoy» — the pre-start plan screen (FER-343)
//
// The screen that precedes a session: the routine's plan (exercises + target scheme + rest rule) and
// the recovery band slot (hidden when there is no recovery score — never invents advice). Pushed from
// the Entrenar hub in the light «Instrumento» language.
//
// The guided, set-by-set session is FER-347 (out of scope), so there is no functional «Empezar» here
// yet — an honest note names what's coming. The band's RULE is W3·bucle / FER-349; this screen only
// renders the shared `RecoveryBand` container.

struct RutinaDeHoyScreen: View {
    /// Which routine to show; nil = today's pick (the most recent), used by DEBUG screenshot-nav.
    var routineId: String?
    var solar: SolarWindow?

    var body: some View {
        RutinaDeHoyContent(routineId: routineId)
            .instrumentoThemeByHour(solar: solar)
    }
}

private struct RutinaDeHoyContent: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue

    var routineId: String?

    @State private var loaded = false
    @State private var routine: Routine?
    @State private var rows: [PlanRow] = []

    private var recovery: Double? { repo.today?.recovery }
    private var imperial: Bool { UnitSystem(rawValue: unitSystemRaw) == .imperial }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                if let rec = recovery {
                    bandCard(rec)
                }

                if loaded {
                    plan
                    startNote
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
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

    // MARK: - Recovery band slot (hidden without recovery)

    private func bandCard(_ rec: Double) -> some View {
        RecoveryBand(recovery: rec)
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
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

    private func planRow(_ row: PlanRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
        }
        .padding(.vertical, 11)
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

    // MARK: - Honest guided-start note (FER-347 ships the real start)

    private var startNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13)).foregroundStyle(theme.inkTertiary)
            Text("Guided, set-by-set tracking arrives in a coming update.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
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
        // Resolve names: bundled catalog first, then user-created exercises.
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        routine = r
        rows = exs.map { re in
            let ex = ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId]
            return PlanRow(re: re, exercise: ex)
        }
        loaded = true
    }
}

/// One row of the plan: a routine slot plus its resolved exercise (nil if it can't be found).
private struct PlanRow: Identifiable {
    let re: RoutineExercise
    let exercise: Exercise?
    var id: String { re.id }
    var name: String { exercise?.name ?? String(localized: "Exercise") }
    /// Up to two primary muscles, capitalized for display (catalog stores them lowercased).
    var musclesText: String? {
        guard let m = exercise?.primaryMuscles, !m.isEmpty else { return nil }
        return m.prefix(2).map { $0.capitalized }.joined(separator: " · ")
    }
}
#endif
