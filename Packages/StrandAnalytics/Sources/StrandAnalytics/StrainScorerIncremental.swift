import Foundation
import WhoopProtocol

// StrainScorerIncremental.swift — an incremental fold for the in-progress day's cumulative strain
// (FER-870). `StrainScorer.cumulativeStrain(_:)` recomputes the whole day from scratch on every call:
// it reads every HR sample (~86k on a densely-worn day) and, worse, sorts ALL of the gaps to find the
// median spacing (`HRZones.medianInterval`, an O(n log n) sort). On a live day with «Hoy» open that
// call fires 2–4×/min, on the main actor, all day. This state folds only the NEW samples per flush.
//
// Why it stays exactly equal to the batch recompute:
//   • TRIMP is additive by construction, so the running Edwards zone-weight sum / Banister contribution
//     sum extend trivially — appending samples never disturbs the earlier terms.
//   • `sampleDur` (= median gap / 60) is a single scalar factored OUT of both accumulators and applied
//     ONCE at materialization (Edwards TRIMP = sampleDur · Σweight; Banister TRIMP = sampleDur · Σterm).
//     So when the median shifts as the day fills in, every bucket re-weights the same way the batch
//     recompute would — the curve is byte-for-byte the batch curve over the same samples, at any hour,
//     not just at end-of-day. (We deliberately do NOT freeze the median once: freezing it early, off a
//     sparse dawn stream, would DIVERGE from the batch, which always applies the full-window median.)
//   • The median itself is tracked with a bounded gap histogram. Gaps count only whole seconds in
//     (0, 300) — the exact window `HRZones.medianInterval` keeps — so at most 299 distinct values: an
//     O(300) median lookup replaces the O(n log n) sort, and it yields the identical order statistic
//     (including the even-count average of the two central values) that the sort would.
//
// See `StrainScorerIncrementalTests` for the chunked-fold == batch-fold equivalence proof (dense,
// sparse, across a bucket boundary, across signal gaps, and empty flushes).

extension StrainScorer {

    /// Incremental accumulator for the in-progress day's cumulative strain (FER-870).
    ///
    /// Seed it once per civil day with the SAME parameters the daily engine uses, feed each flush's
    /// new samples (strictly after `lastTs`) through `extend(with:)`, and read `curve` / `strain`.
    /// The result equals `StrainScorer.cumulativeStrain` / `StrainScorer.strain` over every sample fed
    /// so far. Reset (discard and re-seed) when the civil day rolls over, the data source changes, or
    /// any scoring parameter changes — exactly the cases where the batch recompute would differ.
    ///
    /// `Sendable` value type, so a `@MainActor` cache can hand a snapshot to a detached fold and take
    /// the extended copy back — no scoring work on the UI thread.
    public struct CumulativeStrainState: Sendable, Equatable {

        // MARK: Parameters (fixed for the life of the state; mirror `cumulativeStrain`'s arguments)
        public let bucketSeconds: Int
        public let maxHR: Double?
        public let restingHR: Double
        public let method: Method
        public let sex: String
        public let denominator: Double

        // MARK: Running accumulators (both INDEPENDENT of sampleDur, so a shifting median never
        // forces a re-walk). Edwards keeps Σ zone weight; Banister keeps Σ x·scale·e^{b·x}.
        var accumulator: Double

        // MARK: Bounded gap histogram for the median spacing. `gapCounts[g]` = number of consecutive
        // gaps of exactly `g` seconds, for g in 1...299 (the plausible-gap window). Index 0 unused.
        var gapCounts: [Int]
        var gapTotal: Int

        // MARK: Per-bucket snapshot — the running accumulator at the LAST sample of each bucket,
        // in ascending time order. Materialization maps these to strain with the current sampleDur.
        struct Bucket: Sendable, Equatable { var index: Int; var ts: Int; var accumulator: Double }
        var buckets: [Bucket]

        // MARK: Gate + boundary-gap bookkeeping.
        public private(set) var sampleCount: Int
        public private(set) var firstTs: Int?
        /// Timestamp of the last sample folded — the caller queries `ts > lastTs` for the next flush.
        public private(set) var lastTs: Int?

        public init(bucketSeconds: Int = 900,
                    maxHR: Double? = nil,
                    restingHR: Double = defaultRestingHR,
                    method: Method = .edwards,
                    sex: String = "male",
                    denominator: Double = strainDenominator) {
            self.bucketSeconds = bucketSeconds
            self.maxHR = maxHR
            self.restingHR = restingHR
            self.method = method
            self.sex = sex
            self.denominator = denominator
            self.accumulator = 0
            self.gapCounts = [Int](repeating: 0, count: 300)
            self.gapTotal = 0
            self.buckets = []
            self.sampleCount = 0
            self.firstTs = nil
            self.lastTs = nil
        }

        /// Whether the scoring parameters (not the samples) match another seed — used by the caller to
        /// decide if a cached state can be extended or must be discarded and re-seeded.
        public func hasSameParameters(bucketSeconds: Int, maxHR: Double?, restingHR: Double,
                                      method: Method, sex: String, denominator: Double) -> Bool {
            self.bucketSeconds == bucketSeconds && self.maxHR == maxHR && self.restingHR == restingHR
                && self.method == method && self.sex == sex && self.denominator == denominator
        }

        // MARK: - Fold

