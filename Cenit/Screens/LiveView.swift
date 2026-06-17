import SwiftUI
import StrandDesign
import WhoopStore

/// Live — the connected strap in real time, in the light «Instrumento diurno» language (FER-181):
/// warm paper, ink labels, and colour ONLY in the datum (heart rate / ECG / beats in `dataHeart`;
/// the "live" + "saved" indicators in `dataRecovery`). It is a pure monitor — strap management
/// (model picker, scan/buzz/disconnect, the frame log) and the strain readout were removed; the
/// only action it carries is a single "Connect" CTA in the disconnected state. Strap management
/// lives in Settings; strain lives on Today.
///
/// The theme is passed in explicitly: it does NOT propagate through `.fullScreenCover`/`.sheet`'s
/// fresh environment, so the caller (TodayView's beat-by-beat cover) hands its by-the-hour theme in.
struct LiveView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository

    /// The active «Instrumento diurno» theme, passed from the presenter (does not propagate through
    /// `.fullScreenCover`/`.sheet`). Defaults to `.base` for the standalone (tab) mount.
    var theme: InstrumentoTheme = .base

    /// When true, render only the live monitor (through the data receipt) and omit the manual-workout
    /// card. The Today calibration cover presents the monitor this way; the standalone mount keeps it.
    var monitorOnly: Bool = false

    /// Smoothed, spike-filtered live HR from AppModel (median over a short window).
    private var displayHR: Int? { model.bpm }
    private var activeConnection: Bool { live.connected && live.bonded }
    /// True when a live HR is actually streaming from a worn strap — drives the ECG monitor sweep.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }
    /// Rolling beat-to-beat buffer (last ~40 R-R intervals) so the tachogram builds as beats arrive.
    @State private var rrHistory: [Int] = []
    /// Stored raw-sample counts (on-disk proof), shown at the very bottom of the monitor. Re-queried
    /// as new data flushes (live.hrFlushSeq) so the user watches the numbers climb.
    private typealias Receipt = (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)
    @State private var receipt: Receipt? = nil
    /// "Verify my data" (PRAGMA integrity_check) button state.
    @State private var verifying = false
    @State private var verifyOK: Bool? = nil
    /// Day-key parser for the coverage strip, en_US_POSIX so it matches `DailyMetric.day`.
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    /// How many recent calendar days the coverage strip shows.
    private static let coverageWindow = 28

    var body: some View {
        ScrollView {
            // Tighter section rhythm in the monitor cover so the whole instrument fits one screen;
            // the standalone mount keeps the standard sectionGap.
            VStack(alignment: .leading, spacing: monitorOnly ? 16 : NoopMetrics.sectionGap) {
                header
                connectionRow
                // Can't-connect-at-all guidance: the strap wiped its bond (firmware update / WHOOP app
                // re-bond), so connects loop on "Peer removed pairing information". Show the re-pair steps
                // right here instead of silently retrying. (5/MG firmware reset, 2026-06)
                if let guide = live.reconnectGuide { reconnectGuideBanner(guide) }
                // Bond-refused guidance: a 5/MG strap still bonded to the WHOOP app refuses pairing with
                // "Encryption is insufficient" — this tells the user to free it and re-pair.
                if let hint = live.pairingHint { pairingHintBanner(hint) }
                if live.connected {
                    ecgHero
                    sessionTally
                    liveSignals
                    syncSignals
                    savedFooter
                    // The data receipt — the strap's raw streams as stored counts you can watch climb,
                    // right under the "saved" footer as its proof. Only once something has actually landed.
                    if let r = receipt,
                       r.counts.hr + r.counts.rr + r.counts.spo2 + r.counts.skinTemp + r.counts.resp + r.counts.gravity > 0 {
                        receiptSection(r)
                    }
                } else {
                    // No live connection: a single "Connect" CTA, not a management panel — no dead end.
                    disconnectedState
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        .onAppear { refreshLiveSession() }
        .onDisappear { model.stopRealtimeHR() }
        .onChange(of: live.bonded) { refreshLiveSession() }
        .onChange(of: live.connected) { refreshLiveSession() }
        .onChange(of: live.rr) { _, newRR in
            // LiveState.rr only holds the latest notification's intervals; keep a rolling buffer so the
            // tachogram builds up beat by beat as the user watches.
            rrHistory.append(contentsOf: newRR)
            if rrHistory.count > 40 { rrHistory.removeFirst(rrHistory.count - 40) }
        }
        .task { receipt = await repo.dataReceipt() }
        .onChange(of: live.hrFlushSeq) {
            // A standard-HR flush just committed to SQLite → re-query so the stored counts climb live.
            Task { receipt = await repo.dataReceipt() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live").font(StrandFont.title1).foregroundStyle(theme.ink)
            if !monitorOnly {
                Text("Your strap in real time — heart rate and frames as they arrive.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// The «Instrumento» surface panel — a quiet warm-paper card with a hairline rule. Replaces the
    /// dark `NoopCard`; used sparingly for the few grouped instruments (ECG hero, session tally).
    @ViewBuilder
    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Connection (info only — management & battery live in Settings)

    private var connectionRow: some View {
        HStack(spacing: 10) {
            connectionPill
            Spacer()
        }
    }

    private var connectionPill: some View {
        // Distinguish a GENUINE encrypted bond from the 5/MG live-HR shortcut that flips `bonded` true
        // over the unbonded standard profile (#69): green "Bonded · streaming" only when encryptedBond,
        // warning otherwise; brick-red when disconnected.
        let (label, color): (String, Color) =
            (activeConnection && live.encryptedBond) ? (String(localized: "Bonded · streaming"), theme.dataRecovery)
            : activeConnection ? (String(localized: "Live HR (not fully paired)"), theme.warning)
            : live.connected ? (String(localized: "Connected"), theme.warning)
            : live.encryptedBond ? (String(localized: "Paired · idle"), theme.warning)
            : (String(localized: "Disconnected"), theme.critical)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(StrandFont.subhead).foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Monitor hero (ECG sweep + live BPM)

    private var ecgHero: some View {
        panel {
            VStack(alignment: .leading, spacing: 14) {
                ECGWave(color: isLiveHR ? theme.dataHeart : theme.inkTertiary,
                        flat: displayHR == nil, animate: isLiveHR, bpm: displayHR)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(displayHR.map(String.init) ?? "—")
                        .font(.system(size: 64, weight: .semibold).monospacedDigit())
                        .foregroundStyle(displayHR == nil ? theme.inkTertiary : theme.dataHeart)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: displayHR)
                    Text("bpm").font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 0)
                    if isLiveHR {
                        HStack(spacing: 4) {
                            Circle().fill(theme.dataRecovery).frame(width: 6, height: 6)
                            Text("live").font(StrandFont.caption).foregroundStyle(theme.dataRecovery)
                        }
                    } else {
                        Text("—").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Session tally (beats accruing + beat-to-beat tachogram)

    private var sessionTally: some View {
        panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Beats this session").font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(live.beatsThisSession)")
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(theme.dataHeart)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: live.beatsThisSession)
                        Image(systemName: "arrow.up").font(StrandFont.caption)
                            .foregroundStyle(theme.dataHeart)
                    }
                }
                rrTachogram(rrHistory)
                HStack {
                    Text("Beat to beat").font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(rrHistory.last.map { "\($0) ms" } ?? "—")
                        .font(StrandFont.captionNumber).foregroundStyle(theme.ink)
                }
            }
        }
    }

    private func rrTachogram(_ intervals: [Int]) -> some View {
        let recent = Array(intervals.suffix(28))
        return HStack(alignment: .bottom, spacing: 3) {
            if recent.isEmpty {
                Text("Waiting for beats…").font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { idx, ms in
                    Capsule()
                        .fill(idx == recent.count - 1 ? theme.dataHeart
                                                       : theme.dataHeart.opacity(0.45))
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
        let c = receipt?.counts
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Completes on sync")
            syncRow("drop.fill", String(localized: "Blood oxygen (SpO₂)"), stored: c?.spo2 ?? 0, ago: ago)
            rowDivider
            syncRow("thermometer", String(localized: "Skin temperature"), stored: c?.skinTemp ?? 0, ago: ago)
            rowDivider
            syncRow("lungs.fill", String(localized: "Respiration"), stored: c?.resp ?? 0, ago: ago)
            rowDivider
            syncRow("figure.walk", String(localized: "Movement"), stored: c?.gravity ?? 0, ago: ago)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 0.5)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
            .foregroundStyle(theme.inkSecondary)
            .padding(.bottom, 6)
    }

    private func signalRow(icon: String, name: String, value: String, isLive: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary).frame(width: 22)
            Text(name).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            Text(value).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
            Circle().fill(isLive ? theme.dataRecovery : theme.inkTertiary)
                .frame(width: 7, height: 7)
        }
        .padding(.vertical, 9)
    }

    private func syncRow(_ icon: String, _ name: String, stored: Int, ago: String?) -> some View {
        // Honest: the global last-sync time only means THIS stream arrived if it actually has rows.
        // A stream with 0 stored is still pending — it never claims "synced" just because a sync ran.
        let syncedAgo = stored > 0 ? ago : nil
        return HStack(spacing: 11) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary).frame(width: 22)
            Text(name).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 0)
            Text(syncedAgo.map { String(localized: "synced \($0)") } ?? String(localized: "not yet"))
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Saved footer (the canary: secure pairing + recent sync = everything is saved)

    @ViewBuilder private var savedFooter: some View {
        if activeConnection && live.encryptedBond {
            monitorFooterRow(icon: "checkmark.circle.fill", tint: theme.dataRecovery,
                             text: live.lastSyncedAt.map {
                                String(localized: "Everything saved on your iPhone · synced \(relativeAgo($0))")
                             } ?? String(localized: "Everything saved on your iPhone"))
        } else if activeConnection {
            monitorFooterRow(icon: "exclamationmark.triangle.fill", tint: theme.warning,
                             text: String(localized: "Live heart rate only — finish secure pairing to save the rest"))
        } else {
            monitorFooterRow(icon: "clock", tint: theme.inkTertiary,
                             text: live.lastSyncedAt.map {
                                String(localized: "Last synced \(relativeAgo($0))")
                             } ?? String(localized: "Not synced yet"))
        }
    }

    private func monitorFooterRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Data receipt (stored-sample counts as on-disk proof, under the saved footer)

    @ViewBuilder
    private func receiptSection(_ r: Receipt) -> some View {
        let c = r.counts
        let cov = recentCoverage
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                receiptCount("Heart rate", c.hr)
                receiptCount("Variability (R-R)", c.rr)
                receiptCount("Blood oxygen (SpO₂)", c.spo2)
                receiptCount("Skin temperature", c.skinTemp)
                receiptCount("Respiration", c.resp)
                receiptCount("Movement", c.gravity)
            }
            // Coverage — recent day-by-day continuity, so a night that never synced shows as a gap.
            if !cov.isEmpty {
                let gaps = cov.filter { !$0 }.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(cov.enumerated()), id: \.offset) { _, has in
                            Capsule()
                                .fill(has ? theme.dataRecovery : theme.hairline)
                                .frame(maxWidth: .infinity).frame(height: 16)
                        }
                    }
                    Text(gaps == 0 ? "Continuous · last \(cov.count) days"
                                   : "\(gaps) gaps · last \(cov.count) days")
                        .font(StrandFont.caption)
                        .foregroundStyle(gaps == 0 ? theme.inkTertiary : theme.warning)
                }
            }
            // iCloud backup, when armed. (The "nights stored" line moved out — it's shown elsewhere.)
            if let backup = lastBackupText {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.icloud")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    Text(backup).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            verifyRow
        }
    }

    private func receiptCount(_ label: LocalizedStringKey, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            if n > 0 {
                Text(n, format: .number)
                    .font(StrandFont.number(19, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(theme.ink)
                    .contentTransition(.numericText()).animation(.snappy, value: n)
            } else {
                // Nothing stored yet for this stream (e.g. an offload-only sensor before its first
                // sync) — a muted "—" instead of an alarming "0".
                Text("—")
                    .font(StrandFont.number(19, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// Present/absent flags for the last `coverageWindow` calendar days ending at the most recent
    /// stored day — a missing night (one that never synced) shows as a gap. Bounded + cheap.
    private var recentCoverage: [Bool] {
        guard let lastKey = repo.days.last?.day, let last = Self.dayFmt.date(from: lastKey) else { return [] }
        let keys = Set(repo.days.suffix(Self.coverageWindow * 2).map(\.day))
        let cal = Calendar.current
        return (0..<Self.coverageWindow).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: last).map { keys.contains(Self.dayFmt.string(from: $0)) }
        }
    }

    /// iCloud auto-backup status, read straight from UserDefaults — the `AutoBackup` env object is
    /// NOT injected on macOS and this view is shared, so reading the keys avoids a crash. nil when no
    /// destination/date is set (then no backup line shows).
    private var lastBackupText: String? {
        let d = UserDefaults.standard
        guard d.string(forKey: "noop.autoBackup.folderName") != nil,
              let t = d.object(forKey: "noop.autoBackup.lastDate") as? Double else { return nil }
        return String(localized: "Backed up to iCloud \(relativeAgo(t))")
    }

    @ViewBuilder private var verifyRow: some View {
        HStack(spacing: 10) {
            Button {
                verifying = true; verifyOK = nil
                Task { let ok = await repo.verifyIntegrity(); verifying = false; verifyOK = ok }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield")
                    Text("Verify my data")
                }
                .font(StrandFont.subhead).fontWeight(.medium)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(verifying)
            if verifying {
                ProgressView().controlSize(.small)
                Text("Checking…").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            } else if let ok = verifyOK {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(StrandFont.caption)
                    .foregroundStyle(ok ? theme.dataRecovery : theme.warning)
                Text(ok ? "Everything checks out" : "Check failed — try a re-sync")
                    .font(StrandFont.caption)
                    .foregroundStyle(ok ? theme.inkSecondary : theme.warning)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Disconnected state (single CTA, never a dead end)

    private var disconnectedState: some View {
        VStack(spacing: 18) {
            ECGWave(color: theme.inkTertiary, flat: true, animate: false, bpm: nil)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            VStack(spacing: 8) {
                Text("Connect your strap to see it live")
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                Text("The monitor beats in real time when your WHOOP is nearby and worn.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            connectButton
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The one action Live carries: connect using the strap model the user already picked (persisted
    /// under "selectedWhoopModel"). Ink-filled — a strong but colourless primary (colour stays on data).
    private var connectButton: some View {
        Button { model.scan() } label: {
            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                .font(StrandFont.headline)
                .foregroundStyle(theme.paper)
                .padding(.horizontal, 30).padding(.vertical, 13)
                .background(theme.ink, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reconnect / pairing guidance banners

    private func reconnectGuideBanner(_ guide: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Can't connect — your strap's pairing was reset")
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text(guide)
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(theme.warning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reconnect help: \(guide)")
    }

    private func pairingHintBanner(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live HR works — free the strap to unlock buzz, alarms & sync")
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text(hint)
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(theme.warning.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pairing help: \(hint)")
    }

    private func refreshLiveSession() {
        guard activeConnection else { return }
        model.startRealtimeHR()
        model.getBattery()
    }
}
