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
    @Environment(\.openURL) private var openURL
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
                if !exercise.cues.isEmpty { howToSection }
                if loaded {
                    if history.isEmpty { emptyHistory } else { historySection }
                }
                youtubeRow
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
            Text(StrengthDisplay.name(exercise))
                .font(StrandFont.title1).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Muscles (primary at full ink, assistants at half)

    private var musclesSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            // The worked-muscle silhouette (FER-389): front/back figures reusing the muscle-map atlas,
            // primaries in full ink and assistants at half. Derived from the exercise's own muscle data —
            // no bundled art, no network. Hidden when an exercise carries no muscles (a bare custom one).
            if !exercise.primaryMuscles.isEmpty || !exercise.secondaryMuscles.isEmpty {
                ExerciseMuscleFigures(theme: theme,
                                      primary: Set(exercise.primaryMuscles),
                                      secondary: Set(exercise.secondaryMuscles))
                    .padding(.bottom, 4)
            }
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
            Text(StrengthDisplay.muscle(muscle))
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
        .accessibilityLabel("\(StrengthDisplay.muscle(muscle)), \(primary ? "primary" : "assisting")")
    }

    // MARK: - How to (offline text cues from the bundled catalog · FER-387)

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            Text("How to").instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.top, 18)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(exercise.cues.enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1)")
                            .font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                            .frame(width: 18, alignment: .trailing)
                        Text(cue)
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 11)
        }
    }

    // MARK: - Watch on YouTube (opt-in external hand-off · FER-387)
    // Offline rule: NOOP itself makes NO network call — this only hands off to the system browser /
    // YouTube app on an explicit user tap, and is clearly marked as leaving the app. Chrome, so it
    // carries no saturated color (ink/surface only).

    private var youtubeRow: some View {
        Button {
            let query = "\(exercise.name) exercise form"
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "play.rectangle").foregroundStyle(theme.inkSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch on YouTube").font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text("Opens outside the app · uses the internet")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(theme.inkTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Watch \(exercise.name) on YouTube")
        .accessibilityHint("Opens YouTube outside the app")
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

// MARK: - Worked-muscle silhouette (FER-389)

/// Front + back schematic figures that tint the muscles an exercise works — primaries in full ink,
/// assistants at half — reusing the muscle-map atlas (`MuscleAtlas`/`RegionShape`/`BodyOutlineShape`,
/// FER-350). Pure presentation off the exercise's own `primaryMuscles`/`secondaryMuscles`: no bundled
/// art, no network. Involvement is anatomical, not a live datum, so it reads in ink opacity — the
/// Instrumento «color only on the physiological datum» rule keeps color for HR/strain/recovery. The
/// figures are decorative reinforcement; the named muscle bars below carry the VoiceOver detail.
private struct ExerciseMuscleFigures: View {
    let theme: InstrumentoTheme
    let primary: Set<String>
    let secondary: Set<String>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            figure(.front)
            figure(.back)
        }
        .accessibilityHidden(true)
    }

    private func figure(_ side: MuscleAtlas.Side) -> some View {
        VStack(spacing: 6) {
            ZStack {
                BodyOutlineShape(side: side).stroke(theme.hairline, lineWidth: 1.2)
                ForEach(MuscleAtlas.regions.filter { $0.side == side }) { region in
                    if let fill = fill(for: region.muscle) {
                        let shape = RegionShape(region: region)
                        shape.fill(fill)
                            .overlay(shape.stroke(theme.hairline.opacity(0.5), lineWidth: 0.5))
                    }
                }
            }
            .aspectRatio(100.0 / 220.0, contentMode: .fit)
            .frame(maxHeight: 184)
            Text(side == .front ? "Front" : "Back")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Full ink for a primary mover, half for an assistant, nothing for an uninvolved muscle.
    private func fill(for muscle: String) -> Color? {
        if primary.contains(muscle) { return theme.ink }
        if secondary.contains(muscle) { return theme.ink.opacity(0.4) }
        return nil
    }
}
#endif
