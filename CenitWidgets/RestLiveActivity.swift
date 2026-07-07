// FER-721 · Entrenar v3 · F6 — the rest Live Activity: lock-screen card + Dynamic Island.
//
// «Instrumento diurno» DNA on a system surface: warm paper, one dominant number (the rest timer, in
// the effort hue), color only in the datum, hierarchy by space. Custom fonts aren't registered inside
// the widget extension, so this uses the system rounded face for the numerals (a deliberate,
// widget-safe substitute for the app's numeric type) while every color is a StrandDesign token.

#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import StrandDesign
#if canImport(UIKit)
import UIKit
#endif

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

// MARK: - Live Activity metrics (FER-789)

/// The rest card's own scale — LOCAL to the widget, never `NoopMetrics` (a Live Activity is tighter than
/// an in-app screen). Numerals use the system-rounded face (custom fonts aren't registered in the widget
/// extension); colours are all `InstrumentoTheme` tokens. No hex/font/spacing lands inline in the view.
private enum LiveActivityMetrics {
    static let cardPadding: CGFloat = 16
    static let heroTimer: CGFloat = 52      // the sole dominant numeral
    static let pulse: CGFloat = 17
    static let name: CGFloat = 15           // ≤ hero, so the timer stays the only hero
    static let subtitle: CGFloat = 13
    static let thumb: CGFloat = 44
    static let control: CGFloat = 44        // ≥44pt touch target (HIG)
    static let check: CGFloat = 46
    static let checkGlyph: CGFloat = 22
    static let pillLabel: CGFloat = 13
    static let progressBar: CGFloat = 4
    static let headerGap: CGFloat = 12
    static let heroTopGap: CGFloat = 14
    static let barTopGap: CGFloat = 10
    static let actionsTopGap: CGFloat = 16
    static let pillGap: CGFloat = 8
    static let skipToCheckGap: CGFloat = 8  // isolates «Saltar» from the primary check (no shared edge)
    static let pillRadius: CGFloat = 11
    static let checkRadius: CGFloat = 13
    static let disabledOpacity: CGFloat = 0.4
}

// MARK: - Lock-screen card

private struct RestLockScreenCard: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme

    private typealias M = LiveActivityMetrics

    /// The routine's last pending set is next → the primary action ends the workout, not just the set.
    private var isFinish: Bool { state.phase == .lastSetOfRoutine }
    /// −30 s can't shorten a rest that's already at zero.
    private var restExhausted: Bool { state.restEndsAt <= Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header                                              // exercise + thumbnail + context line
            heroRow.padding(.top, M.heroTopGap)                // the dominant countdown + pulse
            progressBar.padding(.top, M.barTopGap)
            actions.padding(.top, M.actionsTopGap)
        }
        .padding(M.cardPadding)
    }

    // Exercise identity leads (Hevy-style): circular thumbnail (omitted when there's none) + name + context.
    private var header: some View {
        HStack(spacing: M.headerGap) {
            if let image = thumbImage {
                image.resizable().scaledToFill()
                    .frame(width: M.thumb, height: M.thumb)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(state.exerciseName)
                    .font(.system(size: M.name, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text(contextLine)
                    .font(.system(size: M.subtitle))
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilitySortPriority(2)   // read after the timer + pulse
    }

    private var heroRow: some View {
        HStack(alignment: .firstTextBaseline) {
            RestTimerText(state: state, size: M.heroTimer)
                .foregroundStyle(theme.dataStrain)
                .accessibilitySortPriority(4)   // the datum is read first
            Spacer()
            HeartReadout(state: state, theme: theme, size: M.pulse)
                .accessibilitySortPriority(3)
        }
    }

    private var progressBar: some View {
        ProgressView(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true) {
            EmptyView()
        } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(theme.dataStrain)
            .accessibilityHidden(true)
    }

    // One row: [−30 s][+30 s][Saltar] grouped, a gap, then the primary check/flag — read last.
    private var actions: some View {
        HStack(spacing: M.pillGap) {
            PillButton(title: Text("−30 s"), intent: RestRemoveThirtyIntent(), theme: theme)
                .frame(maxWidth: .infinity)
                .disabled(restExhausted)
                .opacity(restExhausted ? M.disabledOpacity : 1)
                .accessibilityLabel(Text("Remove 30 seconds"))
            PillButton(title: Text("+30 s"), intent: RestAddThirtyIntent(), theme: theme)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Add 30 seconds"))
            PillButton(title: Text("Skip"), intent: RestSkipIntent(), theme: theme)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text("Skip rest"))
                .accessibilityHint(Text("Ends the rest without logging the set"))
            Spacer(minLength: M.skipToCheckGap)
            primaryAction
        }
        .accessibilitySortPriority(1)
    }

    // The primary action: a check (complete set) or, on the routine's last set, a flag (finish workout).
    // Ink glyph on `surface` with a `hairlineStrong` border — no fill, no hue, so it never beats the timer.
    @ViewBuilder private var primaryAction: some View {
        if isFinish {
            PrimaryGlyphButton(systemImage: "flag.fill", intent: RestFinishWorkoutIntent(), theme: theme)
                .accessibilityLabel(Text("Finish workout"))
                .accessibilityHint(Text("Logs the last set and ends the workout"))
        } else {
            PrimaryGlyphButton(systemImage: "checkmark", intent: RestCompleteSetIntent(), theme: theme)
                .accessibilityLabel(Text("Complete set"))
                .accessibilityHint(Text("Logs the set and advances"))
        }
    }

    // The context line, per phase: normal «Next: set N of M · detail», exercise handoff «Next up: {ex}»,
    // routine end «last set of the workout». No dangling «·» when there's no weight×reps detail.
    private var contextLine: String {
        switch state.phase {
        case .lastSetOfRoutine?:
            return String(localized: "last set of the workout")
        case .lastSetOfExercise? where state.nextExerciseName != nil:
            return String(localized: "Next up: \(state.nextExerciseName!)")
        default:
            let base = String(localized: "Next: set \(state.setNumber) of \(state.setTotal)")
            return state.returnDetail.isEmpty ? base : "\(base) · \(state.returnDetail)"
        }
    }

    // The staged App Group thumbnail, or nil → the header omits the circle entirely (no placeholder).
    private var thumbImage: Image? {
        #if canImport(UIKit)
        guard let url = RestThumbnailStore.url(for: state.thumbnailName),
              let ui = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: ui)
        #else
        return nil
        #endif
    }
}

// MARK: - Action buttons

/// A quiet rest control — surface fill, hairline border, ink label. Never carries a data hue (§8.4.2).
private struct PillButton<Title: View, I: AppIntent>: View {
    let title: Title
    let intent: I
    let theme: InstrumentoTheme
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            title
                .font(.system(size: M.pillLabel, weight: .semibold))
                .foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: M.pillRadius).strokeBorder(theme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.pillRadius))
        }
        .buttonStyle(.plain)
    }
}

/// The primary action — an ink glyph (no fill, no hue) on `surface` with a heavier `hairlineStrong` border,
/// so it reads as primary by border weight and position, never by colour (FER-789 · §8.4).
private struct PrimaryGlyphButton<I: AppIntent>: View {
    let systemImage: String
    let intent: I
    let theme: InstrumentoTheme
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: M.checkGlyph, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: M.check, height: M.check)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: M.checkRadius).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.checkRadius))
        }
        .buttonStyle(.plain)
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
