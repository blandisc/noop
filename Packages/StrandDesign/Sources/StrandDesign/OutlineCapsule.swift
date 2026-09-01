import SwiftUI

// MARK: - OutlineCapsule (FER-280 · clase 2)
//
// Control tocable en cápsula con `strokeBorder(hairlineStrong)` ± fill opcional.
// Receta pixel-fiel de los sitios reales:
//   · sm — `RoutineSheetLiveTarjeta.swift:125/336` (raise / Start·Stop): pad H s250 · V s150
//   · md — `ExerciseLibraryScreen.swift:206` (chip de filtro): pad H gap · V 6; fill tinta
//     cuando activo (sin stroke).
// Press: `EntrenarPressStyle` (scale 0.97 · Reduce Motion → opacidad).
//
// Cuándo SÍ: acción secundaria en cápsula outline (Use, Start/Stop, raise, filtro, Match…).
// Cuándo NO: CTA de tinta a lo ancho (`StrandCTAButton`); botón pill Liquid de hoja
// (`LiquidGlassButton`); cápsula de header con nombre (`HeaderActionButton`).

public struct OutlineCapsule<Label: View>: View {
    public enum Size: Sendable {
        /// Pad H `LiquidSpace.s250` · V `LiquidSpace.s150` — raise / Start·Stop.
        case sm
        /// Pad H `CenitMetrics.gap` · V 6 — chip de filtro de biblioteca.
        case md

        /// Pad horizontal fijado a la receta citada (no inventar).
        public var horizontalPad: CGFloat {
            switch self {
            case .sm: return LiquidSpace.s250
            case .md: return CenitMetrics.gap
            }
        }

        /// Pad vertical — `md` usa 6 (chip handoff, `ExerciseLibraryScreen:206`).
        public var verticalPad: CGFloat {
            switch self {
            case .sm: return LiquidSpace.s150
            case .md: return 6
            }
        }
    }

    private let theme: InstrumentoTheme
    private let size: Size
    /// `true` → relleno tinta, sin stroke (chip activo). `false` → outline hairlineStrong.
    private let filled: Bool
    /// Relleno cuando `filled`; `nil` = `theme.ink`.
    private let fill: Color?
    private let action: () -> Void
    private let label: () -> Label

    public init(theme: InstrumentoTheme,
                size: Size = .sm,
                filled: Bool = false,
                fill: Color? = nil,
                action: @escaping () -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        self.theme = theme
        self.size = size
        self.filled = filled
        self.fill = fill
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, size.horizontalPad)
                .padding(.vertical, size.verticalPad)
                .background(capsuleFill, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(theme.hairlineStrong, lineWidth: filled ? 0 : 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(EntrenarPressStyle())
    }

    private var capsuleFill: Color {
        filled ? (fill ?? theme.ink) : Color.clear
    }
}

public extension OutlineCapsule where Label == Text {
    /// Atajo de rótulo simple (Start / Stop / Use / Archive…).
    init(_ title: LocalizedStringKey,
         theme: InstrumentoTheme,
         size: Size = .sm,
         filled: Bool = false,
         fill: Color? = nil,
         foreground: Color? = nil,
         weight: Font.Weight = .semibold,
         action: @escaping () -> Void) {
        let fg = foreground ?? (filled ? theme.paper : theme.ink)
        self.init(theme: theme, size: size, filled: filled, fill: fill, action: action) {
            Text(title)
                .font(StrandFont.caption.weight(weight))
                .foregroundStyle(fg)
        }
    }
}

#if DEBUG
#Preview("OutlineCapsule") {
    let t = InstrumentoTheme.base
    VStack(alignment: .leading, spacing: 16) {
        Text("sm · outline").font(StrandFont.overline).foregroundStyle(t.inkTertiary)
        HStack(spacing: 10) {
            OutlineCapsule(theme: t, size: .sm, action: {}) {
                HStack(spacing: LiquidSpace.s150) {
                    Text(verbatim: "▲").foregroundStyle(LiquidColor.verdeProfundo)
                    Text("Take the raise").font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(t.ink)
                }
            }
            OutlineCapsule("Start", theme: t, size: .sm, weight: .bold, action: {})
            OutlineCapsule("Stop", theme: t, size: .sm, weight: .bold, action: {})
        }
        Text("md · filtro").font(StrandFont.overline).foregroundStyle(t.inkTertiary)
        HStack(spacing: 10) {
            OutlineCapsule("Equipment", theme: t, size: .md, action: {})
            OutlineCapsule("Barbell", theme: t, size: .md, filled: true, action: {})
        }
        Text("pressed = EntrenarPressStyle 0.97").font(StrandFont.caption)
            .foregroundStyle(t.inkTertiary)
    }
    .padding(24)
    .background(t.paper)
    .instrumentoTheme(t)
}
#endif
