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
// Liquid Glass · El Eje on system surfaces (DECISIONS 2026-09-03): lock-screen / banner on
// `LiquidColor.fondoAlto` with tinta/dato Liquid; Dynamic Island on `LiquidOLED` (chrome + text
// tintas — `LiquidOLED.rosa`/`ambar` for AA on black). Custom fonts aren't registered in the
// widget extension, so numerals use the system rounded face (FER-817); island font sizes live in
// `WidgetMetrics.island*`; lock-screen roles that match `LiquidType` reuse those tokens.

#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import CenitDesign
#if canImport(UIKit)
import UIKit
#endif

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // Lock-screen / banner presentation. `context.isStale` (the app went quiet past `staleDate`)
            // drives the muted, action-less «Abre Cénit para continuar» rendering.
            SessionLockScreenCard(state: context.state, stale: context.isStale)
                .activityBackgroundTint(LiquidColor.fondoAlto)
                .activitySystemActionForegroundColor(LiquidColor.tinta900)
        } dynamicIsland: { context in
            SessionDynamicIsland.make(state: context.state)
        }
    }
}

// MARK: - Live Activity metrics

/// The card's own scale now lives in the design system as `WidgetMetrics` (auditoría jul-2026, H5) —
/// FIXED Dynamic-Island / Lock-Screen geometry, exempt from Dynamic Type. The
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
    let stale: Bool

    private typealias M = LiveActivityMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IdentityRow(state: state, stale: stale)
            HeroZone(state: state, stale: stale)
                .frame(height: M.heroSlot, alignment: .bottom)
                .padding(.top, M.heroTopGap)
            BarSlot(state: state, stale: stale)
                .padding(.top, M.barTopGap)
            ActionsRow(state: state, stale: stale)
                .padding(.top, M.actionsTopGap)
                .accessibilitySortPriority(1)   // actions read last
        }
        .padding(M.cardPadding)
    }
}

// MARK: - Zone 1 · identity (always present)

