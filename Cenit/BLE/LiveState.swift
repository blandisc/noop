import Foundation
import Combine

/// Observable snapshot of the live connection + biometric state, driven by FrameRouter
/// (from decoded frames) and BLEManager (from CoreBluetooth callbacks).
/// `@MainActor` so SwiftUI views observe it safely; mutators are called on the main queue.
@MainActor
public final class LiveState: ObservableObject {
    @Published public var connected: Bool = false {
        didSet { if connected && !oldValue { beatsThisSession = 0 } }  // fresh session → zero the live beat tally
    }
    // NOTE: do NOT auto-clear `pairingHint` when `bonded` flips true. On a 5/MG, `bonded` is also set by
    // the live-HR shortcut (BLEManager — HR over the unbonded standard profile), so clearing the hint
    // there hides the still-accurate "free the strap" guidance from users who are streaming HR but never
    // got the real encrypted bond (issue #69). The genuine bond path clears the hint itself (the
    // CLIENT_HELLO ack), and a fresh connect attempt resets it.
    @Published public var bonded: Bool = false
    /// True ONLY when the link reached a GENUINE encrypted bond — the WHOOP 5/MG CLIENT_HELLO ack, the
    /// WHOOP 4 confirmed-write bond, or a restored already-bonded link. Deliberately NOT set by the
    /// live-HR shortcut that flips `bonded` true when HR streams over the *unbonded* standard profile on
    /// a 5/MG (issue #69) — so `bonded` can be true while `encryptedBond` is false ("Live HR, not fully
    /// paired"). WHOOP 4 always reaches a genuine bond, so the two track together there. Reset on
    /// connect/disconnect. Drives the Live pill's two-state distinction; the encrypted channel (buzz,
    /// alarm, double-tap, history offload) only works when this is true.
    @Published public var encryptedBond: Bool = false
    @Published public var heartRate: Int? = nil
    @Published public var rr: [Int] = [] {
        didSet { beatsThisSession += rr.count }  // each notification carries the beats since the last → running session total
    }
    /// Beats captured live this connection session (sum of R-R intervals received). Zeroed on a fresh
    /// connect — drives the Live monitor's "beats this session" tally as the user watches data accrue.
    @Published public var beatsThisSession: Int = 0
    @Published public var batteryPct: Double? = nil
    /// Charging flag from the strap's BATTERY_LEVEL events — wire observation: u8 bit0 in the
    /// event payload (4.0 @26 / 5.0 @30), pushed ~every 8 min on captured links. nil until the
    /// first event of a session; cleared on disconnect so a stale flag can't outlive the link.
    /// Flag ONLY — the battery % keeps its family-specific source (#77).
    @Published public var charging: Bool? = nil
    @Published public var lastFrameType: String? = nil
    @Published public var lastEvent: String? = nil
    /// Wrist-wear state from WRIST_ON/WRIST_OFF events. Defaults true so wear-gated features work
    /// before the first event arrives; flipped by FrameRouter on a real event.
    @Published public var worn: Bool = true
    /// Rolling log of human-readable lines for the on-device verification checklist.
    @Published public var log: [String] = []

    /// Fired (live only) when the strap reports a DOUBLE_TAP gesture. Wired by AppModel to the
    /// user's chosen action. Debounced in AppModel.
    public var onDoubleTap: (() -> Void)?
    /// Fired (live only) when wrist-wear changes (true = put on, false = taken off).
    public var onWristChange: ((Bool) -> Void)?

    /// True when the stuck-strap watchdog finds the strap has newer records than us but our frontier
    /// won't advance (likely needs a manual reboot; ~never after high-freq-sync removal). Banner-only.
    @Published public var strapNeedsReboot = false

    /// Wall time (unix seconds) of the last successfully-completed offload (a sync, even if nothing new
    /// came — i.e. caught up). Drives the sync tile + the staleness nudge.
    @Published public var lastSyncedAt: TimeInterval?

    /// Set when an offload ended abnormally (the idle watchdog fired — the strap went quiet mid-sync),
    /// so a stalled history download isn't silent. Cleared by the next successful HISTORY_COMPLETE.
    /// Process-local on purpose (mirrors Android, ed6a31d): the next connect / 15-min tick re-offloads
    /// anyway, so persisting a stale error across launches would outlive its relevance.
    @Published public var lastSyncError: String? = nil

    /// The strap's own stored-history window (real-unix seconds) from the last `GET_DATA_RANGE`
    /// response — proof the SENSOR captured data and the band still holds it. `oldest`/`newest` are
    /// the min/max plausible-unix markers in that response; both nil until a range response arrives.
    /// Surfaced read-only in the Data Sources sync diagnostic (FER-83).
    @Published public var strapHistoryOldest: TimeInterval?
    @Published public var strapHistoryNewest: TimeInterval?

