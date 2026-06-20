#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

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
    @EnvironmentObject var model: AppModel
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
        // The guided strength session (FER-347). Hosted here at the hub root so it survives pushing
        // «Rutina de hoy» / switching tabs; the session itself lives in AppModel, so swiping the sheet
        // down only hides it (the «Resume» row below re-opens). A `.sheet` — no nested NavigationStack.
        .sheet(isPresented: $model.strengthSheetPresented) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session, theme: theme)
                    .environmentObject(model)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.paper)
                    .preferredColorScheme(.light)
            }
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
                if model.strengthSession != nil {
                    resumeStrengthRow
                    divider
                }
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

    /// «Resume» the in-progress guided session (FER-347) — shown only while a session runs but its sheet
    /// is dismissed, so the durable session is always one tap away from the hub.
    private var resumeStrengthRow: some View {
        Button { model.resumeStrengthSession() } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.functional").frame(width: 30)
                    .font(.system(size: 17)).foregroundStyle(theme.dataStrain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workout in progress").font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(model.strengthSession?.routineName ?? "")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Text("Resume").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Resume workout in progress"))
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

// MARK: - Recovery band (the visual container; the rule is W3·bucle / FER-349)

/// The «sube / mantén / baja» recovery band. FER-343 ships only the **container**: a provisional
/// recommendation read straight off today's recovery score. The real autoregulation rule (HRV-guided +
/// RIR/RPE, with citations) is FER-349 — until then this stays transparent and recovery-only, and it
/// **never appears without a recovery score** (no invented advice).
struct RecoveryBand: View {
    @Environment(\.instrumentoTheme) private var theme
    let recovery: Double

    private var band: TrainingBand { TrainingBand(recovery: recovery) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recovery band").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(band.word)
                    .font(StrandFont.title2).foregroundStyle(band.color(theme))
                Text(band.detail(recovery))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Three coarse training-load bands derived from recovery. Coarse on purpose (the honesty is the
/// feature): a provisional stand-in for FER-349's evidence-based rule.
enum TrainingBand {
    case push, hold, ease

    init(recovery: Double) {
        switch recovery {
        case ..<50:  self = .ease
        case ..<70:  self = .hold
        default:     self = .push
        }
    }

    var word: LocalizedStringKey {
        switch self {
        case .push: return "Push"
        case .hold: return "Hold"
        case .ease: return "Ease"
        }
    }

    func color(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .push: return theme.verdict     // ready — push (green)
        case .hold: return theme.ink         // steady — no strong signal (no color)
        case .ease: return theme.warning     // under-recovered — back off (amber)
        }
    }

    func detail(_ recovery: Double) -> String {
        let n = Int(recovery.rounded())
        switch self {
        case .push: return String(localized: "Recovery \(n) · high. A good day to add load.")
        case .hold: return String(localized: "Recovery \(n) · moderate. Keep your usual load.")
        case .ease: return String(localized: "Recovery \(n) · low. Pull back the volume today.")
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
