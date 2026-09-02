import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public extension StrandFont {
    /// SF Pro at an arbitrary point size that STILL scales with Dynamic Type (FER-918).
    ///
    /// The named `StrandFont` scale (`body`, `caption`, …) covers the common reading sizes and
    /// scales, but some components need a specific size the scale doesn't have (a 14pt menu row,
    /// an 11pt tile label). `Font.system(size:)` at a literal size does NOT scale. This wraps the
    /// system font in `UIFontMetrics` so at the default text size it renders at exactly `size`
    /// (zero layout change) and grows/shrinks with the user's setting.
    ///
    /// Use for **reading text** only. Numerals in geometry (`display`/`number`) and fixed chrome
    /// (`tabTitle`) intentionally stay unscaled.
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular,
                       relativeTo style: Font.TextStyle = .body) -> Font {
        #if canImport(UIKit)
        let uiWeight: UIFont.Weight
        switch weight {
        case .black: uiWeight = .black
        case .heavy: uiWeight = .heavy
        case .bold: uiWeight = .bold
        case .semibold: uiWeight = .semibold
        case .medium: uiWeight = .medium
        case .light: uiWeight = .light
        case .thin: uiWeight = .thin
        case .ultraLight: uiWeight = .ultraLight
        default: uiWeight = .regular
        }
        let uiStyle: UIFont.TextStyle
        switch style {
        case .largeTitle: uiStyle = .largeTitle
        case .title: uiStyle = .title1
        case .title2: uiStyle = .title2
        case .title3: uiStyle = .title3
        case .headline: uiStyle = .headline
        case .subheadline: uiStyle = .subheadline
        case .callout: uiStyle = .callout
        case .footnote: uiStyle = .footnote
        case .caption: uiStyle = .caption1
        case .caption2: uiStyle = .caption2
        default: uiStyle = .body
        }
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight)
        return Font(UIFontMetrics(forTextStyle: uiStyle).scaledFont(for: base))
        #else
        return .system(size: size, weight: weight)
        #endif
    }
}
