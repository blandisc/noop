import SwiftUI
import CenitDesign

/// Plain-language helpers for the "days in range" readouts — the per-band counts in the ranges table and
/// the standardized «{band} · X of the last N days/nights in this range» line. Nocturnal metrics read
/// "noches"; the rest "días". (FER-459 / FER-469)
enum BandSummaryCopy {

    /// Metrics whose reading is a nightly measurement → the copy says "noches" instead of "días". Resting
    /// HR is measured overnight too, but it's presented as a daily resting value (and the owner-approved
    /// design reads "días" for it), so it's intentionally a day metric here.
    static func isNightly(metricID: String) -> Bool {
        metricID == "sleep" || metricID == "spo2" || metricID == "resp_rate" || metricID == "skin_temp"
    }

    /// "N days/nights" for a band-row count, with correct singular/plural.
    static func countLabel(_ count: Int, nightly: Bool) -> LocalizedStringKey {
        if nightly { return count == 1 ? "\(count) night" : "\(count) nights" }
        return count == 1 ? "\(count) day" : "\(count) days"
    }
}
