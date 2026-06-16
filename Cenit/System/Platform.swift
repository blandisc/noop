import SwiftUI
import UIKit

/// The native bitmap image type.
public typealias PlatformImage = UIImage

// MARK: - Image bridging

extension Image {
    /// Build a SwiftUI `Image` from the platform-native bitmap type (`UIImage`) so call
    /// sites stay agnostic to the underlying image type.
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

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
