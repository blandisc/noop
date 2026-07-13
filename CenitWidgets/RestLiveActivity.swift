// FER-721 · FER-806 — the strength session Live Activity: lock-screen card + Dynamic Island.
//
// FER-721 showed this only during the rest between sets. FER-806 makes it live the WHOLE session — it is
// born when the session starts and persists through active sets, rests, and pauses until the workout ends.
// The v2 design is a FIXED SKELETON of three zones (identity / hero / actions) that never re-lays-out
// between states, so the card doesn't «jump» as the lifter alternates set↔rest for 40+ minutes:
//   • identity  — thumbnail + exercise name + overline «{context} · N/M series» + (optional) pulse chip
//   • hero      — one dominant 34pt numeral in a fixed-height slot: «Serie X de Y» / countdown / pulse /
//                 «En pausa», with a right-hand «Al volver / Sigue» block during rest & pause
//   • bar slot  — per-set segments (active) ↔ draining bar (rest) ↔ inert bar (pause / stale)
//   • actions   — «Completar» (active) ↔ −30/+30/Saltar (rest) ↔ «Reanudar» (pause) ↔ open-app (stale)
//
// «Instrumento diurno» DNA on a system surface: warm paper, ONE dominant number, color only in the live
// datum (`dataStrain` countdown, `dataHeart` pulse), hierarchy by space, primary action by border + not
// by fill. Custom fonts aren't registered in the widget extension, so numerals use the system rounded face
// (FER-817's firm decision); every color is an `InstrumentoTheme` token — no hex/font/spacing inline.

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
            // Lock-screen / banner presentation. `context.isStale` (the app went quiet past `staleDate`)
            // drives the muted, action-less «Abre Cénit para continuar» rendering.
            SessionLockScreenCard(state: context.state, theme: theme, stale: context.isStale)
                .activityBackgroundTint(theme.paper)
                .activitySystemActionForegroundColor(theme.ink)
        } dynamicIsland: { context in
            SessionDynamicIsland.make(state: context.state, theme: theme)
        }
    }
}

// MARK: - Live Activity metrics

/// The card's own scale now lives in the design system as `WidgetMetrics` (auditoría jul-2026, H5) —
/// FIXED Dynamic-Island / Lock-Screen geometry, exempt from Dynamic Type, never `NoopMetrics`. The
/// height discipline (≤160 pt) is documented at the token. This alias keeps the tight `M.*` call sites.
private typealias LiveActivityMetrics = WidgetMetrics

// MARK: - Phase model (view-side)

/// The session phase to paint, with the pre-FER-806 fallback folded in: an Activity started under the old
/// (rest-only) contract decodes `sessionPhase == nil` → we render the rest layout, exactly as FER-721 did.
private extension RestActivityAttributes.ContentState {
    var resolvedPhase: SessionPhase { sessionPhase ?? .resting }
    /// HR-guided rest — the pulse is the hero and the top-right carries «Tope m:ss» instead of the chip.
    var isHRRest: Bool { resolvedPhase == .resting && isHRMode }
    /// The routine's last pending set is next → the rest card offers the «Terminar entreno» flag.
    var isFinish: Bool { phase == .lastSetOfRoutine }
    /// Global session progress «N/M series», or nil (pre-FER-806) → the overline drops the count.
    var progressText: String? {
        guard let done = setsDone, let total = setsTotal else { return nil }
        return String(localized: "\(done)/\(total) series")
    }
}

// MARK: - Lock-screen card

private struct SessionLockScreenCard: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool

    private typealias M = LiveActivityMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IdentityRow(state: state, theme: theme, stale: stale)
            HeroZone(state: state, theme: theme, stale: stale)
                .frame(height: M.heroSlot, alignment: .bottom)
                .padding(.top, M.heroTopGap)
            BarSlot(state: state, theme: theme, stale: stale)
                .padding(.top, M.barTopGap)
            ActionsRow(state: state, theme: theme, stale: stale)
                .padding(.top, M.actionsTopGap)
                .accessibilitySortPriority(1)   // actions read last
        }
        .padding(M.cardPadding)
    }
}

// MARK: - Zone 1 · identity (always present)

