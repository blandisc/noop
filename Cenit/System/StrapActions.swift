import Foundation
import UIKit

/// What a strap double-tap (or a wrist-off trigger) does. A third-party app cannot lock an iPhone,
/// so `lockScreen` is hidden from the action picker via `available`.
enum StrapActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case lockScreen
    case buzzBack
    case markMoment
    case runShortcut

    var id: String { rawValue }

    /// Actions offered to the user. iOS cannot lock the device, so that action is dropped.
    static var available: [StrapActionKind] {
        allCases.filter { $0 != .lockScreen }
    }

    var label: String {
        switch self {
        case .none:        return String(localized: "Nothing")
        case .lockScreen:  return String(localized: "Lock the device")
        case .buzzBack:    return String(localized: "Buzz back (confirm)")
        case .markMoment:  return String(localized: "Mark a moment")
        case .runShortcut: return String(localized: "Run a Shortcut…")
        }
    }
    var symbol: String {
        switch self {
        case .none:        return "circle.slash"
        case .lockScreen:  return "lock.fill"
        case .buzzBack:    return "waveform.path"
        case .markMoment:  return "mappin.and.ellipse"
        case .runShortcut: return "bolt.fill"
        }
    }
}

/// Side effects for strap-triggered actions. Sandbox-friendly: Shortcuts run via the URL scheme
/// (Shortcuts.app does the privileged work). iOS has no screen-lock entry point, so `lockScreen()`
/// always returns false and callers fall back to a "Lock Screen" Shortcut.
enum StrapActions {
    /// No iOS API can lock the device, so this always returns false; callers fall back to a
    /// "Lock Screen" Shortcut.
    @discardableResult
    static func lockScreen() -> Bool {
        false
    }

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
