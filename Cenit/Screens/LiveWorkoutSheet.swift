import SwiftUI
import StrandDesign
import WhoopStore
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - Train hub: live-workout entry + recording sheet (FER-197)
//
// Restores the manually-started live workout tracker removed from Live in FER-184, now living in the
// Train hub. The Train hub is the light «Instrumento» paper hub (FER-342 / FER-343), so this entry reads
// in the same warm palette as the other tools; tapping it opens a SHEET in the same language — coherent
// with Live, which is itself a light sheet (FER-190). The recording lives in `AppModel` (global), so
// closing the sheet or switching tabs never stops the session; the row then reads "Recording m:ss".
//
// FER-343 moved this from a List `Section` into a plain row that sits in the hub's «Tools» VStack: it
// reads the theme from the environment (the hub themes its whole subtree), and passes that same theme to
// the sheet EXPLICITLY (the theme does not cross the `.sheet` boundary — FER-162).

/// The Train-hub «En vivo» row: a "Start live" action (disabled without a worn strap streaming HR), a
/// "Recording m:ss" state while a session runs, and a brief saved/discarded notice afterwards.
struct LiveWorkoutHubRow: View {
    @Environment(AppModel.self) private var model
    @Environment(LiveState.self) private var live
    @Environment(\.instrumentoTheme) private var theme

    @State private var showSheet = false

    /// The same "HR is genuinely streaming from a worn strap" signal Live uses to light its monitor.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }
    private var isDisabled: Bool { model.activeWorkout == nil && !isLiveHR }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ONE stable Button hosts the sheet, so flipping start → recording never tears it down.
            Button { primaryTap() } label: { rowLabel }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel(Text(model.activeWorkout != nil ? "Recording" : "Start live"))
                .accessibilityHint(isDisabled ? Text("Connect and wear your strap to record live.") : Text(""))
                .sheet(isPresented: $showSheet) {
                    LiveWorkoutSheet(theme: theme)
                        .environment(model)
                        .presentationDetents([.height(CenitMetrics.liveSheetHeight), .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(theme.paper)
                        .preferredColorScheme(.light)
                }

            if isDisabled {
                Text("Connect and wear your strap to record live.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            if model.activeWorkout == nil, model.lastWorkout != nil || model.lastWorkoutDiscarded {
                outcomeRow
            }
        }
    }

    private func primaryTap() {
        if model.activeWorkout == nil { model.startWorkout() }
        showSheet = true
    }

    @ViewBuilder private var rowLabel: some View {
        if let w = model.activeWorkout {
            HStack(spacing: 12) {
                Image(systemName: "circle.fill").frame(width: 30)
                    .font(.system(size: 9)).foregroundStyle(theme.dataRecovery) // token-exempt: microtexto <10pt
                Text("Recording").font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                    Text(Self.elapsed(from: w.start, to: ctx.date))
                        .font(StrandFont.bodyNumber).foregroundStyle(theme.inkSecondary)
                }
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        } else {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").frame(width: 30)
                    .font(StrandFont.glyph(.lead))
                    .foregroundStyle(isLiveHR ? theme.dataRecovery : theme.inkTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start live").font(StrandFont.body)
                        .foregroundStyle(isDisabled ? theme.inkTertiary : theme.ink)
                    Text("Record heart rate and effort with your strap")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .frame(minHeight: 48).contentShape(Rectangle())
        }
    }

    /// Saved-or-discarded notice, auto-acknowledged after a few seconds so the row returns to idle.
    private var outcomeRow: some View {
        let discarded = model.lastWorkoutDiscarded
        return HStack(spacing: 10) {
            Image(systemName: discarded ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(discarded ? theme.warning : theme.dataRecovery)
            Text(noticeText).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            model.acknowledgeLastWorkout()
        }
    }

    private var noticeText: String {
        if model.lastWorkoutDiscarded {
            return String(localized: "Not saved: no heart rate from the strap.")
        }
        if let w = model.lastWorkout {
            let mins = max(1, Int(((w.durationS ?? 0) / 60).rounded()))
            let avg = w.avgHr ?? 0
            return "\(String(localized: "Workout saved")) · \(mins) min · \(avg) \(String(localized: "bpm"))"
        }
        return ""
    }

    /// Elapsed seconds as m:ss, rolling to h:mm:ss past an hour.
    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

/// The live-workout recording sheet, in the light «Instrumento diurno» language. The theme is passed
/// in explicitly — it does NOT propagate through `.sheet`'s fresh environment (same as Live, FER-190).
/// A pure recorder: overline + clock + Rate/Avg/Peak + Finish. No strain on screen (FER-181 direction).
struct LiveWorkoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject
    var theme: InstrumentoTheme = .base

    var body: some View {
        // ScrollView so the clock + stats never clip at large Dynamic Type / small screens (the same
        // graceful-degradation Live uses); at normal sizes it all sits within the medium detent.
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                HStack(spacing: 7) {
                    Circle().fill(theme.dataRecovery).frame(width: 9, height: 9)
                    Text("Recording").instrumentoOverline().foregroundStyle(theme.dataRecovery)
                }

                if let w = model.activeWorkout {
                    TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                        Text(LiveWorkoutHubRow.elapsed(from: w.start, to: ctx.date))
                            .instrumentoHero(56).foregroundStyle(theme.ink)
                    }
                } else {
                    Text("0:00").instrumentoHero(56).foregroundStyle(theme.inkTertiary)
                }

                HStack(spacing: 28) {
                    // PulseReader: the live rate ticks per beat without re-rendering the sheet (FER-755).
                    PulseReader(model.live.pulse) { p in
                        stat("Rate", p.smoothedBpm.map(String.init) ?? "—")
                    }
                    stat("Avg", statValue(model.activeWorkout?.avgHr))
                    stat("Peak", statValue(model.activeWorkout?.peakHr))
                }

                Button(role: .destructive) {
                    model.endWorkout()
                    dismiss()
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(StrandFont.headline)
                        .foregroundStyle(theme.critical)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .instrumentoCard(.card, theme: theme, fill: theme.surface, stroke: theme.critical.opacity(StrandOpacity.strokeSoft))
                .padding(.top, 8)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 28)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        .enableInjection()
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).instrumentoHero(26).foregroundStyle(theme.ink)
        }
    }

    private func statValue(_ v: Int?) -> String { (v ?? 0) > 0 ? "\(v!)" : "—" }
}