private struct IdentityRow: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        HStack(spacing: M.headerGap) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                Text(state.exerciseName)
                    .font(.system(size: M.name, weight: .semibold))
                    .foregroundStyle(stale ? theme.inkTertiary : theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)   // name truncates first; height doesn't move
                Overline(overlineText, theme: theme, stale: stale)
            }
            Spacer(minLength: M.headerGap)
            trailing
        }
        .accessibilitySortPriority(2)   // read after the hero + pulse
    }

    // The exercise identity chip: the staged thumbnail, or the exercise's initials on a paper tile.
    @ViewBuilder private var thumb: some View {
        if let image = thumbImage {
            image.resizable().scaledToFill()
                .frame(width: M.thumb, height: M.thumb)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                .opacity(stale ? 0.6 : 1)
                .accessibilityHidden(true)
        } else {
            Text(initials)
                .font(.system(size: 13, weight: .semibold))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(stale ? theme.inkDim : theme.inkSecondary)
                .frame(width: M.thumb, height: M.thumb)
                .background(theme.surface)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.hairline, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    // Top-right: HR-rest shows «Tope m:ss» (the 5-min cap); every other state shows the pulse chip when
    // there's band data. No band → nothing (never a «--»), per the design's «esconder el chip».
    @ViewBuilder private var trailing: some View {
        if stale {
            EmptyView()
        } else if state.isHRRest {
            VStack(alignment: .trailing, spacing: 2) {
                Overline(String(localized: "Cap"), theme: theme, stale: false)
                RestTimerText(state: state, size: M.pillLabel + 1, weight: .semibold, alignment: .trailing)
                    .foregroundStyle(theme.inkSecondary)
            }
        } else {
            PulseChip(state: state, theme: theme, size: M.pillLabel + 1)
        }
    }

    private var overlineText: String {
        let context: String
        switch state.resolvedPhase {
        case .active:  context = state.routineName
        case .resting: context = state.isHRMode ? String(localized: "By HR") : String(localized: "Rest")
        case .paused:  context = String(localized: "Paused")
        }
        guard let progress = state.progressText else { return context }
        return "\(context) · \(progress)"
    }

    private var initials: String {
        let parts = state.exerciseName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

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

// MARK: - Zone 2 · hero (fixed-height slot)

private struct HeroZone: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        HStack(alignment: .bottom) {
            heroLeading.accessibilitySortPriority(4)   // the datum reads first
            Spacer(minLength: M.headerGap)
            heroTrailing.accessibilitySortPriority(3)
        }
    }

    // The dominant datum, per phase.
    @ViewBuilder private var heroLeading: some View {
        switch state.resolvedPhase {
        case .active:
            // «Serie X de Y» — the «de Y» in a quieter tint/weight so the number leads.
            (Text("\(state.setNumber) ").font(.system(size: M.hero, weight: .semibold, design: .rounded))
                .foregroundColor(stale ? theme.inkTertiary : theme.ink)
                + Text(String(localized: "of \(state.setTotal)"))
                    .font(.system(size: M.hero * 0.7, weight: .medium, design: .rounded))
                    .foregroundColor(theme.inkTertiary))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(Text("set \(state.setNumber) of \(state.setTotal)"))
        case .resting where state.isHRMode:
            PulseHero(state: state, theme: theme, stale: stale)
        case .resting:
            RestTimerText(state: state, size: M.hero, weight: .semibold)
                .foregroundStyle(stale ? theme.inkDim : theme.dataStrain)
                .contentTransition(.numericText())
        case .paused:
            Text(String(localized: "On pause"))
                .font(.system(size: M.hero, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // The right-hand answer to «¿qué sigue?» — present in rest & pause, absent in the active set (where the
    // hero-right is the plain «peso × reps» load).
    @ViewBuilder private var heroTrailing: some View {
        switch state.resolvedPhase {
        case .active:
            if !state.returnDetail.isEmpty {
                Text(state.returnDetail)
                    .font(.system(size: M.name, weight: .medium))
                    .foregroundStyle(stale ? theme.inkTertiary : theme.inkSecondary)
                    .monospacedDigit()
            }
        case .resting, .paused:
            ReturnBlock(state: state, theme: theme, stale: stale)
        }
    }
}

/// The HR-rest hero: the live pulse leads (`dataHeart`) with the «→ target» it's falling toward.
private struct PulseHero: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "heart.fill").font(.system(size: M.hero * 0.45))
            Text("\(state.bpm ?? 0)")
                .font(.system(size: M.hero, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let target = state.hrTarget {
                Text("→ \(target)")
                    .font(.system(size: M.name + 1, weight: .medium))
                    .foregroundStyle(theme.inkTertiary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(stale ? theme.inkDim : theme.dataHeart)
        .accessibilityLabel(pulseLabel)
    }

    private var pulseLabel: Text {
        if let target = state.hrTarget {
            return Text("\(state.bpm ?? 0) beats per minute, recovering toward \(target)")
        }
        return Text("\(state.bpm ?? 0) beats per minute")
    }
}

/// The «Al volver / Sigue» block: overline + the set the lifter returns to, in ink semibold.
private struct ReturnBlock: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Overline(label, theme: theme, stale: stale)
            Text(value)
                .font(.system(size: M.returnValue, weight: .semibold))
                .foregroundStyle(stale ? theme.inkTertiary : theme.ink)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    // Mirrors FER-789's context logic, restyled: routine-end «Última serie»; exercise handoff «Sigue: next»;
    // otherwise «Al volver: Serie N · detail».
    private var label: String {
        switch state.phase {
        case .lastSetOfExercise? where state.nextExerciseName != nil:
            return String(localized: "Next")
        default:
            return String(localized: "Back to")
        }
    }

    private var value: String {
        switch state.phase {
        case .lastSetOfRoutine?:
            return String(localized: "Last set")
        case .lastSetOfExercise? where state.nextExerciseName != nil:
            return state.nextExerciseName!
        default:
            let base = String(localized: "Set \(state.setNumber)")
            return state.returnDetail.isEmpty ? base : "\(base) · \(state.returnDetail)"
        }
    }
}

// MARK: - Zone 3 · bar slot

private struct BarSlot: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        Group {
            if stale {
                inertBar(theme.inkDim)
            } else {
                switch state.resolvedPhase {
                case .active:  segments
                case .resting: drainingBar
                case .paused:  inertBar(theme.inkDim)
                }
            }
        }
        .frame(height: M.bar)
        .accessibilityHidden(true)
    }

    // Per-set progress: one segment per planned set, lit up to the current set.
    private var segments: some View {
        HStack(spacing: M.segmentGap) {
            ForEach(0..<max(state.setTotal, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: M.bar / 2)
                    .fill(i < state.setNumber ? theme.ink : theme.hairline)
            }
        }
    }

    // The rest countdown, drained locally by ActivityKit. `dataStrain` for a clock rest, `dataHeart` in HR
    // mode (the bar tracks the cap while the pulse leads).
    private var drainingBar: some View {
        ProgressView(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true) {
            EmptyView()
        } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(state.isHRMode ? theme.dataHeart : theme.dataStrain)
    }

    // Frozen / dead: a full inert track — no hue, since there's no live datum behind it.
    private func inertBar(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: M.bar / 2).fill(color)
    }
}

// MARK: - Zone 4 · actions

private struct ActionsRow: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        if stale {
            // Dead card: no intents. The whole card taps through to open the app (default LA behaviour),
            // so this is a styled label, not a button.
            Text(String(localized: "Open Cénit to continue"))
                .font(.system(size: M.pillLabel, weight: .semibold))
                .foregroundStyle(theme.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(theme.hairline, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        } else {
            switch state.resolvedPhase {
            case .active:  activeActions
            case .resting: restActions
            case .paused:  pausedActions
            }
        }
    }

    // Active set: one primary «Completar» that logs the set and enters the rest.
    private var activeActions: some View {
        PrimaryButton(title: Text("Complete"), intent: RestCompleteSetIntent(), theme: theme)
            .accessibilityLabel(Text("Complete set"))
            .accessibilityHint(Text("Logs the set and advances"))
    }

    // Rest: −30 / +30 / Saltar. HR rest omits ±30 (they don't apply to a pulse target) → only «Saltar». The
    // routine's last set adds the «Terminar entreno» flag.
    @ViewBuilder private var restActions: some View {
        if state.isHRMode {
            PillButton(title: Text("Skip"), intent: RestSkipIntent(), theme: theme)
                .accessibilityLabel(Text("Skip rest"))
        } else {
            HStack(spacing: M.pillGap) {
                PillButton(title: Text("−30 s"), intent: RestRemoveThirtyIntent(), theme: theme)
                    .disabled(restExhausted)
                    .opacity(restExhausted ? M.disabledOpacity : 1)
                    .accessibilityLabel(Text("Remove 30 seconds"))
                PillButton(title: Text("+30 s"), intent: RestAddThirtyIntent(), theme: theme)
                    .accessibilityLabel(Text("Add 30 seconds"))
                PillButton(title: Text("Skip"), intent: RestSkipIntent(), theme: theme)
                    .accessibilityLabel(Text("Skip rest"))
                if state.isFinish {
                    GlyphButton(systemImage: "flag.fill", intent: RestFinishWorkoutIntent(), theme: theme)
                        .accessibilityLabel(Text("Finish workout"))
                        .accessibilityHint(Text("Logs the last set and ends the workout"))
                }
            }
        }
    }

    // Paused: one primary «Reanudar».
    private var pausedActions: some View {
        PrimaryButton(title: Text("Resume"), intent: RestResumeIntent(), theme: theme)
            .accessibilityLabel(Text("Resume workout"))
    }

    private var restExhausted: Bool { state.restEndsAt <= Date() }
}

// MARK: - Reusable controls

/// A full-width primary control — quiet surface, hairline-strong border, ink label. No fill hue, so it
/// never out-shouts the hero (§8.4).
private struct PrimaryButton<Title: View, I: AppIntent>: View {
    let title: Title
    let intent: I
    let theme: InstrumentoTheme
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            title
                .font(.system(size: M.name, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

/// A quiet rest control — surface fill, hairline border, ink-secondary label. Never a data hue (§8.4.2).
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

/// A square glyph control (the «Terminar entreno» flag) — ink glyph, heavier border, no fill.
private struct GlyphButton<I: AppIntent>: View {
    let systemImage: String
    let intent: I
    let theme: InstrumentoTheme
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: M.glyph, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: M.control, height: M.control)
                .background(theme.surface)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// An uppercase tracking overline — «Descanso · 8/18 series», «Al volver», «Tope».
private struct Overline: View {
    let text: String
    let theme: InstrumentoTheme
    let stale: Bool
    private typealias M = LiveActivityMetrics

    init(_ text: String, theme: InstrumentoTheme, stale: Bool) {
        self.text = text; self.theme = theme; self.stale = stale
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: M.overline, weight: .semibold))
            .tracking(M.overlineTracking)
            .foregroundStyle(stale ? theme.inkDim : theme.inkTertiary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The rest countdown — ticks locally from `restEndsAt`, so no push is needed just to advance the clock.
/// `Text(timerInterval:)` is GREEDY: it claims every point of width it's offered, which stretched the
/// compact island across the whole cutout. The frame caps it at ~«10:00» wide (3× the point size covers
/// five monospaced digits/colon at the rounded face) so the pill hugs its content again.
private struct RestTimerText: View {
    let state: RestActivityAttributes.ContentState
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var alignment: Alignment = .leading
    var body: some View {
        Text(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: size * 3, alignment: alignment)
    }
}

/// The identity-row pulse chip: «♥ 128». Renders NOTHING without band data — no dash, no zero.
private struct PulseChip: View {
    let state: RestActivityAttributes.ContentState
    let theme: InstrumentoTheme
    var size: CGFloat
    var body: some View {
        if let bpm = state.bpm {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").font(.system(size: size * 0.8))
                Text("\(bpm)").font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(theme.dataHeart)
            .accessibilityLabel(Text("\(bpm) beats per minute"))
        }
    }
}

// MARK: - Dynamic Island

private enum SessionDynamicIsland {
    static func make(state s: RestActivityAttributes.ContentState, theme: InstrumentoTheme) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) { expandedLeading(s, theme) }
            DynamicIslandExpandedRegion(.trailing) { expandedTrailing(s, theme) }
            DynamicIslandExpandedRegion(.bottom) { expandedBottom(s, theme) }
        } compactLeading: {
            compactLeading(s, theme)
        } compactTrailing: {
            compactTrailing(s, theme)
        } minimal: {
            minimal(s, theme)
        }
        .widgetURL(URL(string: "noopdev://session"))
        .keylineTint(s.isHRRest ? theme.dataHeart : theme.dataStrain)
    }

    // Compact leading: the phase's dominant glyph — set count / countdown / pulse.
    @ViewBuilder private static func compactLeading(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        switch s.resolvedPhase {
        case .active:
            Text("\(s.setNumber)/\(s.setTotal)")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(theme.ink)
        case .paused:
            Image(systemName: "pause.fill").font(.system(size: 12)).foregroundStyle(theme.inkSecondary)  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
        case .resting where s.isHRMode:
            HStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.system(size: 10))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                Text("\(s.bpm ?? 0)").font(.system(size: 13, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
            }.foregroundStyle(theme.dataHeart)
        case .resting:
            RestTimerText(state: s, size: 15).foregroundStyle(theme.dataStrain)
        }
    }

    // Compact trailing: pulse chip (or the «→ target» in HR mode); nothing without band data.
    @ViewBuilder private static func compactTrailing(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        if s.isHRRest, let target = s.hrTarget {
            Text("→ \(target)").font(.system(size: 13, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(theme.inkSecondary)
        } else if let bpm = s.bpm {
            HStack(spacing: 2) {
                Image(systemName: "heart.fill").font(.system(size: 10))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                Text("\(bpm)").font(.system(size: 13, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
            }.foregroundStyle(theme.dataHeart)
        }
    }

    @ViewBuilder private static func minimal(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        switch s.resolvedPhase {
        case .active:
            Text("\(s.setNumber)/\(s.setTotal)").font(.system(size: 12, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(theme.ink)
        case .paused:
            Image(systemName: "pause.fill").font(.system(size: 11)).foregroundStyle(theme.inkSecondary)  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
        case .resting where s.isHRMode:
            Text("\(s.bpm ?? 0)").font(.system(size: 12, weight: .semibold)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(theme.dataHeart)
        case .resting:
            RestTimerText(state: s, size: 12).foregroundStyle(theme.dataStrain)
        }
    }

    // Expanded leading: the hero datum.
    @ViewBuilder private static func expandedLeading(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        switch s.resolvedPhase {
        case .active:
            (Text("\(s.setNumber)").font(.system(size: 26, weight: .semibold, design: .rounded))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundColor(theme.ink)
                + Text(" / \(s.setTotal)").font(.system(size: 16, weight: .medium, design: .rounded))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                    .foregroundColor(theme.inkTertiary))
                .monospacedDigit()
        case .paused:
            Text("On pause").font(.system(size: 20, weight: .semibold, design: .rounded))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                .foregroundStyle(theme.inkSecondary)
        case .resting where s.isHRMode:
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 14))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                Text("\(s.bpm ?? 0)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                if let target = s.hrTarget {
                    Text("→ \(target)").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.inkTertiary).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                }
            }.foregroundStyle(theme.dataHeart)
        case .resting:
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 13, weight: .semibold))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                RestTimerText(state: s, size: 26)
            }.foregroundStyle(theme.dataStrain)
        }
    }

    // Expanded trailing: the pulse (rest/active) or the «Tope» cap (HR).
    @ViewBuilder private static func expandedTrailing(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        if s.isHRRest {
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(localized: "Cap").uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(theme.inkTertiary)  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                RestTimerText(state: s, size: 14, alignment: .trailing).foregroundStyle(theme.inkSecondary)
            }
        } else if let bpm = s.bpm {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 13))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
                Text("\(bpm)").font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
            }.foregroundStyle(theme.dataHeart)
        }
    }

    // Expanded bottom: the «¿qué sigue?» caption for rest/pause; the exercise name in the active set.
    @ViewBuilder private static func expandedBottom(_ s: RestActivityAttributes.ContentState, _ theme: InstrumentoTheme) -> some View {
        Text(bottomCaption(s))
            .font(.system(size: 12, weight: .medium))  // token-exempt: Live Activity geometry (Dynamic Island / Lock Screen, fixed)
            .foregroundStyle(theme.inkSecondary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)   // air above/below so descenders don't kiss the island's bottom edge
    }

    private static func bottomCaption(_ s: RestActivityAttributes.ContentState) -> String {
        switch s.resolvedPhase {
        case .active:
            return s.returnDetail.isEmpty ? s.exerciseName : "\(s.exerciseName) · \(s.returnDetail)"
        case .paused:
            return String(localized: "back to set \(s.setNumber) · \(s.exerciseName)")
        case .resting:
            let base = String(localized: "back to set \(s.setNumber) · \(s.exerciseName)")
            return s.returnDetail.isEmpty ? base : "\(base) · \(s.returnDetail)"
        }
    }
}
#endif
