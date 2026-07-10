import Foundation
import WhoopProtocol
import WhoopStore

// MARK: - BackfillStoreWriting protocol

/// The async subset the Backfiller needs. Plain async protocol (not @MainActor) so both the
/// real WhoopStore actor and a @MainActor SpyBackfillStore in tests can satisfy it.
protocol BackfillStoreWriting: AnyObject {
    @discardableResult
    func insert(_ streams: Streams, deviceId: String) async throws
        -> (hr: Int, rr: Int, events: Int, battery: Int,
            spo2: Int, skinTemp: Int, resp: Int, gravity: Int)
    func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws
    func setCursor(_ name: String, _ value: Int) async throws
    func cursor(_ name: String) async throws -> Int?
}

extension WhoopStore: BackfillStoreWriting {}

// MARK: - Backfiller

/// Historical-offload state machine (idle / backfilling).
///
/// Per-chunk local safe-trim invariant:
///   decode known → await insert (decoded durable) →
///   await enqueueRawBatch (raw durable) →
///   await setCursor(strap_trim) →
///   ackTrim (link-layer confirmed ack to strap)
///
/// A chunk is forgotten only after decoded AND raw are both locally durable AND the ack
/// (.withResponse) is link-layer confirmed. Never waits on the server.
@MainActor
final class Backfiller {
    /// `@Sendable` so `finishChunk` can run the extract off the main actor (FER-752); the default
    /// (`extractHistoricalStreams`) is a pure function, so this costs test injections nothing.
    /// (parsed frames, deviceClockRef, wallClockRef, sessionOldestUnix?, sessionNewestUnix?) → Streams (#547).
    typealias Extractor = @Sendable ([ParsedFrame], Int, Int, Int?, Int?) -> Streams

    /// Per-chunk "data receipt" the Backfiller hands back so BLEManager can accumulate an honest
    /// "what this sync received" tally and derive the sync verdict (FER-83). Per-sensor fields are
    /// rows ACTUALLY persisted (from `StreamStore.insert`'s return); `framesReceived`/`rowsDecoded`
    /// distinguish "nothing new" from "frames arrive but don't decode".
    struct ChunkReceipt {
        var hr = 0, rr = 0, spo2 = 0, skinTemp = 0, resp = 0, gravity = 0
        var framesReceived = 0
        /// type-47 HISTORICAL_DATA (biometric) frames in this chunk. Zero with frames > 0 is the
        /// lost-clock case — the band narrates CONSOLE_LOGS (type-50) instead of serving history
        /// because it stored nothing — distinct from biometry that arrives but won't decode (FER-152).
        var biometricFrames = 0
        /// type-50 CONSOLE_LOGS frames in this chunk. Feeds `RtcHealthPolicy` (zero biometry + logs > 0 =
        /// the RTC-lost "narrating, not saving" shape) so BLEManager can detect a lost clock and re-assert
        /// it without GET_CLOCK. (FER-93)
        var consoleLogFrames = 0
        var rowsDecoded = 0
    }

    private let store: BackfillStoreWriting
    private let deviceId: String
    /// Confirms one HISTORY_END chunk to the strap. Carries both the trim cursor (= first u32
    /// of end_data, used for the `strap_trim` cursor) and the 8-byte `end_data` (= the raw
    /// HISTORY_END metadata.data[10:18]) that the high-freq-sync ack form requires verbatim.
    private let ackTrim: (_ trim: UInt32, _ endData: [UInt8]) -> Void
    private let extract: Extractor
    /// Research toggle. When false (DEFAULT) no raw frames are persisted — the chunk's
    /// decoded streams are still durable and the trim is still acked (decoded is the product of
    /// record). Injected for tests; backed by UserDefaults in the production init site.
    private let enableRawCapture: Bool

    /// The clock reference set by BLEManager when GET_CLOCK confirms (required for decoding).
    var clockRef: ClockRef?

