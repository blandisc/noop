import Foundation

/// Shared presentation formatters (FER-326). Lives in the design system because formatting is
/// part of the visual language — screens consume these instead of re-declaring NumberFormatters.
public enum StrandFormat {
    /// Thousands-grouped integer (no fraction digits), e.g. 12345 → "12,345".
    public static func groupedInt(_ v: Double) -> String {
        groupedIntFormatter.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }
    private static let groupedIntFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// «Sáb 15 ago» — a short weekday+day+month heading, capitalized, in the current locale. Shared
    /// between `EntrenarView`'s landing header and `TrainingBodyScreen`'s «Tu cuerpo» header
    /// (FER-136 · V7, quisquilloso ronda 4): the two copies drifted apart as a hand-synced duplicate.
    public static func weekdayHeading(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let s = f.string(from: date)
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
