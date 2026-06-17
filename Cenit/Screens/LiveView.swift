import SwiftUI
import StrandDesign
import WhoopStore

/// Live — the connected strap in real time, in the light «Instrumento diurno» language. Designed to
/// read as a single **sheet** (FER-190): everything fits one view, no scrolling on a standard iPhone
/// (a `ScrollView` only graceful-degrades on small screens / large Dynamic Type). Warm paper, ink
/// labels, colour ONLY in the datum (HR / ECG / beats in `dataHeart`; the "live" + "saved" indicators
/// in `dataRecovery`). A pure monitor — no strap management, no battery, no strain, no workout.
///
/// The big move (FER-190): the old three sections — "Capturing live", "Completes on sync" and the
/// stored-count receipt — collapse into ONE "Signals" list. Each row tells a sensor's whole story:
/// its live value or sync state AND its stored count. Two labelled sub-groups keep the honest
/// live-now-vs-arrives-on-sync distinction.
///
/// The theme is passed in explicitly: it does NOT propagate through `.sheet`'s fresh environment, so
/// the caller (TodayView's beat-by-beat sheet) hands its by-the-hour theme in.
struct LiveView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    @EnvironmentObject private var repo: Repository

    /// The active «Instrumento diurno» theme, passed from the presenter (does not propagate through
    /// `.sheet`). Defaults to `.base` for the standalone (tab) mount.
    var theme: InstrumentoTheme = .base

    /// Presented from Today's "beat by beat" sheet. Only tweaks the top inset (the sheet supplies the
    /// grabber); the layout is otherwise identical to the standalone (tab) mount.
    var monitorOnly: Bool = false

    /// Smoothed, spike-filtered live HR from AppModel (median over a short window).
    private var displayHR: Int? { model.bpm }
    private var activeConnection: Bool { live.connected && live.bonded }
    /// True when a live HR is actually streaming from a worn strap — drives the ECG monitor sweep.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }
    /// Rolling beat-to-beat buffer (last ~40 R-R intervals) so the tachogram builds as beats arrive.
    @State private var rrHistory: [Int] = []
    /// Stored raw-sample counts (on-disk proof), merged into the Signals rows. Re-queried as new data
    /// flushes (live.hrFlushSeq) so the counts climb live.
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
    /// Fixed widths for the two right-hand signal columns so rows AND the per-group column headers
    /// line up (FER-192): the status/sync column and the stored-count column.
    private static let statusColW: CGFloat = 76
    private static let countColW: CGFloat = 58

    var body: some View {
        ScrollView {
            // One sheet: header → hero → signals → coverage → saved footer. Tight rhythm so it all
            // fits without scrolling on a standard iPhone; the ScrollView only kicks in on small
            // screens / large Dynamic Type.
            VStack(alignment: .leading, spacing: 18) {
                header
                // Can't-connect-at-all guidance: the strap wiped its bond (firmware update / WHOOP app
                // re-bond), so connects loop on "Peer removed pairing information".
                if let guide = live.reconnectGuide { reconnectGuideBanner(guide) }
                // Bond-refused guidance: a 5/MG strap still bonded to the WHOOP app refuses pairing.
                if let hint = live.pairingHint { pairingHintBanner(hint) }
                if live.connected {
                    hero
                    signalsSection
                    coverageStrip
                    savedFooter
                } else {
                    // No live connection: a single "Connect" CTA, not a management panel — no dead end.
                    disconnectedState
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            // Breathing room below the sheet's grabber so the title isn't cramped against it (FER-192).
            .padding(.top, monitorOnly ? 28 : 18)
            .padding(.bottom, NoopMetrics.screenPadding)
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

    // MARK: - Header (title + connection pill)

    private var header: some View {
        HStack(alignment: .center) {
            Text("Live").font(StrandFont.title1).foregroundStyle(theme.ink)
            Spacer()
            connectionPill
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
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Monitor hero (ECG sweep + live BPM + session beats + tachogram)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            ECGWave(color: isLiveHR ? theme.dataHeart : theme.inkTertiary,
                    flat: displayHR == nil, animate: isLiveHR, bpm: displayHR)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayHR.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .semibold).monospacedDigit())
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
            // Session beats (accruing) + the beat-to-beat tachogram, in one compact line.
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Text("\(live.beatsThisSession)")
                        .font(StrandFont.captionNumber).foregroundStyle(theme.dataHeart)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: live.beatsThisSession)
                    Image(systemName: "arrow.up").font(StrandFont.caption).foregroundStyle(theme.dataHeart)
                    Text("beats").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .fixedSize()
                rrTachogram(rrHistory)
            }
        }
    }

    private func rrTachogram(_ intervals: [Int]) -> some View {
        let recent = Array(intervals.suffix(28))
        return HStack(alignment: .bottom, spacing: 3) {
            if recent.isEmpty {
                Text("Waiting for beats…").font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        .frame(height: 24, alignment: .bottom)
        .animation(.snappy, value: recent.count)
    }

    private func rrBarHeight(_ ms: Int) -> CGFloat {
        let lo = 400.0, hi = 1400.0
        let f = min(1, max(0, (Double(ms) - lo) / (hi - lo)))
        return 6 + CGFloat(f) * 18
    }

    // MARK: - Signals (the merge: live state + sync state + stored count, in two labelled groups)

    private var signalsSection: some View {
        let c = receipt?.counts
        let ago = live.lastSyncedAt.map { relativeAgo($0) }
        return VStack(alignment: .leading, spacing: 0) {
            // Live group: the value column explains itself (84 bpm); only the count column needs a key.
            groupHeader("Capturing live", statusKey: nil, countKey: "records")
            signalRow(icon: "heart.fill", name: "Heart rate",
                      status: displayHR.map { "\($0) bpm" } ?? "—", stored: c?.hr ?? 0, isLive: isLiveHR)
            rowDivider
            signalRow(icon: "waveform.path.ecg", name: "Variability (R-R)",
                      status: rrHistory.last.map { "\($0) ms" } ?? "—", stored: c?.rr ?? 0, isLive: isLiveHR)

            // Sync group: the time column is "when last saved", so key it "saved"; count keyed "records".
            groupHeader("Completes on sync", statusKey: "saved", countKey: "records").padding(.top, 12)
            syncRow(icon: "drop.fill", name: "Blood oxygen (SpO₂)", stored: c?.spo2 ?? 0, ago: ago)
            rowDivider
            syncRow(icon: "thermometer", name: "Skin temperature", stored: c?.skinTemp ?? 0, ago: ago)
            rowDivider
            syncRow(icon: "lungs.fill", name: "Respiration", stored: c?.resp ?? 0, ago: ago)
            rowDivider
            syncRow(icon: "figure.walk", name: "Movement", stored: c?.gravity ?? 0, ago: ago)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 0.5)
    }

    /// A group's overline label plus right-aligned column keys, aligned over the fixed-width status and
    /// count columns of the rows below. `statusKey` is nil for the live group (its value is self-evident).
    private func groupHeader(_ label: LocalizedStringKey, statusKey: LocalizedStringKey?, countKey: LocalizedStringKey) -> some View {
        HStack(spacing: 9) {
            Text(label).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 6)
            colKey(statusKey).frame(width: Self.statusColW, alignment: .trailing)
            colKey(countKey).frame(width: Self.countColW, alignment: .trailing)
            Color.clear.frame(width: 7, height: 1)   // aligns with the row's status dot
        }
        .padding(.bottom, 5)
    }

    @ViewBuilder private func colKey(_ text: LocalizedStringKey?) -> some View {
        if let text {
            Text(text).font(.system(size: 10, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
                .lineLimit(1)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// A live signal (HR / R-R): name · live value · stored count · green-when-live dot.
    private func signalRow(icon: String, name: LocalizedStringKey, status: String, stored: Int, isLive: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary).frame(width: 20)
            Text(name).font(StrandFont.subhead).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            Text(status).font(StrandFont.captionNumber).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: Self.statusColW, alignment: .trailing)
            storedCount(stored)
            Circle().fill(isLive ? theme.dataRecovery : theme.inkTertiary).frame(width: 7, height: 7)
        }
        .padding(.vertical, 8)
    }

    /// A sync-only signal (SpO₂ / temp / respiration / movement): name · sync freshness · stored
    /// count · grey dot. Honest: only claims "synced" when this stream actually has stored rows.
    private func syncRow(icon: String, name: LocalizedStringKey, stored: Int, ago: String?) -> some View {
        let syncedAgo = stored > 0 ? ago : nil
        return HStack(spacing: 9) {
            Image(systemName: icon).font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary).frame(width: 20)
            Text(name).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            Text(syncedAgo ?? String(localized: "not yet"))
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: Self.statusColW, alignment: .trailing)
            storedCount(stored)
            Circle().fill(theme.inkTertiary).frame(width: 7, height: 7)
        }
        .padding(.vertical, 8)
    }

    /// The stored-sample count (the on-disk "receipt"), right-aligned in its fixed column. "—" when a
    /// stream hasn't landed anything yet, instead of an alarming "0".
    @ViewBuilder private func storedCount(_ n: Int) -> some View {
        Group {
            if n > 0 {
                Text(n, format: .number)
                    .contentTransition(.numericText()).animation(.snappy, value: n)
            } else {
                Text("—")
            }
        }
        .font(StrandFont.caption).monospacedDigit().foregroundStyle(theme.inkTertiary)
        .lineLimit(1).minimumScaleFactor(0.7)
        .frame(width: Self.countColW, alignment: .trailing)
    }

    // MARK: - Coverage (recent day-by-day continuity)

    @ViewBuilder private var coverageStrip: some View {
        let cov = recentCoverage
        if !cov.isEmpty {
            let gaps = cov.filter { !$0 }.count
            HStack(spacing: 10) {
                HStack(alignment: .bottom, spacing: 1.5) {
                    ForEach(Array(cov.enumerated()), id: \.offset) { _, has in
                        Capsule().fill(has ? theme.dataRecovery : theme.hairline)
                            .frame(maxWidth: .infinity).frame(height: 12)
                    }
                }
                Text(gaps == 0 ? "Continuous · last \(cov.count) days"
                               : "\(gaps) gaps · last \(cov.count) days")
                    .font(StrandFont.caption)
                    .foregroundStyle(gaps == 0 ? theme.inkTertiary : theme.warning)
                    .fixedSize()
            }
        }
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

    // MARK: - Saved footer (iconographic: iPhone + iCloud chips, plus Verify)

    @ViewBuilder private var savedFooter: some View {
        if activeConnection && live.encryptedBond {
            // Happy path: compact chips (saved-on-iPhone + iCloud backup) + Verify.
            HStack(spacing: 8) {
                savedChip(icon: "iphone", tint: theme.dataRecovery,
                          text: live.lastSyncedAt.map { relativeAgo($0) } ?? String(localized: "saved"))
                if let backupAgo = lastBackupAgo {
                    savedChip(icon: "checkmark.icloud", tint: theme.inkTertiary, text: backupAgo)
                }
                Spacer(minLength: 0)
                verifyButton
            }
        } else if activeConnection {
            // Bonded but not encrypted: only live HR is being saved — say so honestly.
            footerLine(icon: "exclamationmark.triangle.fill", tint: theme.warning,
                       text: String(localized: "Live heart rate only — finish secure pairing to save the rest"))
        } else {
            // Connected but not bonded (5/MG live-HR shortcut): show the last sync time.
            footerLine(icon: "clock", tint: theme.inkTertiary,
                       text: live.lastSyncedAt.map {
                            String(localized: "Last synced \(relativeAgo($0))")
                       } ?? String(localized: "Not synced yet"))
        }
    }

    private func savedChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(StrandFont.caption).foregroundStyle(tint)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func footerLine(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(StrandFont.caption).foregroundStyle(tint)
            Text(text).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var verifyButton: some View {
        Button { runVerify() } label: {
            HStack(spacing: 5) {
                if verifying {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: verifyOK == nil ? "checkmark.shield"
                          : (verifyOK == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                }
                Text("Verify").lineLimit(1)
            }
            .font(StrandFont.caption).fontWeight(.medium)
            .foregroundStyle(verifyOK == false ? theme.warning
                             : (verifyOK == true ? theme.dataRecovery : theme.ink))
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(verifying)
        .accessibilityLabel("Verify my data")
    }

    private func runVerify() {
        verifying = true; verifyOK = nil
        Task { let ok = await repo.verifyIntegrity(); verifying = false; verifyOK = ok }
    }

    /// iCloud auto-backup relative time, read straight from UserDefaults — the `AutoBackup` env object
    /// is NOT injected on macOS and this view is shared, so reading the keys avoids a crash. nil when
    /// no destination/date is set (then no iCloud chip shows).
    private var lastBackupAgo: String? {
        let d = UserDefaults.standard
        guard d.string(forKey: "noop.autoBackup.folderName") != nil,
              let t = d.object(forKey: "noop.autoBackup.lastDate") as? Double else { return nil }
        return relativeAgo(t)
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
