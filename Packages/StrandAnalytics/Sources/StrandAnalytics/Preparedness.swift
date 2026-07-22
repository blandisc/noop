import Foundation
import StrandModels

/// Preparedness — the honest "how you woke up" morning verdict for Apple-only Cénit (FER-1030).
///
/// A pure, deterministic composition (no store, no clock, no UIKit) that reads a handful of
/// overnight Apple-Health signals against the user's OWN baseline and returns a categorical
/// verdict — never a 0–100 number. It answers *"today: push or ease?"*.
///
/// ## Design (settled through two adversarial science rounds + a product negotiation)
/// - **Consensus by AXIS, not by signal.** HRV + resting-HR + respiration collapse into ONE
///   `autonomic` vote via a *weighted composite* (never the min-of-three, which biases to −0.85,
///   and never a flag count) — this is what stops a single bad night (which moves all three at
///   once) from being counted three times (FER-1010).
/// - **Reuses `Baselines`** (public API) for the per-signal z; does NOT depend on `ReadinessEngine`
///   (its ACWR / monotony machinery is band-era load, out of scope for a passive Apple morning read).
/// - **Two different HRV constructs, kept separate:** the autonomic axis z-scores Apple's **SDNN**
///   (`DailyMetric.avgHrv`); the trend sparkline (a separate surface) uses the real nocturnal
///   **RMSSD** carried in `AutonomicTrend.Read`. They never mix (the three-baseline invariant).
/// - **Trend is a nudge, not a vote:** a sustained downward RMSSD trend pushes a borderline day to
///   `easy`, but the daily verdict stands on the body signals.
///
/// ## What is NOT signed here (⚠️ `/cso` gate owns the numbers)
/// The weights, the SDNN baseline calibration, the oriented cut-offs, the thermal °C cut-offs and
/// the hysteresis window all live in `Config` as **named product-calibration knobs with documented
/// defaults**. They are deliberately explicit so `/implement` never invents science; `/cso` signs
/// the values. The *structure* (axis composition, no double-count, cold-start = null vote,
/// hysteresis) is what these tests lock.
///
/// References: Plews et al. 2013 (Sports Med 43(9):773) for trend-over-snapshot; the "signals vs
/// your own typical range" consensus mirrors Apple's own Vitals framing. APPROXIMATE, no clinical
/// claim.
public enum Preparedness {

    // MARK: Output

    /// The four states shown as the hero verdict. The user-facing es-MX copy lives in the UI.
    public enum Verdict: String, Sendable, Equatable {
        case full        // "Dale con todo"     — no axis out
        case caution     // "Bien, con un detalle" — one axis out
        case easy        // "Ándate leve"       — ≥2 axes out, or trend falling
        case lowSignal   // "Baja señal"        — the autonomic core has no usable read → fall to sleep
    }

    public enum Axis: String, Sendable, Equatable { case autonomic, sleep, thermal, load }

    /// Per-axis read. `.inRange` includes "better than your normal" — being *above* baseline on a
    /// good-direction signal is never counted as a problem (oriented z).
    public enum AxisState: String, Sendable, Equatable {
        case inRange
        case low        // worse than baseline in the "down" direction
        case high       // worse than baseline in the "up" direction (e.g. temp elevated)
        case noData     // not enough baseline / no reading tonight → does not vote

        public var isOut: Bool { self == .low || self == .high }
        public var hasData: Bool { self != .noData }
    }

    public struct Driver: Sendable, Equatable {
        public let axis: Axis
        public let state: AxisState
        /// Oriented composite z for the axis (+ = better than baseline). nil for `thermal`/`load`
        /// (they use °C / strain, not z) and for `noData`.
        public let orientedZ: Double?
        public init(axis: Axis, state: AxisState, orientedZ: Double?) {
            self.axis = axis; self.state = state; self.orientedZ = orientedZ
        }
    }

