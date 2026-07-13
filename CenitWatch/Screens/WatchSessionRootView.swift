import SwiftUI
import StrandDesign

/// The watch face for a mirrored strength session (FER-741). One dominant focus per state, color only in
/// the datum, hierarchy by space — «Instrumento diurno» translated to the wrist. It routes the coarse
/// `WatchWorkoutManager.Phase` to a screen; the live face derives rest vs. pulse and the degraded
/// overlays (no reading / no permission / no iPhone) from the finer published state.
struct WatchSessionRootView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    private let t = InstrumentoTheme.base

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(t.paper.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        switch manager.phase {
        case let .idle(couldNotConnect):
            WatchIdleView(couldNotConnect: couldNotConnect)
        case .connecting:
            WatchConnectingView()
        case .running:
            if manager.restEndedBanner { WatchRestEndedView() }
            else { WatchLiveFaceView() }
        case .summary:
            if let summary = manager.summary { WatchSummaryView(summary: summary) }
            else { WatchIdleView(couldNotConnect: false) }
        }
    }
}

// MARK: - 1 · Waiting (and the «couldn't connect» variant)

/// State 1 (and state 2's failure fallback). No dead buttons, no fake data — just what to do next.
struct WatchIdleView: View {
    let couldNotConnect: Bool
    private let t = InstrumentoTheme.base

    var body: some View {
        VStack(spacing: CenitMetrics.space2) {
            Text("No session")
                .font(StrandFont.headline)
                .foregroundStyle(t.ink)
            Text("Start a strength routine on your iPhone and the watch joins in.")
                .font(StrandFont.caption)
                .foregroundStyle(t.inkSecondary)
                .multilineTextAlignment(.center)
            if couldNotConnect {
                Text("Couldn't connect to the session. Keep going on your iPhone.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(t.inkTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, CenitMetrics.gap)
    }
}

// MARK: - 2 · Connecting

/// State 2. A brief transition while the woken app spins up the session; falls to `WatchIdleView`
/// (couldn't connect) after 15s, handled by the manager's watchdog.
struct WatchConnectingView: View {
    private let t = InstrumentoTheme.base

    var body: some View {
        VStack(spacing: CenitMetrics.space2) {
            Text("Connecting")
                .font(StrandFont.headline)
                .foregroundStyle(t.inkSecondary)
            ProgressView()
                .tint(t.inkTertiary)
        }
        .padding(.horizontal, CenitMetrics.gap)
    }
}

// MARK: - 5 · Rest over

/// State 5's visual transition (~3s), shown while the strong rest-end haptic plays. The haptic is the
/// primary signal; this confirms it at a glance and posts a VoiceOver announcement. Returns to the live
/// face on its own.
struct WatchRestEndedView: View {
    private let t = InstrumentoTheme.base

    var body: some View {
        VStack(spacing: CenitMetrics.space2) {
            Image(systemName: "checkmark")
                .font(StrandFont.title1)
                .foregroundStyle(t.verdict)
            Text("Rest over")
                .font(StrandFont.headline)
                .foregroundStyle(t.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, CenitMetrics.gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rest over"))
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Rest over")).post() }
    }
}
