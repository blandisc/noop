import SwiftUI

// MARK: - OriginStamp — the standardized data-origin seal (handoff v2)
//
// One line at the FOOT of every Tendencias/Cuerpo detail screen: a 6px dot in the origin's hue plus
// «{Fuente} · {cuándo}». It answers "where did this number come from, and when" without stealing the
// title (the §8.7 rule keeps the metric icon up top and moves provenance down here). The dot hue is an
// alias of an existing theme role (`originBand`/`originApple`/`originComputed`) so origin and metric
// hues can never drift apart. Pure SwiftUI; no UIKit/AppKit.

/// Where a displayed reading came from. Drives both the dot color and the es-MX source label.
public enum DataOrigin: Sendable, Hashable {
    /// The WHOOP strap/band.
    case band
    /// Apple Salud (HealthKit).
    case apple
    /// Computed on-device from other signals.
    case computed
}

public extension DataOrigin {
    /// Dot color for this origin, pulled from the theme so it tracks the metric roles.
    func color(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .band:     return theme.originBand
        case .apple:    return theme.originApple
        case .computed: return theme.originComputed
        }
    }

    /// Source label shown before the "· {cuándo}". English keys resolve against the app bundle
    /// (handoff «Detalle de Tendencias Final»: es «Medido por tu banda» / «Calculado en tu teléfono»;
    /// «Apple Health» stays a brand name in every locale).
    var label: String {
        switch self {
        case .band:     return String(localized: "Measured by your band", bundle: .main)
        case .apple:    return String(localized: "Apple Health", bundle: .main)
        case .computed: return String(localized: "Computed on your phone", bundle: .main)
        }
    }
}

/// `● {Fuente} · {cuándo}` — the standardized origin seal. `when` is passed by the caller (the screen),
/// typically from `relativeAgo(...)` or a fixed label like «anoche» / «hoy, en curso». `inProgress`
/// renders the dot as a hollow 1.5px ring — a reading still accumulating («hoy, en curso»). (FER-856)
public struct OriginStamp: View {
    private let origin: DataOrigin
    private let when: String
    private let inProgress: Bool
    private let theme: InstrumentoTheme

    public init(origin: DataOrigin, when: String, inProgress: Bool = false, theme: InstrumentoTheme) {
        self.origin = origin
        self.when = when
        self.inProgress = inProgress
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(inProgress ? Color.clear : origin.color(theme))
                .overlay {
                    if inProgress {
                        Circle().strokeBorder(origin.color(theme), lineWidth: 1.5)
                    }
                }
                .frame(width: 6, height: 6)
            // «{Fuente} · {cuándo}» — one flat line, tertiary ink, 11pt.
            Text(verbatim: "\(origin.label) · \(when)")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("OriginStamp") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 12) {
        OriginStamp(origin: .band, when: "anoche", theme: t)
        OriginStamp(origin: .apple, when: "medido hace 3 días", theme: t)
        OriginStamp(origin: .computed, when: "hace 2 h", theme: t)
    }
    .padding(24)
    .background(t.paper)
}
#endif
