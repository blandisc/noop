import Foundation
import BiometricStreams

// NightAutonomicShape.swift — the SHAPE of the nocturnal heart-rate fall (FER-678). Pure, DB-free.
//
// We already find the nightly HR nadir (SleepStager exposes `restingHR` = "lowest 5-min rolling-mean
// HR during the session") but throw away its FORM and TIMING. This engine keeps them and derives three
// read-outs a resting-HR number alone can't show:
//
//   1. dip%          — how far HR fell from your waking reference to the night's valley, as a percent
//                      of the waking value. A deeper fall reflects stronger nocturnal parasympathetic
//                      dominance; a blunted fall is a pattern worth noticing, never a diagnosis.
//   2. nadir hour    — the LOCAL clock time of that valley (earlier = your heart settled sooner).
//   3. % below RHR   — the share of the asleep night spent under your own baseline resting HR.
//
// METHOD (independent implementation of a published, mechanistic finding — not a novel claim):
//   Heart rate falls across the night as parasympathetic tone rises and sympathetic tone withdraws,
//   deepest in slow-wave (NREM) sleep — Trinder J, Kleiman J, Carrington M, et al., "Autonomic activity
//   during human sleep as a function of time and sleep stage", J Sleep Res 2001;10(4):253–264. That same
//   paper reports HR ALSO carries a circadian time-of-night effect on top of the sleep-stage effect, so
//   the fall we measure is not attributable to parasympathetic tone alone — one more reason to surface it
//   as a descriptive shape, never a clean autonomic read-out. The nadir
//   is the minimum of a 5-minute rolling mean (same primitive SleepStager uses for `restingHR`), which
//   suppresses single-beat noise from wrist PPG. This uses ONLY mean HR — no beat-to-beat R-R — so
//   sensor risk is essentially nil (the epic's "best value-per-risk").
//
// HONEST HEDGING (es-MX copy is a PATTERN, never a verdict):
//   APPROXIMATION, not a medical device, no clinical claim. We describe how promptly and deeply the
//   heart eased off ("bajó 14% y tocó su punto más bajo a las 3:10 — señal de que descansaste"), and we
//   NEVER label the user "non-dipper" or infer hypertension. A blunted dip is surfaced as "poco marcado
//   esta noche", not a risk category. The published dipping/non-dipping cut-offs are for ambulatory
//   blood pressure, not wrist HR, so we deliberately don't import their thresholds as diagnoses.
public enum NightAutonomicShape {

    // MARK: - Tuning constants (pinned by test)

    /// Rolling-window length for the nadir search (seconds) — matches SleepStager's 5-min resting-HR window.
    public static let nadirWindowSec: Int = 300
    /// Minimum asleep span (seconds) before we'll report a shape — under ~3 h the night is too short to
    /// read the autonomic fall honestly. 3 h = 10_800 s.
    public static let minAsleepSec: Int = 10_800
    /// Minimum HR coverage (fraction of the asleep span that must carry samples) for a SOLID read.
    public static let minCoverageForSolid: Double = 0.60
    /// Coverage below this ⇒ unreadable (too gappy — off-wrist most of the night).
    public static let minCoverageForRead: Double = 0.35
    /// A fall below this percent of the waking reference reads as "poco marcado" (blunted) — a soft,
    /// non-diagnostic descriptor. 10% mirrors the *conceptual* dipping boundary while we stay explicit
    /// that the clinical cut-off is for blood pressure, not wrist HR.
    public static let bluntedDipPct: Double = 10.0
    /// A fall at/above this percent reads as "marcado" (pronounced). Between the two ⇒ "moderado".
    public static let pronouncedDipPct: Double = 18.0

    // MARK: - Output

    public enum Confidence: String, Equatable, Sendable, Codable {
        case unreadable   // too short / too gappy to read the fall
        case estimate     // enough to report, thin coverage
        case solid        // full coverage over a full night
    }

    /// How pronounced the fall was — a soft descriptor, NOT a risk class.
    public enum DipShape: String, Equatable, Sendable, Codable {
        case blunted      // < bluntedDipPct — "poco marcado"
        case moderate     // in between
        case pronounced   // ≥ pronouncedDipPct — "marcado"
    }