    /// Per-sensor "data receipt" for the current/last offload session — proof NOOP received, decoded
    /// and stored the strap's history. The per-sensor counts are rows ACTUALLY persisted (from
    /// `StreamStore.insert`'s return, accumulated across chunks); `framesReceived` vs `rowsDecoded`
    /// distinguish "the band had nothing new" (no frames) from "frames arrive but don't decode"
    /// (frames, zero decoded rows — the silent-loss case, #30/#77). Zeroed when a fresh offload begins.
    @Published public var syncReceipt = SyncReceipt()

    /// True once a historical offload has run to completion (HISTORY_COMPLETE) THIS session — so the
    /// sync diagnostic only shows its receipt + verdict after a real sync, not a stale `lastSyncedAt`
    /// restored from a prior launch. Reset when a fresh offload begins (FER-83).
    @Published public var syncCompletedThisSession = false

    /// Accumulated offload receipt. Per-sensor fields mirror the six sensor streams the diagnostic
    /// shows (hr/rr/spo₂/temp/respiration/movement); `framesReceived`/`biometricFrames`/`rowsDecoded`
    /// drive the verdict (see `SyncVerdict`).
    public struct SyncReceipt: Equatable {
        public var hr = 0, rr = 0, spo2 = 0, skinTemp = 0, resp = 0, gravity = 0
        /// Total historical frames fed into chunks this session (proof bytes arrived from the band).
        public var framesReceived = 0
        /// type-47 HISTORICAL_DATA (biometric) frames received this session. Zero with frames > 0 is
        /// the lost-clock case — the band sends CONSOLE_LOGS (type-50) because it stored nothing — and
        /// must NOT be confused with biometry that arrives but won't decode (FER-152).
        public var biometricFrames = 0
        /// Total decoded rows across all six sensor streams this session (proof they decoded).
        public var rowsDecoded = 0
        public init() {}
        /// Rows newly stored across the six sensors this session (the "what landed" total).
        public var rowsStored: Int { hr + rr + spo2 + skinTemp + resp + gravity }
    }

    /// The honest sync verdict the Data Sources diagnostic shows — derived purely from what the offload
    /// observed plus whether `GET_DATA_RANGE` reported a plausible stored-history window. Pure and
    /// exhaustive so the branching is unit-testable without the view (FER-83, FER-152).
    public enum SyncVerdict: Equatable {
        /// No frames arrived — the band had nothing new to offload.
        case nothingNew
        /// Frames arrived but none were biometric (type-47) and the band reports no stored history: it
        /// isn't saving anything because its clock is lost. Action: re-arm via the WHOOP app (FER-93).
        case notStoringClock
        /// Biometric frames (type-47) arrived but decoded to zero rows — the silent-loss case
        /// (CRC / unmapped layout / out-of-range timestamp). Action: report it (#30/#77).
        case arrivesButNoDecode
        /// Frames arrived and decoded — receiving and storing everything.
        case receivingAndStoring

        /// Decide the verdict from the session receipt and whether `GET_DATA_RANGE` reported a plausible
        /// stored-history window. Order matters: the lost-clock case is checked before the
        /// decode-failure case so a console-logs-only offload isn't mislabeled "report it" (FER-152).
        public static func decide(_ r: SyncReceipt, reportsStoredHistory: Bool) -> SyncVerdict {
            if r.framesReceived == 0 { return .nothingNew }
            if r.biometricFrames == 0 && !reportsStoredHistory { return .notStoringClock }
            if r.rowsDecoded == 0 { return .arrivesButNoDecode }
            return .receivingAndStoring
        }
    }

    /// True while a historical offload session is running, so screens can say "Syncing strap
    /// history…" instead of presenting half-loaded data as final (#77).
    @Published public var backfilling = false
    /// True in the brief window between one offload session closing and the auto-continue gate (FER-480)
    /// deciding — async, because it awaits the persisted frontier — whether to chain another. Screens OR
    /// this with `backfilling` so the «Descargando la noche…» hero stays steady across chained sessions
    /// instead of flickering off for the async hop. Set when a clean session ends; cleared once the gate
    /// has decided (if it chained, `backfilling` is already true again).
    @Published public var draining = false
    /// Chunks acked during the current offload session — an honest progress signal (total pending is
    /// unknowable from the protocol, so a count, never a percent).
    @Published public var syncChunksThisSession: Int = 0
    /// Incremented each time a standard-HR flush commits to SQLite. TodayView observes this
    /// to re-query hrBuckets immediately, without waiting for the 15-min analyzeRecent cycle.
    @Published public var hrFlushSeq: Int = 0

