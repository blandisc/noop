import SwiftUI
import Foundation
import StrandDesign
import Inject   // recarga en caliente (dev-only, inerte en Release)

/// Silent haptic HIIT interval timer.
///
/// Train hands-free: the phone buzzes every transition so you never have to look
/// at the screen. Strong triple-buzz at the start of each WORK block, a short
/// single buzz into REST, a 3-2-1 tick on the last seconds of every phase, and a
/// long 5-loop buzz when the whole session finishes. On macOS (no UIKit haptics)
/// it still works as a big glanceable visual timer.
///
/// «Instrumento diurno» (FER-342) + cristal El Eje (FER-201 · Anillo 4): el fondo es
/// `.entrenarHojaFondo(tono: .neutro)`; las tarjetas/píldoras internas son papel opaco
/// (`.superficieSolida`/`.pastillaSolida`, regla no-sheet-glass). La cuenta regresiva
/// sigue siendo el numeral dominante en tinta; fase y anillo llevan el hue. Toda la
/// lógica del temporizador y los haptics, intacta.
struct IntervalTimerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.instrumentoTheme) private var theme
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
    /// done = recovery green. Rides the phase label and the ring (a state datum).
    private var phaseColor: Color {
        switch phase {
        case .work: return theme.dataStrain
        case .rest: return theme.dataHrv
        case .done: return theme.dataRecovery
        }
    }

    private var isFinished: Bool { phase == .done }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                if configuring {
                    configureScreen
                } else {
                    header
                    statusRow
                    stageCard
                    overviewCard
                }
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, CenitMetrics.screenPadding)
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
        VStack(alignment: .leading, spacing: 2) {
            Text("Interval Timer")
                .font(InstrumentoType.grotesk(28, weight: .bold, relativeTo: .title))
                .foregroundStyle(theme.ink)
            Text("Silent haptic HIIT: your phone buzzes the transitions")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: Configure screen (pre-session)

    private var configureScreen: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("INTERVALS").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Build your HIIT")
                    .font(InstrumentoType.grotesk(28, weight: .bold, relativeTo: .title))
                    .foregroundStyle(theme.ink)
            }

            // FER-201: tarjeta interna OPACA (no-sheet-glass) — sustituye `EntrenarToolCard` (papel).
            VStack(alignment: .leading, spacing: 14) {
                configStepper(title: "Work", unit: "sec", value: $workSeconds,
                              range: 5...600, step: 5, tint: theme.dataStrain)
                Divider().overlay(theme.hairline)
                configStepper(title: "Rest", unit: "sec", value: $restSeconds,
                              range: 5...600, step: 5, tint: theme.dataHrv)
                Divider().overlay(theme.hairline)
                configStepper(title: "Rounds", unit: nil, value: $rounds,
                              range: 1...30, step: 1, tint: theme.ink)
            }
            .padding(LiquidSpace.s400)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)

            HStack {
                Text("Total \(timeString(totalPlanned))")
                    .font(InstrumentoType.groteskNumber(16))
                    .foregroundStyle(theme.ink)
                Spacer()
            }

            Button {
                startFromConfigure()
            } label: {
                Text("Start")
                    .font(InstrumentoType.groteskHeadline(17))
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.dataStrain, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(EntrenarPressStyle())
        }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 10) {
            Spacer()
            if running {
                statusPill("Running", dotColor: theme.dataStrain)
            } else if isFinished {
                statusPill("Complete", dotColor: theme.dataRecovery)
            } else {
                statusPill("Paused")
            }
        }
    }

    /// Píldora de estado opaca El Eje (FER-201) — sustituye `EntrenarStatusPill` (papel) sobre el cristal.
    private func statusPill(_ text: LocalizedStringKey, dotColor: Color? = nil) -> some View {
        HStack(spacing: LiquidSpace.s150) {
            if let dotColor {
                Circle().fill(dotColor).frame(width: LiquidSpace.s150, height: LiquidSpace.s150)
            }
            Text(text)
                .font(StrandFont.caption)
                .foregroundStyle(theme.ink)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s150)
        .liquidGlass(.pastillaSolida)
    }

    // MARK: Stage card — the big glanceable face

    private var stageCard: some View {
        // FER-201: tarjeta interna OPACA — el anillo/cuenta regresiva no cambian, solo el chrome.
        VStack(spacing: 18) {
            // Phase + round line
            HStack(alignment: .firstTextBaseline) {
                Text(phase.label)
                    .font(InstrumentoType.grotesk(34, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(phaseColor)
                Spacer()
                HStack(spacing: 6) {
                    Text("ROUND").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("\(min(currentRound, rounds))")
                        .font(InstrumentoType.groteskNumber(20))
                        .foregroundStyle(theme.ink)
                    Text("/ \(rounds)")
                        .font(InstrumentoType.groteskNumber(20))
                        .foregroundStyle(theme.inkTertiary)
                }
            }

            // One bar per round — completed amber, current phase hue, future hairline.
            roundIndicators

            // The ring + countdown
            ZStack {
                intervalRing
                VStack(spacing: 2) {
                    // La cuenta regresiva ES el numeral protagonista de esta pantalla, así que habla
                    // en la voz Grotesk como el resto de la app (FER-900) y no en la SF vieja.
                    Text(isFinished ? "✓" : "\(remaining)")
                        .instrumentoHero(96)
                        .foregroundStyle(isFinished ? theme.dataRecovery : theme.ink)
                        .contentTransition(.numericText())
                        .strandAnimation(.snappy, value: remaining)
                    Text(isFinished ? "SESSION DONE" : "SECONDS")
                        .instrumentoOverline()
                        .foregroundStyle(theme.inkTertiary)
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
            // Flat track — a faint warm rule, no glow (Instrumento drops the dark
            // system's gradient + shadow).
            Circle()
                .stroke(theme.hairline, lineWidth: 16)
            Circle()
                .trim(from: 0, to: isFinished ? 1 : intervalProgress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .strandAnimation(.linear(duration: 0.9), value: intervalProgress)
        }
        .frame(width: 240, height: 240)
        .accessibilityHidden(true)
    }

    /// Compact round progress bars above the ring (one capsule per planned round).
    private var roundIndicators: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, rounds), id: \.self) { index in
                Capsule()
                    .fill(roundIndicatorFill(index))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if index > currentRound && phase != .done {
                            Capsule().strokeBorder(theme.hairline, lineWidth: 1)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Round \(min(currentRound, rounds)) of \(rounds)"))
    }

    private func roundIndicatorFill(_ index: Int) -> Color {
        if phase == .done || index < currentRound {
            return theme.dataStrain
        }
        if index == currentRound {
            return phase == .rest ? theme.dataHrv : theme.dataStrain
        }
        return theme.hairline
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if isFinished { resetToStart() }
                toggleRunning()
            } label: {
                Label(running ? "Pause" : (isFinished ? "Restart" : "Start"),
                      systemImage: running ? "pause.fill" : "play.fill")
                    .font(InstrumentoType.groteskHeadline(17))
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(EntrenarPressStyle())

            Button {
                stopAndReset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(InstrumentoType.groteskHeadline(17))
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(EntrenarPressStyle())
            .disabled(!running && remaining == phaseDuration && currentRound == 1 && phase == .work && elapsed == 0)
        }
    }

    // MARK: Overview card — elapsed / planned

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(timeString(elapsed)) / \(timeString(totalPlanned))")
                    .font(InstrumentoType.groteskNumber(15, weight: .semibold))
                    .foregroundStyle(theme.ink)
            }

            // Slim total-session progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.hairline)
                    Capsule()
                        .fill(theme.dataStrain)
                        .frame(width: geo.size.width * sessionProgress)
                        .strandAnimation(.linear(duration: 0.9), value: sessionProgress)
                }
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                overviewStat("Work", "\(workSeconds)s", theme.dataStrain)
                overviewStat("Rest", "\(restSeconds)s", theme.dataHrv)
                overviewStat("Rounds", "\(rounds)", theme.ink)
                overviewStat("Remaining", timeString(max(0, totalPlanned - elapsed)), theme.inkSecondary)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(InstrumentoType.groteskNumber(18)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Config steppers (configure screen only)

    private func configStepper(title: String, unit: String?, value: Binding<Int>,
                               range: ClosedRange<Int>, step: Int, tint: Color) -> some View {
        // El literal inglés ES la clave del catálogo; VoiceOver necesita el String ya resuelto.
        let accessibilityName = String(localized: String.LocalizationValue(title))
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(InstrumentoType.grotesk(16, weight: .semibold)).foregroundStyle(theme.ink)
                Text("\(range.lowerBound)–\(range.upperBound)\(unit.map { " \($0)" } ?? "") · step \(step)")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value.wrappedValue)")
                    .font(InstrumentoType.groteskNumber(24))
                    .foregroundStyle(tint)
                    .frame(minWidth: 44, alignment: .trailing)
                if let unit {
                    Text(unit).font(InstrumentoType.grotesk(12, weight: .medium)).foregroundStyle(theme.inkTertiary)
                }
            }
            PaperStepper(value: value, in: range, step: step,
                         label: accessibilityName, unit: unit)
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
        withAnimation(StrandMotion.gated(.snappy, reduceMotion)) {
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
#Preview("Interval Timer · Instrumento") {
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
