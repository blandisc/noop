import SwiftUI
import StrandDesign

/// Plain-language copy for "where you've been across your bands" — the one-line summary sentence shown
/// above the ranges list (summary sheet) and in the vital detail. Built from the pure
/// `TrendBands.summarize` so the wording is identical wherever it appears, and honest: it only describes
/// where your readings fell, never claims a cause or a trend. (FER-459)
enum BandSummaryCopy {

    /// Metrics whose reading is a nightly measurement → the copy says "noches/anoche" instead of
    /// "días/hoy". Resting HR is measured overnight too, but it's presented as a daily resting value
    /// (and the owner-approved design reads "días/hoy" for it), so it's intentionally a day metric here.
    static func isNightly(metricID: String) -> Bool {
        metricID == "sleep" || metricID == "spo2" || metricID == "resp_rate"
    }

    /// "N days/nights" for a band-row count, with correct singular/plural.
    static func countLabel(_ count: Int, nightly: Bool) -> LocalizedStringKey {
        if nightly { return count == 1 ? "\(count) night" : "\(count) nights" }
        return count == 1 ? "\(count) day" : "\(count) days"
    }

    /// The summary sentence, or `nil` below the 7-reading floor (not enough to claim a pattern). Band
    /// names are tinted with `hue`; the surrounding text inherits the caller's color. (FER-459)
    static func sentence(_ s: BandTrendSummary, labels: [LocalizedStringKey],
                         nightly: Bool, hue: Color) -> Text? {
        guard s.n >= 7, labels.count == s.counts.count else { return nil }
        func band(_ i: Int) -> Text { Text(labels[i]).foregroundStyle(hue) }
        let period = Text(verbatim: ".")

        // Clause 1 — the window + where you mostly were.
        let window = nightly ? Text("In the last \(s.n) nights") : Text("In the last \(s.n) days")

        switch s.tier {
        case .scattered:
            return window + Text(" you haven't stayed in one range.")
        case .alternating:
            let lo = min(s.dominant, s.second ?? s.dominant)
            let hi = max(s.dominant, s.second ?? s.dominant)
            return window + Text(" you've moved between ") + band(lo) + Text(" and ") + band(hi) + period
        case .always:
            return window + Text(" you've stayed in ") + band(s.dominant) + period
        case .almostAlways, .mostly:
            let connective = s.tier == .almostAlways
                ? Text(" you've been almost always in ")
                : Text(" you've been mostly in ")
            let clause1 = window + connective + band(s.dominant)

            // Clause 2 — and today, relative to that dominant band.
            switch s.todayVsDominant {
            case .lower:
                return clause1
                    + (nightly ? Text("; last night it dropped to ") : Text("; today you dropped to "))
                    + band(s.todayIndex!) + period
            case .higher:
                return clause1
                    + (nightly ? Text("; last night it rose to ") : Text("; today you rose to "))
                    + band(s.todayIndex!) + period
            case .same:
                return clause1
                    + (nightly ? Text(", and last night too.") : Text(", and you're still there today."))
            case .none:
                return clause1 + period
            }
        }
    }
}