private struct IdentityRow: View {
    let state: RestActivityAttributes.ContentState
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        HStack(spacing: M.headerGap) {
            thumb
            VStack(alignment: .leading, spacing: M.captionGap) {
                Text(state.exerciseName)
                    .font(.system(size: M.name, weight: .semibold))
                    .foregroundStyle(stale ? LiquidColor.tinta500 : LiquidColor.tinta900)
                    .lineLimit(1).minimumScaleFactor(0.8)   // name truncates first; height doesn't move
                Overline(overlineText, stale: stale)
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
                .overlay(Circle().strokeBorder(LiquidColor.vidrioCanto, lineWidth: 1))
                .opacity(stale ? 0.6 : 1)
                .accessibilityHidden(true)
        } else {
            Text(initials)
                .font(.system(size: M.thumbInitials, weight: .semibold))
                .foregroundStyle(stale ? lockInkDim : LiquidColor.tinta700)
                .frame(width: M.thumb, height: M.thumb)
                .background(LiquidColor.papelTarjeta)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(LiquidColor.vidrioCanto, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }

    // Top-right: HR-rest shows «Tope m:ss» (the 5-min cap); every other state shows the pulse chip when
    // there's band data. No band → nothing (never a «--»), per the design's «esconder el chip».
    @ViewBuilder private var trailing: some View {
        if stale {
            EmptyView()
        } else if state.isHRRest {
            VStack(alignment: .trailing, spacing: M.microGap) {
                Overline(String(localized: "Cap"), stale: false)
                RestTimerText(state: state, size: M.pillLabel + 1, weight: .semibold, alignment: .trailing)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        } else {
            PulseChip(state: state, size: M.pillLabel + 1)
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
                .foregroundColor(stale ? LiquidColor.tinta500 : LiquidColor.tinta900)
                + Text(String(localized: "of \(state.setTotal)"))
                    .font(.system(size: M.hero * 0.7, weight: .medium, design: .rounded))
                    .foregroundColor(LiquidColor.tinta500))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel(Text(String(localized: "set \(state.setNumber) of \(state.setTotal)")))
        case .resting where state.isHRMode:
            PulseHero(state: state, stale: stale)
        case .resting:
            RestTimerText(state: state, size: M.hero, weight: .semibold)
                .foregroundStyle(stale ? lockInkDim : LiquidColor.ambar)
                .contentTransition(.numericText())
        case .paused:
            Text(String(localized: "On pause"))
                .font(.system(size: M.hero, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidColor.tinta700)
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
                    .foregroundStyle(stale ? LiquidColor.tinta500 : LiquidColor.tinta700)
                    .monospacedDigit()
            }
        case .resting, .paused:
            ReturnBlock(state: state, stale: stale)
        }
    }
}

/// The HR-rest hero: the live pulse leads (`LiquidColor.rosa`) with the «→ target» it's falling toward.
private struct PulseHero: View {
    let state: RestActivityAttributes.ContentState
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: M.pulseIconGap) {
            Image(systemName: "heart.fill").font(.system(size: M.hero * 0.45))
            // FER-246 — nunca inventar 0 lpm; Watch usa «--» / «sin lectura».
            (state.bpm.map { Text("\($0)") } ?? Text(verbatim: "--"))
                .font(.system(size: M.hero, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let target = state.hrTarget {
                Text("→ \(target)")
                    .font(.system(size: M.name + 1, weight: .medium))
                    .foregroundStyle(LiquidColor.tinta500)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(stale || state.bpm == nil ? lockInkDim : LiquidColor.rosa)
        .accessibilityLabel(pulseLabel)
    }

    private var pulseLabel: Text {
        guard let bpm = state.bpm else { return Text("no reading") }
        if let target = state.hrTarget {
            return Text("\(bpm) beats per minute, recovering toward \(target)")
        }
        return Text("\(bpm) beats per minute")
    }
}

/// The «Al volver / Sigue» block: overline + the set the lifter returns to, in ink semibold.
private struct ReturnBlock: View {
    let state: RestActivityAttributes.ContentState
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        VStack(alignment: .trailing, spacing: M.microGap) {
            Overline(label, stale: stale)
            Text(value)
                .font(.system(size: M.returnValue, weight: .semibold))
                .foregroundStyle(stale ? LiquidColor.tinta500 : LiquidColor.tinta900)
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
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        Group {
            if stale {
                inertBar(lockInkDim)
            } else {
                switch state.resolvedPhase {
                case .active:  segments
                case .resting: drainingBar
                case .paused:  inertBar(lockInkDim)
                }
            }
        }
        .frame(height: M.bar)
        .accessibilityHidden(true)
    }

    // Per-set progress: one segment per planned set, lit up to the current set. `M.bar / 2` is the
    // system's SECOND radius (FER-225): a track that must reach a fully-rounded pill/capsule ALWAYS
    // derives its radius from its own height, never a hard-coded independent constant.
    private var segments: some View {
        HStack(spacing: M.segmentGap) {
            ForEach(0..<max(state.setTotal, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: M.bar / 2)
                    .fill(i < state.setNumber ? LiquidColor.tinta900 : LiquidColor.vidrioCanto)
            }
        }
    }

    // The rest countdown, drained locally by ActivityKit. `ambar` for a clock rest, `rosa` in HR
    // mode (the bar tracks the cap while the pulse leads).
    private var drainingBar: some View {
        ProgressView(timerInterval: state.restStartedAt...state.restEndsAt, countsDown: true) {
            EmptyView()
        } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(state.isHRMode ? LiquidColor.rosa : LiquidColor.ambar)
    }

    // Frozen / dead: a full inert track — no hue, since there's no live datum behind it.
    private func inertBar(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: M.bar / 2).fill(color)
    }
}

// MARK: - Zone 4 · actions

private struct ActionsRow: View {
    let state: RestActivityAttributes.ContentState
    let stale: Bool
    private typealias M = LiveActivityMetrics

    var body: some View {
        if stale {
            // Dead card: no intents. The whole card taps through to open the app (default LA behaviour),
            // so this is a styled label, not a button.
            Text(String(localized: "Open Cénit to continue"))
                .font(LiquidType.cuerpoBanner.weight(.semibold))
                .foregroundStyle(LiquidColor.tinta700)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(LiquidColor.papelTarjeta)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(LiquidColor.vidrioCanto, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        } else {
            switch state.resolvedPhase {
            case .active:  activeActions
            case .resting: restActions
            case .paused:  pausedActions
            }
        }
    }

    // Active set: one primary «✓ Completar serie» that logs the set and enters the rest (lámina
    // «Fuera de la app · Live Activity»: the checkmark is part of the label, not a separate glyph).
    private var activeActions: some View {
        PrimaryButton(title: Text(verbatim: "✓ ") + Text("Complete set"), intent: RestCompleteSetIntent())
            .accessibilityLabel(Text("Complete set"))
            .accessibilityHint(Text("Logs the set and advances"))
    }

    // Rest: −30 / +30 / Saltar. HR rest omits ±30 (they don't apply to a pulse target) → only «Saltar». The
    // routine's last set adds the «Terminar entreno» flag.
    @ViewBuilder private var restActions: some View {
        if state.isHRMode {
            // FER-225/246 — «Saltar descanso» en todas las superficies.
            PillButton(title: Text("Skip rest"), intent: RestSkipIntent())
                .accessibilityLabel(Text("Skip rest"))
        } else {
            HStack(spacing: M.pillGap) {
                PillButton(title: Text("−30 s"), intent: RestRemoveThirtyIntent())
                    .disabled(restExhausted)
                    .opacity(restExhausted ? M.disabledOpacity : 1)
                    .accessibilityLabel(Text("Remove 30 seconds"))
                PillButton(title: Text("+30 s"), intent: RestAddThirtyIntent())
                    .accessibilityLabel(Text("Add 30 seconds"))
                // FER-246 — visible «Saltar descanso» (antes «Skip» por ancho de fila; el canon gana).
                PillButton(title: Text("Skip rest"), intent: RestSkipIntent())
                    .accessibilityLabel(Text("Skip rest"))
                if state.isFinish {
                    GlyphButton(systemImage: "flag.fill", intent: RestFinishWorkoutIntent())
                        .accessibilityLabel(Text("Finish"))
                        .accessibilityHint(Text("Logs the last set and ends the workout"))
                }
            }
        }
    }

    // Paused: one primary «Reanudar».
    private var pausedActions: some View {
        PrimaryButton(title: Text("Resume"), intent: RestResumeIntent())
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
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            title
                .font(.system(size: M.name, weight: .semibold))
                .foregroundStyle(LiquidColor.tinta900)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(LiquidColor.papelTarjeta)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(LiquidColor.tinta10, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

/// A quiet rest control — surface fill, hairline border, ink-secondary label. Never a data hue (§8.4.2).
/// FER-225 — shares `M.controlRadius` with `PrimaryButton`/`GlyphButton` (the retired `pillRadius`
/// (11pt) sat 2pt off `controlRadius` (13pt) for no visual reason, in the same 12pt-padded card).
private struct PillButton<Title: View, I: AppIntent>: View {
    let title: Title
    let intent: I
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            title
                .font(LiquidType.cuerpoBanner.weight(.semibold))
                .foregroundStyle(LiquidColor.tinta700)
                .frame(maxWidth: .infinity, minHeight: M.control)
                .background(LiquidColor.papelTarjeta)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(LiquidColor.vidrioCanto, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

/// A square glyph control (the «Terminar entreno» flag) — ink glyph, heavier border, no fill.
private struct GlyphButton<I: AppIntent>: View {
    let systemImage: String
    let intent: I
    private typealias M = LiveActivityMetrics

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: M.glyph, weight: .semibold))
                .foregroundStyle(LiquidColor.tinta900)
                .frame(width: M.control, height: M.control)
                .background(LiquidColor.papelTarjeta)
                .overlay(RoundedRectangle(cornerRadius: M.controlRadius).strokeBorder(LiquidColor.tinta10, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: M.controlRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// Tint intentionally below the AA text floor for no-data / stale chrome on the lock-screen card.
private var lockInkDim: Color { LiquidColor.tinta500 }   // tinta terciaria: el chrome sin dato usa el mismo token que en la app (OKLab.mix es interno al paquete)

/// An uppercase tracking overline — «Descanso · 8/18 series», «Al volver», «Tope».
private struct Overline: View {
    let text: String
    let stale: Bool
    private typealias M = LiveActivityMetrics

    init(_ text: String, stale: Bool) {
        self.text = text; self.stale = stale
    }

    var body: some View {
        Text(text.uppercased())
            .font(LiquidType.unidad.weight(.semibold))
            .tracking(M.overlineTracking)
            .foregroundStyle(stale ? lockInkDim : LiquidColor.tinta500)
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
            .frame(maxWidth: size * WidgetMetrics.timerWidthMultiplier, alignment: alignment)
    }
}

/// The identity-row pulse chip: «♥ 128». Renders NOTHING without band data — no dash, no zero.
private struct PulseChip: View {
    let state: RestActivityAttributes.ContentState
    var size: CGFloat
    var body: some View {
        if let bpm = state.bpm {
            HStack(spacing: WidgetMetrics.captionGap) {
                Image(systemName: "heart.fill").font(.system(size: size * 0.8))
                Text("\(bpm)").font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(LiquidColor.rosa)
            .accessibilityLabel(Text("\(bpm) beats per minute"))
        }
    }
}

// MARK: - Dynamic Island

private enum SessionDynamicIsland {
    /// Every region paints on ActivityKit's true black — chrome and text tintas from `LiquidOLED`
    /// (QA FER-311 r2: `LiquidColor.rosa` sobre negro queda bajo AA en texto chico).
    static func make(state s: RestActivityAttributes.ContentState) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) { expandedLeading(s) }
            DynamicIslandExpandedRegion(.trailing) { expandedTrailing(s) }
            DynamicIslandExpandedRegion(.bottom) { expandedBottom(s) }
        } compactLeading: {
            compactLeading(s)
        } compactTrailing: {
            compactTrailing(s)
        } minimal: {
            minimal(s)
        }
        .widgetURL(URL(string: "noopdev://session"))
        .keylineTint(s.isHRRest ? LiquidOLED.rosa : LiquidOLED.ambar)
    }

    // Contraste sobre negro (WCAG): tintas de texto en isla = `LiquidOLED.*`
    // (`LiquidOLED.rosa` #BD546C ≈ 4.65:1; `LiquidOLED.ambar` sobre negro).

    // Compact leading: the phase's dominant glyph — set count / countdown / pulse.
    @ViewBuilder private static func compactLeading(_ s: RestActivityAttributes.ContentState) -> some View {
        switch s.resolvedPhase {
        case .active:
            Text("\(s.setNumber)/\(s.setTotal)")
                .font(.system(size: WidgetMetrics.islandCompact, weight: .semibold)).monospacedDigit()
                .foregroundStyle(LiquidOLED.tinta)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: WidgetMetrics.islandCompactGlyph))
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        case .resting where s.isHRMode:
            HStack(spacing: WidgetMetrics.microGap) {
                Image(systemName: "heart.fill").font(.system(size: WidgetMetrics.islandCompactHeart))
                (s.bpm.map { Text("\($0)") } ?? Text(verbatim: "--"))
                    .font(.system(size: WidgetMetrics.islandCompact, weight: .semibold)).monospacedDigit()
            }.foregroundStyle(s.bpm == nil ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa)
        case .resting:
            RestTimerText(state: s, size: WidgetMetrics.islandCompactTimer).foregroundStyle(LiquidOLED.ambar)
        }
    }

    // Compact trailing: pulse chip (or the «→ target» in HR mode); nothing without band data.
    @ViewBuilder private static func compactTrailing(_ s: RestActivityAttributes.ContentState) -> some View {
        if s.isHRRest, let target = s.hrTarget {
            Text("→ \(target)").font(.system(size: WidgetMetrics.islandCompact, weight: .semibold)).monospacedDigit()
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        } else if let bpm = s.bpm {
            HStack(spacing: WidgetMetrics.microGap) {
                Image(systemName: "heart.fill").font(.system(size: WidgetMetrics.islandCompactHeart))
                Text("\(bpm)").font(.system(size: WidgetMetrics.islandCompact, weight: .semibold)).monospacedDigit()
            }.foregroundStyle(LiquidOLED.rosa)
        }
    }

    @ViewBuilder private static func minimal(_ s: RestActivityAttributes.ContentState) -> some View {
        switch s.resolvedPhase {
        case .active:
            Text("\(s.setNumber)/\(s.setTotal)").font(.system(size: WidgetMetrics.islandMinimal, weight: .semibold)).monospacedDigit()
                .foregroundStyle(LiquidOLED.tinta)
        case .paused:
            Image(systemName: "pause.fill")
                .font(.system(size: WidgetMetrics.islandMinimalGlyph))
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        case .resting where s.isHRMode:
            (s.bpm.map { Text("\($0)") } ?? Text(verbatim: "--"))
                .font(.system(size: WidgetMetrics.islandMinimal, weight: .semibold)).monospacedDigit()
                .foregroundStyle(s.bpm == nil ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa)
        case .resting:
            RestTimerText(state: s, size: WidgetMetrics.islandMinimal).foregroundStyle(LiquidOLED.ambar)
        }
    }

    // Expanded leading: the hero datum.
    @ViewBuilder private static func expandedLeading(_ s: RestActivityAttributes.ContentState) -> some View {
        switch s.resolvedPhase {
        case .active:
            (Text("\(s.setNumber)").font(.system(size: WidgetMetrics.islandExpandedHero, weight: .semibold, design: .rounded))
                .foregroundColor(LiquidOLED.tinta)
                + Text(" / \(s.setTotal)").font(.system(size: WidgetMetrics.islandExpandedSecondary, weight: .medium, design: .rounded))
                    .foregroundColor(LiquidOLED.tintaTerciaria))
                .monospacedDigit()
        case .paused:
            Text("On pause").font(.system(size: WidgetMetrics.islandExpandedPause, weight: .semibold, design: .rounded))
                .foregroundStyle(LiquidOLED.tintaSecundaria)
        case .resting where s.isHRMode:
            HStack(spacing: LiquidSpace.s100) {
                Image(systemName: "heart.fill").font(.system(size: WidgetMetrics.islandExpandedHeart))
                (s.bpm.map { Text("\($0)") } ?? Text(verbatim: "--"))
                    .font(.system(size: WidgetMetrics.islandExpandedHero, weight: .semibold, design: .rounded)).monospacedDigit()
                if let target = s.hrTarget {
                    Text("→ \(target)")
                        .font(.system(size: WidgetMetrics.islandExpandedTarget, weight: .medium))
                        .foregroundStyle(LiquidOLED.tintaTerciaria).monospacedDigit()
                }
            }.foregroundStyle(s.bpm == nil ? LiquidOLED.tintaTerciaria : LiquidOLED.rosa)
        case .resting:
            HStack(spacing: WidgetMetrics.pulseIconGap) {
                Image(systemName: "timer").font(.system(size: WidgetMetrics.islandExpandedTimerGlyph, weight: .semibold))
                RestTimerText(state: s, size: WidgetMetrics.islandExpandedHero)
            }.foregroundStyle(LiquidOLED.ambar)
        }
    }

    // Expanded trailing: the pulse (rest/active) or the «Tope» cap (HR).
    @ViewBuilder private static func expandedTrailing(_ s: RestActivityAttributes.ContentState) -> some View {
        if s.isHRRest {
            VStack(alignment: .trailing, spacing: WidgetMetrics.microGap) {
                Text(String(localized: "Cap").uppercased())
                    .font(.system(size: WidgetMetrics.islandCapLabel, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(LiquidOLED.tintaTerciaria)
                RestTimerText(state: s, size: WidgetMetrics.islandCapTimer, alignment: .trailing)
                    .foregroundStyle(LiquidOLED.tintaSecundaria)
            }
        } else if let bpm = s.bpm {
            HStack(spacing: LiquidSpace.s100) {
                Image(systemName: "heart.fill").font(.system(size: WidgetMetrics.islandExpandedPulseGlyph))
                Text("\(bpm)").font(.system(size: WidgetMetrics.islandExpandedPulse, weight: .semibold, design: .rounded)).monospacedDigit()
            }.foregroundStyle(LiquidOLED.rosa)
        }
    }

    // Expanded bottom: the «¿qué sigue?» caption for rest/pause; the exercise name in the active set.
    @ViewBuilder private static func expandedBottom(_ s: RestActivityAttributes.ContentState) -> some View {
        Text(bottomCaption(s))
            .font(.system(size: WidgetMetrics.islandBottomCaption, weight: .medium))
            .foregroundStyle(LiquidOLED.tintaSecundaria)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, WidgetMetrics.captionGap)   // air above/below so descenders don't kiss the island's bottom edge
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
