import Foundation

/// Display labels for strength sessions imported from a CSV (FER-333 · E9).
/// Never returns a label for sessions logged in Cénit (`source == nil`).
enum StrengthImportSource {
    /// Localized short seal for history rows and the Fuente badge («Strong» / «Hevy» / «Cénit»).
    static func label(_ source: String?) -> String? {
        switch source?.lowercased() {
        case "strong": return String(localized: "Strong")
        case "hevy": return String(localized: "Hevy")
        case "cenit": return String(localized: "Cénit")
        default: return nil
        }
    }
}
