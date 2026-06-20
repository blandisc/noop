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
}