        /// Fold a batch of NEW samples (time-ordered, each `ts` strictly greater than `lastTs`) into
        /// the running state. Empty input is a no-op — a flush with no fresh samples leaves the curve
        /// and its monotonicity untouched. Samples not strictly after `lastTs` are ignored defensively
        /// (the DB keys HR by `(deviceId, ts)`, so real flushes never repeat a timestamp).
        public mutating func extend(with newSamples: [HRSample]) {
            guard !newSamples.isEmpty else { return }
            let effMax = maxHR ?? Double(defaultMaxHR())
            let hrReserve = effMax - restingHR
            let b = sex.lowercased().hasPrefix("f") ? banisterBWomen : banisterBMen

            for sample in newSamples {
                if let last = lastTs, sample.ts <= last { continue }   // defensive dedup / re-order guard
                // Gap histogram: the spacing from the previously folded sample (nil ⇒ first sample ever).
                if let last = lastTs {
                    let g = sample.ts - last
                    if g > 0 && g < 300 { gapCounts[g] += 1; gapTotal += 1 }
                }
                // Accumulator — both branches add a term that does NOT contain sampleDur.
                switch method {
                case .edwards:
                    accumulator += Double(zoneWeight(Double(sample.bpm), restingHR: restingHR, hrReserve: hrReserve))
                case .banister:
                    let x = pctHRR(Double(sample.bpm), restingHR: restingHR, hrReserve: hrReserve) / 100.0
                    if x > 0 { accumulator += x * banisterScale * exp(b * x) }
                }
                // Bucket snapshot: keep the LAST sample of each bucket (batch emits exactly one point
                // per bucket at its last in-bucket sample, plus the final partial bucket).
                let idx = sample.ts / bucketSeconds
                if let lastBucket = buckets.last, lastBucket.index == idx {
                    buckets[buckets.count - 1] = Bucket(index: idx, ts: sample.ts, accumulator: accumulator)
                } else {
                    buckets.append(Bucket(index: idx, ts: sample.ts, accumulator: accumulator))
                }
                if firstTs == nil { firstTs = sample.ts }
                lastTs = sample.ts
                sampleCount += 1
            }
        }

        /// Non-mutating convenience: `state.extended(with:)` returns a folded copy (for a detached fold
        /// that hands the result back to `@MainActor`).
        public func extended(with newSamples: [HRSample]) -> CumulativeStrainState {
            var copy = self
            copy.extend(with: newSamples)
            return copy
        }

        // MARK: - Median (bounded histogram, exact match to `HRZones.medianInterval`)

        /// Median plausible gap in seconds, reproducing `HRZones.medianInterval` from the histogram:
        /// the true median (average of the two central order statistics for an even count), floored at
        /// 1.0, with a 1.0 fallback when there is no plausible gap.
        func medianIntervalSeconds() -> Double {
            guard sampleCount >= 2, gapTotal > 0 else { return 1.0 }
            let n = gapTotal
            if n % 2 == 1 {
                return max(Double(orderStatistic((n + 1) / 2)), 1.0)
            } else {
                let lo = orderStatistic(n / 2)
                let hi = orderStatistic(n / 2 + 1)
                return max(Double(lo + hi) / 2.0, 1.0)
            }
        }

        /// The `k`-th smallest gap (1-indexed) read off the histogram in O(300).
        private func orderStatistic(_ k: Int) -> Int {
            var cumulative = 0
            for g in 1..<gapCounts.count {
                cumulative += gapCounts[g]
                if cumulative >= k { return g }
            }
            return gapCounts.count - 1   // unreachable while k ≤ gapTotal
        }

        /// Per-sample duration in minutes — the exact analogue of `sampleDurationMinutes`.
        var sampleDurationMinutes: Double { medianIntervalSeconds() / 60.0 }

        // MARK: - Gate + materialization

        /// The same acceptance gate as `strain(_:)` / `cumulativeStrain(_:)` (`hasEnoughData`): a dense
        /// stream (≥ `minReadings`) OR a sparse-but-sustained one (≥ `minSparseReadings` spanning
        /// ≥ `minSpanSeconds`). `firstTs`/`lastTs` are the min/max ts since samples arrive ordered.
        public var hasEnoughData: Bool {
            if sampleCount >= minReadings { return true }
            guard sampleCount >= minSparseReadings, let f = firstTs, let l = lastTs else { return false }
            return l - f >= minSpanSeconds
        }

        /// The accumulated intraday curve, identical to `cumulativeStrain` over the folded samples.
        /// `[]` under the same guard (`hasEnoughData`, valid HRR, positive bucket).
        public var curve: [CumulativeStrainPoint] {
            let effMax = maxHR ?? Double(defaultMaxHR())
            guard hasEnoughData, effMax > restingHR, bucketSeconds > 0 else { return [] }
            let sampleDur = sampleDurationMinutes
            return buckets.map {
                CumulativeStrainPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)),
                                      strain: trimpToStrain(sampleDur * $0.accumulator, denominator: denominator))
            }
        }

        /// The day's strain so far, identical to `strain(_:)` over the folded samples. `nil` under the
        /// same guard (not enough data, or invalid HRR).
        public var strain: Double? {
            let effMax = maxHR ?? Double(defaultMaxHR())
            guard hasEnoughData, effMax > restingHR else { return nil }
            return trimpToStrain(sampleDurationMinutes * accumulator, denominator: denominator)
        }
    }
}
