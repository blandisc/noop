import Foundation
import WhoopStore

/// «Qué la movió hoy» — the per-signal decomposition of TODAY's recovery score (FER-628).
///
/// `RecoveryScorer.recovery` composes a weighted mean of per-signal z-scores and squashes it through
/// a logistic. This engine re-derives each of those terms for today and exposes the signal's ADDITIVE
/// share of that composite — `contribution = orientedZ × weight` (weights renormalized over the terms
/// present, exactly like the scorer drops missing ones) — so `Σ contribution` IS the composite z the
/// score squashed. Ranking by |contribution| answers "what moved my recovery today" honestly: a big z
/// on a 5%-weight signal (respiration) cannot outrank a moderate z on the 60% driver (HRV).
///
/// Baseline purity (FER-519 / FER-629): every fold runs on the BAND-ONLY slice — Apple-only days are
/// dropped whole-row before folding, the same `strapOnlyHistory` policy the persisted score uses, so
/// these contributions and the score can never tell two different stories about the same night. An
/// Apple-only "today" therefore returns nil (that day's recovery is the separate SDNN estimate, and a
/// band-baseline decomposition of it would be dishonest).
///
/// Pure and deterministic — no store, no clock, no state. Not medical advice.
public enum RecoveryImpact {

    /// One present signal of today's composite.
    public struct Signal: Equatable, Sendable, Identifiable {
        public let key: String        // "hrv" | "rhr" | "sleep" | "skinTemp" | "respRate"
        /// Deviation from the personal band-only baseline in σ, RAW direction (+ = above your base),
        /// confidence-shrunk exactly like the scorer's term (FER-13).
        public let z: Double
        /// The same deviation ORIENTED toward the score (+ = pushed recovery UP): HRV keeps its sign,
        /// resting HR / respiration / skin temp flip (lower is better).
        public let orientedZ: Double
        /// This signal's share of the composite after renormalizing over the present terms (0…1).
        public let weight: Double
        /// The signal's additive share of the score's composite z. Negative = it pulled today's
        /// recovery down.
        public var contribution: Double { orientedZ * weight }
        public var id: String { key }
        public init(key: String, z: Double, orientedZ: Double, weight: Double) {
            self.key = key; self.z = z; self.orientedZ = orientedZ; self.weight = weight
        }
    }

    public struct Result: Equatable, Sendable {
        /// The present signals, ordered by |contribution| descending — the first row is the day's
        /// real driver (the |z·w| ranking the FER-628/FER-632 headline requires, NOT |z|).
        public let signals: [Signal]
        public var top: Signal? { signals.first }
        /// Σ contribution — the composite z the score squashed through its logistic.
        public var compositeZ: Double { signals.reduce(0) { $0 + $1.contribution } }
        public init(signals: [Signal]) { self.signals = signals }
    }

    /// Skin-temp deviations are already baseline-normalized °C (`skinTempDevC`), so their fold runs in
    /// deviation space: same spread floor / half-lives as the absolute `skin_temp` config, with bounds
    /// wide enough for any plausible nightly deviation.
    static let skinTempDevCfg = MetricCfg(minVal: -5.0, maxVal: 5.0, floorSpread: 0.3,
                                          halfLifeB: 14.0, halfLifeS: 21.0)

