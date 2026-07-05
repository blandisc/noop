import Foundation
import WhoopStore

/// On-device "Readiness" intelligence.
///
/// Synthesizes a handful of established, non-medical sports-science signals from the daily-metrics
/// history into a single readiness read plus the drivers behind it. Everything here is a pure,
/// deterministic function of the rows you pass in — no networking, no strap commands, no state.
///
/// Signals and their references:
/// - **HRV readiness** — z-score of today's HRV against the personal trailing baseline. A drop of
///   roughly half a standard deviation flags autonomic fatigue (Plews et al. 2013; Buchheit 2014).
/// - **Resting-HR drift** — elevated resting HR vs baseline is a classic overtraining / illness
///   signal (Buchheit 2014, Front Physiol 5:73 — resting / exercise / recovery HR for training-status
///   monitoring; Lamberts et al. 2004 covers *submaximal-exercise* HR, a different measure).
/// - **Respiratory-rate drift** — a rise in sleeping respiratory rate is an early illness signal.
/// - **Training Stress Balance (ACWR)** — acute (7-day) vs chronic (28-day) strain. The 0.8–1.3
///   band reads as balanced load (Gabbett 2016). NOOP treats it as a load-balance descriptor, not an
///   injury predictor: the "sweet spot" and the ACWR→injury link are a debated heuristic, not a
///   validated threshold — the coupled ratio (acute is inside chronic) inflates correlation (Lolli
///   et al. 2019, BJSM) and the metric's statistical properties undercut causal use (Impellizzeri
///   et al. 2020, Int J Sports Physiol Perform 15(6):907).
/// - **Training monotony** — mean/SD of daily strain over a week; high monotony (low variety) is
///   associated with higher strain and illness (Foster 1998).
///
/// Not medical advice. These are approximations from a consumer strap; they describe trends in
/// *your own* data, nothing more.
public enum ReadinessEngine {

    // MARK: Output types

    public enum Level: String, Sendable, Equatable {
        case primed       // signals aligned, load supported
        case balanced     // nothing notable either way
        case strained     // one meaningful signal down / load high
        case rundown      // several recovery signals down
        case insufficient // not enough history yet
    }

    public enum Flag: String, Sendable, Equatable {
        case good, neutral, watch, bad

        /// The single place the σ cutoffs live: an oriented z (+ = better than baseline) → flag.
        /// Both the readiness signals and the recovery-summary «Qué la movió hoy» rows (FER-628) map
        /// through this, so a signal's state word can never disagree across surfaces.
        public init(orientedZ z: Double) {
            switch z {
            case 0.5...:        self = .good
            case -0.5..<0.5:    self = .neutral
            case -1.0 ..< -0.5: self = .watch
            default:            self = .bad
            }
        }
    }

    /// Why the verdict reads the way it does, as one small decision the UI turns into a single
    /// reconciling sentence ("you woke up recovered, but your load is the thing to watch"). Kept
    /// separate from the copy so the *decision* is unit-testable without asserting localized
    /// strings. "Recovery high" everywhere here means recovery ≥ `RecoveryScorer.bandYellowMax`
    /// (the green band) — one source of truth, shared with the score's own coloring.
    public enum BridgeKind: String, Sendable, Equatable {
        case divergenceLoad   // recovery high, but training load (ACWR) is the lead flag
        case divergenceBody   // recovery high, but a body signal (HRV/RHR/temp/resp) is flagging
        case aligned          // primed / balanced — nothing meaningfully flagging
        case strainedFlat     // strained without a high-recovery divergence to explain
        case rundown          // several signals down at once
        case none             // insufficient history — no verdict to reconcile
    }

    /// The acute:chronic workload band, as a small named scale shared by every surface so the
    /// thresholds (0.8 / 1.3 / 1.5) live in exactly one place. The verdict hero shows `shortLabel`
    /// colored by `flag`; the signals list keeps the longer per-band sentence in `acwrSignal`.
    public enum LoadBand: String, Sendable, Equatable {
        case rampingDown   // < 0.8  — backing off, room to build
        case sweetSpot     // 0.8–1.3 — the productive band
        case buildingFast  // 1.3–1.5 — ramping hard, watch fatigue
        case spiking       // ≥ 1.5  — load well above your usual; a context signal, not an injury claim

