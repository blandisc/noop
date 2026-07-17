import Foundation
import WhoopProtocol
import WhoopStore

/// The subset of WhoopStore the Collector needs. A protocol so tests can inject a spy
/// (WhoopStore is `final`). WhoopStore conforms via the extension below.
/// Not @MainActor — the WhoopStore actor's async methods satisfy the async requirements;
/// a @MainActor SpyStore in tests also conforms (async witnesses hop actors).
protocol StoreWriting: AnyObject {
    @discardableResult
    func insert(_ streams: Streams, deviceId: String) async throws
        -> (hr: Int, rr: Int, events: Int, battery: Int,
            spo2: Int, skinTemp: Int, resp: Int, gravity: Int)
    func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws
}
extension WhoopStore: StoreWriting {}

/// Cadence: flush after this many buffered frames OR this many seconds since the last
/// flush — whichever first. Also flushed explicitly on disconnect/foreground.
struct CollectorPolicy {
    var maxFrames: Int
    var maxInterval: TimeInterval
    /// Defensive BYTE cap on the PRE-CLOCK buffer only (see `ingest`). Type-43 REALTIME_RAW_DATA
    /// frames are ~1920 B and DO reach `Collector.ingest` on the live path (no offload-frame filter
    /// when `!backfilling`), so a frame-count cap of 4096 would allow ~8 MB, not ~240 KB. Default
    /// 512 KB bounds memory under a type-43 flood while keeping the most recent frames (FER-877).
    var maxPreClockBytes: Int
    /// Legacy frame-count alias kept so existing `CollectorPolicy(maxFrames:maxInterval:maxPreClockFrames:)`
    /// call sites still compile; mapped into `maxPreClockBytes` with a ~60 B/frame assumption only when
    /// the caller passes an explicit count (default path uses `maxPreClockBytes` directly).
    var maxPreClockFrames: Int {
        // Approximate inverse for introspection; the live gate is bytes.
        max(1, maxPreClockBytes / 60)
    }
    init(maxFrames: Int, maxInterval: TimeInterval, maxPreClockFrames: Int = 4096, maxPreClockBytes: Int? = nil) {
        self.maxFrames = maxFrames
        self.maxInterval = maxInterval
        // Prefer explicit bytes; otherwise derive from the (legacy) frame count × ~60 B/frame so
        // old call sites that pass maxPreClockFrames keep a similar memory budget.
        if let maxPreClockBytes {
            self.maxPreClockBytes = maxPreClockBytes
        } else {
            self.maxPreClockBytes = maxPreClockFrames * 60
        }
    }
    /// 512 KB pre-clock byte cap — enough for hundreds of small live frames, tight enough that a
    /// type-43 flood cannot grow the buffer into multi-MB territory before GET_CLOCK lands.
    static let `default` = CollectorPolicy(maxFrames: 64, maxInterval: 30, maxPreClockBytes: 512 * 1024)
}

/// Buffers complete (reassembled) frames and periodically persists them:
/// parse → extractStreams(clockRef) → store.insert (DECODED FIRST, durable) →
/// store.enqueueRawBatch (raw, transient outbox) → clear buffer.
/// Because decoded is committed before raw is queued, pruning raw never loses a metric.
@MainActor
final class Collector {
    private let store: StoreWriting
    /// Concrete store for prune + stats (the StoreWriting seam covers the hot insert/enqueue path;
    /// prune/stats are infrequent so a direct reference is clearer than widening the protocol).
    private let concreteStore: WhoopStore?
    private let deviceId: String
    private let policy: CollectorPolicy
    /// Research toggle. When false (DEFAULT) no raw frames are persisted at all — the app is
    /// decoded-only. Injected for tests; backed by UserDefaults in the production init site.
    private let enableRawCapture: Bool
    private let now: () -> Int
    private let monotonic: () -> TimeInterval