    public struct Result: Equatable, Sendable {
        /// Lowest 5-min rolling-mean HR of the asleep night (bpm).
        public let nadirBpm: Double
        /// Local clock hour of that nadir, in [0, 24).
        public let nadirHour: Double
        /// Percent the heart fell from the waking reference to the nadir ((wake − nadir)/wake · 100),
        /// clamped at 0 (a night that never fell below the waking reference reads as 0, not negative).
        public let dipPct: Double
        /// Soft shape descriptor derived from `dipPct`.
        public let dipShape: DipShape
        /// Fraction of the asleep night spent below the user's baseline resting HR, in [0, 1].
        public let fractionBelowRHR: Double
        public let confidence: Confidence
        /// Honest es-MX one-liner (a pattern, never a diagnosis).
        public let note: String
        public init(nadirBpm: Double, nadirHour: Double, dipPct: Double, dipShape: DipShape,
                    fractionBelowRHR: Double, confidence: Confidence, note: String) {
            self.nadirBpm = nadirBpm; self.nadirHour = nadirHour
            self.dipPct = dipPct; self.dipShape = dipShape
            self.fractionBelowRHR = fractionBelowRHR
            self.confidence = confidence; self.note = note
        }
    }

    // MARK: - Inputs

    /// One asleep span (wall-clock unix seconds). The caller passes the session's non-wake stage spans
    /// (from `SleepStager` staging); pass a single [start, end] span when staging is unavailable.
    public struct AsleepSpan: Equatable, Sendable {
        public let start: Int
        public let end: Int
        public init(start: Int, end: Int) { self.start = start; self.end = end }
    }

    // MARK: - API

    /// Derive the shape of the nocturnal HR fall.
    ///
    /// - Parameters:
    ///   - hr: the night's HR samples (wall-clock ts). Filtered to the asleep spans internally.
    ///   - asleep: the asleep (non-wake) spans of the night. Empty ⇒ unreadable.
    ///   - wakingReferenceHR: the user's waking-day HR reference (bpm) the fall is measured against.
    ///     `nil`/≤0 ⇒ we can't compute a dip, so the whole shape is withheld (returns nil).
    ///   - rhrBaseline: the user's baseline resting HR (bpm) for the "% of night below your RHR" read.
    ///     `nil`/≤0 ⇒ `fractionBelowRHR` is reported as 0 and omitted from the note.
    ///   - tzOffsetSeconds: seconds to add to a UTC ts to get local wall-clock time (for the nadir hour).
    public static func compute(hr: [HRSample],
                               asleep: [AsleepSpan],
                               wakingReferenceHR: Double?,
                               rhrBaseline: Double?,
                               tzOffsetSeconds: Int) -> Result? {
        guard let wake = wakingReferenceHR, wake > 0 else { return nil }
        guard !asleep.isEmpty else { return nil }

        let asleepSec = asleep.reduce(0) { $0 + max(0, $1.end - $1.start) }
        guard asleepSec > 0 else { return nil }

        // Keep only samples that fall inside an asleep span, sorted by time.
        let inSleep = hr
            .filter { s in asleep.contains { s.ts >= $0.start && s.ts < $0.end } }
            .sorted { $0.ts < $1.ts }
        guard inSleep.count >= 2 else { return nil }

        // Coverage: span of time the samples actually cover, over the asleep span length.
        let covered = Double(inSleep.last!.ts - inSleep.first!.ts)
        let coverage = min(1.0, covered / Double(asleepSec))

        let confidence: Confidence
        if asleepSec < minAsleepSec || coverage < minCoverageForRead {
            confidence = .unreadable
        } else if coverage >= minCoverageForSolid {
            confidence = .solid
        } else {
            confidence = .estimate
        }
        if confidence == .unreadable {
            return Result(nadirBpm: 0, nadirHour: 0, dipPct: 0, dipShape: .moderate,
                          fractionBelowRHR: 0, confidence: .unreadable,
                          note: "No hay suficiente señal esta noche para leer cómo bajó tu corazón.")
        }

        // Nadir = minimum of the 5-min rolling mean; report its VALUE and its TIME.
        let (nadirBpm, nadirTs) = rollingMeanMinimum(inSleep, windowSec: nadirWindowSec)
        let nadirHour = localHour(nadirTs, tzOffsetSeconds: tzOffsetSeconds)

        let dipRaw = (wake - nadirBpm) / wake * 100.0
        let dipPct = max(0.0, dipRaw)
        let shape: DipShape = dipPct >= pronouncedDipPct ? .pronounced
                            : dipPct < bluntedDipPct ? .blunted
                            : .moderate

        // % of asleep samples below the user's own baseline RHR.
        var fractionBelowRHR = 0.0
        if let rhr = rhrBaseline, rhr > 0 {
            let below = inSleep.reduce(0) { $0 + (Double($1.bpm) < rhr ? 1 : 0) }
            fractionBelowRHR = Double(below) / Double(inSleep.count)
        }

        let note = phrase(dipPct: dipPct, shape: shape, nadirHour: nadirHour,
                          fractionBelowRHR: (rhrBaseline ?? 0) > 0 ? fractionBelowRHR : nil)

        return Result(nadirBpm: nadirBpm, nadirHour: nadirHour, dipPct: dipPct, dipShape: shape,
                      fractionBelowRHR: fractionBelowRHR, confidence: confidence, note: note)
    }