        /// Short, glanceable label for the verdict row. Localized against the host app catalog.
        public var shortLabel: String {
            switch self {
            case .rampingDown:  return String(localized: "Light load", bundle: .main)
            case .sweetSpot:    return String(localized: "Balanced load", bundle: .main)
            case .buildingFast: return String(localized: "Rising load", bundle: .main)
            case .spiking:      return String(localized: "High load", bundle: .main)
            }
        }

        /// The flag color this band maps to — same mapping the `acwr` Signal uses.
        public var flag: Flag {
            switch self {
            case .sweetSpot:                  return .good
            case .rampingDown, .buildingFast: return .watch
            case .spiking:                    return .bad
            }
        }
    }

    public struct Signal: Sendable, Equatable {
        public let key: String      // "hrv" | "rhr" | "respRate" | "acwr" | "monotony"
        public let label: String    // short human label
        public let detail: String   // one-line plain-English read
        public let flag: Flag
        /// A compact, glanceable read-out of HOW FAR this signal sits from its personal baseline — the
        /// engine's own currency exposed for the instrument cluster's «Señales» row (FER-292 v2). Signed
        /// toward the raw direction (above baseline = `+`), independent of valence (the `flag` carries
        /// good/bad). σ for the z-scored body signals (HRV / resting-HR / respiratory rate), °C for skin
        /// temperature, the bare acute:chronic ratio for training load. Locale-neutral (σ, °C, a number),
        /// so it needs no catalog string. nil when there's nothing meaningful to quantify. Additive — the
        /// flag/level synthesis never reads it, so verdicts are unchanged.
        public let value: String?
        /// The same deviation as `value`, but as a raw signed number in σ (above baseline = `+`), for
        /// surfaces that need to POSITION it on an axis (the recovery «vs your base» bar), not just print
        /// it. Only the z-scored body signals (HRV / resting-HR / respiratory rate) carry it; nil for
        /// skin-temperature (°C, an asymmetric one-sided flag) and training load (a ratio, not a σ).
        /// Additive — the flag/level synthesis never reads it, so verdicts are unchanged. (FER-476)
        public let z: Double?
        public init(key: String, label: String, detail: String, flag: Flag, value: String? = nil, z: Double? = nil) {
            self.key = key; self.label = label; self.detail = detail; self.flag = flag
            self.value = value; self.z = z
        }
    }

    public struct Readiness: Sendable, Equatable {
        public let level: Level
        public let headline: String
        public let summary: String
        public let signals: [Signal]
        /// Acute:chronic workload ratio (nil if not enough strain history).
        public let acwr: Double?
        /// Foster training monotony over the last week (nil if not enough strain history).
        public let monotony: Double?
        /// True when last night's sleep ran short enough to undermine the morning's HRV/recovery read
        /// — the verdict still stands, but surfaces should flag it (caveat line + "Low conf" on HRV)
        /// rather than present it as high-confidence. Additive; defaults to false for existing callers.
        public let confidenceLow: Bool
        /// A localized one-liner explaining `confidenceLow` (nil when confidence is normal).
        public let confidenceNote: String?
        /// Why the verdict reads the way it does — the testable decision behind `bridge`.
        public let bridgeKind: BridgeKind
        /// A localized one-liner reconciling recovery vs. the verdict for the user
        /// ("you woke up recovered, but your load is the thing to watch"). nil only for `.none`.
        public let bridge: String?
        /// Short localized noun for what's behind the verdict, for the verdict card sublabel
        /// ("from your training load"). nil when nothing is to blame (aligned / insufficient).
        public let culpritNoun: String?
        public init(level: Level, headline: String, summary: String,
                    signals: [Signal], acwr: Double?, monotony: Double?,
                    confidenceLow: Bool = false, confidenceNote: String? = nil,
                    bridgeKind: BridgeKind = .none, bridge: String? = nil,
                    culpritNoun: String? = nil) {
            self.level = level; self.headline = headline; self.summary = summary
            self.signals = signals; self.acwr = acwr; self.monotony = monotony
            self.confidenceLow = confidenceLow; self.confidenceNote = confidenceNote
            self.bridgeKind = bridgeKind; self.bridge = bridge
            self.culpritNoun = culpritNoun
        }

        /// The training-load band for this read, derived from `acwr` (nil when there's no load yet).
        /// Surfaces show `loadBand?.shortLabel` instead of a raw ratio the user can't interpret.
        public var loadBand: LoadBand? { acwr.map(ReadinessEngine.loadBand(forACWR:)) }
    }

    // MARK: Tunables (named so the thresholds are auditable)