    /// Set once the GET_CLOCK correlation lands (E1). Until then, frames buffer un-persisted.
    var clockRef: ClockRef?
    /// On-demand bounded raw-capture window. ORs into the raw-persist gate so a "capture
    /// activity sample" action can persist raw even when `enableRawCapture` is off. The window's
    /// monotonic deadline auto-expires so a missed stop callback can't leak raw forever.
    private var rawCapture = RawCaptureWindow()
    /// FER-971 (C-04): the frame travels WITH its one ingest-time parse (mirror of FER-752 on the
    /// offload path), so `flush` never re-parses the batch. Raw bytes stay alongside for the
    /// research raw-capture outbox.
    private var buffer: [(raw: [UInt8], parsed: ParsedFrame)] = []
    /// Running byte total of `buffer` — maintained on append/drop/flush so the pre-clock cap check
    /// is O(1) per frame instead of a full `reduce` per ingest (FER-971).
    private var bufferBytes = 0
    /// Standard 0x2A37 HR/RR buffer — the reliable, always-on stream, recorded continuously
    /// (independent of the custom realtime stream or which screen is open).
    private var stdHR: [HRSample] = []
    private var stdRR: [RRInterval] = []
    /// Wall-clock second of the last HR sample buffered — dedupes HR arriving on both the 0x2A37
    /// profile and the custom realtime stream in the same second.
    private var lastStdHRTs: Int?
    private var batchStartedAt: TimeInterval
    var bufferedCount: Int { buffer.count }
    /// Called after each successful standard-HR flush so callers can signal the UI.
    var onHRFlushed: (() -> Void)?

