import SwiftUI
import Foundation
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Haptic-paced breathing trainer — a timed breath pacer with a felt cue.
///
/// Pick a pace, hit start, close your eyes, and follow the breath orb: a timer drives
/// inhale/exhale, one cue on the inhale, two on the exhale. (Live HRV/RMSSD biofeedback
/// was retired with the band — FER-1003 — since solo breathing has no live R-R source;
/// the pace readout, driven by the pacer itself, is what remains.)
///
/// «Instrumento diurno» (FER-342): warm paper, ink labels, color only in the measured
/// datum. The breath orb keeps the screen's signature motion in a calm physiological
/// glow, not saturated chrome.
struct BreathingView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Pace presets

    private enum Pace: Hashable, CaseIterable {
        case relax          // 4s inhale / 6s exhale
        case coherence      // 5.5s / 5.5s
        case box            // 4s / 4s

        var label: String {
            switch self {
            case .relax:     return String(localized: "Relax 4-6")
            case .coherence: return String(localized: "Coherence 5.5")
            case .box:       return String(localized: "Box 4-4")
            }
        }

        var inhale: Double {
            switch self {
            case .relax:     return 4.0
            case .coherence: return 5.5
            case .box:       return 4.0
            }
        }

        var exhale: Double {
            switch self {
            case .relax:     return 6.0
            case .coherence: return 5.5
            case .box:       return 4.0
            }
        }

        var cycle: Double { inhale + exhale }

        /// Breaths per minute for this pace.
        var bpm: Double { 60.0 / cycle }

        var tagline: String {
            switch self {
            case .relax:     return String(localized: "Long exhale · winds down")
            case .coherence: return String(localized: "Even breathing · ~5.5/min")
            case .box:       return String(localized: "Square · steady focus")
            }
        }
    }

    private enum Phase {
        case inhale
        case exhale
    }

    // MARK: State

    @State private var pace: Pace = .coherence
    @State private var running = false

    @State private var phase: Phase = .inhale
    /// Wall-clock start of the current inhale/exhale; drives orb scale via TimelineView.
    @State private var phaseStart: Date = .distantPast
    @State private var phaseDeadline: Date = .distantFuture

    @State private var sessionSeconds: Int = 0
    @State private var breathCount: Int = 0

    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// Phase driver (fast, smooth) and a once-per-second session tick.
    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                statusRow
                paceSelector
                orbCard
                controlRow
                readoutRow
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // Phase driver: advance the orb toward its target and flip phases.
        .onReceive(phaseTimer) { now in
            guard running else { return }
            advance(now: now)
        }
        // Session clock — only ticks while running.
        .onReceive(secondTimer) { _ in
            guard running else { return }
            sessionSeconds += 1
        }
        // Changing pace mid-session re-arms the current phase cleanly.
        .onChange(of: pace) {
            if running { armPhase(.inhale, from: Date(), buzz: false) }
        }
        .onDisappear { stop() }
        .enableInjection()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Breathe")
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(theme.ink)
            Text("Haptic-paced breathing · watch your HRV respond")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 10) {
            EntrenarStatusPill(running ? "Session live" : "Ready",
                               dotColor: running ? theme.dataRecovery : nil)

            Spacer()

            HStack(spacing: 6) {
                Text(timeString(sessionSeconds))
                    .font(InstrumentoType.groteskNumber(15))
                    .foregroundStyle(theme.ink)
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("\(breathCount) breaths")
                    .font(InstrumentoType.groteskNumber(12, weight: .medium))
                    .foregroundStyle(theme.inkSecondary)
            }
        }
    }

    // MARK: - Pace selector

    private var paceSelector: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BREATHE").groteskOverline().foregroundStyle(theme.inkTertiary)
                Text("Choose a pace")
                    .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                    .foregroundStyle(theme.ink)
            }

            VStack(spacing: CenitMetrics.gap) {
                ForEach(Pace.allCases, id: \.self) { option in
                    paceRow(option)
                }
            }
        }
    }

    private func paceRow(_ option: Pace) -> some View {
        let selected = pace == option
        return Button {
            pace = option
        } label: {
            HStack(alignment: .center, spacing: CenitMetrics.gap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(InstrumentoType.grotesk(16, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text(option.tagline)
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Text(String(format: "%.1f br/min", option.bpm))
                    .font(InstrumentoType.groteskNumber(12, weight: .medium))
                    .foregroundStyle(selected ? theme.dataHrv : theme.inkSecondary)
            }
            .padding(CenitMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? theme.tint(theme.dataHrv)
                    : theme.surface,
                in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(selected ? theme.softStroke(theme.dataHrv) : theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - The orb

    private var orbCard: some View {
        EntrenarToolCard(padding: 24) {
            VStack(spacing: 18) {
                HStack {
                    Text(pace.label).groteskOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(String(format: "%.1f br/min", pace.bpm))
                        .font(InstrumentoType.groteskNumber(12, weight: .medium))
                        .foregroundStyle(theme.inkSecondary)
                }

                breathingOrb
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)

                Text(running ? phaseWord : pace.tagline)
                    .font(StrandFont.subhead)
                    .foregroundStyle(running ? theme.ink : theme.inkSecondary)
                    .strandAnimation(.easeInOut(duration: 0.2), value: phaseWord)
                    .strandAnimation(.easeInOut(duration: 0.2), value: running)
            }
        }
    }

    private var phaseWord: String {
        switch phase {
        case .inhale: return String(localized: "Breathe in…")
        case .exhale: return String(localized: "Breathe out…")
        }
    }

    /// Orb only — progress is scoped here via TimelineView so the rest of the screen
    /// does not re-evaluate each animation frame (FER-876). Paused whenever the breath
    /// isn't running OR Reduce Motion is on — frozen at rest, never animated (mismo
    /// patrón que `OrbeVivo`). Hidden from VoiceOver: `phaseWord` already says
    /// «Breathe in…/out…», so the orb is redundant motion, not information.
    private var breathingOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running || reduceMotion)) { timeline in
            let progress = (running && !reduceMotion) ? easedProgress(at: timeline.date) : 0
            orbGeometry(progress: progress)
        }
        .accessibilityHidden(true)
    }

    /// easeInOut cubic progress for the current phase at `date`.
    /// Inhale: 0→1; exhale: 1→0. Same visual feel as SwiftUI's easeInOut.
    private func easedProgress(at date: Date) -> CGFloat {
        guard running else { return 0 }
        let duration = (phase == .inhale) ? pace.inhale : pace.exhale
        let elapsed = date.timeIntervalSince(phaseStart)
        let t = max(0, min(1, elapsed / duration))
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        return phase == .inhale ? CGFloat(eased) : CGFloat(1 - eased)
    }

    private func orbGeometry(progress: CGFloat) -> some View {
        GeometryReader { geo in
            // Orb scales between a calm minimum and the available square.
            let maxDiameter = min(geo.size.width, geo.size.height)
            let minScale: CGFloat = 0.42
            let scale = minScale + (1.0 - minScale) * progress
            let diameter = maxDiameter * scale

            ZStack {
                // Static guide ring at the inhale extent.
                Circle()
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1)
                    .frame(width: maxDiameter, height: maxDiameter)

                // Outer breathing halo — a soft physiological glow (HRV hue), not chrome.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.dataHrv.opacity(0.18), // token-exempt: rampa decorativa (halo)
                                     theme.dataHrv.opacity(0.0)], // token-exempt: rampa decorativa (halo)
                            center: .center,
                            startRadius: diameter * 0.20,
                            endRadius: diameter * 0.70
                        )
                    )
                    .frame(width: diameter * 1.35, height: diameter * 1.35)
                    .blur(radius: 18)

                // The orb body — a calm HRV-tinted fill on paper.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.dataHrv.opacity(0.32), // token-exempt: rampa decorativa (orbe)
                                     theme.dataHrv.opacity(0.14)], // token-exempt: rampa decorativa (orbe)
                            center: .init(x: 0.4, y: 0.35),
                            startRadius: 2,
                            endRadius: diameter * 0.62
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(theme.dataHrv.opacity(0.45), lineWidth: 1) // token-exempt: anillo decorativo (orbe)
                    )
                    .frame(width: diameter, height: diameter)

                // Ola 2: no live HR source for solo breathing (band gone; Watch mirror is strength-only).
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: CenitMetrics.gap) {
            Button {
                running ? stop() : start()
            } label: {
                Label(running ? "Stop session" : "Start · 3 min",
                      systemImage: running ? "stop.fill" : "play.fill")
                    .font(InstrumentoType.groteskHeadline(17))
                    .foregroundStyle(theme.paper)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(running ? theme.critical : theme.ink,
                                in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(EntrenarPressStyle())

            Button {
                model.buzz(loops: 1)
            } label: {
                Label("Test buzz", systemImage: "waveform.path")
                    .font(InstrumentoType.groteskHeadline(17))
                    .foregroundStyle(theme.ink)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .background(theme.surface,
                                in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(EntrenarPressStyle())
        }
    }

    // MARK: - Readouts

    // FER-1003: the live HRV/RMSSD readout and the coherence-estimate card were retired with the band —
    // solo breathing has no live R-R source (the Watch mirror is strength-only), so both were permanently
    // stuck at "—" / "No data". Only the pace readout, driven by the pacer itself, remains.
    private var readoutRow: some View {
        readoutTile(label: "Pace",
                    value: String(format: "%.1f", pace.bpm),
                    unit: "br/min",
                    accent: theme.ink,
                    caption: String(format: "%.0f / %.0fs", pace.inhale, pace.exhale))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `label` y `unit` son `LocalizedStringKey`: como `String` planos, `Text(label)` los pintaba tal cual
    /// y ni «HRV (RMSSD)» ni «Pace» ni las unidades pasaban por el catálogo (auditoría i18n 2026-07-18).
    /// `caption` se queda `String` a propósito — una de las llamadas interpola un conteo, y un ternario
    /// con rama interpolada resuelve a `String`, no a `LocalizedStringKey`; los call sites usan
    /// `String(localized:)` en cada rama.
    private func readoutTile(label: LocalizedStringKey, value: String, unit: LocalizedStringKey,
                             accent: Color, caption: String) -> some View {
        EntrenarToolCard(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(InstrumentoType.groteskNumber(26))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                }
                Text(caption)
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        }
        .frame(height: CenitMetrics.tileHeight)
    }


    // MARK: - Session control

    private func start() {
        running = true
        sessionSeconds = 0
        breathCount = 0
        armPhase(.inhale, from: Date(), buzz: true)
    }

    private func stop() {
        running = false
        phaseDeadline = .distantFuture
        // Orb snaps to contracted rest (progress 0) and pauses: `breathingOrb` gates on `running`.
    }

    /// Begin a breath phase: set the target, schedule its end, and (optionally)
    /// fire the haptic cue. Inhale = 1 pulse, exhale = 2 pulses.
    private func armPhase(_ newPhase: Phase, from now: Date, buzz: Bool) {
        phase = newPhase
        phaseStart = now
        let duration = (newPhase == .inhale) ? pace.inhale : pace.exhale
        phaseDeadline = now.addingTimeInterval(duration)

        if buzz {
            model.buzz(loops: newPhase == .inhale ? 1 : 2)
        }
    }

    /// Called by the fast timer: when the current phase elapses, flip to the next.
    private func advance(now: Date) {
        guard now >= phaseDeadline else { return }
        switch phase {
        case .inhale:
            armPhase(.exhale, from: now, buzz: true)
        case .exhale:
            breathCount += 1
            armPhase(.inhale, from: now, buzz: true)
        }
    }

    // MARK: - Formatting

    private func timeString(_ total: Int) -> String {
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#if DEBUG
#Preview("Breathe · Instrumento") {
    BreathingView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 900)
}

#Preview("Breathe · xxxLarge (AX5)") {
    BreathingView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 1100)
        .dynamicTypeSize(.accessibility5)
}
#endif
