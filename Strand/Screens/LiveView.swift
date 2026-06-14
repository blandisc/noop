import SwiftUI
#if os(macOS)
import AppKit
#endif
import StrandDesign
import WhoopProtocol
import WhoopStore

/// Live — the connected strap in real time. Built on the shared design system
/// (ScreenScaffold chrome, StrandPalette, StrandFont) so it lines up pixel-for-pixel
/// with every other screen instead of the old standalone Milestone-1 layout.
struct LiveView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState

    /// When true, render only the live monitor (through the saved-data footer) and omit the strap-
    /// management chrome — workout, model picker, controls, and the frame log. The Today calibration
    /// card presents the monitor this way; the Live tab keeps the full chrome (default false).
    var monitorOnly: Bool = false

    /// Which strap the user is pairing — persists across launches. Drives which
    /// BLE service we scan for so a WHOOP 4.0 scan never hangs on a WHOOP 5 wrist.
    @AppStorage("selectedWhoopModel") private var selectedModelRaw = WhoopModel.whoop4.rawValue
    private var selectedModel: WhoopModel { WhoopModel(rawValue: selectedModelRaw) ?? .whoop4 }

    /// Smoothed, spike-filtered live HR from AppModel (median over a short window).
    private var displayHR: Int? { model.bpm }
    private var activeConnection: Bool { live.connected && live.bonded }
    /// True when a live HR is actually streaming from a worn strap — drives the ECG monitor sweep.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }
    /// Rolling beat-to-beat buffer (last ~40 R-R intervals) so the tachogram builds as beats arrive.
    @State private var rrHistory: [Int] = []

    var body: some View {
        ScreenScaffold(title: "Live",
                       subtitle: "Your strap in real time — heart rate and frames as they arrive.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                connectionRow
                // Can't-connect-at-all guidance: the strap wiped its bond (firmware update / WHOOP app
                // re-bond), so connects loop on "Peer removed pairing information". Show the re-pair steps
                // right here instead of silently retrying. (5/MG firmware reset, 2026-06)
                if let guide = live.reconnectGuide { reconnectGuideBanner(guide) }
                // Bond-refused guidance, shown right here on Live where people actually connect (it
                // also appears in Settings). A 5/MG strap still bonded to the WHOOP app refuses pairing
                // with "Encryption is insufficient" — this tells the user to free it and re-pair.
                if let hint = live.pairingHint { pairingHintBanner(hint) }
                ecgHero
                sessionTally
                liveSignals
                syncSignals
                savedFooter
                // Strap-management chrome lives only on the Live tab — the Today "see it beat by beat"
                // monitor cover ends at the saved-data footer (monitorOnly).
                if !monitorOnly {
                    workoutSection
                    // Show the strap picker whenever we're not actively streaming, so a user with both
                    // a WHOOP 4 and a 5/MG can switch between them. (It used to hide once `bonded`, which
                    // is sticky across disconnects — so after the first pairing the picker vanished.)
                    if !activeConnection { modelPicker }
                    controls
                    logCard
                }
            }
        }
        .onAppear { refreshLiveSession() }
        .onDisappear { model.stopRealtimeHR() }
        .onChange(of: live.bonded) { _ in refreshLiveSession() }
        .onChange(of: live.connected) { _ in refreshLiveSession() }
        .onChange(of: live.rr) { newRR in
            // LiveState.rr only holds the latest notification's intervals; keep a rolling buffer so the
            // tachogram builds up beat by beat as the user watches.
            rrHistory.append(contentsOf: newRR)
            if rrHistory.count > 40 { rrHistory.removeFirst(rrHistory.count - 40) }
        }
    }

    // MARK: - Connection

    private var connectionRow: some View {
        HStack(spacing: 10) {
            connectionPill
            Spacer()
            if let b = live.batteryPct {
                Label("\(Int(b))%", systemImage: batteryIcon(b))
                    .labelStyle(.titleAndIcon)
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func batteryIcon(_ pct: Double) -> String {
        switch pct {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default:    return "battery.100"
        }
    }

    private var connectionPill: some View {
        // Distinguish a GENUINE encrypted bond from the 5/MG live-HR shortcut that flips `bonded` true
        // over the unbonded standard profile (#69): green "Bonded · streaming" only when encryptedBond,
        // amber "Live HR (not fully paired)" otherwise. The pairingHintBanner below gives the how-to.
        let (label, color): (String, Color) =
            (activeConnection && live.encryptedBond) ? (String(localized: "Bonded · streaming"), StrandPalette.accent)
            : activeConnection ? (String(localized: "Live HR (not fully paired)"), StrandPalette.statusWarning)
            : live.connected ? (String(localized: "Connected"), StrandPalette.statusWarning)
            : live.encryptedBond ? (String(localized: "Paired · idle"), StrandPalette.statusWarning)
            : (String(localized: "Disconnected"), StrandPalette.metricRose)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(StrandPalette.surfaceRaised, in: Capsule())
    }

    // MARK: - Monitor hero (ECG sweep + live BPM)

    private var ecgHero: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 14) {
                ECGWave(color: isLiveHR ? StrandPalette.accent : StrandPalette.textTertiary,
                        flat: displayHR == nil, animate: isLiveHR, bpm: displayHR)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(displayHR.map(String.init) ?? "—")
                        .font(.system(size: 64, weight: .semibold).monospacedDigit())
                        .foregroundStyle(displayHR == nil ? StrandPalette.textTertiary : StrandPalette.accent)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: displayHR)
                    Text("bpm").font(StrandFont.headline).foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 0)
                    Text(isLiveHR ? "live" : "—").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Session tally (beats accruing + beat-to-beat tachogram)

    private var sessionTally: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Beats this session").font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(live.beatsThisSession)")
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(StrandPalette.accent)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: live.beatsThisSession)
                        Image(systemName: "arrow.up").font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
                rrTachogram(rrHistory)
                HStack {
                    Text("Beat to beat").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    Text(rrHistory.last.map { "\($0) ms" } ?? "—")
                        .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textPrimary)
                }
            }
        }
    }

    private func rrTachogram(_ intervals: [Int]) -> some View {
        let recent = Array(intervals.suffix(28))
        return HStack(alignment: .bottom, spacing: 3) {
            if recent.isEmpty {
                Text("Waiting for beats…").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { idx, ms in
                    Capsule()
                        .fill(idx == recent.count - 1 ? StrandPalette.accent
                                                       : StrandPalette.accent.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: rrBarHeight(ms))
                }
            }
        }
        .frame(height: 40, alignment: .bottom)
        .animation(.snappy, value: recent.count)
    }

    private func rrBarHeight(_ ms: Int) -> CGFloat {
        let lo = 400.0, hi = 1400.0
        let f = min(1, max(0, (Double(ms) - lo) / (hi - lo)))
        return 8 + CGFloat(f) * 30
    }

    // MARK: - Signal lists (honest: what's live now vs. what arrives on the next sync)

    private var liveSignals: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Capturing live")
            signalRow(icon: "heart.fill", name: String(localized: "Heart rate"),
                      value: displayHR.map { "\($0) bpm" } ?? "—", isLive: isLiveHR)
            rowDivider
            signalRow(icon: "waveform.path.ecg", name: String(localized: "Variability (R-R)"),
                      value: rrHistory.last.map { "\($0) ms" } ?? "—", isLive: isLiveHR)
        }
    }

    private var syncSignals: some View {
        let ago = live.lastSyncedAt.map { relativeAgo($0) }
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Completes on sync")
            syncRow("drop.fill", String(localized: "Blood oxygen (SpO₂)"), ago)
            rowDivider
            syncRow("thermometer", String(localized: "Skin temperature"), ago)
            rowDivider
            syncRow("lungs.fill", String(localized: "Respiration"), ago)
            rowDivider
            syncRow("figure.walk", String(localized: "Movement"), ago)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(StrandPalette.textSecondary)
            .padding(.bottom, 6)
    }

    private func signalRow(icon: String, name: String, value: String, isLive: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.accent).frame(width: 22)
            Text(name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: 0)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            Circle().fill(isLive ? StrandPalette.accent : StrandPalette.textTertiary)
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 9)
    }

    private func syncRow(_ icon: String, _ name: String, _ ago: String?) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary).frame(width: 22)
            Text(name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
            Text(ago.map { String(localized: "synced \($0)") } ?? String(localized: "not yet"))
                .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Saved footer (the canary: secure pairing + recent sync = everything is saved)

    @ViewBuilder private var savedFooter: some View {
        if activeConnection && live.encryptedBond {
            monitorFooterRow(icon: "checkmark.circle.fill", tint: StrandPalette.accent,
                             text: live.lastSyncedAt.map {
                                String(localized: "Everything saved on your iPhone · synced \(relativeAgo($0))")
                             } ?? String(localized: "Everything saved on your iPhone"))
        } else if activeConnection {
            monitorFooterRow(icon: "exclamationmark.triangle.fill", tint: StrandPalette.statusWarning,
                             text: String(localized: "Live heart rate only — finish secure pairing to save the rest"))
        } else {
            monitorFooterRow(icon: "clock", tint: StrandPalette.textTertiary,
                             text: live.lastSyncedAt.map {
                                String(localized: "Last synced \(relativeAgo($0))")
                             } ?? String(localized: "Not synced yet"))
        }
    }

    private func monitorFooterRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Manual workout

    @ViewBuilder private var workoutSection: some View {
        if let w = model.activeWorkout {
            activeWorkoutCard(w)
        } else {
            if activeConnection {
                Button { model.startWorkout() } label: {
                    Label("Start workout", systemImage: "figure.run")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(StrandPalette.accent)
                .help("Track a workout manually — records heart rate and strain until you end it.")
            }
            if let last = model.lastWorkout {
                workoutSavedRow(last)
            }
        }
    }

    private func activeWorkoutCard(_ w: AppModel.ActiveWorkout) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(StrandPalette.metricRose).frame(width: 8, height: 8)
                    Text("RECORDING WORKOUT").font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking).foregroundStyle(StrandPalette.metricRose)
                    Spacer()
                    // Re-render once a second so the elapsed clock ticks without a manual Timer.
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.elapsed(since: w.start)).font(StrandFont.headline).monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                HStack(spacing: NoopMetrics.gap) {
                    workoutStat("HR", model.bpm.map { "\($0)" } ?? "—")
                    workoutStat("Avg", w.avgHr > 0 ? "\(w.avgHr)" : "—")
                    workoutStat("Peak", w.peakHr > 0 ? "\(w.peakHr)" : "—")
                    workoutStat("Strain", String(format: "%.1f", w.liveStrain))
                }
                Button(role: .destructive) { model.endWorkout() } label: {
                    Label("End workout", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(StrandPalette.metricRose)
            }
        }
    }

    private func workoutStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(value).font(StrandFont.headline).monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutSavedRow(_ row: WorkoutRow) -> some View {
        let mins = Int((row.durationS ?? 0) / 60)
        let parts = ["\(mins) min", row.avgHr.map { "\($0) avg bpm" },
                     row.strain.map { String(format: "strain %.1f", $0) }].compactMap { $0 }
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(StrandPalette.accent)
            Text("Workout saved · \(parts.joined(separator: " · "))")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private static func elapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func reconnectGuideBanner(_ guide: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Can't connect — your strap's pairing was reset")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(guide)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(StrandPalette.statusWarning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reconnect help: \(guide)")
    }

    private func pairingHintBanner(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(StrandPalette.statusWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live HR works — free the strap to unlock buzz, alarms & sync")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                Text(hint)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(StrandPalette.statusWarning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pairing help: \(hint)")
    }

    // MARK: - Strap picker

    /// Pick the strap family to scan for. Switching the selection drops the current strap's bond so the
    /// newly-picked one connects fresh — letting a user move between a WHOOP 4 and a 5/MG.
    private var modelPicker: some View {
        HStack(spacing: 10) {
            Text("Strap").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
            SegmentedPillControl(
                WhoopModel.allCases,
                selection: Binding(
                    get: { selectedModel },
                    set: { newModel in
                        guard newModel.rawValue != selectedModelRaw else { return }
                        selectedModelRaw = newModel.rawValue
                        // Clear the previous strap's sticky bond/connection so the next scan targets the
                        // new family's service and bonds it fresh.
                        model.prepareStrapSwitch()
                    }
                ),
                label: { $0.displayName }
            )
            Spacer()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button { model.scan(model: selectedModel) } label: {
                Label(live.connected ? "Re-scan" : "Scan & Connect",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(StrandPalette.accent)

            Button { model.buzz() } label: {
                Label("Buzz strap", systemImage: "waveform.path")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).tint(StrandPalette.accent)
            .disabled(!activeConnection)
            .help("Fire a test haptic buzz on the strap (requires an active strap connection)")

            Button(role: .destructive) { model.disconnect() } label: {
                Label("Disconnect", systemImage: "xmark.circle")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .disabled(!live.connected)
        }
    }

    private func refreshLiveSession() {
        guard activeConnection else { return }
        model.startRealtimeHR()
        model.getBattery()
    }

    // MARK: - Strap log

    private var logCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("STRAP LOG").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer()
                    // Export the log so people can attach it to a bug report (issue #17 — macOS users
                    // had no way to share it). Copy → clipboard; Save… → a .txt file.
                    Button("Copy") { copyStrapLog() }
                        .buttonStyle(.plain).font(StrandFont.mono).foregroundStyle(StrandPalette.accent)
                    Button("Save…") { saveStrapLog() }
                        .buttonStyle(.plain).font(StrandFont.mono).foregroundStyle(StrandPalette.accent)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(live.log.enumerated()), id: \.offset) { idx, line in
                                Text(line).font(StrandFont.mono)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                        }
                    }
                    .frame(height: 200)
                    .onChange(of: live.log.count) { _ in
                        if let last = live.log.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Strap-log export (issue #17 — let macOS users share the log for bug reports)

    private func strapLogText() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        #if os(iOS)
        let osName = "iOS"
        #else
        let osName = "macOS"
        #endif
        let header = "NOOP strap log — \(osName)\nApp: \(v)\n\(osName): "
            + ProcessInfo.processInfo.operatingSystemVersionString + "\n"
            + String(repeating: "-", count: 40) + "\n"
        return header + live.log.joined(separator: "\n")
    }

    private func copyStrapLog() {
        PlatformPasteboard.copy(strapLogText())
    }

    private func saveStrapLog() {
        FileExport.exportText(strapLogText(), suggestedName: "noop-strap-log.txt")
    }
}
