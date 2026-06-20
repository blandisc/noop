#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Entrenar (the Train tab root) — FER-343
//
// The redesigned «Entrenar» hub in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). It replaces the interim list of rows (FER-342) with a real hub: a
// «Hoy» card carrying the day's routine + a recovery band, the «Mis rutinas» list, and the
// Respira / Intervalos / En-vivo tools. The door to the strength tracker (FER-39 epic).
//
// Navigation, like Cuerpo/Ajustes, is owned by the tab's `NavigationStack` in RootTabView: the hub
// pushes «Rutina de hoy» / Respira / Intervalos via the injected closures, so the screen stays
// decoupled from the private route types. En vivo opens its own sheet (the recorder lives in AppModel).
//
// Out of scope here (each its own issue): the routine builder (FER-346) and the guided session
// (FER-347). Their entry points show an honest «coming soon» note rather than a dead action.

/// Theme wrapper: drives `\.instrumentoTheme` by the hour (like Today / Cuerpo / Ajustes) so Entrenar
/// warms with the real sun, then hands to `EntrenarLanding`, which reads the resolved theme.
struct EntrenarView: View {
    /// Sunrise/sunset for today (from RootTabView, which already computes it for the instrument bar).
    var solar: SolarWindow?
    /// Push «Rutina de hoy» for a given routine id (the tab's NavigationStack owns the path).
    var openRoutine: (String) -> Void
    /// Push the exercise library (browse) onto the tab's NavigationStack.
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine, openLibrary: openLibrary,
                        openBreathe: openBreathe, openIntervals: openIntervals, openDiet: openDiet)
            .instrumentoThemeByHour(solar: solar)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// Drives the routine builder sheet (FER-346): `.new` or `.edit(routine)`.
    @State private var builderTarget: BuilderTarget? = nil

    /// Today's recovery (0–100), nil until a score exists. Drives whether the band shows.
    private var recovery: Double? { repo.today?.recovery }
    /// «Today's» pick: with no scheduler yet (W3·bucle), the most recent/ordered routine stands in.
    private var todayRoutine: Routine? { routines.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                if loaded {
                    if let today = todayRoutine {
                        hoyCard(today)
                        misRutinas
                    } else {
                        emptyHoy
                    }
                }

                herramientas
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(item: $builderTarget) { target in
            RoutineBuilderScreen(routine: target.routine) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Train").font(StrandFont.title1).foregroundStyle(theme.ink)
            Text("Your plan for today, your routines, and your tools.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - «Hoy» card

    private func hoyCard(_ routine: Routine) -> some View {
        Button { openRoutine(routine.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(routine.name)
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .padding(.top, 3)
                Text(exerciseCountText(exerciseCounts[routine.id] ?? 0))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .padding(.top, 2)

                if let rec = recovery {
                    Divider().overlay(theme.hairline).padding(.vertical, 14)
                    RecoveryBand(recovery: rec)
                }

                HStack(spacing: 6) {
                    Text("View routine").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 16)
            }
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens today's routine"))
    }

    // MARK: - «Mis rutinas»

    private var misRutinas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("My routines").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(routines) { r in
                    routineRow(r)
                    if r.id != routines.last?.id { divider }
                }
                divider
                Button { builderTarget = .new } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").frame(width: 30)
                            .font(.system(size: 17)).foregroundStyle(theme.inkSecondary)
                        Text("New routine").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func routineRow(_ r: Routine) -> some View {
        Button { openRoutine(r.id) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(exerciseCountText(exerciseCounts[r.id] ?? 0))
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { builderTarget = .edit(r) } label: { Label("Edit routine", systemImage: "slider.horizontal.3") }
            Button(role: .destructive) {
                Task { try? await repo.deleteRoutine(id: r.id); await load() }
            } label: { Label("Delete routine", systemImage: "trash") }
        }
    }

    // MARK: - Empty state (no routines yet → CTA, FER-343 criterion)

    private var emptyHoy: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell")
                .font(.system(size: 38, weight: .regular)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("No routines yet")
                .font(StrandFont.title2).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text("Create your first routine, or start from a template.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                QuietButton("New routine") { builderTarget = .new }
                Button { openLibrary() } label: {
                    Text("Browse the exercise library")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Tools

    private var herramientas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tools").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                LiveWorkoutHubRow()
                divider
                toolRow("Exercise library", "book", action: openLibrary)
                divider
                toolRow("Breathe", "wind", action: openBreathe)
                divider
                toolRow("Intervals", "timer", action: openIntervals)
                divider
                toolRow("Diet", "fork.knife", action: openDiet)
            }
        }
    }

    private func toolRow(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 30)
                    .font(.system(size: 19)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    private var divider: some View { Divider().overlay(theme.hairline) }

    private func exerciseCountText(_ n: Int) -> String {
        String(localized: "\(n) exercises")
    }

    // MARK: - Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        var counts: [String: Int] = [:]
        for r in rs {
            counts[r.id] = (try? await store.routineExercises(routineId: r.id))?.count ?? 0
        }
        routines = rs
        exerciseCounts = counts
        loaded = true
    }
}

// MARK: - Recovery band (the «sube / mantén / baja» autoregulation suggestion — FER-349)

/// The recovery band: an OPT-IN "push / hold / ease" suggestion shown before a session, driven by the
/// cited `TrainingRegulation` rule (StrandAnalytics) rather than ad-hoc cuts. It maps today's recovery
/// to the app's canonical recovery bands and carries a fixed "suggestion · you decide" label — it
/// never gates training. It **never appears without a recovery score** (the rule returns nil and the
/// caller hides the slot — no invented advice).
struct RecoveryBand: View {
    @Environment(\.instrumentoTheme) private var theme
    let recovery: Double

    /// The cited rule. The score-only path uses the canonical recovery bands; a personal z is preferred
    /// when a caller has it (not plumbed here yet).
    private var suggestion: TrainingRegulation.Suggestion? {
        TrainingRegulation.suggest(recovery: recovery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery band").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let s = suggestion {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word(s.adjustment))
                        .font(StrandFont.title2).foregroundStyle(color(s.adjustment))
                    Text(detail(s.reason))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                    Text("Suggestion · you decide")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func word(_ a: TrainingRegulation.Adjustment) -> LocalizedStringKey {
        switch a {
        case .dialUp:   return "Push"
        case .hold:     return "Hold"
        case .dialBack: return "Ease"
        }
    }

    private func color(_ a: TrainingRegulation.Adjustment) -> Color {
        switch a {
        case .dialUp:   return theme.verdict   // recovered — push (green)
        case .hold:     return theme.ink       // within your normal — no color
        case .dialBack: return theme.warning   // under-recovered — ease off (amber)
        }
    }

    private func detail(_ reason: TrainingRegulation.Reason) -> String {
        let n = Int(recovery.rounded())
        switch reason {
        case .recoveryHigh:  return String(localized: "Recovery \(n) · high. A good day to add load.")
        case .withinNormal:  return String(localized: "Recovery \(n) · moderate. Keep your usual load.")
        case .recoveryLow:   return String(localized: "Recovery \(n) · low. Pull back the volume today.")
        }
    }
}

// MARK: - Honest «coming soon» sheet (for builder/guided start — FER-346 / FER-347)

/// A quiet Instrumento sheet that names what's coming, instead of a dead button. Used by the routine
/// builder entry points until FER-346 ships.
struct TrainingSoonSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    let overline: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text(message)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}
#endif