    private static let baselineWindow = 30   // days for HRV / RHR / RR baselines
    private static let minBaseline    = 7    // need at least this many baseline nights
    private static let acuteWindow    = 7
    private static let chronicWindow  = 28
    private static let minChronic     = 14   // need at least this much strain history for ACWR
    /// Below this much sleep last night the morning read is flagged low-confidence (a short night
    /// suppresses HRV and inflates resting HR independent of true recovery). 6 hours.
    private static let shortNightMinutes: Double = 360

    // MARK: Entry point

    /// Evaluate readiness from daily metrics. `days` may be in any order; the most recent day is
    /// treated as "today" unless `today` (a YYYY-MM-DD string) is given.
    public static func evaluate(days: [DailyMetric], today: String? = nil) -> Readiness {
        let sorted = days.sorted { $0.day < $1.day }
        // When an explicit `today` is given (the dashboard passes the device's real local day key), use
        // the row for THAT day and nothing else: a stale historical import has no row for today, so the
        // readiness card reads "insufficient" rather than synthesizing off the newest stored — possibly
        // months-old — row (issue #23/#24). With no `today` (live-strap default callers) fall back to the
        // most recent row exactly as before, so nothing wearing the strap nightly changes.
        let latestRow: DailyMetric?
        if let today { latestRow = sorted.first { $0.day == today } } else { latestRow = sorted.last }
        guard let latest = latestRow else {
            return Readiness(level: .insufficient,
                             headline: String(localized: "Readiness", bundle: .main),
                             summary: String(localized: "Wear the strap for a few nights and your readiness read will appear here.", bundle: .main),
                             signals: [], acwr: nil, monotony: nil)
        }
        let history = sorted.filter { $0.day < latest.day }   // everything before today

        var signals: [Signal] = []

        // HRV readiness ------------------------------------------------------
        let hrvSignal = zSignal(
            value: latest.avgHrv,
            history: history.map { $0.avgHrv }, cfg: Baselines.hrvCfg,
            key: "hrv", label: String(localized: "HRV", bundle: .main),
            higherIsBetter: true,
            goodText: String(localized: "above your baseline — well recovered", bundle: .main),
            neutralText: String(localized: "in your normal range", bundle: .main),
            watchText: String(localized: "slightly below your usual", bundle: .main),
            badText: String(localized: "suppressed — a sign of autonomic fatigue", bundle: .main))
        if let s = hrvSignal { signals.append(s) }

        // Resting-HR drift ---------------------------------------------------
        let rhrSignal = zSignal(
            value: latest.restingHr.map(Double.init),
            history: history.map { $0.restingHr.map(Double.init) }, cfg: Baselines.restingHRCfg,
            key: "rhr", label: String(localized: "Resting HR", bundle: .main),
            higherIsBetter: false,
            goodText: String(localized: "at or below baseline", bundle: .main),
            neutralText: String(localized: "in your normal range", bundle: .main),
            watchText: String(localized: "running a little high", bundle: .main),
            badText: String(localized: "elevated — overtraining or illness can do this", bundle: .main))
        if let s = rhrSignal { signals.append(s) }

        // Respiratory-rate drift (illness early signal) ----------------------
        if let rr = latest.respRateBpm {
            let base = history.suffix(baselineWindow).compactMap { $0.respRateBpm }
            if base.count >= minBaseline, let sd = sampleSD(base), sd > 0 {
                let z = (rr - mean(base)!) / sd
                if z >= 1.5 {
                    signals.append(Signal(key: "respRate", label: String(localized: "Respiratory rate", bundle: .main),
                        detail: String(localized: "up vs baseline — sometimes an early sign of getting sick", bundle: .main),
                        flag: .bad, value: String(format: "%+.1fσ", z), z: z))
                } else if z >= 1.0 {
                    signals.append(Signal(key: "respRate", label: String(localized: "Respiratory rate", bundle: .main),
                        detail: String(localized: "slightly raised vs baseline", bundle: .main),
                        flag: .watch, value: String(format: "%+.1fσ", z), z: z))
                }
            }
        }

        // Skin-temperature rise (illness / overreaching early signal) --------
        // skinTempDevC is already baseline-normalized (°C above the personal mean);
        // a sustained rise is a classic early illness marker (Oura uses ~+0.5 °C).
        if let dev = latest.skinTempDevC {
            if dev >= 0.8 {
                signals.append(Signal(key: "skinTemp", label: String(localized: "Skin temperature", bundle: .main),
                    detail: String(localized: "well above baseline — often an early sign of illness", bundle: .main),
                    flag: .bad, value: String(format: "%+.1f °C", dev)))
            } else if dev >= 0.4 {
                signals.append(Signal(key: "skinTemp", label: String(localized: "Skin temperature", bundle: .main),
                    detail: String(localized: "running warm vs baseline", bundle: .main),
                    flag: .watch, value: String(format: "%+.1f °C", dev)))
            }
        }

        // Training Stress Balance (ACWR) + monotony --------------------------
        // Computed on TRIMP-like LINEAR load, not the 0–21 log-compressed strain:
        // the log map flattens hard days, which understates the acute:chronic ramp
        // (and inflates monotony) that these signals exist to catch. strainToLoad
        // inverts StrainScorer's log map so a spike reads as a spike.
        let strainSeries = sorted.compactMap { $0.strain }.map(strainToLoad)
        var acwr: Double? = nil
        var monotony: Double? = nil
        if strainSeries.count >= minChronic {
            let acute = mean(Array(strainSeries.suffix(acuteWindow)))!
            let chronic = mean(Array(strainSeries.suffix(chronicWindow)))!
            if chronic > 0 {
                let ratio = acute / chronic
                acwr = ratio
                signals.append(acwrSignal(ratio))
            }
            // Foster monotony over the last week of strain.
            let week = Array(strainSeries.suffix(acuteWindow))
            if week.count >= 4, let sd = sampleSD(week), sd > 0, let m = mean(week) {
                let mono = m / sd
                monotony = mono
                if mono >= 2.0 {
                    signals.append(Signal(key: "monotony", label: String(localized: "Training variety", bundle: .main),
                        detail: String(localized: "low — similar strain every day raises strain/illness risk", bundle: .main),
                        flag: .watch, value: String(format: "%.1f", mono)))
                }
            }
        }

        // Confidence: a short night suppresses HRV / lifts resting HR regardless of true recovery,
        // so the morning read is honestly flagged low-confidence (drives the verdict caveat + the
        // "Low conf" chip on HRV). Only claimed when we actually have last night's sleep duration.
        let confidenceLow = (latest.totalSleepMin ?? .greatestFiniteMagnitude) < Self.shortNightMinutes
        let confidenceNote = confidenceLow
            ? String(localized: "Based on a short night — confidence low.", bundle: .main)
            : nil

        let (level, headline, summary) = synthesize(signals: signals,
                                                    hasHistory: !history.isEmpty || acwr != nil)
        // Reconciliation line: recovery and the verdict are two different reads and can diverge
        // (a high recovery with a "Strained" verdict is the classic case). Decide WHY in one place
        // (testable), then localize it. recovery comes from today's row; nil → not "high".
        let lead = leadSignal(signals)
        let kind = bridgeKind(level: level, recovery: latest.recovery, lead: lead)
        return Readiness(level: level, headline: headline, summary: summary,
                         signals: signals, acwr: acwr, monotony: monotony,
                         confidenceLow: confidenceLow, confidenceNote: confidenceNote,
                         bridgeKind: kind, bridge: bridgeCopy(kind, lead: lead),
                         culpritNoun: verdictCulprit(kind: kind, lead: lead))
    }

