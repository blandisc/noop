import Foundation
import UIKit

/// What a strap double-tap does — the action the user picks in Automations.
enum StrapActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case buzzBack
    case markMoment
    case runShortcut

    var id: String { rawValue }

    /// Actions offered in the double-tap picker.
    static var available: [StrapActionKind] { allCases }

    var label: String {
        switch self {
        case .none:        return String(localized: "Nothing")
        case .buzzBack:    return String(localized: "Buzz back (confirm)")
        case .markMoment:  return String(localized: "Mark a moment")
        case .runShortcut: return String(localized: "Run a Shortcut…")
        }
    }
    var symbol: String {
        switch self {
        case .none:        return "circle.slash"
        case .buzzBack:    return "waveform.path"
        case .markMoment:  return "mappin.and.ellipse"
        case .runShortcut: return "bolt.fill"
        }
    }
}

/// Side effects for strap-triggered actions. Sandbox-friendly: Shortcuts run via the URL scheme
/// (Shortcuts.app does the privileged work).
enum StrapActions {
    /// Run a Shortcut by name via the `shortcuts://` URL scheme. Anything the user can build in
    /// Shortcuts is reachable this way; this foregrounds the Shortcuts app to run it.
    @MainActor
    static func runShortcut(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)") else { return }
        PlatformOpen.url(url)
    }
}
