// FER-721 · Entrenar v3 · F6 — the rest Live Activity: lock-screen card + Dynamic Island.
//
// «Instrumento diurno» DNA on a system surface: warm paper, one dominant number (the rest timer, in
// the effort hue), color only in the datum, hierarchy by space. Custom fonts aren't registered inside
// the widget extension, so this uses the system rounded face for the numerals (a deliberate,
// widget-safe substitute for the app's numeric type) while every color is a StrandDesign token.

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit
import StrandDesign

struct RestLiveActivity: Widget {
    private let theme = InstrumentoTheme.base

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Lock-screen / banner presentation.
            RestLockScreenCard(state: context.state, theme: theme)
                .activityBackgroundTint(theme.paper)
                .activitySystemActionForegroundColor(theme.ink)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                // Expanded — the timer leads, heart rate trails, the return caption sits below.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "timer").font(.system(size: 13, weight: .semibold))
                        RestTimerText(state: s, size: 22)
                    }
                    .foregroundStyle(theme.dataStrain)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeartReadout(state: s, theme: theme, size: 15)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(returnCaption(s))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            } compactLeading: {
                RestTimerText(state: s, size: 15).foregroundStyle(theme.dataStrain)
            } compactTrailing: {
                if let bpm = s.bpm {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").font(.system(size: 10))
                        Text("\(bpm)").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(theme.dataHeart)
                }
            } minimal: {
                RestTimerText(state: s, size: 13).foregroundStyle(theme.dataStrain)
            }
            .widgetURL(URL(string: "noopdev://rest"))
            .keylineTint(theme.dataStrain)
        }
    }
}

// MARK: - Lock-screen card

private struct RestLockScreenCard: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Overline: «{Rutina} · serie N de M».
            Text(headline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline) {
                // The dominant datum: the rest countdown, in the effort hue.
                RestTimerText(state: state, size: 44)
                    .foregroundStyle(theme.dataStrain)
                Spacer()
                HeartReadout(state: state, theme: theme, size: 20)
            }

            // Progress bar over the rest window (ticks locally, no updates).
            ProgressView(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(theme.dataStrain)

            // Caption: «al volver: serie N · {peso} × {reps}».
            Text(returnCaption(state))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Actions.
            HStack(spacing: 10) {
                Button(intent: RestAddThirtyIntent()) {
                    Label("+30 s", systemImage: "goforward.30")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(theme.dataStrain)

                Button(intent: RestSkipIntent()) {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(theme.inkSecondary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
        }
        .padding(16)
    }

    private var headline: String {
        // «Rutina · serie N de M»
        "\(state.routineName) · " + String(
            localized: "set \(state.setNumber) of \(state.setTotal)")
    }
}

// MARK: - Shared pieces

/// The rest countdown. In HR mode the timer still counts (it's the 5-minute cap) but the pulse is the
/// story; either way the numerals tick locally from `restEndsAt`.
private struct RestTimerText: View {
    let state: RestActivityAttributes.ContentState
    let size: CGFloat
    var body: some View {
        Text(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

/// The heart-rate readout: live pulse (and, in HR mode, the «→ N» ready target). Renders NOTHING when
/// there's no band data — no dash, no zero (acceptance criterion 4).
private struct HeartReadout: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    var size: CGFloat = 16
    var body: some View {
        if let bpm = state.bpm {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: size * 0.72))
                Text("\(bpm)").font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                if state.isHRMode, let target = state.hrTarget {
                    Text("→ \(target)")
                        .font(.system(size: size * 0.78, weight: .medium))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .foregroundStyle(theme.dataHeart)
        }
    }
}

/// «al volver: serie N · {peso} × {reps}» — drops the detail when the exercise has no weight×reps datum.
private func returnCaption(_ s: RestActivityAttributes.ContentState) -> String {
    let base = String(localized: "back to set \(s.setNumber) · \(s.exerciseName)")
    return s.returnDetail.isEmpty ? base : "\(base) · \(s.returnDetail)"
}
#endif