    // MARK: - Internals

    /// Minimum of the centered-forward 5-min rolling mean of HR, and the timestamp at its center.
    /// For each sample i, average all samples in [ts_i, ts_i + windowSec); the returned ts is `ts_i`
    /// (the window's start). The same primitive SleepStager uses for `restingHR`, kept with its time.
    static func rollingMeanMinimum(_ hr: [HRSample], windowSec: Int) -> (bpm: Double, ts: Int) {
        var best = Double.greatestFiniteMagnitude
        var bestTs = hr.first!.ts
        var lo = 0
        // Two-pointer sliding window over time-sorted samples.
        var runningSum = 0
        var count = 0
        var hi = 0
        for i in hr.indices {
            let windowEnd = hr[i].ts + windowSec
            // extend hi to include all samples with ts < windowEnd
            while hi < hr.count && hr[hi].ts < windowEnd {
                runningSum += hr[hi].bpm; count += 1; hi += 1
            }
            // shrink lo to i (window starts at sample i)
            while lo < i {
                runningSum -= hr[lo].bpm; count -= 1; lo += 1
            }
            if count > 0 {
                let mean = Double(runningSum) / Double(count)
                if mean < best { best = mean; bestTs = hr[i].ts }
            }
        }
        return (best, bestTs)
    }

    /// Local clock hour in [0, 24) for a wall-clock ts and a tz offset (locale-free; pure).
    static func localHour(_ ts: Int, tzOffsetSeconds: Int) -> Double {
        let local = ((ts + tzOffsetSeconds) % 86_400 + 86_400) % 86_400
        return Double(local) / 3600.0
    }

    /// Honest es-MX one-liner. A pattern, never a diagnosis.
    static func phrase(dipPct: Double, shape: DipShape, nadirHour: Double, fractionBelowRHR: Double?) -> String {
        let pct = Int(dipPct.rounded())
        let clock = clockString(nadirHour)
        let shapeWord: String
        switch shape {
        case .pronounced: shapeWord = "un descenso marcado"
        case .moderate:   shapeWord = "un descenso moderado"
        case .blunted:    shapeWord = "un descenso poco marcado"
        }
        var s = "Tu corazón bajó \(pct)% y tocó su punto más bajo a las \(clock) — \(shapeWord)."
        if let f = fractionBelowRHR {
            let below = Int((f * 100).rounded())
            s += " Pasaste \(below)% de la noche por debajo de tu ritmo en reposo."
        }
        return s
    }

    /// Format a clock hour as "H:MM" (24 h, no leading zero on the hour), locale-free.
    static func clockString(_ hour: Double) -> String {
        var h = Int(hour) % 24
        var m = Int(((hour - Double(Int(hour))) * 60.0).rounded())
        if m == 60 { m = 0; h = (h + 1) % 24 }
        return String(format: "%d:%02d", h, m)
    }
}
