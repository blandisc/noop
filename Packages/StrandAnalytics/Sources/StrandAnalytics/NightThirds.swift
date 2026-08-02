import Foundation
import BiometricStreams

// NightThirds.swift — the FIRST-third vs LAST-third contrast of the sleeping heart rate
// (FER-7 · Veredicto v4 Fase 4). Pure, DB-free, Foundation-only. A DESCRIPTIVE reading — it never
// votes in the verdict.
//
// WHY: alcohol and intense evening exercise raise nocturnal HR ASYMMETRICALLY between the halves of
// the night (Myllymäki et al.), so the change in mean HR from the first third of SLEEP to the last
// separates "last night you trained hard or drank" (hits the start of the night) from "your baseline
// moved" (level all night). MOTIVATION, not a claim: we surface the delta and how it compares to your
// own normal, never a prescription, never the nadir's timing (an Oura product claim with no
// peer-reviewed backing — NightAutonomicShape keeps `nadirHour` descriptive; we do not promote it).
//
// METHOD (honest hedging, APPROXIMATION — no medical device, no clinical claim):
//   • Partition by ACCUMULATED SLEEP TIME, not clock time: an awake gap mid-night adds zero asleep
//     seconds, so it never shifts the first/last boundary. "First third of the night" means the first
//     third of SLEEP.
//   • Each third's central value is the MEDIAN of its samples, not the mean. Apple's sleeping HR is
//     wrist PPG with heavy-tailed artifacts; a single 140-bpm spike moves a mean by roughly the size
//     of the signal we measure (~ a few bpm), so the mean would be dominated by noise. The median of
//     12–32 samples loses ~nothing on clean data (same robustness discipline NightAutonomicShape
//     applies via its 5-min rolling mean).
//   • The reading depends on Apple's hypnogram (κ≈0.53 on Apple Watch, Schyvens 2025), so the es-MX
//     copy is a READING, never a precision measurement.
public enum NightThirds {

    /// 3 h asleep minimum before we'll read the contrast — same floor as `NightAutonomicShape`.
    public static let minAsleepSec: Int = 10_800
    /// Minimum samples in a third for a SOLID read (~1 h at Apple's ~5-min sleeping-HR cadence, which
    /// is one third of the 3 h minimum night). A floor that protects genuinely sparse nights; on a
    /// normal 8 h night both thirds clear it easily.
    public static let minSamplesPerThird: Int = 12
    /// PPG artifact gate (same bounds as `NocturnalRestingHR`): drop implausible beats before the median.
    static let minPlausibleBpm = 30
    static let maxPlausibleBpm = 120

    public enum Confidence: String, Equatable, Sendable { case estimate, solid }

    public struct Result: Equatable, Sendable {
        /// MEDIAN bpm of the first third of sleep.
        public let firstThirdBpm: Double
        /// MEDIAN bpm of the last third of sleep.
        public let lastThirdBpm: Double
        /// `lastThirdBpm − firstThirdBpm` ( >0 = the heart rose across the night ).
        public let deltaBpm: Double
        public let confidence: Confidence
        public init(firstThirdBpm: Double, lastThirdBpm: Double, deltaBpm: Double, confidence: Confidence) {
            self.firstThirdBpm = firstThirdBpm; self.lastThirdBpm = lastThirdBpm
            self.deltaBpm = deltaBpm; self.confidence = confidence
        }
    }

    /// Contrast the first vs last third of the sleeping heart rate.
    ///
    /// Reuses `NightAutonomicShape.AsleepSpan` (wall-clock unix seconds). `hr` and `asleep` MUST be in
    /// the SAME wall-clock frame — the caller (the refresh) guarantees this by feeding Apple's HR
    /// samples and the session's stage segments, never the screen's relative `SleepInterval`s.
    ///
    /// Returns `nil` when there is no readable contrast: `asleep` empty, total asleep < `minAsleepSec`,
    /// or either the first or last third has fewer than 2 samples.
    public static func compute(hr: [HRSample], asleep: [NightAutonomicShape.AsleepSpan]) -> Result? {
        guard !asleep.isEmpty else { return nil }
        let spans = asleep.sorted { $0.start < $1.start }
        let totalAsleep = spans.reduce(0) { $0 + max(0, $1.end - $1.start) }
        guard totalAsleep >= minAsleepSec else { return nil }

        // Keep samples inside an asleep span with a plausible bpm, sorted by time.
        let inSleep = hr
            .filter { s in
                s.bpm >= minPlausibleBpm && s.bpm <= maxPlausibleBpm
                    && spans.contains { s.ts >= $0.start && s.ts < $0.end }
            }
            .sorted { $0.ts < $1.ts }

        // Accumulated asleep-seconds before each span begins (so an awake gap contributes zero).
        var cumBefore = [Int](repeating: 0, count: spans.count)
        var acc = 0
        for i in spans.indices { cumBefore[i] = acc; acc += max(0, spans[i].end - spans[i].start) }

        let third = Double(totalAsleep) / 3.0
        var first: [Double] = []
        var last: [Double] = []
        for s in inSleep {
            guard let k = spans.firstIndex(where: { s.ts >= $0.start && s.ts < $0.end }) else { continue }
            let p = Double(cumBefore[k] + (s.ts - spans[k].start))   // accumulated asleep seconds at s
            if p < third { first.append(Double(s.bpm)) }
            else if p >= 2.0 * third { last.append(Double(s.bpm)) }
        }

        guard first.count >= 2, last.count >= 2 else { return nil }
        let f = median(first)
        let l = median(last)
        let conf: Confidence =
            (first.count >= minSamplesPerThird && last.count >= minSamplesPerThird) ? .solid : .estimate
        return Result(firstThirdBpm: f, lastThirdBpm: l, deltaBpm: l - f, confidence: conf)
    }

    /// Median of a non-empty list, in `Double` (bpm accumulates in Double — never Int truncation).
    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
    }
}
