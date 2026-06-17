import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Train hub: live-workout entry + recording sheet (FER-197)
//
// Restores the manually-started live workout tracker removed from Live in FER-184, now living in the
// Train hub. The HUB ROW stays in the hub's dark `StrandPalette` (matching Breathe/Intervals); tapping
// it opens a SHEET written in the light «Instrumento diurno» language — coherent with Live, which is
// itself a light sheet (FER-190). The recording lives in `AppModel` (global), so closing the sheet or
// switching tabs never stops the session; the row then reads "Recording m:ss" and reopens the sheet.
//
// Theme note: the dark hub has no `instrumentoTheme` in its environment, and `.sheet` starts a fresh
// environment anyway — so the by-the-hour theme is computed here and passed to the sheet EXPLICITLY.

/// The Train-hub Section: a "Start live" action (disabled without a worn strap streaming HR), a
/// "Recording m:ss" row while a session runs, and a brief saved/discarded notice afterwards.
struct LiveWorkoutHubRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// Sunrise/sunset so the sheet's «Instrumento» paper tracks the hour, like Today/Live. Passed from
    /// RootTabView (which already computes it for the instrument bar). `nil` → fixed-hour fallback.
    var solar: SolarWindow?

    @State private var showSheet = false

    /// The same "HR is genuinely streaming from a worn strap" signal Live uses to light its monitor.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }
    private var isDisabled: Bool { model.activeWorkout == nil && !isLiveHR }
    private var sheetTheme: InstrumentoTheme { InstrumentoThemeEngine.theme(at: Date(), solar: solar) }

    var body: some View {
        Section {
            // ONE stable Button hosts the sheet, so flipping start → recording never tears it down.
            Button { primaryTap() } label: { rowLabel }
                .disabled(isDisabled)
                .listRowBackground(StrandPalette.surfaceRaised)
                .accessibilityLabel(Text(model.activeWorkout != nil ? "Recording" : "Start live"))
                .accessibilityHint(isDisabled ? Text("Connect and wear your strap to record live.") : Text(""))
                .sheet(isPresented: $showSheet) {
                    LiveWorkoutSheet(theme: sheetTheme)
                        .environmentObject(model)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackground(sheetTheme.paper)
                        .preferredColorScheme(.light)
                }

            if model.activeWorkout == nil, model.lastWorkout != nil || model.lastWorkoutDiscarded {
                outcomeRow
            }
        } footer: {
            if isDisabled {
                Text("Connect and wear your strap to record live.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func primaryTap() {
        if model.activeWorkout == nil { model.startWorkout() }
        showSheet = true
    }

    @ViewBuilder private var rowLabel: some View {
        if let w = model.activeWorkout {
            HStack(spacing: 10) {
                Circle().fill(StrandPalette.accent).frame(width: 8, height: 8)
                Text("Recording").font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                    Text(Self.elapsed(from: w.start, to: ctx.date))
                        .font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textSecondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(StrandPalette.textTertiary)
            }
        } else {
            Label("Start live", systemImage: "play.fill")
                .font(StrandFont.body)
                .foregroundStyle(isLiveHR ? StrandPalette.accent : StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Saved-or-discarded notice, auto-acknowledged after a few seconds so the row returns to idle.
    private var outcomeRow: some View {
        let discarded = model.lastWorkoutDiscarded
        return HStack(spacing: 10) {
            Image(systemName: discarded ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(discarded ? StrandPalette.statusWarning : StrandPalette.accent)
            Text(noticeText).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .listRowBackground(StrandPalette.surfaceRaised)
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
            return "\(String(localized: "Workout saved")) · \(mins) min · \(avg) bpm"
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
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var theme: InstrumentoTheme = .base

    var body: some View {
        // ScrollView so the clock + stats never clip at large Dynamic Type / small screens (the same
        // graceful-degradation Live uses); at normal sizes it all sits within the medium detent.
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
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
                    stat("Rate", model.bpm.map(String.init) ?? "—")
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
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.critical.opacity(0.4), lineWidth: 1))
                .padding(.top, 8)
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 28)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
    }

    private func stat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).instrumentoHero(26).foregroundStyle(theme.ink)
        }
    }

    private func statValue(_ v: Int?) -> String { (v ?? 0) > 0 ? "\(v!)" : "—" }
}