    /// Decompose today's recovery into per-signal contributions.
    ///
    /// - Parameters:
    ///   - days: the merged daily history (`repo.days`); Apple-only rows are dropped here.
    ///   - todayKey: the local "yyyy-MM-dd" being explained.
    ///   - appleDays: the Apple-sourced day keys (`repo.appleHealthDays`) — the same set
    ///     `IntelligenceEngine.strapOnlyHistory` filters by before folding the score's baselines.
    /// - Returns: nil while the HRV baseline isn't usable (cold-start, mirroring the scorer's gate),
    ///   or when today has no band reading (including an Apple-only today).
    public static func compute(days: [DailyMetric], todayKey: String,
                               appleDays: Set<String> = []) -> Result? {
        let band = (appleDays.isEmpty ? days : days.filter { !appleDays.contains($0.day) })
            .sorted { $0.day < $1.day }
        guard let idx = band.firstIndex(where: { $0.day == todayKey }),
              let hrv = band[idx].avgHrv, let rhr = band[idx].restingHr else { return nil }
        let today = band[idx]
        let history = Array(band[..<idx])   // sorted, so everything before today needs no re-scan

        // Cold-start gate: same as the scorer — no usable band HRV baseline, no decomposition.
        let hrvState = Baselines.foldHistory(history.map(\.avgHrv), cfg: Baselines.hrvCfg)
        guard hrvState.usable else { return nil }

        /// A term's confidence-shrunk z vs its personal baseline (the scorer's own recipe).
        func shrunkZ(_ value: Double, _ state: BaselineState) -> Double {
            Baselines.deviation(value, state: state).z * Baselines.confidence(nValid: state.nValid)
        }

        var terms: [(key: String, z: Double, oriented: Double, w: Double)] = []

        // HRV — higher is better; the dominant driver.
        let zHrv = shrunkZ(hrv, hrvState)
        terms.append(("hrv", zHrv, zHrv, RecoveryScorer.wHRV))

        // Resting HR — lower is better. (Each optional term is gated on a USABLE personal baseline;
        // the scorer reaches the same place through its seeded pass-2 folds.)
        let rhrState = Baselines.foldHistory(history.map { $0.restingHr.map(Double.init) },
                                             cfg: Baselines.restingHRCfg)
        if rhrState.usable {
            let z = shrunkZ(Double(rhr), rhrState)
            terms.append(("rhr", z, -z, RecoveryScorer.wRHR))
        }

        // Sleep performance — higher is better. Efficiency is stored as % or fraction depending on
        // the source; normalize both today and the history the same way before folding. Falls back
        // to the fixed population center while the personal baseline seeds (the scorer's cold-start).
        func normEff(_ raw: Double?) -> Double? { raw.map { $0 > 1 ? $0 / 100 : $0 } }
        if let eff = normEff(today.efficiency) {
            let effState = Baselines.foldHistory(history.map { normEff($0.efficiency) },
                                                 cfg: Baselines.metricCfg["efficiency"]!)
            let z = effState.usable
                ? shrunkZ(eff, effState)
                : (eff - RecoveryScorer.sleepPerfCenter) / RecoveryScorer.sleepPerfScale
            terms.append(("sleep", z, z, RecoveryScorer.wSleep))
        }

        // Skin temperature — lower is better. The dashboard carries the already-normalized nightly
        // deviation (°C vs your base), not the raw mean the scorer folds, so the z runs in deviation
        // space against its own spread — the same construct, expressed relative to base. APPROXIMATE.
        if let dev = today.skinTempDevC {
            let devState = Baselines.foldHistory(history.map(\.skinTempDevC), cfg: skinTempDevCfg)
            if devState.usable {
                let z = shrunkZ(dev, devState)
                terms.append(("skinTemp", z, -z, RecoveryScorer.wTemp))
            }
        }

        // Respiration — lower is better; the scorer gates this term on a usable baseline too.
        if let resp = today.respRateBpm {
            let respState = Baselines.foldHistory(history.map(\.respRateBpm), cfg: Baselines.respCfg)
            if respState.usable {
                let z = shrunkZ(resp, respState)
                terms.append(("respRate", z, -z, RecoveryScorer.wResp))
            }
        }

        // Renormalize over the present terms (the scorer's missing-term rule), then rank by real
        // contribution to today's score.
        let totalW = terms.reduce(0) { $0 + $1.w }
        guard totalW > 0 else { return nil }
        let signals = terms
            .map { Signal(key: $0.key, z: $0.z, orientedZ: $0.oriented, weight: $0.w / totalW) }
            .sorted { abs($0.contribution) > abs($1.contribution) }
        return Result(signals: signals)
    }
}
