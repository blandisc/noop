import SwiftUI

/// Elevation scale — 5 drop-shadow levels, all cast with the theme ink color.
/// Values are derived from the real inline shadows across the app (grouped). The
/// thermal receipt and ambient glows are a separate micro-system and stay exempt.
public enum StrandElevation {
    case hairline   // tile, keypad
    case raised     // card that lifts
    case floating   // banner, menu
    case overlay    // sheet
    case modal      // modal panel

    public var radius: CGFloat {
        switch self {
        case .hairline: return 1.5
        case .raised:   return 8
        case .floating: return 12
        case .overlay:  return 20
        case .modal:    return 25
        }
    }
    public var y: CGFloat {
        switch self {
        case .hairline: return 1
        case .raised:   return 3
        case .floating: return 6
        case .overlay:  return 12
        case .modal:    return 14
        }
    }
    public var opacity: Double {
        switch self {
        case .hairline: return 0.05
        case .raised:   return 0.08
        case .floating: return 0.10
        case .overlay:  return 0.18
        case .modal:    return 0.20
        }
    }
}

public extension View {
    /// Apply a named elevation shadow. Pass the theme ink color (e.g. `theme.ink`).
    func strandElevation(_ level: StrandElevation, ink: Color) -> some View {
        shadow(color: ink.opacity(level.opacity), radius: level.radius, y: level.y)
    }
}

#Preview("Elevation") {
    VStack(spacing: 28) {
        ForEach([StrandElevation.hairline, .raised, .floating, .overlay, .modal], id: \.radius) { level in
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.98))
                .frame(width: 220, height: 48)
                .strandElevation(level, ink: .black)
        }
    }
    .padding(50)
    .background(Color(red: 0.945, green: 0.925, blue: 0.882))
}
