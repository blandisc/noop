import SwiftUI
import UIKit

// MARK: - Pasteboard

/// Clipboard write via `UIPasteboard`.
enum PlatformPasteboard {
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}

// MARK: - Opening URLs

/// "Open this URL with the system" helper. Used for `mailto:` and `shortcuts://`.
enum PlatformOpen {
    @MainActor static func url(_ url: URL) {
        UIApplication.shared.open(url)
    }
}
