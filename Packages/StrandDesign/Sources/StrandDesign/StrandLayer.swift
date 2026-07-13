import SwiftUI

/// Z-index layers — the app's stacking order, named. Higher draws on top.
public enum StrandLayer: Double {
    case base = 0      // root content
    case overlay = 1   // onboarding, detail-as-layer
    case gate = 2      // Terms gate — above everything

    public var z: Double { rawValue }
}

public extension View {
    /// Place this view on a named stacking layer instead of a raw `.zIndex(1)`.
    func strandLayer(_ layer: StrandLayer) -> some View { zIndex(layer.z) }
}
