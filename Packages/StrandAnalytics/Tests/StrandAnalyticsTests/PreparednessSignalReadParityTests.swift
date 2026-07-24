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

    /// `share` mirrors the signed weights (rhr 0.40 > hrv 0.35 > resp 0.25) and the array is ordered
    /// by weight. With all three present the shares equal the raw weights (den == 1.0).
    func testSignals_sharesAreRenormalizedWeights_orderedByWeight() {
        var days = baseline(); days.append(dm("2026-06-21"))
        let r = read(days, asOf: "2026-06-21")
        XCTAssertEqual(r.signals.map(\.signal), [.rhr, .hrv, .resp])
        XCTAssertEqual(signal(r, .rhr)?.share ?? 0, 0.40, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .hrv)?.share ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .resp)?.share ?? 0, 0.25, accuracy: 1e-9)
    }

    /// An absent signal carries no vote: `orientedZ == nil`, `share == 0`, and the PRESENT shares
    /// renormalize to 1 among themselves (den drops that signal's weight).
    func testSignals_absentSignal_zeroShare_presentRenormalize() {
        var days = baseline()
        days.append(dm("2026-06-21", resp: nil))   // no respiration tonight
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        let resp = signal(r, .resp)
        XCTAssertNil(resp?.orientedZ)
        XCTAssertEqual(resp?.share ?? -1, 0)
        // rhr (0.40) + hrv (0.35) renormalize over 0.75 → 0.5333… and 0.4666…, summing to 1.
        let present = r.signals.filter { $0.orientedZ != nil }
        XCTAssertEqual(present.reduce(0) { $0 + $1.share }, 1.0, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .rhr)?.share ?? 0, 0.40 / 0.75, accuracy: 1e-9)
        XCTAssertEqual(signal(r, .hrv)?.share ?? 0, 0.35 / 0.75, accuracy: 1e-9)
    }

    /// `flaggedAlone` is respiration-only and mirrors the `respBadZ` branch: a big respiration rise
    /// flags it even when HRV/RHR are calm. HRV and RHR never flag alone.
    func testSignals_respFlaggedAlone_mirrorsRespBadZ() {
        var days = baseline()
        // HRV/RHR normal, respiration WAY up → its raw z clears respBadZ on its own.
        days.append(dm("2026-06-21", hrv: 55, rhr: 55, resp: 22, sleep: 450, temp: 0.0))
        let r = read(days, asOf: "2026-06-21", config: noHyst)
        XCTAssertEqual(signal(r, .resp)?.flaggedAlone, true, "a lone respiration spike flags the axis")
        XCTAssertEqual(signal(r, .hrv)?.flaggedAlone, false)
        XCTAssertEqual(signal(r, .rhr)?.flaggedAlone, false)
        // And the axis itself is out because respiration alone crossed its wider cut.
        XCTAssertEqual(r.drivers.first { $0.axis == .autonomic }?.state, .low)

        // A calm respiration never flags alone.
        var calm = baseline(); calm.append(dm("2026-06-21"))
        let rc = read(calm, asOf: "2026-06-21")
        XCTAssertEqual(signal(rc, .resp)?.flaggedAlone, false)
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
