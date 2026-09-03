import SwiftUI
import Foundation
import CenitDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Silent haptic HIIT interval timer.
///
/// Train hands-free: the phone buzzes every transition so you never have to look
/// at the screen. Strong triple-buzz at the start of each WORK block, a short
/// single buzz into REST, a 3-2-1 tick on the last seconds of every phase, and a
/// long 5-loop buzz when the whole session finishes. On macOS (no UIKit haptics)
/// it still works as a big glanceable visual timer.
///
/// Liquid Glass · El Eje · régimen sobrio (FER-243): fondo `.entrenarHojaFondo(.neutro)`;
/// tarjetas/píldoras `.superficieSolida` / `.pastillaSolida`. El countdown manda en
/// tinta; el hue de fase vive solo en label + anillo + barras. CTAs = `LiquidGlassButton`
/// (nunca hue de dato en fill). Lógica del temporizador y haptics, intacta.
struct IntervalTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Config (persisted only in-view)

    @State private var workSeconds: Int = 30
    @State private var restSeconds: Int = 15
    @State private var rounds: Int = 8

    // MARK: Run state

    private enum Phase { case work, rest, done
        var label: String {
            switch self {
            case .work: return String(localized: "WORK")
            case .rest: return String(localized: "REST")
            case .done: return String(localized: "DONE")
            }
        }
    }

    @State private var phase: Phase = .work
    @State private var currentRound: Int = 1
    @State private var remaining: Int = 30          // seconds left in the current phase
    @State private var running: Bool = false
    @State private var elapsed: Int = 0             // total elapsed seconds across the session
    @State private var configuring: Bool = true
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    // 1Hz tick.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: Derived

    private var phaseDuration: Int {
        switch phase {
        case .work: return max(1, workSeconds)
        case .rest: return max(1, restSeconds)
        case .done: return 1
        }
    }

    /// 0...1 progress through the current interval.
    private var intervalProgress: Double {
        guard phaseDuration > 0 else { return 0 }
        let done = Double(phaseDuration - remaining)
        return min(1, max(0, done / Double(phaseDuration)))
    }

    /// Total planned session length in seconds (work*rounds + rest*(rounds-1)).
    private var totalPlanned: Int {
        guard rounds > 0 else { return 0 }
        return workSeconds * rounds + restSeconds * max(0, rounds - 1)
    }

    /// The one hue for the current phase — work = ember effort, rest = calm cyan,
    /// done = recovery green. Rides the phase label and the ring (a state datum) —
    /// never button chrome (H-022).
    private var phaseColor: Color {
        switch phase {
        case .work: return LiquidColor.ambar
        case .rest: return LiquidColor.cian
        case .done: return LiquidColor.verdePrimario
        }
    }

    private var isFinished: Bool { phase == .done }

    private var primaryControlLabel: String {
        if running { return String(localized: "Pause") }
        if isFinished { return String(localized: "Restart") }
        return String(localized: "Start")
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                if configuring {
                    configureScreen
                } else {
                    header
                    statusRow
                    stageCard
                    overviewCard
                }
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-201 (Anillo 4, épico FER-195): fondo de cristal El Eje — se CONSERVA el
        // chrome de título a mano (sin control de salida propio: el pop lo da el
        // NavigationStack ambiente vía trainChrome). Agregar `EntrenarHojaCabecera(.cerrar)`
        // AÑADIRÍA un control que hoy no existe (regla suprema: cero cambio de comportamiento).
        .entrenarHojaFondo(tono: .neutro)
        .onReceive(ticker) { _ in tick() }
        .onChange(of: workSeconds) { if !running { resetToStart() } }
        .onChange(of: restSeconds) { if !running { resetToStart() } }
        .onChange(of: rounds) {
            if currentRound > rounds { currentRound = rounds }
            if !running { resetToStart() }
        }
        .onAppear { if remaining == 0 { resetToStart() } }
        .enableInjection()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text("Interval Timer")
                .font(LiquidType.displayL)
                .tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text("Silent haptic HIIT: your phone buzzes the transitions")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
        }
    }

    // MARK: Configure screen (pre-session)

    private var configureScreen: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text("INTERVALS").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                Text("Build your HIIT")
                    .font(LiquidType.displayL)
                    .tracking(LiquidType.displayLTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                configStepper(title: "Work", unit: "sec", value: $workSeconds,
                              range: 5...600, step: 5, tint: LiquidColor.ambar)
                Divider().overlay(LiquidColor.tinta10)
                configStepper(title: "Rest", unit: "sec", value: $restSeconds,
                              range: 5...600, step: 5, tint: LiquidColor.cian)
                Divider().overlay(LiquidColor.tinta10)
                configStepper(title: "Rounds", unit: nil, value: $rounds,
                              range: 1...30, step: 1, tint: LiquidColor.tinta900)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)

            HStack {
                Text("Total \(timeString(totalPlanned))")
                    .font(LiquidType.valorM)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
            }

            LiquidGlassButton(String(localized: "Start"), variant: .primary, expands: true) {
                startFromConfigure()
            }
        }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: LiquidSpace.s250) {
            Spacer()
            if running {
                LiquidStatePill(String(localized: "Running"), dot: LiquidColor.ambar)
            } else if isFinished {
                LiquidStatePill(String(localized: "Complete"), dot: LiquidColor.verdePrimario)
            } else {
                LiquidStatePill(String(localized: "Paused"))
            }
        }
    }

    // MARK: Stage card — the big glanceable face

    private var stageCard: some View {
        VStack(spacing: LiquidSpace.s400) {
            // Phase + round line
            HStack(alignment: .firstTextBaseline) {
                Text(phase.label)
                    .liquidKicker()
                    .foregroundStyle(phaseColor)
                Spacer()
                HStack(spacing: LiquidSpace.s150) {
                    Text("ROUND").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                    Text("\(min(currentRound, rounds))")
                        .font(LiquidType.valorL)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text("/ \(rounds)")
                        .font(LiquidType.valorL)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }

            // One bar per round — completed amber, current phase hue, future hairline.
            roundIndicators

            // The ring + countdown
            ZStack {
                intervalRing
                VStack(spacing: LiquidSpace.s050) {
                    // Countdown = dominante sobrio: Grotesk tabular en tinta (nunca hue de fase).
                    Text(isFinished ? "✓" : "\(remaining)")
                        .font(LiquidType.displayXL).tracking(LiquidType.displayXLTracking)
                        .monospacedDigit()
                        .foregroundStyle(LiquidColor.tinta900)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .strandAnimation(.snappy, value: remaining)
                    Text(isFinished ? "SESSION DONE" : "SECONDS")
                        .liquidRegla()
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)

            controls
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }

    /// Hidden from VoiceOver: the numeral (`remaining`) and `phase.label`, already read as part of
    /// `stageCard`, cover the same ground in text — the ring is redundant motion, not information.
    private var intervalRing: some View {
        ZStack {
            Circle()
                .stroke(LiquidColor.tinta10, lineWidth: LiquidSpace.s400)
            Circle()
                .trim(from: 0, to: isFinished ? 1 : intervalProgress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: LiquidSpace.s400, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Reduce Motion: strandAnimation se anula → anillo congelado (sin lerp).
                .strandAnimation(.linear(duration: 0.9), value: intervalProgress)
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }

    /// Compact round progress bars above the ring (one capsule per planned round).
    private var roundIndicators: some View {
        HStack(spacing: LiquidSpace.s100) {
            ForEach(1...max(1, rounds), id: \.self) { index in
                LiquidBarraProgreso(
                    fraccion: 1,
                    tono: roundIndicatorFill(index),
                    pista: roundIndicatorFill(index),
                    altura: LiquidSpace.s150,
                    animada: false,
                    contorno: (index > currentRound && phase != .done) ? LiquidColor.tinta10 : nil)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Round \(min(currentRound, rounds)) of \(rounds)"))
    }

    private func roundIndicatorFill(_ index: Int) -> Color {
        if phase == .done || index < currentRound {
            return LiquidColor.ambar
        }
        if index == currentRound {
            return phase == .rest ? LiquidColor.cian : LiquidColor.ambar
        }
        return LiquidColor.tinta10
    }

    private var controls: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(primaryControlLabel, variant: .primary, expands: true) {
                if isFinished { resetToStart() }
                toggleRunning()
            }

            LiquidGlassButton(String(localized: "Reset"), variant: .glass, expands: true) {
                stopAndReset()
            }
            .disabled(!running && remaining == phaseDuration && currentRound == 1 && phase == .work && elapsed == 0)
        }
    }

    // MARK: Overview card — elapsed / planned

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session").liquidRegla().foregroundStyle(LiquidColor.tinta500)
                Spacer()
                Text("\(timeString(elapsed)) / \(timeString(totalPlanned))")
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            // Slim total-session progress bar
            LiquidBarraProgreso(fraccion: sessionProgress, tono: LiquidColor.ambar,
                                altura: LiquidSpace.s200)


            HStack(spacing: .zero) {
                overviewStat("Work", "\(workSeconds)s", LiquidColor.ambar)
                overviewStat("Rest", "\(restSeconds)s", LiquidColor.cian)
                overviewStat("Rounds", "\(rounds)", LiquidColor.tinta900)
                overviewStat("Remaining", timeString(max(0, totalPlanned - elapsed)), LiquidColor.tinta700)
            }
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }

    private var sessionProgress: Double {
        guard totalPlanned > 0 else { return 0 }
        return min(1, max(0, Double(elapsed) / Double(totalPlanned)))
    }

    private func overviewStat(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(label).liquidRegla().foregroundStyle(LiquidColor.tinta500)
            Text(value).font(LiquidType.valorM).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Config steppers (configure screen only)

    private func configStepper(title: String, unit: String?, value: Binding<Int>,
                               range: ClosedRange<Int>, step: Int, tint: Color) -> some View {
        // El literal inglés ES la clave del catálogo; VoiceOver necesita el String ya resuelto.
        let accessibilityName = String(localized: String.LocalizationValue(title))
        return HStack {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(LocalizedStringKey(title))
                    .font(LiquidType.tituloGemela)
                    .foregroundStyle(LiquidColor.tinta900)
                Text("\(range.lowerBound)–\(range.upperBound)\(unit.map { " \($0)" } ?? "") · step \(step)")
                    .font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text("\(value.wrappedValue)")
                    .font(LiquidType.valorTileM)
                    .foregroundStyle(tint)
                    .frame(minWidth: 44, alignment: .trailing)
                if let unit {
                    Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                }
            }
            EntrenarStepper(valor: "\(value.wrappedValue)",
                            puedeBajar: value.wrappedValue - step >= range.lowerBound,
                            puedeSubir: value.wrappedValue + step <= range.upperBound,
                            onBajar: { value.wrappedValue = max(range.lowerBound, value.wrappedValue - step) },
                            onSubir: { value.wrappedValue = min(range.upperBound, value.wrappedValue + step) })
                .accessibilityLabel(Text(verbatim: unit.map { "\(accessibilityName), \($0)" } ?? accessibilityName))
        }
    }

    // MARK: Timer logic

    private func tick() {
        guard running, !isFinished else { return }

        // Optional 3-2-1 countdown tick on the last seconds of the current phase.
        if remaining <= 3 && remaining >= 1 {
            buzz(loops: 1)
        }

        if remaining > 1 {
            remaining -= 1
            elapsed += 1
            return
        }

        // remaining hits 0 — advance to the next phase/round.
        elapsed += 1
        advancePhase()
    }

    private func advancePhase() {
        switch phase {
        case .work:
            if currentRound >= rounds {
                // Last work block finished → session complete.
                finishSession()
            } else {
                // Into rest.
                phase = .rest
                remaining = max(1, restSeconds)
                buzz(loops: 1)              // short cue into rest
            }
        case .rest:
            // Rest done → next round's work.
            currentRound += 1
            phase = .work
            remaining = max(1, workSeconds)
            buzz(loops: 3)                  // strong cue into work
        case .done:
            break
        }
    }

    private func finishSession() {
        withAnimation(LiquidMotion.condicionado(.snappy, reduceMotion)) {
            phase = .done
            remaining = 0
            running = false
        }
        buzz(loops: 5)                      // long completion cue
    }

    private func toggleRunning() {
        if isFinished { return }
        if running {
            running = false
        } else {
            // Starting fresh from a clean reset → fire the opening WORK cue.
            let startingFresh = (phase == .work && currentRound == 1
                                 && remaining == max(1, workSeconds) && elapsed == 0)
            running = true
            if startingFresh { buzz(loops: 3) }
        }
    }

    /// Leave the configure screen and start a fresh session (opening WORK buzz).
    private func startFromConfigure() {
        resetToStart()
        configuring = false
        running = true
        buzz(loops: 3)
    }

    private func stopAndReset() {
        running = false
        resetToStart()
        configuring = true
    }

    /// Reset run state back to round 1 / start of work, using current config.
    private func resetToStart() {
        phase = .work
        currentRound = 1
        remaining = max(1, workSeconds)
        elapsed = 0
    }

    /// Fire phone haptic via `AppModel.buzz` (no-op on platforms without UIKit).
    private func buzz(loops: UInt8) {
        model.buzz(loops: loops)
    }

    // MARK: Formatting

    private func timeString(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

#if DEBUG
#Preview("Interval Timer · Liquid Glass") {
    IntervalTimerView()
        .environment(AppModel.preview)
        .frame(width: 720, height: 900)
}

#Preview("Interval Timer · xxxLarge (AX5)") {
    IntervalTimerView()
        .environment(AppModel.preview)
        .frame(width: 390, height: 1100)
        .dynamicTypeSize(.accessibility5)
}
#endif