    // MARK: Signal builders

    /// Build a z-score signal for a metric, scored against the SAME robust EWMA
    /// baseline (winsorized center + abs-dev spread) that RecoveryScorer consumes —
    /// so the readiness read and the recovery score never tell two different stories
    /// about the same HRV / resting-HR night. `history` is the ordered nightly series
    /// before today (oldest → newest), with nils for missing nights (skip-and-hold).
    private static func zSignal(value: Double?, history: [Double?], cfg: MetricCfg,
                                key: String, label: String, higherIsBetter: Bool,
                                goodText: String, neutralText: String,
                                watchText: String, badText: String) -> Signal? {
        guard let v = value else { return nil }
        let state = Baselines.foldHistory(history, cfg: cfg)
        guard state.nValid >= minBaseline, state.spread > 0 else { return nil }
        // deviation.z = (value − baseline) / (1.253 × spread); orient so positive
        // always means "better" (invert for lower-is-better metrics like resting HR).
        let dev = Baselines.deviation(v, state: state)
        // Shrink toward neutral when the baseline is thin (FER-13), so a flag isn't
        // raised on weak evidence; a trusted baseline (≥ minNightsTrust) is unshrunk.
        let z = (higherIsBetter ? dev.z : -dev.z) * Baselines.confidence(nValid: state.nValid)
        let flag = Flag(orientedZ: z)
        let text: String
        switch flag {
        case .good:    text = goodText
        case .neutral: text = neutralText
        case .watch:   text = watchText
        case .bad:     text = badText
        }
        // The compact read-out shows the RAW deviation from baseline (above = `+`), in σ — the unit the
        // flag itself is decided in. `dev.z` is unoriented (not flipped for lower-is-better metrics), so a
        // high resting-HR reads `+1.2σ` (raw direction) with a `.watch`/`.bad` dot, while a high HRV reads
        // `+1.4σ` with `.good`: the number is direction, the dot is valence.
        let valueText = String(format: "%+.1fσ", dev.z)
        return Signal(key: key, label: label, detail: text, flag: flag, value: valueText, z: dev.z)
    }

