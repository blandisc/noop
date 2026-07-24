import XCTest
import StrandModels
@testable import StrandAnalytics

/// Parity guard for the autonomic `signals` breakdown (autonomic detail screen, FER-1045).
///
/// Exposing `Read.signals` is a PURE surfacing of quantities `evaluate` already computes — it must
/// not move a single verdict, driver, or coverage count. These tests lock two things on a fixed,
/// deterministic series:
///   1. The observable verdict/drivers are the FROZEN values (same as `PreparednessTests`), so the
///      change added a field and touched nothing else.
///   2. The surfaced `signals` are consistent with the axis they came from — the weighted average of
///      the present oriented z's, using `share` as the weight, reproduces the `autonomic` driver's
///      composite `orientedZ` exactly. If `signals` were a re-derivation (or drifted), this breaks.
final class PreparednessSignalReadParityTests: XCTestCase {

    // MARK: Fixtures (identical to PreparednessTests, so "before/after" is the same series)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp, respRateBpm: resp)
    }

    private func baseline(_ n: Int = 20) -> [DailyMetric] {
        (1...n).map { (i: Int) -> DailyMetric in
            let hrv: Double = 52 + Double(i % 5)
            let rhr: Int = 54 + i % 3
            let resp: Double = 13 + Double(i % 3)
            let sleep: Double = 440 + Double(i % 4) * 5
            return dm(String(format: "2026-06-%02d", i), hrv: hrv, rhr: rhr, resp: resp, sleep: sleep, temp: 0.0)
        }
    }

    private var noHyst: Preparedness.Config { var c = Preparedness.Config(); c.hysteresisDays = 1; return c }

    private func read(_ days: [DailyMetric], asOf: String, strain: [String: Double] = [:],
                      trend: AutonomicTrend.Read? = nil, config: Preparedness.Config? = nil) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: strain, trend: trend, asOf: asOf),
                              config: config ?? .default)
    }

    private func signal(_ r: Preparedness.Read, _ s: Preparedness.Signal) -> Preparedness.SignalRead? {
        r.signals.first { $0.signal == s }
    }

    // MARK: 1 · The verdict/drivers are unchanged by the added field (frozen values)

    /// The exact same assertions `PreparednessTests` makes on the "one bad night" case, re-run here to
    /// prove that adding `signals` did not perturb the verdict or the drivers.
    func testVerdictAndDrivers_unchanged_badNight() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(r.verdict, .caution)
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .low)
        XCTAssertEqual(r.drivers.first { $0.axis == .sleep }?.state, .inRange)
        XCTAssertEqual(r.drivers.first { $0.axis == .thermal }?.state, .inRange)
        XCTAssertEqual(r.signalsPresent, 3)
    }

    func testVerdictAndDrivers_unchanged_allInRange() {
        var days = baseline(); days.append(dm("2026-06-21"))
        let r = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r.verdict, .full)
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .inRange)
    }

    // MARK: 2 · signals is a faithful read-out of the composite (not a re-derivation)

    /// The weighted average of the present oriented z's — weighting each by its surfaced `share` —
    /// must equal the `autonomic` driver's composite `orientedZ` to machine precision. This is the
    /// invariant that proves `signals` was surfaced from the SAME numbers, not recomputed.
    func testSignals_reconstructTheComposite() {
        var days = baseline()
        days.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        let composite = r.drivers.first { $0.axis == .autonomic }?.orientedZ
        XCTAssertNotNil(composite)

        // All three present tonight → shares renormalize over all three and sum to 1.
        let present = r.signals.filter { $0.orientedZ != nil }
        XCTAssertEqual(present.count, 3)
        XCTAssertEqual(present.reduce(0) { $0 + $1.share }, 1.0, accuracy: 1e-9)

        let recomposed = r.signals.reduce(0.0) { acc, s in acc + (s.orientedZ ?? 0) * s.share }
        XCTAssertEqual(recomposed, composite!, accuracy: 1e-9,
                       "signals must reconstruct the exact composite the axis voted on")
    }

    /// v3 re-gate: the autonomic vote is resting-HR ONLY (`wRHR=1`, `wHRV=0`, `wResp=0`). SDNN and
    /// respiration still SHOW in the breakdown (context) but carry share 0 — they don't vote. The
    /// array is still ordered [rhr, hrv, resp].
    func testSignals_sharesAreRenormalizedWeights_orderedByWeight() {
        var days = baseline(); days.append(dm("2026-06-21"))
        let r = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r.signals.map(\.signal), [.rhr, .hrv, .resp])
        XCTAssertEqual(signal(r, .rhr)?.share ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .hrv)?.share ?? -1, 0.0, accuracy: 1e-9, "SDNN shows but does not vote (v3)")
        XCTAssertEqual(signal(r, .resp)?.share ?? -1, 0.0, accuracy: 1e-9, "resp moved to the sentinel (v3)")
    }

    /// An absent signal carries no vote: `orientedZ == nil`, `share == 0`. v3: the vote is resting-HR
    /// only, so the surfaced shares are [rhr 1, hrv 0, resp 0] and the present shares still sum to 1
    /// (only rhr carries weight). Dropping respiration changes nothing about the vote.
    func testSignals_absentSignal_zeroShare_presentRenormalize() {
        var days = baseline()
        days.append(dm("2026-06-21", resp: nil))   // no respiration tonight
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        let resp = signal(r, .resp)
        XCTAssertNil(resp?.orientedZ)
        XCTAssertEqual(resp?.share ?? -1, 0)
        let present = r.signals.filter { $0.orientedZ != nil }   // rhr + hrv have z tonight
        XCTAssertEqual(present.reduce(0) { $0 + $1.share }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .rhr)?.share ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .hrv)?.share ?? -1, 0.0, accuracy: 1e-9)
    }

    /// v3 re-gate: respiration NO LONGER flags the autonomic axis by itself — it moved to the illness
    /// sentinel (judged with temp, in `rawVerdictAt`). A lone respiration spike (HRV/RHR calm, temp
    /// normal) leaves the autonomic axis `inRange` and `flaggedAlone == false`. This is the exact
    /// inverse of the v2 assertion, on purpose: it prevents a lone breathing rise (talking, a dream,
    /// a stuffy room) from spuriously flagging autonomic recovery.
    func testSignals_respNoLongerFlagsAxisAlone_v3() {
        var days = baseline()
        // HRV/RHR normal, respiration WAY up, temp normal → nothing corroborates.
        days.append(dm("2026-06-21", hrv: 55, rhr: 55, resp: 22, sleep: 450, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(signal(r, .resp)?.flaggedAlone, false, "resp no longer flags the axis alone (v3)")
        XCTAssertEqual(signal(r, .hrv)?.flaggedAlone, false)
        XCTAssertEqual(signal(r, .rhr)?.flaggedAlone, false)
        // The autonomic axis stands on resting-HR (calm) → in range; the lone breathing rise does not
        // move the verdict off `full`.
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .inRange)
        XCTAssertEqual(r.verdict, .full)
    }

    /// `out` marks the signal that itself woke up at/under the axis OUT cut (`autonomicOutZ`, i.e. ≥1
    /// SD below your own baseline) — the row the detail screen washes. A bad night pushes all three
    /// past the cut; a normal night leaves them all in range. Independent of the axis verdict.
    func testSignals_outMarksLowSignals() {
        var bad = baseline()
        bad.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450, temp: 0.0))
        let rb = read(bad, asOf: "2026-06-21", config: noHyst)
        // HRV crashed, RHR and respiration spiked → each oriented z is far below −1.0.
        XCTAssertEqual(signal(rb, .hrv)?.out, true)
        XCTAssertEqual(signal(rb, .rhr)?.out, true)
        XCTAssertEqual(signal(rb, .resp)?.out, true)
        // `out` reuses the SAME cut the composite uses: it holds iff orientedZ ≤ autonomicOutZ (or resp
        // flagged alone) — no independent threshold.
        for s in rb.signals {
            let expected = (s.orientedZ.map { $0 <= Preparedness.Config.default.autonomicOutZ } ?? false)
                || s.flaggedAlone
            XCTAssertEqual(s.out, expected, "\(s.signal) out must mirror the axis cut")
        }

        var calm = baseline(); calm.append(dm("2026-06-21"))
        let rc = read(calm, asOf: "2026-06-21")
        XCTAssertTrue(rc.signals.allSatisfy { !$0.out }, "a normal night leaves every signal in range")
    }

    /// Cold start: the autonomic core has no usable baseline → verdict is `lowSignal` AND the surfaced
    /// signals carry no vote (all shares 0), so the detail screen shows "sin base" honestly.
    func testSignals_coldStart_noVote() {
        var days = (1...3).map { dm(String(format: "2026-06-%02d", $0)) }   // < seed
        days.append(dm("2026-06-21"))
        let r = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r.verdict, .lowSignal)
        XCTAssertEqual(r.signals.count, 3)
        XCTAssertTrue(r.signals.allSatisfy { $0.share == 0 && $0.orientedZ == nil },
                      "no usable baseline → no signal votes")
    }
}