    public struct Read: Sendable, Equatable {
        public let verdict: Verdict
        public let drivers: [Driver]
        /// Coverage as (signals-with-a-reading-tonight, total body signals) — surfaced as the
        /// honest confidence tether. Never hidden.
        public let signalsPresent: Int
        public let signalsTotal: Int
        /// Model maturity of the autonomic baseline, mapped to the shipped enum. `.calibrating`
        /// means the verdict is `lowSignal` (not enough of your own nights yet).
        public let maturity: BaselineStatus
        /// The RMSSD trend direction (from `AutonomicTrend`), for the sparkline + the "falling"
        /// nudge. Independent of the verdict's body-signal axes.
        public let trend: AutonomicTrend.Direction?
        public init(verdict: Verdict, drivers: [Driver], signalsPresent: Int, signalsTotal: Int,
                    maturity: BaselineStatus, trend: AutonomicTrend.Direction?) {
            self.verdict = verdict; self.drivers = drivers
            self.signalsPresent = signalsPresent; self.signalsTotal = signalsTotal
            self.maturity = maturity; self.trend = trend
        }
    }

    // MARK: Inputs

    /// Everything the composer needs, pre-resolved by the caller (keeps this pure). `days` are the
    /// RAW Apple rows (no `SourceLens` masking — greenfield has one source); `strainByDay` is the
    /// per-day Apple workout strain (FER-883), which lives OUTSIDE `days` in `DashboardData`.
    public struct Input: Sendable {
        public let days: [DailyMetric]              // oldest → newest, includes the asOf row
        public let strainByDay: [String: Double]    // Apple workout-HR strain; nil-absent = no workout
        public let trend: AutonomicTrend.Read?
        public let asOf: String                     // "YYYY-MM-DD" local civil day
        public init(days: [DailyMetric], strainByDay: [String: Double],
                    trend: AutonomicTrend.Read?, asOf: String) {
            self.days = days; self.strainByDay = strainByDay; self.trend = trend; self.asOf = asOf
        }
    }

    // MARK: Config — named, `/cso`-gated knobs (defaults are provisional)

    public struct Config: Sendable, Equatable {
        // Autonomic composite weights (must sum > 0). Default: RHR/HRV weighted for Apple's better
        // resting-HR fidelity vs its sparse SDNN. `/cso` signs these.
        public var wHRV: Double = 0.35
        public var wRHR: Double = 0.40
        public var wResp: Double = 0.25
        /// Oriented-z below which an axis counts as OUT. −1.0 (one-sided ≈16%) matches the shipped
        /// `ReadinessEngine.Flag.bad` cut; NOT `|z|≤1` (rejected as noisy in `VitalBands`). `/cso`.
        public var autonomicOutZ: Double = -1.0
        /// Respiration is watched wider (its own shipped cut-offs), so a normal rise isn't flagged.
        public var respWatchZ: Double = 1.0
        public var respBadZ: Double = 1.5
        /// Skin-temp deviation (°C from Apple's own baseline) that counts as OUT. Absolute, no z.
        public var thermalOutC: Double = 0.8
        /// Consecutive daily readings a NEW raw verdict must hold before it replaces the stable one.
        public var hysteresisDays: Int = 2
        /// Baseline config used to z-score Apple's SDNN. ⚠️ `Baselines.metricCfg["hrv"]` is
        /// calibrated for ln(RMSSD); reusing it for SDNN is provisional and MUST be validated by
        /// `/cso` (RMSSD ≠ SDNN — the same trap that killed the v1 design).
        public var sdnnCfgKey: String = "hrv"
        public init() {}
        public static let `default` = Config()
    }

    // MARK: Evaluate

