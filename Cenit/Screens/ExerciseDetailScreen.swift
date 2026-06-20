#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// ExerciseDetailScreen.swift — one exercise: which muscles it loads, your history, and an estimated-1RM
// trend (FER-346). Presented as a sheet from the library. «Báscula de papel»: weights are the heroes,
// in ink; the only color is the 1RM trend line (`dataStrain`, the output hue). With no logged work yet
// it stays honest — muscles + why the history is empty, nothing fabricated.

struct ExerciseDetailScreen: View {
    let exercise: Exercise

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Work sets across sessions (oldest→newest), the raw material for best-mark / last-time / 1RM.
    @State private var history: [(startTs: Int, weightKg: Double, reps: Int)] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                musclesSection
                if loaded {
                    if history.isEmpty { emptyHistory } else { historySection }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: exercise.id) {
            history = await repo.exerciseHistory(exerciseId: exercise.id)
            loaded = true
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text(StrengthDisplay.subtitle(exercise) + " · ") + Text(StrengthDisplay.typeLabel(exercise.type)))
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(exercise.name)
                .font(StrandFont.title1).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Muscles (primary at full ink, assistants at half)

    private var musclesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(exercise.primaryMuscles, id: \.self) { m in muscleBar(m, primary: true) }
                ForEach(exercise.secondaryMuscles, id: \.self) { m in muscleBar(m, primary: false) }
            }
            if !exercise.secondaryMuscles.isEmpty {
                Text("Primary at full ink · assisting at half")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    private func muscleBar(_ muscle: String, primary: Bool) -> some View {
        HStack(spacing: 12) {
            Text(StrengthDisplay.titleCase(muscle))
                .font(StrandFont.subhead)
                .foregroundStyle(primary ? theme.ink : theme.inkSecondary)
                .frame(width: 116, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 7)
                    Capsule().fill(primary ? theme.ink : theme.inkTertiary)
                        .frame(width: geo.size.width * (primary ? 1.0 : 0.5), height: 7)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(StrengthDisplay.titleCase(muscle)), \(primary ? "primary" : "assisting")")
    }

    // MARK: - History (best mark / last time / estimated 1RM)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            HStack(alignment: .top, spacing: 24) {
                if let best = bestSet { heroStat("Best mark", best.weightKg, "× \(best.reps) reps · \(relative(best.startTs))") }
                if let last = history.last { heroStat("Last time", last.weightKg, "× \(last.reps) reps · \(relative(last.startTs))") }
            }
            .padding(.top, 18)

            oneRepMaxSection.padding(.top, 6)
        }
    }

    private func heroStat(_ label: LocalizedStringKey, _ kg: Double, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(StrengthDisplay.weightNumber(kg, system: system))
                    .instrumentoHero(38).foregroundStyle(theme.ink)
                Text(StrengthDisplay.weightUnit(system))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            Text(caption).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var oneRepMaxSection: some View {
        let spark = OneRepMax.dailySparkline(history.map {
            (day: Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval($0.startTs))),
             weightKg: $0.weightKg, reps: $0.reps)
        })
        if let latest = spark.last {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(theme.hairline).padding(.top, 18)
                HStack(alignment: .firstTextBaseline) {
                    Text("Estimated 1RM").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(StrengthDisplay.weightNumber(latest.estimatedKg, system: system))
                            .font(StrandFont.number(22, weight: .semibold)).foregroundStyle(theme.ink)
                        Text(StrengthDisplay.weightUnit(system))
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                }
                if spark.count >= 2 {
                    Sparkline(values: spark.map(\.estimatedKg),
                              gradient: Gradient(colors: [theme.dataStrain.opacity(0.55), theme.dataStrain]),
                              bandColor: theme.hairlineStrong,
                              showsScrub: true,
                              valueFormat: { StrengthDisplay.weight($0, system: system) })
                        .frame(height: 64)
                        .accessibilityLabel("Estimated 1RM trend")
                }
                Text("From your best set with the Epley (1985) formula. A progress signal, not a target to load.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Honest empty

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            VStack(spacing: 11) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30, weight: .regular)).foregroundStyle(theme.inkTertiary)
                Text("Not logged yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("Your best mark, your last session and your estimated 1RM appear here once you complete a work set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    // MARK: - Derived + formatting

    private var bestSet: (weightKg: Double, reps: Int, startTs: Int)? {
        history.max { $0.weightKg < $1.weightKg }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    private func relative(_ ts: Int) -> String {
        Self.relativeFormatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(ts)), relativeTo: Date())
    }
}
#endif
