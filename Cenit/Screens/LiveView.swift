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
    @Environment(LiveState.self) private var live
    @EnvironmentObject private var repo: Repository
    /// Drives the release/re-arm of the heavy R10/R11 realtime stream around backgrounding (FER-636):
    /// `onDisappear` doesn't fire when the app backgrounds with this sheet still open, so without this
    /// the strap floods live HR (~2/s) 24/7 until the user returns and swipes the sheet away.
    @Environment(\.scenePhase) private var scenePhase

    /// The active «Instrumento diurno» theme, passed from the presenter (does not propagate through
    /// `.sheet`). Defaults to `.base` for the standalone (tab) mount.
    var theme: InstrumentoTheme = .base

    /// Presented from Today's "beat by beat" sheet. Only tweaks the top inset (the sheet supplies the
    /// grabber); the layout is otherwise identical to the standalone (tab) mount.
    var monitorOnly: Bool = false

    /// Smoothed, spike-filtered live HR from AppModel (median over a short window). Blanked to "—"
    /// while reconnecting so the paused monitor doesn't show the stale pre-drop value (FER-195): the
    /// BLE layer doesn't clear `bpm`/`heartRate` on a drop, so the view must mask them itself.
    private var displayHR: Int? { showsReconnecting ? nil : model.bpm }
    private var activeConnection: Bool { live.connected && live.bonded }
    /// True when a live HR is actually streaming from a worn strap — drives the ECG monitor sweep.
    /// False while reconnecting so the "live" dot + sweep don't animate over a dropped link (FER-195).
    private var isLiveHR: Bool { !showsReconnecting && live.heartRate != nil && live.worn }
    /// Inside the post-drop grace window AND no pairing-error guidance is up (FER-195): a live link we
    /// were showing dropped and BLEManager is auto-reconnecting, so the monitor stays mounted-but-paused
    /// under a "Reconnecting…" pill instead of collapsing to the "Connect your strap" CTA. A
    /// reconnect-guide / pairing-hint means the honest disconnected state (with its banner) belongs.
    private var showsReconnecting: Bool {
        isReconnecting && live.reconnectGuide == nil && live.pairingHint == nil
    }
    /// Rolling beat-to-beat buffer (last ~40 R-R intervals) so the tachogram builds as beats arrive.
    @State private var rrHistory: [Int] = []
    /// Stored raw-sample counts (on-disk proof), merged into the Signals rows. Re-queried as new data
    /// flushes (live.hrFlushSeq) so the counts climb live.
    private typealias Receipt = (counts: (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int), latestHRTs: Int?)
    @State private var receipt: Receipt? = nil
    /// "Verify my data" (PRAGMA integrity_check) button state.
    @State private var verifying = false
    @State private var verifyOK: Bool? = nil
    #if os(iOS)
    /// iCloud auto-backup engine, injected at the iOS app root (`CenitApp.swift`). Drives the tappable
    /// iCloud chip in `savedFooter`: tap → back up now, with a busy spinner + error tint. iOS-only — it
    /// isn't injected on macOS (where `lastBackupAgo` just reads UserDefaults). (FER-352)
    @EnvironmentObject private var autoBackup: AutoBackup
    /// Counter trigger for the light háptico fired when the user taps the iCloud chip to back up — the
    /// same declarative `.sensoryFeedback` pattern as TodayView's pull-to-sync (FER-204). (FER-352)
    @State private var backupHaptic = 0
    #endif
    /// Post-drop "Reconnecting…" grace window is active (FER-195). Set when a live link we were showing
    /// flips connected true→false; cleared on reconnect or after `reconnectGraceSeconds`. Drives the
    /// paused monitor + "Reconnecting…" pill via `showsReconnecting`. Presentation-only.
    @State private var isReconnecting = false
    /// Times out the grace window; cancelled if the link returns (or the view disappears) first.
    @State private var reconnectTimeout: Task<Void, Never>? = nil
    /// Measured content height → the sheet detent, so the sheet opens exactly as tall as the content
    /// instead of full-screen with empty space below (FER-196).
    @State private var sheetHeight: CGFloat = 0
    /// Whether the Signals list is expanded. Starts open so the honest live-vs-on-sync story is visible
    /// on first open; the user can fold it to keep the card compact (FER-586).
    @State private var signalsExpanded = true
    /// Cached coverage classification. Depends only on `repo.days`/`appleHealthDays`, so it's
    /// recomputed via `.task(id: repo.refreshSeq)` rather than on every `body` pass — LiveView
    /// re-renders on each live-HR tick, and recomputing `Set(repo.days…)` per tick was wasteful (FER-319).
    @State private var coverageCache = Coverage(perDay: [], strap: 0, apple: 0, none: 0)
    /// How many recent calendar days the coverage strip shows.
    private static let coverageWindow = 28
    /// Fixed widths for the two right-hand signal columns so rows AND the per-group column headers
    /// line up (FER-192): the status/sync column and the stored-count column.
    private static let statusColW: CGFloat = 76
    private static let countColW: CGFloat = 58
    /// How long to keep the monitor paused under "Reconnecting…" before falling back to the manual
    /// "Connect" CTA (FER-195). A live link routinely drops for a few seconds as the strap duty-cycles;
    /// BLEManager auto-reconnects in ~3s, so a short grace window hides the churn without stranding the
    /// user on "Reconnecting…" forever if the strap is genuinely gone.
    private static let reconnectGraceSeconds: UInt64 = 15

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
                if live.connected || showsReconnecting {
                    // Connected — or a live link we were showing just dropped and is mid-reconnect
                    // (FER-195): keep the monitor mounted but paused (HR "—", flat ECG) instead of
                    // flashing the empty "Connect" state on every few-second duty-cycle drop.
                    hero
                    batteryRow
                    signalsSection
                    integritySection
                } else {
                    // No live connection: a single "Connect" CTA, not a management panel — no dead end.
                    disconnectedState
                }
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
            // Breathing room below the sheet's grabber so the title isn't cramped against it (FER-192).
            .padding(.top, monitorOnly ? 28 : 18)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Measure the content height so the sheet detent fits it exactly (FER-196).
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            })
        }
        .background(theme.paper.ignoresSafeArea())
        .instrumentoTheme(theme)
        // Open the sheet exactly as tall as the content (falls back to a sane height before the first
        // measurement; the system caps at the screen and the ScrollView scrolls if content overflows).
        .onPreferenceChange(SheetContentHeightKey.self) { sheetHeight = $0 }
        .presentationDetents([.height(sheetHeight > 0 ? sheetHeight : 640)])
        .onAppear { refreshLiveSession() }
        .onDisappear { model.releaseRealtimeHR("live"); reconnectTimeout?.cancel() }
        // Backgrounding with this sheet still open doesn't fire onDisappear, so the heavy realtime stream
        // would otherwise stay armed and drain the strap (FER-636). Release "live" on background — the
        // ref-count keeps the stream alive if a strength session ("strength") still holds it — and re-arm
        // on return to foreground while the sheet is up. `.inactive` (Control Center / app switcher) is
        // transient, so we leave the stream alone there.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.releaseRealtimeHR("live")
            case .active: refreshLiveSession()
            default: break
            }
        }
        .onChange(of: live.bonded) { refreshLiveSession() }
        .onChange(of: live.connected) { wasConnected, nowConnected in
            refreshLiveSession()
            updateReconnecting(was: wasConnected, now: nowConnected)
        }
        .onReceive(live.pulse.$rr.dropFirst()) { newRR in
            // LiveState.rr only holds the latest notification's intervals; keep a rolling buffer so the
            // tachogram builds up beat by beat as the user watches. onReceive (not onChange): the outer
            // body no longer re-renders per beat, so a render-driven onChange would starve (FER-755).
            rrHistory.append(contentsOf: newRR)
            if rrHistory.count > 40 { rrHistory.removeFirst(rrHistory.count - 40) }
        }
        .task { receipt = await repo.dataReceipt() }
        .task(id: repo.refreshSeq) { coverageCache = computeCoverage() }
        .onChange(of: live.hrFlushSeq) {
            // A standard-HR flush just committed to SQLite → re-query so the stored counts climb live.
            Task { receipt = await repo.dataReceipt() }
        }
    }

    // MARK: - Header (title + connection pill)

    private var header: some View {
        HStack(alignment: .center) {
            Text("Heartbeats").groteskSheetTitle().foregroundStyle(theme.ink)
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
            : showsReconnecting ? (String(localized: "Reconnecting…"), theme.warning)
            : live.encryptedBond ? (String(localized: "Paired · idle"), theme.warning)
            : (String(localized: "Disconnected"), theme.critical)
        // The one live marker: the dot breathes on the shared cadence while a strap is actually
        // streaming (bonded + connected); static otherwise (idle / reconnecting / disconnected). It's
        // the DNA's «punto que respira» (FER-709), auto-static under Reduce Motion.
        return HStack(spacing: 7) {
            BreathingDot(color: color, radius: 4, breathes: activeConnection)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - Monitor hero (ECG sweep + live BPM + session beats + tachogram)

    private var hero: some View {
        // PulseReader: the hero is the one live subtree — it re-evaluates per heartbeat while the
        // rest of the screen (signals, coverage, actions) only re-renders on connection/flush
        // changes (FER-755). The computed vars read through LiveState's forwards, so values are
        // fresh at each pulse-driven render.
        PulseReader(live.pulse) { _ in
        VStack(alignment: .leading, spacing: 10) {
            ECGWave(color: isLiveHR ? theme.dataHeart : theme.inkTertiary,
                    flat: displayHR == nil, lineWidth: 1.8, animate: isLiveHR, bpm: displayHR)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(displayHR.map(String.init) ?? "—")
                    .font(InstrumentoType.groteskLiveBpm)
                    .tracking(InstrumentoType.groteskLiveBpmTracking)
                    .lineLimit(1).minimumScaleFactor(0.6)   // FER-394: never overflow on 375pt
                    .foregroundStyle(displayHR == nil ? theme.inkTertiary : theme.dataHeart)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: displayHR)
                Text("bpm").font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
                // The "live" indicator sits right next to the unit, not floating far right (FER-196).
                if isLiveHR {
                    HStack(spacing: 4) {
                        Circle().fill(theme.dataRecovery).frame(width: 6, height: 6)
                        Text("live").font(StrandFont.caption).foregroundStyle(theme.dataRecovery)
                    }
                    .padding(.leading, 3)
                }
                Spacer(minLength: 0)
            }
            // Session beats (accruing) + the beat-to-beat tachogram, in one compact line.
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Text("\(live.beatsThisSession)")
                        .font(StrandFont.captionNumber).foregroundStyle(theme.dataHeart)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: live.beatsThisSession)
                    StrandIcon.up.image.font(StrandFont.caption).foregroundStyle(theme.dataHeart)
                    Text("beats").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .fixedSize()
                rrTachogram(rrHistory)
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ForEach(Array(recent.enumerated()), id: \.offset) { idx, ms in
                    Capsule()
                        .fill(idx == recent.count - 1 ? theme.dataHeart
                                                       : theme.dataHeart.opacity(0.40)) // token-exempt: alfa exacto de barra viva RR
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

    // MARK: - Strap battery (reuses Today's by-level battery accent)

    /// The strap's battery level, painted with the shared by-level accent — green / amber ≤20 % /
    /// red ≤10 % (`theme.batteryColor`), the same rule as Today's header. Hidden when the level is
    /// unknown so there's no ugly "—". Presentation-only: the value already arrives via
    /// `model.getBattery()` into `live.batteryPct` (FER-586).
    @ViewBuilder private var batteryRow: some View {
        if let pct = live.batteryPct {
            HStack(spacing: 9) {
                // FER-590: la banda es un sensor BLE que transmite, no un Apple Watch — glifo agnóstico.
                Image(systemName: "sensor.tag.radiowave.forward").font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary).frame(width: 20)
                Text("Strap").font(StrandFont.subhead).foregroundStyle(theme.ink)
                Spacer(minLength: 6)
                Image(systemName: batteryIcon(pct: pct, charging: live.charging == true))
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.batteryColor(forLevel: pct))
                Text("\(Int(pct.rounded()))%")
                    .font(StrandFont.captionNumber).monospacedDigit()
                    .foregroundStyle(theme.ink)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(live.charging == true
                ? Text("Strap battery: \(Int(pct.rounded()))%, charging")
                : Text("Strap battery: \(Int(pct.rounded()))%"))
        }
    }

    /// SF Symbol for the battery level. Charging → `battery.100.bolt` (the only battery-with-bolt glyph
    /// SF Symbols actually ships); the bolt says "charging" and the "%" carries the exact level. Same
    /// logic as Today's header (`batteryIcon`).
    private func batteryIcon(pct: Double, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch pct {
        case 75...:   return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default:      return "battery.25"
        }
    }

    // MARK: - Signals (the merge: live state + sync state + stored count, in two labelled groups)

    /// The two signal groups, foldable behind a chevron header (FER-586). Content is unchanged — the
    /// disclosure just lets the card collapse the list to keep the sheet compact.
    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            signalsDisclosureHeader
            if signalsExpanded {
                signalGroups.padding(.top, 4)
            }
        }
    }

    /// Tappable header: a rotating chevron + "Signals", with at-a-glance live / on-sync count chips so
    /// the user sees what's inside even when folded.
    private var signalsDisclosureHeader: some View {
        Button {
            withAnimation(.snappy) { signalsExpanded.toggle() }
        } label: {
            HStack(spacing: 9) {
                StrandIcon.disclosure.image
                    .font(StrandFont.caption).fontWeight(.semibold)
                    .foregroundStyle(theme.inkTertiary)
                    .rotationEffect(.degrees(signalsExpanded ? 90 : 0))
                Text("Signals").font(StrandFont.subhead).foregroundStyle(theme.ink)
                Spacer(minLength: 6)
                signalCountChip(theme.dataRecovery, 2, "live")
                signalCountChip(theme.inkTertiary, 3, "on sync")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Signals"))
        .accessibilityValue(signalsExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private func signalCountChip(_ color: Color, _ count: Int, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)").font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
        }
    }

    private var signalGroups: some View {
        let c = receipt?.counts
        let ago = live.lastSyncedAt.map { relativeAgo($0) }
        let bpm = String(localized: "bpm")   // unit localizes to "lpm" in Spanish (FER-196)
        return VStack(alignment: .leading, spacing: 0) {
            // Only the count column carries a header ("records"); the value/time column explains itself.
            // PulseReader keeps the two live-value rows beating without re-rendering the whole screen.
            groupHeader("Capturing live")
            PulseReader(live.pulse) { _ in
                signalRow(icon: "heart.fill", name: "Heart rate",
                          status: displayHR.map { "\($0) \(bpm)" } ?? "—", stored: c?.hr ?? 0, isLive: isLiveHR)
                rowDivider
                signalRow(icon: "waveform.path.ecg", name: "Variability (R-R)",
                          status: showsReconnecting ? "—" : (rrHistory.last.map { "\($0) ms" } ?? "—"),
                          stored: c?.rr ?? 0, isLive: isLiveHR)
            }

            groupHeader("Completes on sync").padding(.top, 12)
            // SpO₂ is decoded but no longer persisted (FER-511), so it's omitted here rather than
            // showing a perpetual "—"/0 row that reads as a fault.
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

    /// A group's overline label plus the single "records" column key. The key is right-aligned over the
    /// count column but allowed to span the (header-less) status column too, so "REGISTROS" never gets
    /// truncated (FER-196).
    private func groupHeader(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: 9) {
            Text(label).font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 6)
            Text("records").font(.system(size: 10, weight: .medium)).tracking(0.4) // token-exempt: sello 10pt peso/tracking propios
                .textCase(.uppercase).foregroundStyle(theme.inkTertiary).lineLimit(1)
                .frame(width: Self.statusColW + 9 + Self.countColW, alignment: .trailing)
            Color.clear.frame(width: 7, height: 1)   // aligns with the row's trailing dot
        }
        .padding(.bottom, 5)
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

    /// A sync-only signal (temp / respiration / movement): name · sync freshness · stored
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

    // MARK: - Coverage (per-day, broken out by source — reuses the FER-115 classification)

    /// A day's data source over the last `coverageWindow` days: from the strap, Apple-Health-only, or
    /// nothing. Mirrors `DataSourcesView`'s coverage so the two screens agree (FER-196).
    private struct Coverage { let perDay: [Source]; let strap: Int; let apple: Int; let none: Int
        enum Source { case strap, apple, none } }

    private func computeCoverage() -> Coverage {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let allKeys = Set(repo.days.map(\.day))
        let appleKeys = repo.appleHealthDays
        let perDay: [Coverage.Source] = (0..<Self.coverageWindow).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { date in
                let key = Repository.localDayKey(date)
                if appleKeys.contains(key) { return .apple }
                if allKeys.contains(key) { return .strap }
                return .none
            }
        }
        return Coverage(perDay: perDay,
                        strap: perDay.filter { $0 == .strap }.count,
                        apple: perDay.filter { $0 == .apple }.count,
                        none: perDay.filter { $0 == .none }.count)
    }

    /// «Data integrity» — one heading over the 28-day coverage strip AND the saved/Verify footer, which
    /// used to sit apart. Pure regrouping: the coverage and footer logic is untouched (FER-586).
    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data integrity").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkTertiary)
            coverageStrip
            savedFooter
        }
    }

    @ViewBuilder private var coverageStrip: some View {
        let cov = coverageCache
        // Only show once at least one day has data — no alarming all-grey strip on first use.
        if cov.strap + cov.apple > 0 {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 3) {
                    ForEach(Array(cov.perDay.enumerated()), id: \.offset) { _, src in
                        RoundedRectangle(cornerRadius: 2) // token-exempt: geometría de dato
                            .fill(src == .strap ? theme.dataRecovery
                                  : src == .apple ? theme.dataSpO2 : theme.hairlineStrong)
                            .frame(maxWidth: .infinity).frame(height: 10)
                    }
                }
                coverageLegend(cov)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func coverageLegend(_ cov: Coverage) -> some View {
        HStack(spacing: 14) {
            if cov.strap > 0 { legendItem(theme.dataRecovery, "Strap", cov.strap) }
            if cov.apple > 0 { legendItem(theme.dataSpO2, "Apple Health", cov.apple) }
            if cov.none > 0 {
                legendItem(theme.hairlineStrong, "No data", cov.none)
            } else {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(theme.hairlineStrong).frame(width: 9, height: 9) // token-exempt: geometría de dato
                    Text("No gaps").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func legendItem(_ color: Color, _ label: LocalizedStringKey, _ count: Int) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9) // token-exempt: geometría de dato
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            Text("\(count)").font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
    }

    // MARK: - Saved footer (iconographic: iPhone + iCloud chips, plus Verify)

    @ViewBuilder private var savedFooter: some View {
        if activeConnection && live.encryptedBond {
            // Happy path: compact chips (saved-on-iPhone + iCloud backup) + Verify.
            HStack(spacing: 8) {
                savedChip(icon: "iphone", tint: theme.dataRecovery,
                          text: live.lastSyncedAt.map { relativeAgo($0) } ?? String(localized: "saved"))
                iCloudBackupChip
                Spacer(minLength: 0)
                verifyButton
            }
        } else if activeConnection {
            // Bonded but not encrypted: only live HR is being saved — say so honestly.
            footerLine(icon: "exclamationmark.triangle.fill", tint: theme.warning,
                       text: String(localized: "Live heart rate only: finish secure pairing to save the rest"))
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

    /// The iCloud auto-backup chip. On iOS it's a button: tap to back up now (light háptico), showing a
    /// busy spinner while the copy runs and an error tint if it failed — all driven by the `AutoBackup`
    /// engine. Visible only once a folder is chosen AND a prior backup exists (same gate as before:
    /// `lastBackupAgo != nil`); the configuration flow stays in Settings. On other platforms it remains
    /// the passive chip it always was. (FER-352)
    @ViewBuilder private var iCloudBackupChip: some View {
        #if os(iOS)
        if let agoText = lastBackupAgo {
            let isError = autoBackup.lastError != nil && !autoBackup.busy
            Button {
                backupHaptic += 1
                Task { await autoBackup.backupNow(checkpoint: { await repo.checkpointForBackup() }) }
            } label: {
                HStack(spacing: 6) {
                    if autoBackup.busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.icloud")
                            .font(StrandFont.caption)
                            .foregroundStyle(isError ? theme.warning : theme.inkTertiary)
                    }
                    Text(autoBackup.busy ? String(localized: "Backing up…")
                         : (isError ? String(localized: "Couldn't back up") : agoText))
                        .font(StrandFont.caption)
                        .foregroundStyle(isError ? theme.warning : theme.inkSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(autoBackup.busy)
            .sensoryFeedback(.impact(weight: .light), trigger: backupHaptic)
            .accessibilityLabel(autoBackup.busy ? String(localized: "Backing up to iCloud")
                                : (isError ? String(localized: "iCloud backup failed: tap to retry")
                                   : String(localized: "Back up to iCloud now")))
        }
        #else
        if let backupAgo = lastBackupAgo {
            savedChip(icon: "checkmark.icloud", tint: theme.inkTertiary, text: backupAgo)
        }
        #endif
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
            StrandIcon.warning.image
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Can't connect: your strap's pairing was reset")
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text(guide)
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .instrumentoCard(.control, theme: theme, stroke: theme.warning.opacity(0.5)) // token-exempt: stroke ámbar 0.5 (banner de aviso, alfa propio)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reconnect help: \(guide)")
    }

    private func pairingHintBanner(_ hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StrandIcon.warning.image
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live HR works: free the strap to unlock buzz, alarms & sync")
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text(hint)
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .instrumentoCard(.control, theme: theme, stroke: theme.warning.opacity(0.5)) // token-exempt: stroke ámbar 0.5 (banner de aviso, alfa propio)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pairing help: \(hint)")
    }

    private func refreshLiveSession() {
        guard activeConnection else { return }
        model.acquireRealtimeHR("live")
        model.getBattery()
    }

    /// Drive the post-drop "Reconnecting…" grace window (FER-195). When a live link we were showing
    /// drops, keep the monitor paused while BLEManager auto-reconnects — unless it's a genuine pairing
    /// failure (a guide/hint is up), where the honest disconnected state belongs. The window self-clears
    /// on reconnect or after `reconnectGraceSeconds`, falling back to the manual "Connect" CTA.
    private func updateReconnecting(was: Bool, now: Bool) {
        reconnectTimeout?.cancel()
        reconnectTimeout = nil
        if now {
            isReconnecting = false                       // link is back — resume the live monitor
        } else if was, live.reconnectGuide == nil, live.pairingHint == nil {
            isReconnecting = true                        // a live link dropped — pause, don't collapse
            reconnectTimeout = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.reconnectGraceSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                isReconnecting = false                   // gave up waiting — fall back to the CTA
            }
        } else {
            isReconnecting = false                       // dropped with a pairing error — honest disconnect
        }
    }
}