    /// #547 SESSION-RELATIVE gate: the strap's own GET_DATA_RANGE oldest/newest banked-record markers for
    /// the CURRENT offload, set by BLEManager when the range reply lands. A record dated months outside this
    /// window is wandering-clock pollution even if it clears the absolute 2023-11 floor, so the ingest gate
    /// rejects it. nil (both) until the range is known — the gate then falls back to the absolute floor only,
    /// so behaviour is unchanged on the no-range / replay paths. Owned per-connection by BLEManager
    /// (`resetConnectionState` clears them; the GET_DATA_RANGE reply re-publishes them) — NOT reset in
    /// `begin()`, because the range reply lands BEFORE the deferred offload kick and must survive it.
    var sessionOldestUnix: Int?
    var sessionNewestUnix: Int?

    /// #547: total records dropped this session for an implausible timestamp (accumulated across chunks),
    /// so the bad-clock log line fires once instead of per-chunk.
    private var sessionDroppedImplausible = 0

    /// True while a historical offload session is active.
    private(set) var isBackfilling = false

    /// Set true when the session ended because the offload caught up to the live edge (FER-201) rather
    /// than via HISTORY_COMPLETE. BLEManager reads it to pick the teardown reason — both complete the
    /// sync as success; this only distinguishes the honest log/diagnostic. Reset each `begin`.
    private(set) var didCatchUp = false

    /// The `strap_trim` cursor of the LAST chunk this Backfiller durably acked (persisted + confirmed to
    /// the strap). A cross-session high-water mark — **NOT** reset in `begin()` — so BLEManager can snapshot
    /// it at session start and compare at session end to ask "did the offload actually advance the strap's
    /// trim this session?" (the anti-spin signal `DrainContinuationPolicy` needs, FER-480). nil until the
    /// first ack.
    private(set) var lastAckedTrim: UInt32?

    /// Decides when the offload has drained its backlog (a sustained run of small HISTORY_END chunks =
    /// only the live drip) so the session can complete as success even when the firmware never sends
    /// HISTORY_COMPLETE (FER-201). Pure; reset per session.
    private var caughtUpDetector = CaughtUpDetector()

    /// Buffered data frames for the current open chunk (between START and END). Each entry carries
    /// the raw bytes (raw-capture persistence + hex diagnostics) AND the `ParsedFrame` the caller
    /// already produced, so no frame is ever re-parsed inside the Backfiller (FER-752).
    private var chunk: [(raw: [UInt8], parsed: ParsedFrame)] = []
    /// Whether a START has been received and we're accumulating a chunk.
    private var chunkOpen = false
    /// Strap family for the current offload, set at begin(). Drives family-aware frame parsing (WHOOP 5/MG
    /// records sit at +4 offsets vs WHOOP 4.0) and the end_data slice the ack needs. Captured at begin()
    /// rather than init so it's correct even if the Backfiller was constructed before the strap was known.
    private var family: DeviceFamily = .whoop4

    /// Diagnostic sink (strap log). Surfaces historical records whose firmware layout we can't decode.
    private let log: ((String) -> Void)?
    /// Per-chunk receipt sink (FER-83). Invoked once per HISTORY_END that carried frames, so the
    /// caller can accumulate the session's "what was received/decoded/stored" tally. nil in tests
    /// that don't care.
    private let onReceipt: ((ChunkReceipt) -> Void)?
    /// FER-693 (#77 / #91): durably archives undecodable HISTORICAL_DATA frames BEFORE the trim ack.
    /// Returns true once the frames are durable (or safely skipped at the cap); returns FALSE on a genuine
    /// write failure, which holds the ack so the strap re-sends the chunk next session (no data loss). nil
    /// when no archive is wired (tests, or a build that doesn't preserve rejects).
    private let rejectedSink: ((_ frames: [[UInt8]], _ trim: UInt32, _ family: DeviceFamily) -> Bool)?
    /// Versions already reported this session, so the diagnostic logs each once (no spam).
    private var loggedUnmappedVersions: Set<Int> = []
    /// FER-692 (#150): logged once per session when the strap reports the `trim=0xFFFFFFFF` sentinel —
    /// its "no valid flash cursor" state: it has no banked history to offload (a clock/charge condition
    /// on the strap, not a Cénit decode bug). Reset in `begin`.
    private var loggedNoCursor = false

