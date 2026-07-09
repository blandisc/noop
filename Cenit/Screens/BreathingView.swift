import SwiftUI
import Foundation
import StrandDesign

/// HRV haptic breathing biofeedback trainer — Strand's flagship novel feature.
///
/// The strap both *measures* HRV (via R-R intervals) and *buzzes* (haptic strap
/// motor), so we can pace the user's breath with a felt cue and watch their HRV
/// respond in real time. Pick a pace, hit start, close your eyes: one buzz on the
/// inhale, two on the exhale. Live HR + a rolling RMSSD (an honest estimate) show
/// the autonomic response building as the session deepens.
///
/// «Instrumento diurno» (FER-342): warm paper, ink labels, color only in the
/// measured datum — live HR in `dataHeart`, HRV in `dataHrv`. The breath orb keeps
/// the screen's signature motion but in a calm physiological glow, not saturated
/// chrome. All session logic (paces, timers, RMSSD) is unchanged from the dark
/// original; only the view layer was repainted.
struct BreathingView: View {

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.instrumentoTheme) private var theme

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
            case .relax:     return String(localized: "Long exhale · downshift to rest")
            case .coherence: return String(localized: "Equal breath · ~5.5 br/min coherence")
            case .box:       return String(localized: "Square breath · steady focus")
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

    /// 0 = fully contracted, 1 = fully expanded. Drives the orb scale.
    @State private var orbProgress: CGFloat = 0
    @State private var phase: Phase = .inhale
    @State private var phaseDeadline: Date = .distantFuture

    @State private var sessionSeconds: Int = 0
    @State private var breathCount: Int = 0

    /// Rolling buffer of the most recent R-R intervals (ms) for RMSSD.
    @State private var rrBuffer: [Int] = []
    @State private var rmssd: Double? = nil

    /// Phase driver (fast, smooth) and a once-per-second session tick.
    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private let rrWindow = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                statusRow
                orbCard
                controlRow
                readoutRow
                coherenceCard
                if !live.bonded { hapticHint }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
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
        // Pull new R-R intervals into the rolling buffer as they arrive. onReceive (not onChange):
        // the body no longer re-renders per beat, so a render-driven onChange would starve (FER-755).
        .onReceive(live.pulse.$rr.dropFirst()) { rr in
            ingest(rr)
        }
        // Changing pace mid-session re-arms the current phase cleanly.
        .onChange(of: pace) {
            if running { armPhase(.inhale, from: Date(), buzz: false) }
        }
        .onDisappear { stop() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Breathe")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
            Text("Haptic-paced breathing · watch your HRV respond")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: 10) {
            pill(running ? "Session live" : "Ready",
                 dotColor: running ? theme.dataRecovery : nil)

            if live.bonded {
                pill("Haptics on", dotColor: theme.dataRecovery)
            } else {
                pill("Visual only", dotColor: theme.warning)
            }

            Spacer()

            HStack(spacing: 6) {
                Text(timeString(sessionSeconds))
                    .font(StrandFont.number(15))
                    .foregroundStyle(theme.ink)
                Text("·").foregroundStyle(theme.inkTertiary)
                Text("\(breathCount) breaths")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// A quiet «Instrumento» status pill — surface capsule, ink label, an optional
    /// colored dot (the only place a hue rides chrome here, to mark live/warn state).
    private func pill(_ text: LocalizedStringKey, dotColor: Color?) -> some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: 6, height: 6)
            }
            Text(text)
                .font(StrandFont.caption)
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.surface, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// A contained «Instrumento» group — surface card with a hairline edge. Used
    /// sparingly (rule 3); the orb / readouts need a held surface to sit on.
    @ViewBuilder
    private func card<V: View>(padding: CGFloat = 16, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - The orb

    private var orbCard: some View {
        card(padding: 24) {
            VStack(spacing: 18) {
                HStack {
                    Text(pace.label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(String(format: "%.1f br/min", pace.bpm))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(theme.inkSecondary)
                }

                breathingOrb
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)

                Text(running ? phaseWord : pace.tagline)
                    .font(StrandFont.subhead)
                    .foregroundStyle(running ? theme.dataRecovery : theme.inkSecondary)
                    .animation(.easeInOut(duration: 0.2), value: phaseWord)
                    .animation(.easeInOut(duration: 0.2), value: running)

                SegmentedPillControl(Pace.allCases, selection: $pace) { $0.label }
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var phaseWord: String {
        switch phase {
        case .inhale: return String(localized: "Breathe in…")
        case .exhale: return String(localized: "Breathe out…")
        }
    }

    private var breathingOrb: some View {
        GeometryReader { geo in
            // Orb scales between a calm minimum and the available square.
            let maxDiameter = min(geo.size.width, geo.size.height)
            let minScale: CGFloat = 0.42
            let scale = minScale + (1.0 - minScale) * orbProgress
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

                // Centre readout — live HR is the measured datum, so it carries color.
                // PulseReader: only this readout re-evaluates per heartbeat (FER-755).
                PulseReader(live.pulse) { p in
                    VStack(spacing: 2) {
                        Text(p.smoothedBpm.map(String.init) ?? "—")
                            .font(StrandFont.number(40))
                            .foregroundStyle(p.smoothedBpm == nil ? theme.inkTertiary : theme.dataHeart)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: p.smoothedBpm)
                        Text("BPM")
                            .font(StrandFont.footnote)
                            .tracking(0.8)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: 12) {
            Button {
                running ? stop() : start()
            } label: {
                Label(running ? "Stop session" : "Start session",
                      systemImage: running ? "stop.fill" : "play.fill")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.paper)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(running ? theme.critical : theme.ink,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                model.buzz(loops: 1)
            } label: {
                Label("Test buzz", systemImage: "waveform.path")
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 14)
                    .background(theme.surface,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!live.bonded)
            .opacity(live.bonded ? 1 : 0.5)
            .help("Fire a single haptic pulse on the strap (requires a bonded connection)")
        }
    }

    // MARK: - Readouts

    private var readoutRow: some View {
        HStack(spacing: NoopMetrics.gap) {
            PulseReader(live.pulse) { p in
                readoutTile(label: "Heart rate",
                            value: p.smoothedBpm.map { "\($0)" } ?? "—",
                            unit: String(localized: "bpm"),
                            accent: theme.dataHeart,
                            caption: live.worn ? "Live" : "Strap not worn")
            }

            readoutTile(label: "HRV (RMSSD)",
                        value: rmssd.map { String(format: "%.0f", $0) } ?? "—",
                        unit: "ms",
                        accent: theme.dataHrv,
                        caption: rrBuffer.isEmpty ? "Waiting for R-R" : "Last \(rrBuffer.count) beats")

            readoutTile(label: "Pace",
                        value: String(format: "%.1f", pace.bpm),
                        unit: "br/min",
                        accent: theme.ink,
                        caption: String(format: "%.0f / %.0fs", pace.inhale, pace.exhale))
        }
    }

    private func readoutTile(label: String, value: String, unit: String,
                             accent: Color, caption: String) -> some View {
        card(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(StrandFont.number(26))
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
        .frame(height: NoopMetrics.tileHeight)
    }

    // MARK: - Coherence estimate

    private var coherenceCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Coherence estimate").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    pill(LocalizedStringKey(coherenceLabel), dotColor: coherenceDotColor)
                }

                // A simple normalized bar — RMSSD mapped 0…120ms → 0…1.
                GeometryReader { geo in
                    let frac = coherenceFraction
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.hairline)
                        Capsule()
                            .fill(theme.dataHrv)
                            .frame(width: max(6, geo.size.width * frac))
                            .animation(.easeInOut(duration: 0.5), value: frac)
                    }
                }
                .frame(height: 10)

                Text("Estimate only — a higher RMSSD while paced usually means your parasympathetic \"rest\" branch is engaging. It is not a clinical reading; trends over a session matter more than any single number.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// RMSSD normalized to a 0…1 bar (0…120 ms full scale).
    private var coherenceFraction: CGFloat {
        guard let r = rmssd else { return 0 }
        return CGFloat(min(max(r / 120.0, 0), 1))
    }

    private var coherenceLabel: String {
        guard let r = rmssd else { return String(localized: "No data") }
        switch r {
        case ..<20:  return String(localized: "Building")
        case ..<45:  return String(localized: "Settling")
        case ..<80:  return String(localized: "Coherent")
        default:     return String(localized: "Deep calm")
        }
    }

    private var coherenceDotColor: Color? {
        guard let r = rmssd else { return nil }
        switch r {
        case ..<20:  return theme.warning
        case ..<45:  return theme.inkTertiary
        default:     return theme.dataRecovery
        }
    }

    // MARK: - Haptic hint

    private var hapticHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .foregroundStyle(theme.warning)
            Text("Connect your strap for haptic guidance — you'll feel one pulse on the inhale, two on the exhale, so you can breathe with your eyes closed.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .instrumentoCard(.card, theme: theme, fill: theme.tint(theme.warning), stroke: theme.softStroke(theme.warning))
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
        withAnimation(.easeInOut(duration: 0.8)) {
            orbProgress = 0
        }
    }

    /// Begin a breath phase: set the target, schedule its end, and (optionally)
    /// fire the haptic cue. Inhale = 1 pulse, exhale = 2 pulses.
    private func armPhase(_ newPhase: Phase, from now: Date, buzz: Bool) {
        phase = newPhase
        let duration = (newPhase == .inhale) ? pace.inhale : pace.exhale
        phaseDeadline = now.addingTimeInterval(duration)

        withAnimation(.easeInOut(duration: duration)) {
            orbProgress = (newPhase == .inhale) ? 1.0 : 0.0
        }

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

    // MARK: - HRV (RMSSD)

    /// Append newly-arrived R-R intervals, keep a rolling window, recompute RMSSD.
    private func ingest(_ rr: [Int]) {
        guard !rr.isEmpty else { return }
        // The published `rr` is the latest set of intervals; append the tail and trim.
        rrBuffer.append(contentsOf: rr)
        if rrBuffer.count > rrWindow {
            rrBuffer.removeFirst(rrBuffer.count - rrWindow)
        }
        rmssd = computeRMSSD(rrBuffer)
    }

    /// RMSSD = sqrt(mean of squared successive differences) over the R-R series.
    private func computeRMSSD(_ intervals: [Int]) -> Double? {
        guard intervals.count >= 2 else { return nil }
        var sumSq = 0.0
        for i in 1..<intervals.count {
            let d = Double(intervals[i] - intervals[i - 1])
            sumSq += d * d
        }
        let meanSq = sumSq / Double(intervals.count - 1)
        return meanSq.squareRoot()
    }

    // MARK: - Formatting

    private func timeString(_ total: Int) -> String {
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