    /// The one place the acute:chronic thresholds live. `acwrSignal` and `Readiness.loadBand`
    /// both route through this, so the verdict word and the signal sentence can never disagree.
    public static func loadBand(forACWR ratio: Double) -> LoadBand {
        switch ratio {
        case ..<0.8:    return .rampingDown
        case 0.8..<1.3: return .sweetSpot
        case 1.3..<1.5: return .buildingFast
        default:        return .spiking
        }
    }

    private static func acwrSignal(_ ratio: Double) -> Signal {
        let pct = String(format: "%.2f", ratio)
        let label = String(localized: "Training load", bundle: .main)
        let band = loadBand(forACWR: ratio)
        // The compact read-out is the bare acute:chronic ratio (one decimal) — a load of 1.0 means acute
        // == chronic. No σ here: load is already a normalized ratio, not a deviation from a baseline.
        let value = String(format: "%.1f", ratio)
        // Copy is PURELY DESCRIPTIVE of the acute↔chronic relationship — no injury-risk imperative
        // ("watch fatigue", "ease off"): Impellizzeri et al. 2020 (Br J Sports Med 54:1451–1462) show the
        // ACWR does NOT predict injury, so the sentence states where your acute load sits vs your chronic,
        // nothing more. See docs/ANALYTICS.md (Training Stress Balance).
        switch band {
        case .rampingDown:
            return Signal(key: "acwr", label: label,
                detail: String(localized: "ramping down (acute:chronic \(pct)) — acute below chronic", bundle: .main), flag: band.flag, value: value)
        case .sweetSpot:
            return Signal(key: "acwr", label: label,
                detail: String(localized: "in the sweet spot (acute:chronic \(pct)) — acute in line with chronic", bundle: .main), flag: band.flag, value: value)
        case .buildingFast:
            return Signal(key: "acwr", label: label,
                detail: String(localized: "building fast (acute:chronic \(pct)) — acute above chronic", bundle: .main), flag: band.flag, value: value)
        case .spiking:
            return Signal(key: "acwr", label: label,
                detail: String(localized: "spiking (acute:chronic \(pct)) — acute well above chronic", bundle: .main), flag: band.flag, value: value)
        }
    }

    // MARK: Synthesis

    private static func synthesize(signals: [Signal], hasHistory: Bool) -> (Level, String, String) {
        guard hasHistory, !signals.isEmpty else {
            return (.insufficient, String(localized: "Readiness", bundle: .main),
                    String(localized: "A few more nights of data and your readiness read will sharpen.", bundle: .main))
        }
        let bad = signals.filter { $0.flag == .bad }
        let watch = signals.filter { $0.flag == .watch }
        let good = signals.filter { $0.flag == .good }
        let recoveryDown = signals.contains { ["hrv", "rhr", "respRate", "skinTemp"].contains($0.key) && ($0.flag == .bad) }
        let loadHigh = signals.contains { $0.key == "acwr" && $0.flag == .bad }

        if bad.count >= 2 || (recoveryDown && loadHigh) {
            return (.rundown, String(localized: "Run down", bundle: .main),
                    String(localized: "Several signals are down at once. Treat today as recovery — easy movement, real sleep tonight.", bundle: .main))
        }
        if recoveryDown || loadHigh || bad.count >= 1 {
            return (.strained, String(localized: "Strained", bundle: .main),
                    String(localized: "One of your signals is flagging. You can train, but keep it controlled and bank the recovery.", bundle: .main))
        }
        if good.count >= 2 && watch.isEmpty {
            return (.primed, String(localized: "Primed", bundle: .main),
                    String(localized: "Your signals are aligned and your load is supported. A harder session is well backed today.", bundle: .main))
        }
        return (.balanced, String(localized: "Balanced", bundle: .main),
                String(localized: "Nothing's flagging. Train to feel — your body's holding steady.", bundle: .main))
    }