    public static func evaluate(_ input: Input, config: Config = .default) -> Read {
        let ordered = input.days
            .filter { $0.day <= input.asOf }
            .sorted { $0.day < $1.day }
        guard let today = ordered.last, today.day == input.asOf else {
            return Read(verdict: .lowSignal, drivers: [], signalsPresent: 0, signalsTotal: 3,
                        maturity: .calibrating, trend: input.trend?.direction)
        }
        let priors = Array(ordered.dropLast())   // history strictly before asOf

        // --- Body-signal oriented z's (raw days; greenfield = one source, no masking) ---
        let hrvZ = orientedZ(priors: priors, today: today,
                             value: { $0.avgHrv }, cfgKey: config.sdnnCfgKey, betterWhenHigher: true)
        let rhrZ = orientedZ(priors: priors, today: today,
                             value: { $0.restingHr.map(Double.init) }, cfgKey: "resting_hr", betterWhenHigher: false)
        let respZ = orientedZ(priors: priors, today: today,
                              value: { $0.respRateBpm }, cfgKey: "resp", betterWhenHigher: false)

        let signalsPresent = [hrvZ, rhrZ, respZ].compactMap { $0 }.count

        // --- Axis: autonomic (weighted composite of the present oriented z's) ---
        let autonomic = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR),
                                      resp: (respZ, config.wResp), cfg: config)

        // --- Axis: sleep ---
        let sleepAxis: Driver
        if let mins = today.totalSleepMin {
            let band = SleepBands.band(mins)
            sleepAxis = Driver(axis: .sleep, state: band == .short ? .low : .inRange, orientedZ: nil)
        } else {
            sleepAxis = Driver(axis: .sleep, state: .noData, orientedZ: nil)
        }

        // --- Axis: thermal (skinTempDevC is already a deviation from Apple's own baseline) ---
        let thermalAxis: Driver
        if let dev = today.skinTempDevC {
            let state: AxisState = dev >= config.thermalOutC ? .high : (dev <= -config.thermalOutC ? .low : .inRange)
            thermalAxis = Driver(axis: .thermal, state: state, orientedZ: nil)
        } else {
            thermalAxis = Driver(axis: .thermal, state: .noData, orientedZ: nil)
        }

        // --- Axis: load (optional — present ONLY with a real workout; its OUT logic is deferred to
        // `/cso`, so today it contributes coverage/context but never flips the verdict). ---
        let loadAxis: Driver = input.strainByDay[today.day] != nil
            ? Driver(axis: .load, state: .inRange, orientedZ: nil)
            : Driver(axis: .load, state: .noData, orientedZ: nil)

        let drivers = [autonomic, sleepAxis, thermalAxis, loadAxis]

        // --- Cold start / low signal: the autonomic core must have a usable read. ---
        if autonomic.state == .noData {
            return Read(verdict: .lowSignal, drivers: drivers, signalsPresent: signalsPresent,
                        signalsTotal: 3, maturity: autonomicMaturity(priors: priors, cfgKey: config.sdnnCfgKey),
                        trend: input.trend?.direction)
        }

        // --- Consensus + hysteresis over RAW body verdicts across history (deterministic, no persistence) ---
        let stable = hysteresed(ordered: ordered, input: input, config: config)
        // Trend nudge (post-hysteresis): a sustained falling RMSSD trend pushes a borderline day
        // (`caution`) to `easy`. It never overrides a clean `full`. `/cso` may widen this.
        let final: Verdict = (stable == .caution && input.trend?.direction == .below) ? .easy : stable

        return Read(verdict: final, drivers: drivers, signalsPresent: signalsPresent, signalsTotal: 3,
                    maturity: autonomicMaturity(priors: priors, cfgKey: config.sdnnCfgKey),
                    trend: input.trend?.direction)
    }

    // MARK: - Internals

    /// Oriented z for one body signal: builds the baseline from `priors`, deviates today's value,
    /// and orients it so + = better. Returns `(state, orientedZ)`; state is nil (noData) when the
    /// baseline isn't usable or tonight's value is missing.
    private static func orientedZ(priors: [DailyMetric], today: DailyMetric,
                                  value: (DailyMetric) -> Double?, cfgKey: String,
                                  betterWhenHigher: Bool) -> Double? {
        guard let cfg = Baselines.metricCfg[cfgKey], let todayVal = value(today) else { return nil }
        let state = Baselines.foldHistory(priors.map { (day: $0.day, value: value($0)) }, epoch: nil, cfg: cfg)
        guard state.usable else { return nil }   // < seed nights → noData (cold start)
        let dev = Baselines.deviation(todayVal, state: state)
        return betterWhenHigher ? dev.z : -dev.z   // + = better than baseline
    }

    /// Collapse HRV/RHR/resp into one autonomic vote via a weighted average of the PRESENT oriented
    /// z's (weights renormalized over present signals). `.low` iff the composite is at/under the OUT
    /// cut; respiration additionally flags on its own wider cut. Never the min (no −0.85 bias).
    private static func autonomicAxis(hrv: (Double?, Double), rhr: (Double?, Double),
                                      resp: (Double?, Double), cfg: Config) -> Driver {
        var num = 0.0, den = 0.0
        if let z = hrv.0 { num += hrv.1 * z; den += hrv.1 }
        if let z = rhr.0 { num += rhr.1 * z; den += rhr.1 }
        if let z = resp.0 { num += resp.1 * z; den += resp.1 }
        guard den > 0 else { return Driver(axis: .autonomic, state: .noData, orientedZ: nil) }
        let composite = num / den
        // Respiration has its own (wider) watch: a big respiration rise alone can flag the axis.
        // resp.0 is the ORIENTED z (−raw); raw high (bad) = −resp.0 ≥ respBadZ.
        let respOut = (resp.0.map { -$0 }).map { $0 >= cfg.respBadZ } ?? false
        let out = composite <= cfg.autonomicOutZ || respOut
        return Driver(axis: .autonomic, state: out ? .low : .inRange, orientedZ: composite)
    }

    private static func autonomicMaturity(priors: [DailyMetric], cfgKey: String) -> BaselineStatus {
        guard let cfg = Baselines.metricCfg[cfgKey] else { return .calibrating }
        return Baselines.foldHistory(priors.map { (day: $0.day, value: $0.avgHrv) }, epoch: nil, cfg: cfg).status
    }

    /// The RAW (pre-hysteresis, pre-trend) body verdict for a single as-of day. Trend is applied
    /// once, after hysteresis, in `evaluate` — never folded into the per-day raw (that would make
    /// the historical raws depend on today's trend).
    private static func rawVerdict(ordered: [DailyMetric], strainByDay: [String: Double],
                                   asOf: String, config: Config) -> Verdict {
        let sub = Input(days: ordered, strainByDay: strainByDay, trend: nil, asOf: asOf)
        let (a, s, t) = axisStates(sub, config: config)
        guard a.hasData else { return .lowSignal }
        let out = [a, s, t].filter { $0.isOut }.count
        if out == 0 { return .full }
        if out == 1 { return .caution }
        return .easy
    }

    /// Compute the three voting axis states for a given as-of (no hysteresis, no load — load never
    /// votes today).
    private static func axisStates(_ input: Input, config: Config) -> (AxisState, AxisState, AxisState) {
        let ordered = input.days.filter { $0.day <= input.asOf }.sorted { $0.day < $1.day }
        guard let today = ordered.last, today.day == input.asOf else { return (.noData, .noData, .noData) }
        let priors = Array(ordered.dropLast())
        let hrvZ = orientedZ(priors: priors, today: today, value: { $0.avgHrv }, cfgKey: config.sdnnCfgKey, betterWhenHigher: true)
        let rhrZ = orientedZ(priors: priors, today: today, value: { $0.restingHr.map(Double.init) }, cfgKey: "resting_hr", betterWhenHigher: false)
        let respZ = orientedZ(priors: priors, today: today, value: { $0.respRateBpm }, cfgKey: "resp", betterWhenHigher: false)
        let a = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR), resp: (respZ, config.wResp), cfg: config).state
        let s: AxisState = today.totalSleepMin.map { SleepBands.band($0) == .short ? .low : .inRange } ?? .noData
        let t: AxisState = today.skinTempDevC.map { $0 >= config.thermalOutC ? .high : ($0 <= -config.thermalOutC ? .low : .inRange) } ?? .noData
        return (a, s, t)
    }

    /// Forward pass applying hysteresis over the RAW verdicts of every day up to `asOf`. A new raw
    /// verdict must persist `hysteresisDays` consecutive days before it replaces the stable one.
    /// Operates on RAW (not smoothed) verdicts, so there is no unbounded recursion.
    private static func hysteresed(ordered: [DailyMetric], input: Input, config: Config) -> Verdict {
        let raws = ordered.map { rawVerdict(ordered: ordered, strainByDay: input.strainByDay,
                                            asOf: $0.day, config: config) }
        guard var stable = raws.first else { return .lowSignal }
        // A new raw verdict must persist `hysteresisDays` CONSECUTIVE days before it replaces the
        // stable one — so an isolated borderline day never flips the hero.
        var runVal = stable
        var runLen = 1
        for r in raws.dropFirst() {
            if r == runVal { runLen += 1 } else { runVal = r; runLen = 1 }
            if runVal != stable && runLen >= max(1, config.hysteresisDays) { stable = runVal }
        }
        return stable
    }
}
