import SwiftUI
import Foundation
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Haptic-paced breathing trainer — a timed breath pacer with a felt cue.
///
/// Pick a pace, hit start, close your eyes, and follow the breath orb: a timer drives
/// inhale/exhale, one cue on the inhale, two on the exhale. (Live HRV/RMSSD biofeedback
/// was retired with the band — FER-1003 — since solo breathing has no live R-R source;
/// the pace readout, driven by the pacer itself, is what remains. Copy no longer
/// promises HRV response — FER-242 / H-020.)
///
/// Liquid Glass · El Eje, régimen sobrio (FER-242): `.entrenarHojaFondo(.neutro)`;
/// cards/píldoras internas opacas (`.superficieSolida`/`.pastillaSolida`); orbe =
/// `LiquidColor.azul` (identidad de respiración); CTAs = `LiquidGlassButton`. El pacer
/// y los haptics se conservan; Reduce Motion congela el orbe.
struct BreathingView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    // MARK: Pace presets

    private enum Pace: Hashable, CaseIterable {
        case relax          // 4s inhale / 6s exhale
        case coherence      // 5.5s / 5.5s
        case box            // 4s / 4s

        var label: String {
            switch self {
            case .relax:
                return String(localized: "breath.pace.relax", defaultValue: "Relax 4-6")
            case .coherence:
                return String(localized: "breath.pace.coherence", defaultValue: "Coherence 5.5")
            case .box:
                return String(localized: "breath.pace.box", defaultValue: "Box 4-4")
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
            case .relax:
                return String(localized: "breath.tag.relax",
                              defaultValue: "Long exhale · winds down")
            case .coherence:
                return String(localized: "breath.tag.coherence",
                              defaultValue: "Even breathing · ~5.5/min")
            case .box:
                return String(localized: "breath.tag.box",
                              defaultValue: "Square · steady focus")
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
    /// Paused when the scene is inactive so a backgrounded session does not burn 20 Hz.
    private let phaseTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    /// Timers only advance while the session is live and the scene is active.
    private var timersActive: Bool { running && scenePhase == .active }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                statusRow
                if !running {
                    paceSelector
                }
                orbCard
                controlRow
                readoutRow
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-201 / FER-242: fondo El Eje — chrome de título a mano (sin control de salida
        // propio: el pop lo da el NavigationStack ambiente vía trainChrome).
        .entrenarHojaFondo(tono: .neutro)
        .onReceive(phaseTimer) { now in
            guard timersActive else { return }
            advance(now: now)
        }
        .onReceive(secondTimer) { _ in
            guard timersActive else { return }
            sessionSeconds += 1
        }
        .onChange(of: pace) {
            if running { armPhase(.inhale, from: Date(), buzz: false) }
        }
        .onDisappear { stop() }
        .enableInjection()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(String(localized: "breath.title", defaultValue: "Breathe"))
                .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "breath.subtitle",
                        defaultValue: "Haptic-paced rhythm · follow the orb"))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack(spacing: LiquidSpace.s250) {
            LiquidStatePill(
                running
                    ? String(localized: "breath.status.live", defaultValue: "Session live")
                    : String(localized: "breath.status.ready", defaultValue: "Ready"),
                dot: running ? LiquidStatePillMetrics.dotVivoDefault : nil)

            Spacer()

            HStack(spacing: LiquidSpace.s150) {
                Text(timeString(sessionSeconds))
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("·").foregroundStyle(LiquidColor.tinta500)
                Text("\(breathCount) " + String(localized: "breath.breaths",
                                                 defaultValue: "breaths"))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        }
    }

    // MARK: - Pace selector

    private var paceSelector: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(String(localized: "breath.kicker", defaultValue: "Breathe"))
                    .font(LiquidType.regla).tracking(LiquidType.reglaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(String(localized: "breath.choosePace", defaultValue: "Choose a pace"))
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            VStack(spacing: LiquidSpace.s300) {
                ForEach(Pace.allCases, id: \.self) { option in
                    paceRow(option)
                }
            }
        }
    }

    private func paceRow(_ option: Pace) -> some View {
        let selected = pace == option
        let shape = RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
        return Button {
            pace = option
        } label: {
            HStack(alignment: .center, spacing: LiquidSpace.s300) {
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(verbatim: option.label)
                        .font(LiquidType.tituloGemela)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text(verbatim: option.tagline)
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta700)
                }
                Spacer(minLength: 0)
                Text(bpmString(option.bpm))
                    .font(LiquidType.caption)
                    .foregroundStyle(selected ? LiquidColor.azul : LiquidColor.tinta700)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected
                    ? LiquidColor.tonoCampo(LiquidColor.azul)
                    : LiquidColor.papelTarjeta,
                in: shape)
            .overlay(
                shape.strokeBorder(
                    selected
                        ? LiquidColor.azul.opacity(0.32) // token-exempt: borde de selección (preview)
                        : LiquidColor.vidrioCanto,
                    lineWidth: 1))
        }
        .buttonStyle(.liquidPress)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - The orb

    private var orbCard: some View {
        VStack(spacing: LiquidSpace.s550) {
            HStack {
                Text(verbatim: pace.label)
                    .font(LiquidType.regla).tracking(LiquidType.reglaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer()
                Text(bpmString(pace.bpm))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta700)
            }

            breathingOrb
                .frame(height: 300)
                .frame(maxWidth: .infinity)

            Text(verbatim: running ? phaseWord : pace.tagline)
                .font(LiquidType.cuerpo)
                .foregroundStyle(running ? LiquidColor.tinta900 : LiquidColor.tinta700)
                .strandAnimation(LiquidMotion.ambient(LiquidMotion.soft), value: phaseWord)
                .strandAnimation(LiquidMotion.ambient(LiquidMotion.soft), value: running)
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous))
        .liquidGlass(.superficieSolida)
    }

    private var phaseWord: String {
        switch phase {
        case .inhale:
            return String(localized: "breath.phase.inhale", defaultValue: "Inhale…")
        case .exhale:
            return String(localized: "breath.phase.exhale", defaultValue: "Exhale…")
        }
    }

    /// Orb only — progress is scoped here via TimelineView so the rest of the screen
    /// does not re-evaluate each animation frame (FER-876). Paused whenever the breath
    /// isn't running OR Reduce Motion is on — frozen at rest, never animated (mismo
    /// patrón que `OrbeVivo`). Hidden from VoiceOver: `phaseWord` already says
    /// the phase, so the orb is redundant motion, not information.
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
            let azul = LiquidColor.azul

            ZStack {
                // Static guide ring at the inhale extent.
                Circle()
                    .strokeBorder(LiquidColor.tinta900.opacity(0.14), lineWidth: 1) // token-exempt: guide ring
                    .frame(width: maxDiameter, height: maxDiameter)

                // Outer breathing halo — soft physiological glow in breath identity hue.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [azul.opacity(0.18), // token-exempt: rampa decorativa (halo)
                                     azul.opacity(0.0)], // token-exempt: rampa decorativa (halo)
                            center: .center,
                            startRadius: diameter * 0.20,
                            endRadius: diameter * 0.70
                        )
                    )
                    .frame(width: diameter * 1.35, height: diameter * 1.35)
                    .blur(radius: LiquidSpace.s550)

                // The orb body — azul fill (breath identity), not dataHrv/cyan.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [azul.opacity(0.32), // token-exempt: rampa decorativa (orbe)
                                     azul.opacity(0.14)], // token-exempt: rampa decorativa (orbe)
                            center: .init(x: 0.4, y: 0.35),
                            startRadius: LiquidSpace.s050,
                            endRadius: diameter * 0.62
                        )
                    )
                    .overlay(
                        Circle().strokeBorder(azul.opacity(0.45), lineWidth: 1) // token-exempt: anillo decorativo (orbe)
                    )
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            if running {
                LiquidGlassButton(
                    String(localized: "breath.stop", defaultValue: "End session"),
                    variant: .glass,
                    expands: true
                ) { stop() }
            } else {
                LiquidGlassButton(
                    String(localized: "breath.start", defaultValue: "Start · 3 min"),
                    variant: .primary,
                    expands: true
                ) { start() }
                LiquidGlassButton(
                    String(localized: "breath.testBuzz", defaultValue: "Test buzz"),
                    variant: .glass
                ) { model.buzz(loops: 1) }
            }
        }
    }

    // MARK: - Readouts

    // FER-1003: the live HRV/RMSSD readout and the coherence-estimate card were retired with the band —
    // solo breathing has no live R-R source (the Watch mirror is strength-only), so both were permanently
    // stuck at "—" / "No data". Only the pace readout, driven by the pacer itself, remains.
    private var readoutRow: some View {
        readoutTile(
            label: String(localized: "breath.readout.pace", defaultValue: "Pace"),
            value: String(format: "%.1f", pace.bpm),
            unit: String(localized: "breath.readout.unit", defaultValue: "br/min"),
            caption: String(format: "%.0f / %.0fs", pace.inhale, pace.exhale))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readoutTile(label: String, value: String, unit: String,
                             caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .font(LiquidType.regla).tracking(LiquidType.reglaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: LiquidSpace.s150)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text(value)
                    .font(LiquidType.valorTileM).tracking(LiquidType.valorTileTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(verbatim: unit)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Text(verbatim: caption)
                .font(LiquidType.unidad)
                .foregroundStyle(LiquidColor.tinta500)
                .lineLimit(1)
                .padding(.top, LiquidSpace.s100)
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CenitMetrics.tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous))
        .liquidGlass(.superficieSolida)
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

    private func bpmString(_ bpm: Double) -> String {
        String(format: "%.1f ", bpm)
            + String(localized: "breath.bpm.unit", defaultValue: "br/min")
    }
}

#if DEBUG
#Preview("Breathe · El Eje") {
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
