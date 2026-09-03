import Foundation
import BiometricStreams

// HRCoverage.swift — how much of a session's wall clock actually carries a plausible pulse
// (ola 1 · E2; gate estadístico H1, 2026-09-02).
//
// Until this existed, the only gate on «the watch measured this session» was
// `StrainScorer.hasEnoughData`: an ABSOLUTE floor (~10 min of samples, dense or sparse-sustained).
// Edwards TRIMP is linear in time, so a 50-minute session with 12 minutes of watch coverage cleared
// that floor and was stored as MEASURED carrying a TRIMP of ~24 instead of ~100 — strain 7.5 where
// the session was a 10.9. A quarter of the truth, labelled whole.
//
// Coverage is TIME WITH A PLAUSIBLE PULSE, not the fraction of holes: the sum of the intervals
// between consecutive samples shorter than `maxPlausibleGapS`, over the session's elapsed seconds
// (which already excludes pauses, FER-823). Same «a gap this long is not coverage» criterion
// `HRZones` applies to its own gap cap.
//
// APPROXIMATE and calibration-owned: `minCoverage` is a calibration default, /estadistico owns it.
// Reference: gate estadístico ola 1 · H1 — «cobertura ≥ 0.8 de elapsedSeconds con gaps plausibles,
// además de hasEnoughData».
public enum HRCoverage {

    /// A gap longer than this between consecutive samples is a hole, not covered time (seconds).
    /// calibration default, /estadistico owns.
    public static let maxPlausibleGapS: Int = 300

    /// The fraction of the session's elapsed time that must carry a plausible pulse before the
    /// strain may be called MEASURED. calibration default, /estadistico owns (H1: c = 0.5 costs
    /// 1.6 strain points, c = 0.8 costs 0.5 — half a band).
    public static let minCoverage: Double = 0.8

    /// Covered fraction of `elapsedSeconds` in [0, 1]. Fewer than 2 samples or a non-positive
    /// elapsed time → 0 (nothing is covered), never a divide-by-zero.
    /// Known approximation: the pulse is NOT scored while a session is paused, so a pause shorter than
    /// `maxPlausibleGapS` shows up here as one covered gap while `elapsedSeconds` excludes it — the
    /// fraction can be inflated by at most one gap per pause (Grok E2 H1; accepted, documented).
    public static func fraction(_ samples: [HRSample], elapsedSeconds: Int) -> Double {
        guard elapsedSeconds > 0, samples.count >= 2 else { return 0 }
        let ts = samples.map(\.ts).sorted()
        var covered = 0
        for i in 1..<ts.count {
            let dt = ts[i] - ts[i - 1]
            if dt > 0 && dt < maxPlausibleGapS { covered += dt }
        }
        return min(1.0, Double(covered) / Double(elapsedSeconds))
    }

    /// The single rule for «this session's load was MEASURED by the pulse»: enough data to trust the
    /// score AND enough of the session actually covered. Both gates, never one.
    public static func isMeasured(_ samples: [HRSample], elapsedSeconds: Int) -> Bool {
        StrainScorer.hasEnoughData(samples) && fraction(samples, elapsedSeconds: elapsedSeconds) >= minCoverage
    }
}