    init(store: BackfillStoreWriting,
         deviceId: String,
         ackTrim: @escaping (_ trim: UInt32, _ endData: [UInt8]) -> Void,
         enableRawCapture: Bool = false,
         log: ((String) -> Void)? = nil,
         onReceipt: ((ChunkReceipt) -> Void)? = nil,
         rejectedSink: ((_ frames: [[UInt8]], _ trim: UInt32, _ family: DeviceFamily) -> Bool)? = nil,
         extract: @escaping Extractor = { extractHistoricalStreams($0, deviceClockRef: $1, wallClockRef: $2,
                                                                    sessionOldestUnix: $3, sessionNewestUnix: $4) }) {
        self.store = store
        self.deviceId = deviceId
        self.ackTrim = ackTrim
        self.enableRawCapture = enableRawCapture
        self.log = log
        self.onReceipt = onReceipt
        self.rejectedSink = rejectedSink
        self.extract = extract
    }

    /// Called by BLEManager when the strap signals a historical offload is beginning.
    /// chunkOpen starts TRUE: the high-freq-sync biometric replay streams records immediately and
    /// sends one HISTORY_START then repeated HISTORY_ENDs, so we must accumulate from the outset.
    func begin(family: DeviceFamily) {
        self.family = family
        isBackfilling = true
        chunk.removeAll(keepingCapacity: true)
        chunkOpen = true
        caughtUpDetector.reset()
        didCatchUp = false
        sessionDroppedImplausible = 0
        loggedNoCursor = false
    }

    /// Feed one raw BLE frame into the state machine. May trigger async store operations.
    /// `parsed` is the caller's ParsedFrame for these SAME bytes (BLEManager already parses every
    /// frame once in `didUpdateValueFor`, FER-183) — reused here for classification and buffered
    /// alongside the raw bytes so the offload path parses each frame exactly once (FER-752).
    func ingest(_ frame: [UInt8], parsed: ParsedFrame) async {
        switch classifyHistoricalMeta(parsed) {
        case .start:
            isBackfilling = true
            chunk.removeAll(keepingCapacity: true)
            chunkOpen = true
        case .end(let unix, let trim):
            await finishChunk(unix: unix, trim: trim, endFrame: frame)
        case .complete:
            isBackfilling = false
            chunk.removeAll(keepingCapacity: true)
            chunkOpen = false
        case .other:
            if chunkOpen { chunk.append((raw: frame, parsed: parsed)) }
        }
    }

    /// The 8-byte `end_data` the high-freq-sync ack requires: metadata.data[10:18].
    /// metadata.data begins at frame[7] (after [type,seq,cmd]), so end_data = frame[17:25].
    /// trim cursor = the first u32 of end_data (data[10:14]). Returns nil if the frame is too
    /// short to contain the field (shouldn't happen for a real HISTORY_END, which is >=14 data
    /// bytes, but guards against a malformed frame).
    static func endData(from frame: [UInt8], family: DeviceFamily) -> [UInt8]? {
        // metadata.data begins at frame[7] (WHOOP4) / frame[11] (WHOOP5, the +4 puffin envelope); the
        // ack's end_data = data[10:18] → frame[17:25] (WHOOP4) or frame[21:29] (WHOOP5). The WHOOP5 slice
        // is verified on a real HISTORY_END (trim=112193 = frame[21..25]) in Whoop5HistoricalTests.
        let start = family == .whoop5 ? 21 : 17
        guard frame.count >= start + 8 else { return nil }
        return Array(frame[start..<(start + 8)])
    }

