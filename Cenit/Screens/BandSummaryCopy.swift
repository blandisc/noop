import SwiftUI
import StrandDesign

/// Plain-language helpers for the "days in range" readouts — the per-band counts in the ranges table and
/// the standardized «{band} · X of the last N days/nights in this range» line. Nocturnal metrics read
/// "noches"; the rest "días". (FER-459 / FER-469)
enum BandSummaryCopy {

    /// Metrics whose reading is a nightly measurement → the copy says "noches" instead of "días".
    /// Resting HR is the lowest pulse of the NIGHT and Hoy reads it as «anoche» since FER-55/118
    /// (module, scrub, listed hero): the sheet dates it the same way — «LAST NIGHT · Aug 21», «nights»
    /// (FER-128, explorer r4; the earlier «días» reading predates the nightly anchoring).
    static func isNightly(metricID: String) -> Bool {
        metricID == "sleep" || metricID == "rhr" || metricID == "spo2" || metricID == "resp_rate" || metricID == "skin_temp"
    }

    /// "N days/nights" for a band-row count, with correct singular/plural.
    static func countLabel(_ count: Int, nightly: Bool) -> LocalizedStringKey {
        if nightly { return count == 1 ? "\(count) night" : "\(count) nights" }
        return count == 1 ? "\(count) day" : "\(count) days"
    }
}