    /// Optional hook invoked on every battery update (wired by LiveViewModel to the alert monitor).
    /// Kept as a closure so LiveState stays a plain observable snapshot with no alert dependency.
    public var onBatteryUpdate: ((Double) -> Void)?

    /// Number of WHOOP 5/MG ("puffin") frames captured this session (when frame capture is enabled in
    /// Settings → Experimental). Drives the capture status line + export button.
    @Published public var puffinCaptureCount: Int = 0
    /// On-disk location of the current puffin capture file, once anything has been flushed. The
    /// Settings "Export" / "Reveal" actions target this URL.
    @Published public var puffinCaptureURL: URL?

    /// Set when a WHOOP 5/MG strap refuses the encrypted bond on first connect ("Encryption/Authentication
    /// is insufficient") — CoreBluetooth won't start a fresh just-works bond against a strap still bonded to
    /// the official WHOOP app. Surfaced as actionable pairing-mode guidance; cleared once the link bonds.
    @Published public var pairingHint: String? = nil

    /// Set when a connect attempt fails because the strap wiped its bond ("Peer removed pairing
    /// information") — a firmware update, or the official WHOOP app re-bonding it. macOS keeps re-presenting
    /// the now-stale pairing key, so reconnects loop on the same error with no recovery. Carries an
    /// actionable forget-and-re-pair guide; cleared on the next successful connect. (5/MG firmware reset, 2026-06)
    @Published public var reconnectGuide: String? = nil

    /// Set when NOOP detects a marginal Bluetooth radio that can't sustain the WHOOP 4 R10/R11 raw realtime
    /// stream (#80 — a 2016 Mac / OpenCore drops the link the instant that high-bandwidth burst is armed).
    /// After repeated arm-then-timeout cycles NOOP stops arming the heavy stream and falls back to the
    /// low-bandwidth 0x2A37 standard Heart Rate profile, so live HR can still flow on a radio that otherwise
    /// looped forever. Informational note for the Live screen; cleared on a clean reconnect or Live re-open.
    @Published public var standardHRMode: String? = nil

    public init() {}

    /// Single funnel for battery readings — updates the published value AND notifies the hook,
    /// so both write sites (FrameRouter, BLEManager) drive the alert monitor identically.
    public func setBattery(_ pct: Double) {
        batteryPct = pct
        onBatteryUpdate?(pct)
    }

    public func append(log line: String) {
        log.append(Self.redactPii(line))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    /// Scrub personal identifiers from a strap-log line so it's safe to share publicly (#445): BLE MAC
    /// addresses are masked to their first + last byte, the WHOOP's SERIAL — carried in its device
    /// name ("WHOOP 4C1594026") and tied to the owner's account — is removed, and the CoreBluetooth
    /// peripheral identifier (a per-install random UUID iOS/macOS print in "Discovered …(<uuid>)" lines)
    /// is masked. Applied at the single log sink, so every line that reaches the shareable strap log
    /// (BLEManager + the generic-HR diagnostics both feed it via `append(log:)`) is redacted.
    /// MACs require colons, so hex command payloads are untouched; the dotted model names ("WHOOP
    /// 4.0"/"5.0") don't match the serial pattern. The UUID rule deliberately KEEPS standard-BLE-base
    /// UUIDs (…-0000-1000-8000-00805f9b34fb, e.g. the 0x2A37 HR characteristic) and the WHOOP vendor
    /// service base (…-8d6d-82b8-614a-1c8cb0f8dcc6) — those are public, identical on every strap, and
    /// are exactly the GATT diagnostics a shared log needs to be useful (#421). Thanks @ujix (#447) for
    /// catching the peripheral-UUID leak; this is a targeted form so we don't redact the service UUIDs.
    static func redactPii(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(
            of: "([0-9A-Fa-f]{2}):[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:([0-9A-Fa-f]{2})",
            with: "$1:••:••:••:••:$2", options: .regularExpression)
        out = out.replacingOccurrences(
            of: "WHOOP (\\d[0-9A-Za-z]{5,})", with: "WHOOP <serial>", options: .regularExpression)
        // Mask a CoreBluetooth peripheral UUID, but NOT a standard-BLE / WHOOP-vendor service UUID.
        out = out.replacingOccurrences(
            of: "(?![0-9A-Fa-f]{8}-(?:0000-1000-8000-00805f9b34fb|8d6d-82b8-614a-1c8cb0f8dcc6))[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
            with: "<device>", options: [.regularExpression, .caseInsensitive])
        return out
    }
}