    init(store: StoreWriting, deviceId: String,
         policy: CollectorPolicy = .default,
         enableRawCapture: Bool = false,
         now: @escaping () -> Int = { Int(Date().timeIntervalSince1970) },
         monotonic: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }) {
        self.store = store; self.deviceId = deviceId; self.policy = policy
        self.enableRawCapture = enableRawCapture
        self.now = now; self.monotonic = monotonic
        self.batchStartedAt = monotonic()
        self.concreteStore = store as? WhoopStore
    }

    /// Light storage summary for the UI. nil if there's no concrete store or the read throws.
    func storageStats() async -> (decodedRows: Int, rawBatches: Int, rawBytes: Int)? {
        guard let s = concreteStore else { return nil }
        return try? await s.storageStats()
    }

    /// Max persisted HR sample ts (the biometric "data frontier" for the stuck-strap watchdog).
    /// nil if there's no concrete store or nothing persisted yet. Mirrors storageStats().
    func latestHRSampleTs() async -> Int? {
        guard let s = concreteStore else { return nil }
        return try? await s.latestHRSampleTs(deviceId: deviceId)
    }

    /// Recent gravity samples in `[from, to]` (wall-clock unix seconds), for the inactivity reminder's
    /// offload hook (FER-664). Empty if there's no concrete store or the read throws. Mirrors the
    /// read-only accessors above.
    func recentGravity(from: Int, to: Int, limit: Int = 100_000) async -> [GravitySample] {
        guard let s = concreteStore else { return [] }
        return (try? await s.gravitySamples(deviceId: deviceId, from: from, to: to, limit: limit)) ?? []
    }

    /// Apply the raw-retention policy. Returns rows pruned (0 if no concrete store).
    @discardableResult
    func prune() async -> Int {
        guard let s = concreteStore else { return 0 }
        return (try? await s.pruneRaw(now: now(),
                                keepWindowSeconds: PrunePolicy.keepWindowSeconds,
                                maxUnsyncedBytes: PrunePolicy.maxUnsyncedBytes)) ?? 0
    }

    /// Buffer one complete frame (synchronous: preserves delegate arrival order), together with
    /// the single parse the delegate already produced for it (FER-971 · C-04 — no second parse).
    /// Auto-flushes via a detached Task when the cadence threshold is hit (flush is async).
    func ingest(_ frame: [UInt8], parsed: ParsedFrame) {
        buffer.append((frame, parsed))
        bufferBytes += frame.count
        // Pre-clock only: bound memory if GET_CLOCK never lands while data keeps flowing.
        // Cap by approximate total BYTES (type-43 frames are ~1920 B, not ~60 B). Drop OLDEST
        // until under the byte cap (keep most recent). Post-clock this branch is skipped —
        // the cadence flush below bounds the buffer instead (FER-877).
        if clockRef == nil, bufferBytes > policy.maxPreClockBytes {
            var drop = 0
            while drop < buffer.count && bufferBytes > policy.maxPreClockBytes {
                bufferBytes -= buffer[drop].raw.count
                drop += 1
            }
            if drop > 0 { buffer.removeFirst(drop) }
        }
        guard clockRef != nil else { return }   // can't correlate ts yet → keep buffering
        if buffer.count >= policy.maxFrames || (monotonic() - batchStartedAt) >= policy.maxInterval {
            Task { @MainActor in await self.flush() }
        }
    }

    /// Persist + queue everything buffered. No-op when empty or before a clock ref exists.
    /// Buffer is snapshotted and cleared SYNCHRONOUSLY before the first await so that any
    /// concurrent ingest() calls during persistence accumulate into the NEXT batch cleanly.
    func flush() async {
        guard let ref = clockRef, !buffer.isEmpty else { return }
        // SNAPSHOT + CLEAR before any await: decoded-before-raw ordering AND the
        // buffer-snapshot-before-await invariant are both satisfied here.
        let frames = buffer
        buffer.removeAll(keepingCapacity: true)
        bufferBytes = 0

        // Extraction is CPU-pure (`extractStreams` never touches the DB or UIKit). Run it OFF the
        // main actor so the ~64-frame batch extraction can't jank the UI (FER-183). The frames
        // travel with their ingest-time `ParsedFrame` (FER-971 · C-04), so the old second
        // `parseFrame` pass per batch is gone; everything captured is Sendable and `Streams`
        // crosses back cleanly.
        let devRef = ref.device, wallRef = ref.wall
        let streams = await Task.detached {
            extractStreams(frames.map(\.parsed), deviceClockRef: devRef, wallClockRef: wallRef)
        }.value
        do {
            try await store.insert(streams, deviceId: deviceId)   // DECODED FIRST (durable)
        } catch {
            // Re-buffer at the front so these frames are retried on the next cadence.
            buffer.insert(contentsOf: frames, at: 0)
            bufferBytes += frames.reduce(0) { $0 + $1.raw.count }
            return
        }
        // Reset only after a successful insert so the interval trigger keeps firing if
        // inserts fail (batchStartedAt must NOT advance on a failed drain).
        batchStartedAt = monotonic()
        // RAW SECOND (transient outbox), only when the research toggle is ON. Default OFF →
        // decoded-only, no raw is stored. Failure is non-fatal — decoded is already durable.
        guard enableRawCapture || rawCapture.isActive(at: monotonic()) else { return }
        let wall = now()
        let tsValues = streams.hr.map(\.ts) + streams.rr.map(\.ts)
            + streams.events.map(\.ts) + streams.battery.map(\.ts)
        let meta = RawBatchMeta(
            batchId: UUID().uuidString, deviceId: deviceId, clockRef: ref, capturedAt: wall,
            startTs: tsValues.min() ?? wall, endTs: tsValues.max() ?? wall,
            frameCount: frames.count, byteSize: frames.reduce(0) { $0 + $1.raw.count })
        try? await store.enqueueRawBatch(meta, frames: frames.map(\.raw))
    }

    // MARK: - Standard 0x2A37 HR/RR (continuous recording)

    /// Buffer one standard Heart-Rate-Measurement reading. No clock correlation needed —
    /// these carry a wall-clock `ts` directly. Auto-flushes ~every 30 readings (~30s).
    func ingestStandardHR(hr: Int, rr: [Int], at ts: Int) {
        // Dedupe by second: HR can arrive on BOTH the 0x2A37 profile and the custom realtime stream
        // (now routed here too). One sample per wall-clock second keeps a dual-emitting strap from
        // doubling rows; the 0x2A37 profile itself is ~1 Hz so this never drops genuine detail. RR is
        // appended separately (below), so the 0x2A37 R-R intervals survive even on a deduped second.
        if hr >= 30, hr <= 220, ts != lastStdHRTs {
            stdHR.append(HRSample(ts: ts, bpm: hr))
            lastStdHRTs = ts
        }
        for r in rr where r >= 250 && r <= 3000 { stdRR.append(RRInterval(ts: ts, rrMs: r)) }
        if stdHR.count + stdRR.count >= 30 {
            Task { @MainActor in await self.flushStandardHR() }
        }
    }

    /// Persist the buffered standard HR/RR. Re-buffers on failure so nothing is lost.
    func flushStandardHR() async {
        guard !stdHR.isEmpty || !stdRR.isEmpty else { return }
        let hr = stdHR, rr = stdRR
        stdHR.removeAll(keepingCapacity: true)
        stdRR.removeAll(keepingCapacity: true)
        do {
            try await store.insert(Streams(hr: hr, rr: rr), deviceId: deviceId)
            onHRFlushed?()
        } catch {
            stdHR.insert(contentsOf: hr, at: 0)
            stdRR.insert(contentsOf: rr, at: 0)
        }
    }

    // MARK: - On-demand raw capture

    /// Open a bounded raw-capture window so the next flushes persist raw even with the global
    /// research toggle off. Auto-expires at the (clamped) monotonic deadline.
    func beginRawCapture(seconds: TimeInterval) {
        rawCapture.open(at: monotonic(), duration: seconds)
    }

    /// Flush WHILE the window is still active so the just-captured frames get persisted as raw,
    /// THEN close the window.
    func endRawCapture() async {
        await flush()
        rawCapture.close()
    }
}