    // MARK: Reconciliation (recovery vs. verdict)

    /// The single signal most responsible for the verdict, for the reconciling sentence: the
    /// worst-flagged one (`.bad` before `.watch`), taken in append order so the first match is the
    /// natural culprit. nil when nothing is flagging.
    static func leadSignal(_ signals: [Signal]) -> Signal? {
        signals.first { $0.flag == .bad } ?? signals.first { $0.flag == .watch }
    }

    /// The reconciliation decision (pure, deterministic, testable). `recovery` is today's 0–100
    /// recovery score (nil while calibrating). "High" reuses `RecoveryScorer.bandYellowMax` so the
    /// "you woke up recovered" claim and the score's green band can never disagree.
    static func bridgeKind(level: Level, recovery: Double?, lead: Signal?) -> BridgeKind {
        let recoveryHigh = (recovery ?? 0) >= RecoveryScorer.bandYellowMax
        switch level {
        case .insufficient:    return .none
        case .primed, .balanced: return .aligned
        case .rundown:         return .rundown
        case .strained:
            // Only a genuinely high recovery makes this a "great everywhere except X" divergence;
            // otherwise it's a flat caution with nothing to reconcile.
            guard recoveryHigh, let lead else { return .strainedFlat }
            return lead.key == "acwr" ? .divergenceLoad : .divergenceBody
        }
    }

    /// Possessive noun for a signal, for the divergence sentence ("…what needs care is {your HRV}")
    /// and the verdict card's sublabel ("from {your training load}"). One source so both agree.
    private static func signalNoun(_ key: String) -> String {
        switch key {
        case "acwr":     return String(localized: "your training load", bundle: .main)
        case "hrv":      return String(localized: "your HRV", bundle: .main)
        case "rhr":      return String(localized: "your resting heart rate", bundle: .main)
        case "skinTemp": return String(localized: "your skin temperature", bundle: .main)
        case "respRate": return String(localized: "your breathing", bundle: .main)
        default:         return String(localized: "one of your signals", bundle: .main)
        }
    }

    /// Short noun for the culprit behind the verdict, for the verdict card's sublabel
    /// ("Strained · from your training load"). nil when there's nothing to blame (aligned / none).
    static func verdictCulprit(kind: BridgeKind, lead: Signal?) -> String? {
        switch kind {
        case .none, .aligned:
            return nil
        case .rundown:
            return String(localized: "several signals", bundle: .main)
        case .divergenceLoad, .divergenceBody, .strainedFlat:
            return lead.map { signalNoun($0.key) }
        }
    }

    /// The localized reconciling sentence for a bridge decision (nil only for `.none`).
    static func bridgeCopy(_ kind: BridgeKind, lead: Signal?) -> String? {
        switch kind {
        case .none:
            return nil
        case .aligned:
            return String(localized: "Your signals are aligned and your load is supported. A harder session is well backed today.", bundle: .main)
        case .rundown:
            return String(localized: "Several signals are down at once. Treat today as recovery.", bundle: .main)
        case .strainedFlat:
            return String(localized: "One of your signals is flagging. You can train, but keep it controlled.", bundle: .main)
        case .divergenceLoad:
            return String(localized: "You woke up well recovered. What needs care today is your training load, not your body.", bundle: .main)
        case .divergenceBody:
            return String(localized: "Your recovery is high, but \(signalNoun(lead?.key ?? "")) is flagging — keep an eye on that today.", bundle: .main)
        }
    }

    // MARK: Stats helpers

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n-1). nil for fewer than 2 points.
    static func sampleSD(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let ss = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(xs.count - 1)).squareRoot()
    }

    /// Linearize a 0–21 logarithmic strain back to a TRIMP-like load (the inverse
    /// of StrainScorer's `21·ln(TRIMP+1)/ln(D)` map) so ACWR and monotony run on a
    /// dose linear in physiological load. For imported strains on a comparable 0–21
    /// log scale this is a consistent linearization, not an exact TRIMP recovery.
    static func strainToLoad(_ strain: Double) -> Double {
        guard strain > 0 else { return 0 }
        let lnD = log(StrainScorer.strainDenominator)
        return max(0, exp(strain * lnD / StrainScorer.maxStrain) - 1.0)
    }
}
