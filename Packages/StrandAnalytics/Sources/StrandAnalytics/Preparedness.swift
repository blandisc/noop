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
/// ## Design (v3 — 2026-07-24, after a deep CSO+Grok science investigation with verified citations)
/// The daily verdict stands on what an Apple Watch measures WELL: **resting HR + sleep**. The
/// all-day SDNN (`avgHrv`) is OUT of the vote (`wHRV=0`) — MAPE ~29% (O'Grady 2024), the wrong
/// construct measured in the wrong window; it survives only as a `SignalRead` read-out. The nocturnal
/// RMSSD re-enters via a dedicated dense-night path (deferred to the Repository wiring). Apple's own
/// Vitals app reached the same shape (nocturnal HR + resp + temp, no HRV). Details:
/// - **Autonomic axis = resting HR** vs your own baseline (`wRHR=1`). One signal, the dense/reliable one.
/// - **Sleep = graded vs need + efficiency** (`sleepDriver`), NOT the binary 6h cliff (Van Dongen 2003).
/// - **Illness sentinel:** temp + respiration must CORROBORATE (both elevated) to vote — a lone temp
///   or breathing rise no longer flags anything (kills warm-room / talking false positives; Mishra 2020).
/// - **Consensus by AXIS, not by signal** (autonomic · sleep · sentinel): a single bad night that moves
///   several signals at once is still ONE vote, never triple-counted (FER-1010).
/// - **Optional v3 inputs (all default to no-op):** `nocturnalRestingHr` (the real nocturnal resting
///   HR from `NocturnalRestingHR`, substituted through the WHOLE series so baseline and day share one
///   construct), `cyclePhase` (luteal allowance on the asOf day ONLY — never the baseline — so a normal
///   luteal RHR/temp shift isn't misread as "out of range"; Shilaih 2017 / Maijala 2019), and
///   `nocturnalRmssd` (dense nights only; never votes without resting HR present).
/// - Still outside the engine: the Repository wiring that feeds those three, and HRR (deliberately NOT
///   implemented — Cole 1999 validates it in a standardized exercise test for mortality, not as a
///   free-living daily readiness marker). See the spec.
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

    /// The three raw signals that COMPOSE the `autonomic` axis vote. The axis is one `Driver`;
    /// this is the breakdown *inside* it, surfaced so the autonomic detail screen can show which
    /// signal carried the vote and by how much — the exact same numbers `evaluate` already
    /// computed to build the composite, never a re-derivation.
    public enum Signal: String, Sendable, Equatable {
        case hrv   // Apple SDNN (better when higher)
        case rhr   // resting HR (better when lower)
        case resp  // respiratory rate (better when lower)
    }

    /// One autonomic signal's contribution to the axis vote — a pure read-out of the composite's
    /// internals (`autonomicAxis`): the oriented z (+ = better than your baseline), the renormalized
    /// weight it carried over the signals that were PRESENT tonight, and — respiration only — whether
    /// its raw z crossed `respBadZ` on its own (the one signal that can flag the axis by itself).
    public struct SignalRead: Sendable, Equatable {
        public let signal: Signal
        /// Oriented z (+ = better than baseline). nil when the signal had no usable read tonight
        /// (missing value or a baseline that isn't ready) — it then carries `share == 0` (no vote).
        public let orientedZ: Double?
        /// The axis weight renormalized over the signals PRESENT tonight (the present shares sum to
        /// 1; an absent signal is 0). This is exactly the weight used in the composite average.
        /// When dense nocturnal RMSSD participates (asOf-only), its weight is in `den` but has no
        /// `Signal` row — the three visible shares then sum to less than 1 (honest missing share).
        public let share: Double
        /// `true` only for respiration, only when its RAW z reached `respBadZ` — the wider cut that
        /// lets a breathing-rate spike flag the autonomic axis even when the composite doesn't.
        public let flaggedAlone: Bool
        /// `true` when THIS signal itself woke up at/under the axis out cut (`orientedZ ≤
        /// autonomicOutZ`, i.e. ≥1 SD below your own baseline) — or, for respiration, `flaggedAlone`.
        /// A pure read-out against the SAME cut the composite uses, so the detail screen can wash the
        /// row that came in low. Independent of the axis verdict: a single signal can be below its cut
        /// while the composite (with the other two) still reads in-range, and vice-versa — both honest.
        public let out: Bool
        public init(signal: Signal, orientedZ: Double?, share: Double,
                    flaggedAlone: Bool, out: Bool = false) {
            self.signal = signal; self.orientedZ = orientedZ
            self.share = share; self.flaggedAlone = flaggedAlone; self.out = out
        }
    }

    /// Tonight's dense/ralo nocturnal RMSSD z, pre-computed by the caller (asOf-day only — no
    /// historical series). Participates in the autonomic composite iff `dense == true` AND the
    /// asOf day's resting-HR z is present (RMSSD never votes alone).
    public struct DenseRmssd: Sendable, Equatable {
        public let z: Double
        public let dense: Bool
        public init(z: Double, dense: Bool) { self.z = z; self.dense = dense }
    }

    public struct Read: Sendable, Equatable {
        public let verdict: Verdict
        public let drivers: [Driver]
        /// The three signals that compose the `autonomic` axis, ordered by their weight
        /// (rhr ≥ hrv ≥ resp under the signed defaults). Surfaced for the autonomic detail
        /// screen; the axis verdict still stands on the `autonomic` `Driver`, never on this.
        public let signals: [SignalRead]
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
        /// FER-8 · Fase 5: the illness sentinel (temp∧resp) with streak memory, exposed for the
        /// guardian strip. `nil` when the asOf night has neither temperature nor respiration to read.
        /// The streak drives COPY only — it never changes `verdict` (the sentinel's single vote is
        /// unchanged from v3).
        public let sentinel: SentinelRead?
        public init(verdict: Verdict, drivers: [Driver], signals: [SignalRead] = [],
                    signalsPresent: Int, signalsTotal: Int,
                    maturity: BaselineStatus, autonomicNights: Int, trend: AutonomicTrend.Direction?,
                    sentinel: SentinelRead? = nil) {
            self.verdict = verdict; self.drivers = drivers; self.signals = signals
            self.signalsPresent = signalsPresent; self.signalsTotal = signalsTotal
            self.maturity = maturity; self.autonomicNights = autonomicNights; self.trend = trend
            self.sentinel = sentinel
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

        /// v3 cold-start middle tier: a real verdict, but on a resting-HR baseline that isn't fully
        /// mature yet (`seed ≤ nights < trust`). The UI shows it with a visible "provisional, aún
        /// aprendo tu normal" hedge — never the confident word, never a silent `lowSignal`. Below seed
        /// the verdict is already `lowSignal`; at trust the hedge lifts. Derived, so no init change.
        public var provisional: Bool { verdict != .lowSignal && maturity != .trusted }
    }

    // MARK: Illness sentinel with streak memory (FER-8 · Fase 5)

    /// The illness sentinel's state for the asOf night. `corroborated` (temp AND resp out) is the one
    /// that votes — exactly as v3; `watchingOneSignal` (exactly one out) NEVER votes; `quiet` is neither.
    public enum SentinelState: String, Sendable, Equatable { case quiet, watchingOneSignal, corroborated }
    public enum SentinelSignal: String, Sendable, Equatable { case temp, resp }
    /// Exposed on `Read.sentinel`. `streakNights` = consecutive calendar-contiguous nights ending at
    /// asOf in the SAME state (and, for `watchingOneSignal`, the same signal out). The streak drives
    /// COPY only — the vote (one, when `corroborated`) is unchanged from v3.
    public struct SentinelRead: Sendable, Equatable {
        public let state: SentinelState
        public let streakNights: Int
        public let watchingSignal: SentinelSignal?
        public let tempOut: Bool
        public let respOut: Bool
        public init(state: SentinelState, streakNights: Int, watchingSignal: SentinelSignal?,
                    tempOut: Bool, respOut: Bool) {
            self.state = state; self.streakNights = streakNights; self.watchingSignal = watchingSignal
            self.tempOut = tempOut; self.respOut = respOut
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
        /// Optional per-day nocturnal resting HR (bpm, key = "yyyy-MM-dd"). When present for a day,
        /// replaces Apple's awake `restingHr` for BOTH that day's z-score AND the resting-HR baseline
        /// series (one resolved series everywhere — never mix constructions). While any night still
        /// falls back to Apple's awake value, the axis is honestly "en reposo" (resting), NOT
        /// "nocturno" (nocturnal) — UI copy must not claim overnight precision for the axis as a whole.
        public let nocturnalRestingHr: [String: Double]
        /// Optional menstrual-cycle phase for the asOf day only. When `.lutealLean`, a partial
        /// allowance is subtracted from asOf-day resting HR and from the HIGH side of asOf-day skin
        /// temp (never from history or any baseline/prefix series). See `Config.lutealRHRAllowanceBpm`
        /// / `lutealTempAllowanceC`.
        public let cyclePhase: CyclePhaseEngine.Phase?
        /// Optional tonight-only dense nocturnal RMSSD (pre-computed z). Participates in the asOf
        /// autonomic composite only when `dense` and resting-HR z is present — never alone, never
        /// historically. See `Config.wNocturnalRMSSD`.
        public let nocturnalRmssd: DenseRmssd?
        public init(days: [DailyMetric], strainByDay: [String: Double],
                    trend: AutonomicTrend.Read?, asOf: String,
                    nocturnalRestingHr: [String: Double] = [:],
                    cyclePhase: CyclePhaseEngine.Phase? = nil,
                    nocturnalRmssd: DenseRmssd? = nil) {
            self.days = days; self.strainByDay = strainByDay; self.trend = trend; self.asOf = asOf
            self.nocturnalRestingHr = nocturnalRestingHr
            self.cyclePhase = cyclePhase
            self.nocturnalRmssd = nocturnalRmssd
        }
    }

    // MARK: Config — named, `/cso`-gated knobs (defaults are provisional)

    public struct Config: Sendable, Equatable {
        // Autonomic composite weights (must sum > 0). v3 re-gate (2026-07-24, CSO+Grok deep
        // investigation): the daily verdict stands on **resting HR** — Apple's densest, most
        // validated cardiac signal (O'Grady 2024: RHR MAE 3.73 bpm vs SDNN MAPE 28.88%). The
        // all-day SDNN (`avgHrv`) is OUT of the vote (`wHRV=0`) — kept only as a `SignalRead`
        // read-out; the nocturnal RMSSD re-enters via a dedicated dense-night path (deferred).
        // Respiration leaves the autonomic vote too (`wResp=0`) and becomes an illness-sentinel
        // corroborator (see `rawVerdictAt`). `/cso` signs these.
        public var wHRV: Double = 0.0
        public var wRHR: Double = 1.0
        public var wResp: Double = 0.0
        /// Weight of dense nocturnal RMSSD in the asOf-day autonomic composite (when
        /// `Input.nocturnalRmssd?.dense == true` and resting-HR z is present). Default 0.5 so RHR
        /// remains the backbone; RMSSD is a co-vote, never a solo vote.
        public var wNocturnalRMSSD: Double = 0.5
        /// Oriented-z below which an axis counts as OUT. −1.0 (one-sided ≈16%) matches the shipped
        /// `ReadinessEngine.Flag.bad` cut; NOT `|z|≤1` (rejected as noisy in `VitalBands`). `/cso`.
        public var autonomicOutZ: Double = -1.0
        /// Respiration flags on its own (wider) cut, so a normal nightly rise isn't flagged. A raw
        /// respiratory z at or above this counts the autonomic axis out even if the composite doesn't.
        public var respBadZ: Double = 1.5
        /// Skin-temp deviation (°C from Apple's own baseline) that counts as elevated for the illness
        /// sentinel. Absolute, no z. v3: temp alone no longer votes — it must be CORROBORATED by an
        /// elevated respiration (both together, the multi-signal illness pattern — Mishra 2020, Apple
        /// Vitals "2+ out"), which cuts the lone-temp false positives (warm room, blanket).
        public var thermalOutC: Double = 0.8
        /// Shilaih 2017 Sci Rep 7: sleeping pulse +1.8 bpm mid-luteal vs fertile-window baseline —
        /// discounted from the asOf-day resting-HR value ONLY, so a normal luteal-phase RHR bump isn't
        /// misread as "out of range". Never applied to the baseline series (see field doc on `cyclePhase`).
        public var lutealRHRAllowanceBpm: Double = 2.0
        /// Maijala 2019 BMC Women's Health: luteal-phase nightly skin-temp shift ≈ +0.30 °C — discounted
        /// from the asOf-day HIGH-side temperature deviation only (never the low/cold side, and never the
        /// baseline series).
        public var lutealTempAllowanceC: Double = 0.3
        // Sleep axis (v3 — graded vs need, not the binary 6h cliff). `low` when the night is short
        // vs the personal need OR efficiency is poor. Need = a population FLOOR here (Hirshkowitz
        // 2015 ≈ 7 h); a personal-need input is deferred (a rolling average of what was *achieved*
        // would normalise the chronically deprived — CSO hallazgo #4). Van Dongen 2003: sleep debt is
        // a continuous gradient, so a hard 360-min cliff is wrong.
        public var sleepNeedFloorMin: Double = 420
        /// Minutes below `need` before the night counts as short — a slack band so a normal −30 min
        /// isn't flagged.
        public var sleepSlackMin: Double = 45
        /// Sleep efficiency (fraction 0–1, `DailyMetric.efficiency`) below which the night reads poor
        /// even at full duration. Ohayon 2017: SE <75% is bad, ≥85% good — 0.80 is the honest margin.
        public var sleepEffFloor: Double = 0.80
        /// Consecutive daily readings a NEW raw verdict must hold before it replaces the stable one.
        public var hysteresisDays: Int = 2
        /// Baseline config key for Apple's SDNN (`Baselines.metricCfg["sdnn"]`). SIGNED by `/cso`
        /// (FER-1030): SDNN is z-scored WITHIN-SOURCE — Apple's SDNN against the user's OWN
        /// Apple-SDNN norm — which is right-skewed / log-normal like RMSSD and takes the same log
        /// treatment (Task Force 1996). This is NOT a cross-construct RMSSD conversion, so the
        /// "RMSSD ≠ SDNN" trap that killed the v1 design does not apply here.
        public var sdnnCfgKey: String = "sdnn"
        /// Nights (including today) averaged into the resting-HR value that gets z-scored — a
        /// past-only simple mean applied ONCE to the resolved series and used EVERYWHERE (the
        /// baseline fold AND each day's value), so measurement noise is reduced in one construct
        /// (Plews 2013: the multi-day trend has better validity than a single night). ⚠️ DEFAULT 1
        /// ON PURPOSE (FER-1049): this phase ships a CAPACITY, not a behavior change. `1` is
        /// byte-identical to pre-v4 (the series is returned untouched). An audit that EXECUTED the
        /// criteria found the smoothing has SYMMETRIC latency — an N>1 default breaks the frozen
        /// hysteresis sequence and delays recognising recovery — so the operating value is left for
        /// `/cso` to sign on real data. `hysteresisDays` stays 2 (don't stack behavior changes).
        public var rhrSmoothingNights: Int = 1
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

        // --- ONE resolved resting-HR series, in ONE construct (never a blend) ---
        // Resting HR comes in two INCOMPATIBLE constructs: the real nocturnal value (a low quantile
        // of the sleep window) and Apple's `restingHr` (an awake-sedentary aggregate that by
        // definition EXCLUDES sleep, and so reads systematically higher). Falling back per-day —
        // nocturnal for the recent nights, awake for the rest — silently builds a HALF-AND-HALF
        // baseline (the EWMA half-life is 14 nights, so a 14-night nocturnal window leaves the
        // baseline permanently ~half awake). Today's lower nocturnal value would then be scored
        // against a partly-awake, higher baseline: the oriented z drifts POSITIVE and the verdict
        // skews optimistic — exactly blind to the real elevations it exists to catch.
        // So: use the nocturnal series ONLY if it covers enough of the history to stand on its own
        // (`Baselines.minNightsSeed`); otherwise use the awake series WHOLE. One construct, always.
        let nocturnalSeries: [Double?] = ordered.map { input.nocturnalRestingHr[$0.day] }
        let awakeSeries: [Double?] = ordered.map { $0.restingHr.map(Double.init) }
        let nocturnalCount = nocturnalSeries.compactMap { $0 }.count
        // The asOf night must itself be nocturnal — a nocturnal baseline with an awake day is the
        // same mixed-construct bug in miniature.
        let nocturnalUsable = nocturnalCount >= Baselines.minNightsSeed && nocturnalSeries.last.flatMap { $0 } != nil
        let resolvedRhr: [Double?] = nocturnalUsable ? nocturnalSeries : awakeSeries
        // Fase 1a (FER-1049): smooth the resolved series ONCE, then use the smoothed series for BOTH
        // the baseline fold and every per-day z — never smooth the day against a raw baseline (that
        // would desalign the variance and make the z meaningless). Default N=1 → identity (paridad).
        let rhrSeries: [Double?] = smoothedRhrSeries(resolvedRhr, nights: config.rhrSmoothingNights)

        // --- ONE forward pass per body signal (FER-1040) ---
        // `priorStates.<sig>[i]` is the baseline built from `ordered[0..<i]` — exactly the "priors"
        // baseline day `i` must be deviated against. This replaces the old O(n²) machinery, where
        // every per-day raw verdict re-filtered + re-sorted the whole `days` array and re-folded the
        // full history from scratch (`hysteresed` × `axisStates`). `prefixStates` reuses the SAME
        // `Baselines.update` reduce, so every state — and therefore every verdict — is bit-identical.
        let priorStates = bodySignalPriorStates(ordered, rhrSeries: rhrSeries, config: config)
        let lastIdx = ordered.count - 1

        // --- today's oriented z's (from the last priors state) ---
        // B2: luteal allowance on asOf-day resolved RHR only (never folded into the baseline).
        let rhrValueToday = adjustedRhr(rhrSeries[lastIdx], cyclePhase: input.cyclePhase,
                                        isAsOf: true, config: config)
        let hrvZ  = orientedZ(prior: priorStates.hrv?[lastIdx],  value: today.avgHrv,      betterWhenHigher: true)
        let rhrZ  = orientedZ(prior: priorStates.rhr?[lastIdx],  value: rhrValueToday,     betterWhenHigher: false)
        let respZ = orientedZ(prior: priorStates.resp?[lastIdx], value: today.respRateBpm, betterWhenHigher: false)

        let signalsPresent = [hrvZ, rhrZ, respZ].compactMap { $0 }.count

        // B3: dense nocturnal RMSSD co-votes only when dense AND rhrZ is present (never alone).
        let rmssdTerm = nocturnalRmssdTerm(input.nocturnalRmssd, rhrZ: rhrZ, isAsOf: true, config: config)

        // --- Axis: autonomic (weighted composite of the present oriented z's) ---
        let autonomic = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR),
                                      resp: (respZ, config.wResp), nocturnalRmssd: rmssdTerm, cfg: config)
        // The breakdown INSIDE that axis — same z's, same weights (incl. RMSSD den), same respBadZ.
        let signals = autonomicSignals(hrv: hrvZ, rhr: rhrZ, resp: respZ,
                                       nocturnalRmssdWeight: rmssdTerm?.weight ?? 0, cfg: config)
        let sleepAxis = sleepDriver(today, config: config)
        // B2: luteal high-side temp allowance on asOf day only.
        let thermalAxis = thermalDriver(
            skinTempDevC: adjustedTempDev(today.skinTempDevC, cyclePhase: input.cyclePhase,
                                          isAsOf: true, config: config),
            config: config)
        // --- Axis: load (optional — present ONLY with a real workout; its OUT logic is deferred to
        // `/cso`, so today it contributes coverage/context but never flips the verdict). ---
        let loadAxis: Driver = input.strainByDay[today.day] != nil
            ? Driver(axis: .load, state: .inRange, orientedZ: nil)
            : Driver(axis: .load, state: .noData, orientedZ: nil)

        let drivers = [autonomic, sleepAxis, thermalAxis, loadAxis]

        // Maturity + confidence depth come from the RESTING-HR priors baseline — v3's autonomic
        // backbone — NOT the SDNN one (`prefixStates` last element == fold over the days strictly
        // before asOf). The verdict now stands on RHR, so its confidence must too: a mature SDNN
        // history would otherwise over-state confidence in a verdict RHR actually carries.
        let autoBaseline = priorStates.rhr?[lastIdx]
        let maturity = autoBaseline?.status ?? .calibrating
        let autonomicNights = autoBaseline?.nValid ?? 0

        // --- Cold start / low signal: the autonomic core must have a usable read. ---
        if autonomic.state == .noData {
            return Read(verdict: .lowSignal, drivers: drivers, signals: signals,
                        signalsPresent: signalsPresent,
                        signalsTotal: 3, maturity: maturity, autonomicNights: autonomicNights,
                        trend: input.trend?.direction)
        }

        // --- Consensus + hysteresis over RAW body verdicts across history (deterministic, no persistence) ---
        // ONE forward pass yields the per-day RawDay (verdict + illness-sentinel signals): hysteresis
        // rides the verdicts, the sentinel STREAK (FER-8) rides the temp/resp flags — same pass, no
        // extra cost, and no drift between the vote and the sentinel.
        let raws = ordered.indices.map {
            rawVerdictAt($0, ordered: ordered, priorStates: priorStates, rhrSeries: rhrSeries,
                         cyclePhase: input.cyclePhase, asOf: input.asOf,
                         nocturnalRmssd: input.nocturnalRmssd, config: config)
        }
        let stable = hysteresed(raws.map(\.verdict), hysteresisDays: config.hysteresisDays)
        // Trend nudge (post-hysteresis): a sustained falling RMSSD trend pushes a borderline day
        // (`caution`) to `easy`. It never overrides a clean `full`. `/cso` may widen this.
        let final: Verdict = (stable == .caution && input.trend?.direction == .below) ? .easy : stable

        return Read(verdict: final, drivers: drivers, signals: signals,
                    signalsPresent: signalsPresent, signalsTotal: 3,
                    maturity: maturity, autonomicNights: autonomicNights, trend: input.trend?.direction,
                    sentinel: sentinelStreak(ordered: ordered, raws: raws))
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
    private static func bodySignalPriorStates(_ ordered: [DailyMetric], rhrSeries: [Double?],
                                              config: Config) -> PriorStates {
        PriorStates(
            hrv:  Baselines.metricCfg[config.sdnnCfgKey].map { Baselines.prefixStates(ordered.map { $0.avgHrv }, cfg: $0) },
            // RHR baseline folds the SAME resolved series used for per-day z (nocturnal override or
            // Apple awake) — never recompute a second map of `day.restingHr` here.
            rhr:  Baselines.metricCfg["resting_hr"].map { Baselines.prefixStates(rhrSeries, cfg: $0) },
            resp: Baselines.metricCfg["resp"].map { Baselines.prefixStates(ordered.map { $0.respRateBpm }, cfg: $0) }
        )
    }

    /// Past-only simple moving average of the resolved resting-HR series (FER-1049 · fase 1a).
    /// Applied ONCE to the whole series so the baseline fold and every per-day value share one
    /// smoothed construct. `nights <= 1` returns the series untouched — byte-identical pre-v4
    /// behaviour (paridad), no floating-point mean-of-one drift. For each day `i` the mean of the
    /// non-nil values in the trailing window `series[max(0, i-nights+1)...i]`; with fewer than 2
    /// non-nil values in the window the day's RAW value is kept (never fabricate from a single point).
    /// Simple mean, strictly backward-looking — never peeks at the future.
    private static func smoothedRhrSeries(_ series: [Double?], nights: Int) -> [Double?] {
        guard nights > 1 else { return series }
        return series.indices.map { i in
            let lo = max(0, i - nights + 1)
            let window = series[lo...i].compactMap { $0 }
            guard window.count >= 2 else { return series[i] }
            return window.reduce(0, +) / Double(window.count)
        }
    }

    /// asOf-only luteal RHR discount (B2). Applied on top of the B1-resolved value; never to history.
    private static func adjustedRhr(_ resolved: Double?, cyclePhase: CyclePhaseEngine.Phase?,
                                    isAsOf: Bool, config: Config) -> Double? {
        guard let r = resolved else { return nil }
        if isAsOf, cyclePhase == .lutealLean { return r - config.lutealRHRAllowanceBpm }
        return r
    }

    /// asOf-only luteal high-side skin-temp discount (B2). Cold side (`dev ≤ 0`) is untouched.
    private static func adjustedTempDev(_ dev: Double?, cyclePhase: CyclePhaseEngine.Phase?,
                                        isAsOf: Bool, config: Config) -> Double? {
        guard let d = dev else { return nil }
        if isAsOf, cyclePhase == .lutealLean, d > 0 {
            return max(0, d - config.lutealTempAllowanceC)
        }
        return d
    }

    /// Dense nocturnal RMSSD composite term (B3). Participates only on asOf when `dense` and rhrZ
    /// is present — RMSSD never votes alone (axis must still fall to `.noData` without RHR).
    private static func nocturnalRmssdTerm(_ nr: DenseRmssd?, rhrZ: Double?, isAsOf: Bool,
                                           config: Config) -> (z: Double, weight: Double)? {
        guard isAsOf, let nr, nr.dense, rhrZ != nil else { return nil }
        return (nr.z, config.wNocturnalRMSSD)
    }

    /// Oriented z for one body signal against a pre-built priors baseline: + = better than baseline.
    /// nil (noData) when the baseline isn't usable (< seed nights) or tonight's value is missing.
    private static func orientedZ(prior: BaselineState?, value: Double?, betterWhenHigher: Bool) -> Double? {
        guard let prior, prior.usable, let v = value else { return nil }
        let dev = Baselines.deviation(v, state: prior)
        return betterWhenHigher ? dev.z : -dev.z
    }

    /// Sleep axis for a given day (v3 — graded vs need, not the binary 6h cliff). `.low` when the
    /// night is materially short vs the personal need OR efficiency is poor; `.noData` when unmeasured.
    /// Deliberately does NOT call `SleepBands.short` (the global 360-min cliff) — that band stays for
    /// other surfaces, but the verdict now reads duration-vs-need + continuity (Van Dongen 2003 dose–
    /// response; Ohayon 2017 efficiency). A personal-need input is deferred (see `Config`).
    private static func sleepDriver(_ day: DailyMetric, config: Config) -> Driver {
        guard let mins = day.totalSleepMin else { return Driver(axis: .sleep, state: .noData, orientedZ: nil) }
        let shortVsNeed = mins < config.sleepNeedFloorMin - config.sleepSlackMin
        let poorEfficiency = day.efficiency.map { $0 < config.sleepEffFloor } ?? false
        return Driver(axis: .sleep, state: (shortVsNeed || poorEfficiency) ? .low : .inRange, orientedZ: nil)
    }

    /// Thermal axis — `skinTempDevC` is already a deviation from Apple's own baseline (caller may
    /// pass a luteal-adjusted asOf value; history never gets that discount).
    private static func thermalDriver(skinTempDevC: Double?, config: Config) -> Driver {
        guard let dev = skinTempDevC else { return Driver(axis: .thermal, state: .noData, orientedZ: nil) }
        let state: AxisState = dev >= config.thermalOutC ? .high : (dev <= -config.thermalOutC ? .low : .inRange)
        return Driver(axis: .thermal, state: state, orientedZ: nil)
    }

    /// Collapse HRV/RHR/resp (+ optional dense nocturnal RMSSD) into one autonomic vote via a
    /// weighted average of the PRESENT oriented z's (weights renormalized over present terms).
    /// `.low` iff the composite is at/under the OUT cut; respiration additionally flags on its own
    /// wider cut. Never the min (no −0.85 bias).
    private static func autonomicAxis(hrv: (Double?, Double), rhr: (Double?, Double),
                                      resp: (Double?, Double),
                                      nocturnalRmssd: (z: Double, weight: Double)? = nil,
                                      cfg: Config) -> Driver {
        var num = 0.0, den = 0.0
        if let z = hrv.0 { num += hrv.1 * z; den += hrv.1 }
        if let z = rhr.0 { num += rhr.1 * z; den += rhr.1 }
        if let z = resp.0 { num += resp.1 * z; den += resp.1 }
        if let rmssd = nocturnalRmssd {
            num += rmssd.weight * rmssd.z
            den += rmssd.weight
        }
        guard den > 0 else { return Driver(axis: .autonomic, state: .noData, orientedZ: nil) }
        let composite = num / den
        // Respiration's lone-flag ONLY applies while respiration is part of the autonomic vote
        // (`wResp > 0`). v3 moves respiration to the illness sentinel (`wResp = 0`), so it no longer
        // flags the autonomic axis by itself — a breathing rise is judged there, corroborated by temp.
        let respOut = cfg.wResp > 0
            ? ((resp.0.map { -$0 }).map { $0 >= cfg.respBadZ } ?? false)
            : false
        let out = composite <= cfg.autonomicOutZ || respOut
        return Driver(axis: .autonomic, state: out ? .low : .inRange, orientedZ: composite)
    }

    /// The per-signal breakdown of the autonomic composite — a PURE read-out of the exact quantities
    /// `autonomicAxis` uses (the same oriented z's, the same `den` renormalization, the same
    /// `respBadZ` cut). It computes no new science and can never move a verdict: `share` mirrors the
    /// weight each present signal carries in the average, and `flaggedAlone` mirrors the `respOut`
    /// branch. Ordered by weight (rhr ≥ hrv ≥ resp under the signed defaults).
    /// `nocturnalRmssdWeight` is the composite's 4th-term weight when active (else 0) — it widens
    /// `den` so rhr/hrv/resp shares honestly drop below 1, without adding a `Signal` enum case.
    private static func autonomicSignals(hrv: Double?, rhr: Double?, resp: Double?,
                                         nocturnalRmssdWeight: Double = 0,
                                         cfg: Config) -> [SignalRead] {
        // `den` — sum of the weights of the terms PRESENT tonight — is identical to the composite's
        // denominator, so `share` is the exact weight each present signal carried in the average.
        var den = 0.0
        if hrv  != nil { den += cfg.wHRV }
        if rhr  != nil { den += cfg.wRHR }
        if resp != nil { den += cfg.wResp }
        den += nocturnalRmssdWeight
        func share(_ z: Double?, _ w: Double) -> Double { (z != nil && den > 0) ? w / den : 0 }
        // Same expression as `respOut` in `autonomicAxis`: raw high (bad) = −orientedZ ≥ respBadZ.
        // Gated on `wResp > 0` for the same reason: with respiration moved to the sentinel (v3), it
        // no longer "flags the axis alone", so the read-out must not claim it did.
        let respAlone = cfg.wResp > 0
            ? ((resp.map { -$0 }).map { $0 >= cfg.respBadZ } ?? false)
            : false
        // Per-signal `out`: this signal itself at/under the composite's OUT cut. Same threshold the
        // axis uses (`autonomicOutZ`), applied to the signal's own oriented z — no new science.
        func low(_ z: Double?) -> Bool { z.map { $0 <= cfg.autonomicOutZ } ?? false }
        return [
            SignalRead(signal: .rhr,  orientedZ: rhr,  share: share(rhr,  cfg.wRHR),  flaggedAlone: false,     out: low(rhr)),
            SignalRead(signal: .hrv,  orientedZ: hrv,  share: share(hrv,  cfg.wHRV),  flaggedAlone: false,     out: low(hrv)),
            SignalRead(signal: .resp, orientedZ: resp, share: share(resp, cfg.wResp), flaggedAlone: respAlone, out: low(resp) || respAlone),
        ]
    }

    /// The RAW (pre-hysteresis, pre-trend) body verdict for one day `i`, from its pre-built priors
    /// baselines. Trend is applied once, after hysteresis, in `evaluate` — never folded into the
    /// per-day raw (that would make the historical raws depend on today's trend). O(1) per day.
    /// B1/B2/B3: uses the resolved `rhrSeries`; applies luteal + dense-RMSSD only when
    /// `day.day == asOf` (historical raws stay pre-adjustment so hysteresis is consistent).
    /// One day's raw evaluation: the consensus verdict PLUS the illness-sentinel signals (temp/resp
    /// out), so the forward pass carries both without recomputing (FER-8).
    private struct RawDay { let verdict: Verdict; let tempOut: Bool; let respOut: Bool }

    private static func rawVerdictAt(_ i: Int, ordered: [DailyMetric],
                                     priorStates: PriorStates, rhrSeries: [Double?],
                                     cyclePhase: CyclePhaseEngine.Phase?, asOf: String,
                                     nocturnalRmssd: DenseRmssd?, config: Config) -> RawDay {
        let day = ordered[i]
        let isAsOf = day.day == asOf
        let rhrVal = adjustedRhr(rhrSeries[i], cyclePhase: cyclePhase, isAsOf: isAsOf, config: config)
        let hrvZ  = orientedZ(prior: priorStates.hrv?[i],  value: day.avgHrv,      betterWhenHigher: true)
        let rhrZ  = orientedZ(prior: priorStates.rhr?[i],  value: rhrVal,          betterWhenHigher: false)
        let respZ = orientedZ(prior: priorStates.resp?[i], value: day.respRateBpm, betterWhenHigher: false)
        // v3 illness sentinel: temp counts as OUT only when CORROBORATED by an elevated respiration
        // (both together, sustained illness pattern — Mishra 2020; Apple Vitals "2+ out"). A lone temp
        // anomaly (warm room, blanket) or a lone breathing rise no longer votes → far fewer false
        // "ease" days. `respZ` is oriented (+ = better); an elevated (bad) breathing rate is
        // `−respZ ≥ respBadZ`. Cold temp is not an illness sign — only the HIGH side corroborates.
        // B2: asOf-only luteal high-side temp discount. Computed BEFORE the autonomic gate so a
        // low-signal day still reports its sentinel signals (FER-8), without changing the vote below.
        let tempDev = adjustedTempDev(day.skinTempDevC, cyclePhase: cyclePhase, isAsOf: isAsOf, config: config)
        let tempHigh = tempDev.map { $0 >= config.thermalOutC } ?? false
        let respHigh = (respZ.map { -$0 }).map { $0 >= config.respBadZ } ?? false

        let rmssdTerm = nocturnalRmssdTerm(nocturnalRmssd, rhrZ: rhrZ, isAsOf: isAsOf, config: config)
        let a = autonomicAxis(hrv: (hrvZ, config.wHRV), rhr: (rhrZ, config.wRHR),
                              resp: (respZ, config.wResp), nocturnalRmssd: rmssdTerm, cfg: config).state
        guard a.hasData else { return RawDay(verdict: .lowSignal, tempOut: tempHigh, respOut: respHigh) }
        let s = sleepDriver(day, config: config).state
        let sentinelOut = tempHigh && respHigh
        let out = (a.isOut ? 1 : 0) + (s.isOut ? 1 : 0) + (sentinelOut ? 1 : 0)
        let v: Verdict = out == 0 ? .full : (out == 1 ? .caution : .easy)
        return RawDay(verdict: v, tempOut: tempHigh, respOut: respHigh)
    }

    /// Run-length hysteresis over the RAW verdicts (computed once by the caller — the same pass the
    /// sentinel streak rides). A new raw verdict must persist `hysteresisDays` CONSECUTIVE days before
    /// it replaces the stable one, so an isolated borderline day never flips the hero. O(n).
    private static func hysteresed(_ raws: [Verdict], hysteresisDays: Int) -> Verdict {
        guard var stable = raws.first else { return .lowSignal }
        var runVal = stable
        var runLen = 1
        for r in raws.dropFirst() {
            if r == runVal { runLen += 1 } else { runVal = r; runLen = 1 }
            if runVal != stable && runLen >= max(1, hysteresisDays) { stable = runVal }
        }
        return stable
    }

    /// The illness-sentinel read for the asOf night, with streak memory (FER-8). `nil` when the asOf
    /// night has neither temperature nor respiration to read. `streakNights` counts consecutive
    /// CALENDAR-CONTIGUOUS nights ending at asOf in the SAME state (and, for `watchingOneSignal`, the
    /// same signal out) — a quiet night, a state change, a signal flip, OR a calendar gap ends it
    /// (`Input.days` is not calendar-filled, so a missing night is an ABSENT row, not a nil — the
    /// contiguity is checked by civil date via `ComparisonEngine.epochDay`). COPY only: never the vote.
    private static func sentinelStreak(ordered: [DailyMetric], raws: [RawDay]) -> SentinelRead? {
        guard let asOfDay = ordered.last, let asOf = raws.last else { return nil }
        if asOfDay.skinTempDevC == nil && asOfDay.respRateBpm == nil { return nil }

        let state: SentinelState
        let signal: SentinelSignal?
        if asOf.tempOut && asOf.respOut { state = .corroborated; signal = nil }
        else if asOf.tempOut          { state = .watchingOneSignal; signal = .temp }
        else if asOf.respOut          { state = .watchingOneSignal; signal = .resp }
        else                          { state = .quiet; signal = nil }

        var streak = state == .quiet ? 0 : 1
        if state != .quiet {
            var prevDay = asOfDay.day
            var idx = ordered.count - 2
            while idx >= 0 {
                guard let ePrev = ComparisonEngine.epochDay(of: prevDay),
                      let eThis = ComparisonEngine.epochDay(of: ordered[idx].day),
                      ePrev - eThis == 1 else { break }          // calendar gap ends the streak
                let r = raws[idx]
                let matches: Bool
                switch state {
                case .corroborated:      matches = r.tempOut && r.respOut
                case .watchingOneSignal: matches = signal == .temp ? (r.tempOut && !r.respOut)
                                                                    : (r.respOut && !r.tempOut)
                case .quiet:             matches = false
                }
                if !matches { break }                            // state change / signal flip ends it
                streak += 1
                prevDay = ordered[idx].day
                idx -= 1
            }
        }
        return SentinelRead(state: state, streakNights: streak, watchingSignal: signal,
                            tempOut: asOf.tempOut, respOut: asOf.respOut)
    }
}
