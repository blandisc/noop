import Foundation
import StrandModels

/// Preparedness — the honest "how you woke up" morning verdict for Apple-only Cénit (FER-1030).
///
/// A pure, deterministic composition (no store, no clock, no UIKit) that reads a handful of
/// resting Apple-Health signals against the user's OWN baseline and returns a categorical
/// verdict — never a 0–100 number. It answers *"today: push or ease?"*.
///
/// **Honest limit (`/cso`, inherited from the illness engine):** Apple's `avgHrv` is SDNN sampled
/// *all day* (`discreteAverage`), not sleep-windowed, and `restingHr` is an awake-sedentary
/// aggregate — so this is "your resting signals vs your own norm", NOT a nocturnal/sleep
/// measurement. UI copy must not claim overnight precision, and the four verdict strings must be
/// added to the claims allow-list (docs/ANALYTICS.md) before they surface.
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
        /// FER-1040: nights of the user's OWN autonomic (Apple SDNN) baseline the verdict actually
        /// stands on — the honest confidence *depth*, surfaced by the arc. This is the maturity of the
        /// SAME baseline as `maturity`, NOT the nocturnal-RMSSD `AutonomicTrend.nightsUsable` (a
        /// different construct on a different partition); the two must not be confused on the UI.
        public let autonomicNights: Int
        /// The RMSSD trend direction (from `AutonomicTrend`), for the sparkline + the "falling"
        /// nudge. Independent of the verdict's body-signal axes.
        public let trend: AutonomicTrend.Direction?
        public init(verdict: Verdict, drivers: [Driver], signalsPresent: Int, signalsTotal: Int,
                    maturity: BaselineStatus, autonomicNights: Int, trend: AutonomicTrend.Direction?) {
            self.verdict = verdict; self.drivers = drivers
            self.signalsPresent = signalsPresent; self.signalsTotal = signalsTotal
            self.maturity = maturity; self.autonomicNights = autonomicNights; self.trend = trend
        }

        /// Whether today's read is anchored by a RECORDED night of sleep (FER-1033). `false` means
        /// the body signals exist (Apple's day-aggregate SDNN / awake resting HR / respiration) but
        /// no sleep session was recorded — the user likely did not sleep with the watch, so the UI
        /// MUST demote the surface to the explicit "lectura de día" (less precise, no verdict word),
        /// never present it as the full night-anchored Preparación. Derived from the sleep axis; a
        /// night the watch missed (slept with it, Apple logged nothing) demotes too — without a
        /// session we cannot claim night anchoring.
        public var isNightAnchored: Bool {
            drivers.first(where: { $0.axis == .sleep })?.state.hasData ?? false
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
        /// Respiration flags on its own (wider) cut, so a normal nightly rise isn't flagged. A raw
        /// respiratory z at or above this counts the autonomic axis out even if the composite doesn't.
        public var respBadZ: Double = 1.5
        /// Skin-temp deviation (°C from Apple's own baseline) that counts as OUT. Absolute, no z.
        public var thermalOutC: Double = 0.8
        /// Consecutive daily readings a NEW raw verdict must hold before it replaces the stable one.
        public var hysteresisDays: Int = 2
        /// Baseline config key for Apple's SDNN (`Baselines.metricCfg["sdnn"]`). SIGNED by `/cso`
        /// (FER-1030): SDNN is z-scored WITHIN-SOURCE — Apple's SDNN against the user's OWN
        /// Apple-SDNN norm — which is right-skewed / log-normal like RMSSD and takes the same log
        /// treatment (Task Force 1996). This is NOT a cross-construct RMSSD conversion, so the
        /// "RMSSD ≠ SDNN" trap that killed the v1 design does not apply here.
        public var sdnnCfgKey: String = "sdnn"
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
                        maturity: .calibrating, autonomicNights: 0, trend: input.trend?.direction)
        }

        // --- ONE forward pass per body signal (FER-1040) ---
        // `priorStates.<sig>[i]` is the baseline built from `ordered[0..<i]` — exactly the "priors"
        // baseline day `i` must be deviated against. This replaces the old O(n²) machinery, where
        // every per-day raw verdict re-filtered + re-sorted the whole `days` array and re-folded the
        // full history from scratch (`hysteresed` × `axisStates`). `prefixStates` reuses the SAME
        // `Baselines.update` reduce, so every state — and therefore every verdict — is bit-identical.
        let priorStates = bodySignalPriorStates(ordered, config: config)
        let lastIdx = ordered.count - 1

        // --- today's oriented z's (from the last priors state) ---
        let hrvZ  = orientedZ(prior: priorStates.hrv?[lastIdx],  value: today.avgHrv,                    betterWhenHigher: true)
        let rhrZ  = orientedZ(prior: priorStates.rhr?[lastIdx],  value: today.restingHr.map(Double.init), betterWhenHigher: false)
        let respZ = orientedZ(prior: priorStates.resp?[lastIdx], value: today.respRateBpm,               betterWhenHigher: false)

        let signalsPresent = [hrvZ, rhrZ, respZ].compactMap { $0 }.count

        // --- Axis: autonomic (weighted composite of the present oriented z's) ---
        let autonomic = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR),
                                      resp: (respZ, config.wResp), cfg: config)
        let sleepAxis = sleepDriver(today)
        let thermalAxis = thermalDriver(today, config: config)
        // --- Axis: load (optional — present ONLY with a real workout; its OUT logic is deferred to
        // `/cso`, so today it contributes coverage/context but never flips the verdict). ---
        let loadAxis: Driver = input.strainByDay[today.day] != nil
            ? Driver(axis: .load, state: .inRange, orientedZ: nil)
            : Driver(axis: .load, state: .noData, orientedZ: nil)

        let drivers = [autonomic, sleepAxis, thermalAxis, loadAxis]

        // Maturity + confidence depth come from the SAME SDNN priors baseline the verdict stands on
        // (`prefixStates` last element == fold over the days strictly before asOf).
        let autoBaseline = priorStates.hrv?[lastIdx]
        let maturity = autoBaseline?.status ?? .calibrating
        let autonomicNights = autoBaseline?.nValid ?? 0

        // --- Cold start / low signal: the autonomic core must have a usable read. ---
        if autonomic.state == .noData {
            return Read(verdict: .lowSignal, drivers: drivers, signalsPresent: signalsPresent,
                        signalsTotal: 3, maturity: maturity, autonomicNights: autonomicNights,
                        trend: input.trend?.direction)
        }

        // --- Consensus + hysteresis over RAW body verdicts across history (deterministic, no persistence) ---
        let stable = hysteresed(ordered: ordered, priorStates: priorStates, config: config)
        // Trend nudge (post-hysteresis): a sustained falling RMSSD trend pushes a borderline day
        // (`caution`) to `easy`. It never overrides a clean `full`. `/cso` may widen this.
        let final: Verdict = (stable == .caution && input.trend?.direction == .below) ? .easy : stable

        return Read(verdict: final, drivers: drivers, signalsPresent: signalsPresent, signalsTotal: 3,
                    maturity: maturity, autonomicNights: autonomicNights, trend: input.trend?.direction)
    }

    // MARK: - Internals

    /// Per-day priors baselines for the three body signals, each in ONE forward pass. `nil` for a
    /// signal whose baseline config is missing (never, for the shipped keys). Element `i` of each is
    /// the baseline over `ordered[0..<i]` — what `ordered[i]` deviates against.
    private struct PriorStates {
        let hrv: [BaselineState]?
        let rhr: [BaselineState]?
        let resp: [BaselineState]?
    }
    private static func bodySignalPriorStates(_ ordered: [DailyMetric], config: Config) -> PriorStates {
        PriorStates(
            hrv:  Baselines.metricCfg[config.sdnnCfgKey].map { Baselines.prefixStates(ordered.map { $0.avgHrv }, cfg: $0) },
            rhr:  Baselines.metricCfg["resting_hr"].map { Baselines.prefixStates(ordered.map { $0.restingHr.map(Double.init) }, cfg: $0) },
            resp: Baselines.metricCfg["resp"].map { Baselines.prefixStates(ordered.map { $0.respRateBpm }, cfg: $0) }
        )
    }

    /// Oriented z for one body signal against a pre-built priors baseline: + = better than baseline.
    /// nil (noData) when the baseline isn't usable (< seed nights) or tonight's value is missing.
    private static func orientedZ(prior: BaselineState?, value: Double?, betterWhenHigher: Bool) -> Double? {
        guard let prior, prior.usable, let v = value else { return nil }
        let dev = Baselines.deviation(v, state: prior)
        return betterWhenHigher ? dev.z : -dev.z
    }

    /// Sleep axis for a given day — `.low` iff the night is short, `.noData` when unmeasured.
    private static func sleepDriver(_ day: DailyMetric) -> Driver {
        guard let mins = day.totalSleepMin else { return Driver(axis: .sleep, state: .noData, orientedZ: nil) }
        return Driver(axis: .sleep, state: SleepBands.band(mins) == .short ? .low : .inRange, orientedZ: nil)
    }

    /// Thermal axis for a given day — `skinTempDevC` is already a deviation from Apple's own baseline.
    private static func thermalDriver(_ day: DailyMetric, config: Config) -> Driver {
        guard let dev = day.skinTempDevC else { return Driver(axis: .thermal, state: .noData, orientedZ: nil) }
        let state: AxisState = dev >= config.thermalOutC ? .high : (dev <= -config.thermalOutC ? .low : .inRange)
        return Driver(axis: .thermal, state: state, orientedZ: nil)
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

    /// The RAW (pre-hysteresis, pre-trend) body verdict for one day `i`, from its pre-built priors
    /// baselines. Trend is applied once, after hysteresis, in `evaluate` — never folded into the
    /// per-day raw (that would make the historical raws depend on today's trend). O(1) per day.
    private static func rawVerdictAt(_ i: Int, ordered: [DailyMetric],
                                     priorStates: PriorStates, config: Config) -> Verdict {
        let day = ordered[i]
        let hrvZ  = orientedZ(prior: priorStates.hrv?[i],  value: day.avgHrv,                    betterWhenHigher: true)
        let rhrZ  = orientedZ(prior: priorStates.rhr?[i],  value: day.restingHr.map(Double.init), betterWhenHigher: false)
        let respZ = orientedZ(prior: priorStates.resp?[i], value: day.respRateBpm,               betterWhenHigher: false)
        let a = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR), resp: (respZ, config.wResp), cfg: config).state
        guard a.hasData else { return .lowSignal }
        let s = sleepDriver(day).state
        let t = thermalDriver(day, config: config).state
        let out = [a, s, t].filter { $0.isOut }.count
        if out == 0 { return .full }
        if out == 1 { return .caution }
        return .easy
    }

    /// Forward pass applying hysteresis over the RAW verdicts of every day up to `asOf`. A new raw
    /// verdict must persist `hysteresisDays` consecutive days before it replaces the stable one.
    /// Operates on RAW (not smoothed) verdicts, so there is no unbounded recursion. O(n): each raw
    /// is O(1) from the single-pass `priorStates` (was O(n²) re-folding the full history per day).
    private static func hysteresed(ordered: [DailyMetric], priorStates: PriorStates, config: Config) -> Verdict {
        let raws = ordered.indices.map { rawVerdictAt($0, ordered: ordered, priorStates: priorStates, config: config) }
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
