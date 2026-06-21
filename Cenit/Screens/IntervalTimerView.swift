import SwiftUI
import Foundation
import StrandDesign

/// Silent haptic HIIT interval timer.
///
/// Train hands-free: the strap buzzes every transition so you never have to look
/// at the screen. Strong triple-buzz at the start of each WORK block, a short
/// single buzz into REST, a 3-2-1 tick on the last seconds of every phase, and a
/// long 5-loop buzz when the whole session finishes. With no strap bonded it still
/// works as a big glanceable visual timer (just without haptics).
///
/// «Instrumento diurno» (FER-342): warm paper, the countdown is the dominant
/// numeral in ink (a mechanical reading), the phase (WORK/REST/DONE) and the ring
/// carry the one hue, and the glow/gradient of the dark original is dropped for a
/// flat ring. All timer logic and haptics are unchanged.
struct IntervalTimerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @Environment(\.instrumentoTheme) private var theme

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
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                statusRow
                stageCard
                overviewCard
                configCard
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .onReceive(ticker) { _ in tick() }
        .onChange(of: workSeconds) { if !running { resetToStart() } }
        .onChange(of: restSeconds) { if !running { resetToStart() } }
        .onChange(of: rounds) {
            if currentRound > rounds { currentRound = rounds }
            if !running { resetToStart() }
        }
        .onAppear { if remaining == 0 { resetToStart() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Interval Timer")
                .font(StrandFont.title1)
                .foregroundStyle(theme.ink)
            Text("Silent haptic HIIT — the strap buzzes the transitions")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 10) {
            if live.bonded {
                pill("Buzz cues on", dotColor: theme.dataRecovery)
            } else {
                pill("Connect strap for buzz cues", dotColor: theme.warning)
            }
            Spacer()
            if running {
                pill("Running", dotColor: theme.dataStrain)
            } else if isFinished {
                pill("Complete", dotColor: theme.dataRecovery)
            } else {
                pill("Paused", dotColor: nil)
            }
        }
    }

    /// A quiet «Instrumento» status pill — surface capsule, ink label, optional dot.
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

    /// A contained «Instrumento» group — surface card with a hairline edge.
    @ViewBuilder
    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: Stage card — the big glanceable face

    private var stageCard: some View {
        card {
            VStack(spacing: 18) {
                // Phase + round line
                HStack(alignment: .firstTextBaseline) {
                    Text(phase.label)
                        .font(StrandFont.number(34, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(phaseColor)
                    Spacer()
                    HStack(spacing: 6) {
                        Text("ROUND").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        Text("\(min(currentRound, rounds))")
                            .font(StrandFont.number(20))
                            .foregroundStyle(theme.ink)
                        Text("/ \(rounds)")
                            .font(StrandFont.number(20))
                            .foregroundStyle(theme.inkTertiary)
                    }
                }

                // The ring + countdown
                ZStack {
                    intervalRing
                    VStack(spacing: 2) {
                        Text(isFinished ? "✓" : "\(remaining)")
                            .font(StrandFont.number(96, weight: .bold))
                            .foregroundStyle(isFinished ? theme.dataRecovery : theme.ink)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: remaining)
                            .monospacedDigit()
                        Text(isFinished ? "SESSION DONE" : "SECONDS")
                            .font(StrandFont.footnote)
                            .tracking(1.2)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)

                controls

                if !live.bonded {
                    Label("Bond your strap on the Live screen to feel the transitions hands-free.",
                          systemImage: "wave.3.right")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

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
                .animation(.linear(duration: 0.9), value: intervalProgress)
        }
        .frame(width: 240, height: 240)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if isFinished { resetToStart() }
                toggleRunning()
            } label: {
                Label(running ? "Pause" : (isFinished ? "Restart" : "Start"),
                      systemImage: running ? "pause.fill" : "play.fill")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                stopAndReset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!running && remaining == phaseDuration && currentRound == 1 && phase == .work && elapsed == 0)
        }
    }

    // MARK: Overview card — elapsed / planned

    private var overviewCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Session").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text("\(timeString(elapsed)) / \(timeString(totalPlanned))")
                        .font(StrandFont.bodyNumber)
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
                            .animation(.linear(duration: 0.9), value: sessionProgress)
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
        }
    }

    private var sessionProgress: Double {
        guard totalPlanned > 0 else { return 0 }
        return min(1, max(0, Double(elapsed) / Double(totalPlanned)))
    }

    private func overviewStat(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(18)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Config card

    private var configCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Configure").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                configStepper(title: "Work", unit: "sec", value: $workSeconds,
                              range: 5...600, step: 5, tint: theme.dataStrain)
                Divider().overlay(theme.hairline)
                configStepper(title: "Rest", unit: "sec", value: $restSeconds,
                              range: 5...600, step: 5, tint: theme.dataHrv)
                Divider().overlay(theme.hairline)
                configStepper(title: "Rounds", unit: nil, value: $rounds,
                              range: 1...30, step: 1, tint: theme.ink)
            }
            .disabled(running)
            .opacity(running ? StrandPalette.disabledOpacity : 1)
        }
    }

    private func configStepper(title: LocalizedStringKey, unit: String?, value: Binding<Int>,
                               range: ClosedRange<Int>, step: Int, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
                Text("\(range.lowerBound)–\(range.upperBound)\(unit.map { " \($0)" } ?? "") · step \(step)")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(value.wrappedValue)")
                    .font(StrandFont.number(24))
                    .foregroundStyle(tint)
                    .frame(minWidth: 44, alignment: .trailing)
                if let unit {
                    Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .tint(theme.inkSecondary)
                .accessibilityLabel(title)
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
        withAnimation(.snappy) {
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

    private func stopAndReset() {
        running = false
        resetToStart()
    }

    /// Reset run state back to round 1 / start of work, using current config.
    private func resetToStart() {
        phase = .work
        currentRound = 1
        remaining = max(1, workSeconds)
        elapsed = 0
    }

    /// Fire a strap buzz (no-op when not bonded — `buzz` already guards, but we
    /// also skip the call entirely so this stays a pure visual tool when unbonded).
    private func buzz(loops: UInt8) {
        guard live.bonded else { return }
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
        .environmentObject(AppModel())
        .environmentObject(LiveState())
        .frame(width: 720, height: 900)
}
#endif