    /// Commit one HISTORY_END chunk: (persist decoded → enqueueRaw when present) → setCursor → ackTrim.
    /// Early-returns on any throw to preserve the safe-trim invariant.
    ///
    /// CRITICAL: high-freq-sync sends ONE HISTORY_START then REPEATED HISTORY_ENDs (a chunk-close
    /// every ~50 records). So we must ack EVERY end and keep accumulating afterwards — NOT close
    /// the chunk after the first. We snapshot+clear the accumulated frames but leave `chunkOpen`
    /// TRUE so the records following this END become the next chunk. An END with no accumulated
    /// records is still acked (it advances the strap's trim) — that's how the offload progresses.
    /// `endFrame` carries the 8-byte `end_data` the ack requires.
    private func finishChunk(unix: UInt32, trim: UInt32, endFrame: [UInt8]) async {
        guard let endData = Backfiller.endData(from: endFrame, family: family) else { return }

        // FER-692 (#150): trim=0xFFFFFFFF is the strap's "no valid flash cursor" sentinel — it has no
        // banked history to hand over. Surface it once so a strap log reads as a clock/charge state on the
        // strap, not a Cénit decode bug (retro-decode can't help here). The ack still proceeds below.
        if trim == 0xFFFFFFFF, !loggedNoCursor {
            loggedNoCursor = true
            log?("Backfill: la banda reporta que no tiene cursor de historial (trim=0xFFFFFFFF) — no hay historia guardada que descargar. Es un estado de reloj/carga de la banda, no un problema de decodificación; cárgala por completo y reconéctala para que empiece a guardar.")
        }

        let frames = chunk
        chunk.removeAll(keepingCapacity: true)   // next records accumulate into the next chunk

        // type-47 frame count for the caught-up detector (0 for an empty END). Fed only AFTER the
        // safe-trim commit + ack below, so the triggering chunk is already durable (FER-201).
        var biometricFramesThisEnd = 0
        var consoleLogFramesThisEnd = 0
        if !frames.isEmpty {
            // type-47 HISTORICAL_DATA carries its OWN real-unix timestamp — extractHistoricalStreams
            // ignores the clock offset for it — so the historical offload does NOT need GET_CLOCK.
            // If the (device,wall) correlation isn't established yet (e.g. GET_CLOCK silent), fall back
            // to an identity ref (device==wall==now): the offset math becomes a no-op, type-47 still
            // decodes to correct wall time, and we can persist + ack + upload. The correlation is only
            // truly required to map REALTIME (type-40/43) device-epoch timestamps, never in a hist chunk.
            let ref = clockRef ?? { let now = Int(Date().timeIntervalSince1970); return ClockRef(device: now, wall: now) }()
            // Parse-once (FER-752): the ParsedFrames travelled with the raw bytes since ingest —
            // this used to re-parse the whole chunk (~50 frames) synchronously on the main actor.
            let parsed = frames.map(\.parsed)
            // FER-90 diagnostic: break down what this chunk actually contained by frame type. The 4.0
            // "historical offload" sometimes returns CONSOLE_LOGS (type 50) and ZERO biometric records
            // (type 47) — the band narrating firmware errors instead of serving history. This count makes
            // that visible in the strap log (vs the opaque "decoded to 0 rows").
            let bio = parsed.filter { $0.typeName == "HISTORICAL_DATA" }.count
            biometricFramesThisEnd = bio
            let logs = parsed.filter { $0.typeName == "CONSOLE_LOGS" }.count
            consoleLogFramesThisEnd = logs
            log?("Offload: \(frames.count) frames — \(bio) biometría (type-47), \(logs) console logs (type-50), \(parsed.count - bio - logs) otros")
            // Diagnostic (#30): a historical record whose firmware version we don't have a field map for
            // bails out of decode entirely — no HR, no R-R, no GRAVITY — so sleep (which is gravity/
            // motion-driven) can never be computed from it, even though the offload "completes". Surface
            // each unmapped version once so the user's strap log reveals what their firmware emits.
            for p in parsed {
                guard let v = p.parsed["hist_version"]?.intValue,
                      p.parsed["heart_rate"] == nil,            // decoded nothing → unmapped layout
                      !loggedUnmappedVersions.contains(v) else { continue }
                loggedUnmappedVersions.insert(v)
                log?("Historical records use firmware layout v\(v), which Cénit doesn't decode yet — no motion data, so sleep can't be computed from the strap. Please report this (issue #30).")
            }
            // Decode OFF the main actor (FER-752, same pattern as Collector.flush / FER-183):
            // `extract` is CPU-pure (@Sendable, never touches the DB or UIKit) and `ParsedFrame` /
            // `Streams` are Sendable, so the ~50-record chunk decode can't jank the UI. The result
            // is AWAITED here — the insert below and the ack after it still run strictly after the
            // decode, on the main actor, so the safe-trim ordering (insert durable → ack) holds.
            let extract = self.extract
            let devRef = ref.device, wallRef = ref.wall
            let oldest = sessionOldestUnix, newest = sessionNewestUnix
            let decoded = await Task.detached {
                extract(parsed, devRef, wallRef, oldest, newest)
            }.value
            // #547: surface a bad-clock strap. extractHistoricalStreams DROPPED any record whose own unix
            // timestamp was implausible (far-past / bogus-2027 / future-dated) before it could pollute the
            // DB. Log it once per session so the user's strap log explains why a clock-broken strap banks
            // fewer rows than expected — this is the strap's clock, not a Cénit decode bug.
            if decoded.droppedImplausible > 0 {
                let wasZero = sessionDroppedImplausible == 0
                sessionDroppedImplausible += decoded.droppedImplausible
                if wasZero {
                    log?("Backfill: dropped record(s) with an implausible timestamp (trim=\(trim)) — the strap's clock is wrong (records dated far in the past or future), so those samples were skipped rather than misfiled onto the wrong day. Fully charge and reconnect the strap so its clock re-syncs.")
                }
            }
            // FER-693 (#77 / #91): classify the GENUINE losses — type-47 records that failed CRC or hit an
            // unmapped layout — separately from type-50 console frames, which decode to 0 rows BY DESIGN
            // and are NOT lost data (the "rejected frames" red herring users kept reporting). This drives
            // both the log wording and the archive-before-ack guard below.
            let rejected = rejectedHistoricalRecords(frames.map(\.raw), family: family)
            // Diagnostic (#77): the AGGREGATE silent-loss case — frames arrived but produced no rows at
            // all. Console-only ENDs read calmly (not data loss); genuine rejects say what will be archived.
            if decoded.isEmpty && rejected.isEmpty {
                log?("Backfill: \(frames.count) frame(s) this chunk carried no sensor records (strap console/diagnostic output) — normal, nothing to persist (trim=\(trim)).")
            }
            if !rejected.isEmpty {
                log?("Backfill: \(rejected.count) undecodable sensor record(s) of \(frames.count) frame(s) (trim=\(trim)) — archiving raw bytes before ack (CRC/unmapped layout).")
                // #91 / #30: dump a hex sample of the genuine rejects so an unmapped firmware's record
                // layout can be mapped from a user's strap log — the count alone can't be decoded.
                for (i, f) in rejected.prefix(3).enumerated() {
                    let hex = f.prefix(64).map { String(format: "%02x", $0) }.joined()
                    log?("Backfill: rejected frame[\(i)] \(f.count)B: \(hex)\(f.count > 64 ? "…" : "")")
                }
            }
            let stored: (hr: Int, rr: Int, events: Int, battery: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int)
            do { stored = try await store.insert(decoded, deviceId: deviceId) } catch { return }

            // Data receipt (FER-83): rows actually stored per sensor, plus frames-received vs
            // rows-decoded so the diagnostic can tell "nothing new" from "frames but no decode".
            let rowsDecoded = decoded.hr.count + decoded.rr.count + decoded.spo2.count
                + decoded.skinTemp.count + decoded.resp.count + decoded.gravity.count
            onReceipt?(ChunkReceipt(
                hr: stored.hr, rr: stored.rr, spo2: stored.spo2, skinTemp: stored.skinTemp,
                resp: stored.resp, gravity: stored.gravity,
                framesReceived: frames.count, biometricFrames: bio, consoleLogFrames: logs, rowsDecoded: rowsDecoded))

            // RAW: only persisted when the research toggle is ON. Default OFF → decoded-only; the
            // chunk is still durably committed (decoded) so the trim is safe to advance + ack.
            if enableRawCapture {
                let meta = RawBatchMeta(
                    batchId: "hist-\(deviceId)-\(trim)",
                    deviceId: deviceId,
                    clockRef: ref,
                    capturedAt: Int(Date().timeIntervalSince1970),
                    startTs: ref.wall,
                    endTs: ref.wall,
                    frameCount: frames.count,
                    byteSize: frames.reduce(0) { $0 + $1.raw.count })
                do { try await store.enqueueRawBatch(meta, frames: frames.map(\.raw)) } catch { return }
            }

            // FER-693 (#77 / #91): any genuinely-undecodable type-47 record in this chunk must be ARCHIVED
            // before we ack — the ack frees the strap's copy, so the archive is the only remaining copy of
            // an unmapped firmware's records. A genuine archive write FAILURE aborts the chunk (no
            // setCursor, no ack) so the strap re-sends it next session — no data loss either way. (A full
            // archive still returns true and we ack; the frames are counted as unarchived by the sink.)
            if !rejected.isEmpty, let rejectedSink {
                guard rejectedSink(rejected, trim, family) else {
                    log?("Backfill: rejected-frame archive failed (trim=\(trim)) — holding ack so the strap re-sends.")
                    return
                }
            }
        }
        do { try await store.setCursor("strap_trim", Int(trim)) } catch { return }

        ackTrim(trim, endData)
        lastAckedTrim = trim   // FER-480: record the advanced cursor for the auto-continue anti-spin gate

        // Caught-up completion (FER-201): once a sustained run of small ENDs proves the backlog is
        // drained, end the session as SUCCESS. Some WHOOP 4.0 firmware never sends HISTORY_COMPLETE,
        // so without this the session always wedges to the 300 s cap ("Sync ran long and was paused").
        // Evaluated AFTER the commit + ack above, so the triggering chunk is durable; the durable
        // strap_trim cursor + periodic re-sync make an early call self-healing (never loses data).
        // FER-93: a narrating-not-saving END (zero type-47 + CONSOLE_LOGS = the RTC-lost band talking, not
        // the live drip) must not let the offload complete "green". Pass it so the detector resets its run
        // instead of counting it as a small caught-up chunk.
        // FER-692 (#150): a `trim=0xFFFFFFFF` no-cursor sentinel END also carries zero real banked history —
        // it must NOT be read as a small "caught-up" chunk (that would complete the sync green while the
        // strap has nothing banked). Fold it into the same reset signal so caught-up only fires on a
        // genuine small-but-SAVING tail, never on a sentinel or a narrating END.
        let narratingThisEnd = (biometricFramesThisEnd == 0 && consoleLogFramesThisEnd > 0)
            || trim == 0xFFFFFFFF
        if isBackfilling, caughtUpDetector.observe(biometricFrames: biometricFramesThisEnd, narratingNotSaving: narratingThisEnd) {
            isBackfilling = false
            didCatchUp = true
            chunkOpen = false
        }
    }

    /// Called when a backfill watchdog timer fires (strap went silent mid-offload).
    /// Clears state without acking — the chunk was never durably committed.
    func timeoutFired() {
        isBackfilling = false
        chunk.removeAll(keepingCapacity: true)
        chunkOpen = false
    }
}
