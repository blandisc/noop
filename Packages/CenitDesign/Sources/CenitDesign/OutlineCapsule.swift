import SwiftUI

// MARK: - OutlineCapsule (FER-280 · clase 2 · FER-295 · 2A · FER-316)
//
// Control tocable en cápsula con `strokeBorder(vidrioBordeFuerte)` ± fill opcional, o con
// `Estilo` (outline / papel / vidrio / teñida). Receta pixel-fiel de los sitios reales:
//   · sm — `RoutineSheetLiveTarjeta.swift:125/336` (raise / Start·Stop): pad H s250 · V s150
//   · md — `ExerciseLibraryScreen.swift:206` (chip de filtro): pad H gap · V 6; fill tinta
//     cuando activo (sin stroke).
//   · lg — pad H `LiquidSpace.s400` · minHeight `EntrenarMetrics.secondaryButton` (36) · toque 44
//     vía `contentShape` con inset negativo (Terminar / Saltar descanso / Casi).
// Press: `EntrenarPressStyle` (scale 0.97 · Reduce Motion → opacidad).
//
// Cuándo SÍ: acción secundaria en cápsula outline (Use, Start/Stop, raise, filtro, Match…);
//   píldoras de papel/vidrio/tono del hub (Terminar, Otra forma, Hoy subes).
// Cuándo NO: CTA de tinta a lo ancho (`CenitCTAButton`); botón pill Liquid de hoja
// (`LiquidGlassButton`); cápsula de header con nombre (`HeaderActionButton`).

public struct OutlineCapsule<Label: View>: View {
    public enum Size: Sendable {
        /// Pad H `LiquidSpace.s250` · V `LiquidSpace.s150` — raise / Start·Stop.
        case sm
        /// Pad H `LiquidSpace.s300` · V 6 — chip de filtro de biblioteca.
        case md
        /// Pad H `LiquidSpace.s400` · minHeight `EntrenarMetrics.secondaryButton` (36) —
        /// Terminar / Saltar descanso. El dibujo queda en 36; el toque llega a 44 vía
        /// `contentShape` con inset negativo (`EntrenarMetrics.row`).
        case lg
        /// Pad H `LiquidSpace.s400` · minHeight `EntrenarMetrics.focusRestSkip` (46) —
        /// «Saltar descanso» en Foco a pantalla completa. Ya ≥ 44; sin expandTouch.
        case xl
        /// Geometría dictada por el caller (FER-295 ronda 3): conserva recetas previas pixel a pixel
        /// (píldoras del héroe, pill del teclado) sin inventar tallas nuevas. `touchInset` > 0 expande el toque.
        case aMedida(insets: EdgeInsets, minHeight: CGFloat?, touchInset: CGFloat)

        /// Pad horizontal fijado a la receta citada (no inventar).
        public var horizontalPad: CGFloat {
            switch self {
            case .sm: return LiquidSpace.s250
            case .md: return LiquidSpace.s300
            case .lg, .xl: return LiquidSpace.s400
            case .aMedida(let i, _, _): return i.leading
            }
        }

        /// Pad vertical — `md` usa 6 (chip handoff, `ExerciseLibraryScreen:206`);
        /// `lg`/`xl` usan 0 (la altura la fija `minHeight`).
        public var verticalPad: CGFloat {
            switch self {
            case .sm: return LiquidSpace.s150
            case .md: return 6
            case .lg, .xl: return 0
            case .aMedida(let i, _, _): return i.top
            }
        }

        /// Insets completos (asimétricos cuando la receta lo pide).
        public var insets: EdgeInsets {
            switch self {
            case .aMedida(let i, _, _): return i
            default: return EdgeInsets(top: verticalPad, leading: horizontalPad, bottom: verticalPad, trailing: horizontalPad)
            }
        }

        /// Alto mínimo del dibujo. `lg` = 36; `xl` = 46 (`focusRestSkip`);
        /// `sm`/`md` dejan que el padding vertical defina la altura.
        public var minHeight: CGFloat? {
            switch self {
            case .sm, .md: return nil
            case .lg: return EntrenarMetrics.secondaryButton
            case .xl: return EntrenarMetrics.focusRestSkip
            case .aMedida(_, let h, _): return h
            }
        }

        /// Inset negativo del `contentShape` para llegar al toque HIG (44) sin agrandar el
        /// dibujo. Solo `lg` (36 → 44 ⇒ 4 pt por lado). `xl` ya mide 46.
        public var touchInset: CGFloat {
            switch self {
            case .sm, .md, .xl: return 0
            case .lg:
                return (EntrenarMetrics.row - EntrenarMetrics.secondaryButton) / 2
            case .aMedida(_, _, let t): return t
            }
        }
    }

    private let size: Size
    private let estilo: Estilo
    /// Legacy (FER-280): `true` → relleno tinta, sin stroke (chip activo). Tiene prioridad
    /// sobre `estilo` para no romper callers de `filled:`/`fill:`.
    private let filled: Bool
    /// Relleno cuando `filled`; `nil` = `LiquidColor.tinta900`.
    private let fill: Color?
    private let action: () -> Void
    private let label: () -> Label

    /// Init canónico (FER-295 · 2A). `estilo` default `.outline`; `filled`/`fill` legacy
    /// siguen compilando sin tocar una línea en los callers existentes.
    /// `theme` se ignora (FER-316): el cromo lee `LiquidColor` directo.
    public init(theme: InstrumentoTheme = .base,
                size: Size = .sm,
                estilo: Estilo = .outline,
                filled: Bool = false,
                fill: Color? = nil,
                action: @escaping () -> Void,
                @ViewBuilder label: @escaping () -> Label) {
        _ = theme
        self.size = size
        self.estilo = estilo
        self.filled = filled
        self.fill = fill
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .modifier(OutlineCapsuleChrome<Label>(
                    size: size, estilo: estilo,
                    filled: filled, fill: fill, expandTouch: true))
        }
        .buttonStyle(EntrenarPressStyle())
    }
}

// MARK: - Estilo (FER-295 · 2A)

public extension OutlineCapsule {
    /// Cromo de la cápsula. Los alfas de `.vidrio` / `.tenida` reusan
    /// `EntrenarHubMetrics.otraForma*` / `subPill*` — no inventar números.
    enum Estilo: Sendable {
        /// Stroke `LiquidColor.tinta10`, sin relleno (comportamiento `filled: false`).
        case outline
        /// Stroke `LiquidColor.tinta7` (canto suave), sin relleno: el estado DESHABILITADO de una
        /// pill (teclado de sesión, FER-298 ítem 5) — misma geometría que `.outline`.
        case outlineSuave
        /// Fondo `LiquidColor.papelTarjeta` + stroke `LiquidColor.tinta10`
        /// (Terminar / Saltar descanso / Casi).
        case papel
        /// Vidrio blanco — alfas de `EntrenarHubMetrics.otraForma*` (Otra forma ⌄).
        case vidrio
        /// Superficie teñida — fondo a intensidad default + alfas `subPill*` (Hoy subes).
        case tenida(LiquidTono)
    }
}

// MARK: - Atajo Text

public extension OutlineCapsule where Label == Text {
    /// Atajo de rótulo simple (Start / Stop / Use / Archive…). `estilo` default `.outline`;
    /// `filled`/`fill` legacy sin cambios de firma.
    /// `theme` se ignora (FER-316): el cromo lee `LiquidColor` directo.
    init(_ title: LocalizedStringKey,
         theme: InstrumentoTheme = .base,
         size: Size = .sm,
         estilo: Estilo = .outline,
         filled: Bool = false,
         fill: Color? = nil,
         foreground: Color? = nil,
         weight: Font.Weight = .semibold,
         action: @escaping () -> Void) {
        let fg = foreground ?? (filled ? LiquidColor.fondoAlto : LiquidColor.tinta900)
        self.init(theme: theme, size: size, estilo: estilo, filled: filled, fill: fill,
                  action: action) {
            Text(title)
                .font(StrandFont.caption.weight(weight))
                .foregroundStyle(fg)
        }
    }
}

// MARK: - Modifier decorativo (sin Button)

public extension View {
    /// Solo el cromo (padding de la talla + fondo + borde + sombra según `estilo`),
    /// sin `Button` — para rótulos que no son botón («ZONA 2», «Casi») o controles con
    /// su propio gesto.
    /// `theme` se ignora (FER-316): el cromo lee `LiquidColor` directo.
    func outlineCapsule(_ estilo: OutlineCapsule<Text>.Estilo = .outline,
                        size: OutlineCapsule<Text>.Size = .sm) -> some View {
        modifier(OutlineCapsuleChrome<Text>(
            size: size, estilo: estilo,
            filled: false, fill: nil, expandTouch: false))
    }

    /// `theme` ya no pinta nada (FER-316). Preferí `outlineCapsule(_:size:)`.
    @available(*, deprecated, message: "theme ya no pinta nada: la pieza lee LiquidColor (FER-316)")
    func outlineCapsule(_ estilo: OutlineCapsule<Text>.Estilo = .outline,
                        size: OutlineCapsule<Text>.Size = .sm,
                        theme: InstrumentoTheme) -> some View {
        _ = theme
        return outlineCapsule(estilo, size: size)
    }
}

// MARK: - Chrome compartido

/// Padding + fondo + borde + sombra. `expandTouch` solo en el path `Button` (lg → 44 pt).
/// Genérico en `CapsuleLabel` para que `Size`/`Estilo` (anidados en el genérico) no choquen
/// entre `OutlineCapsule<Label>` y el modifier decorativo tipado a `Text`.
private struct OutlineCapsuleChrome<CapsuleLabel: View>: ViewModifier {
    let size: OutlineCapsule<CapsuleLabel>.Size
    let estilo: OutlineCapsule<CapsuleLabel>.Estilo
    let filled: Bool
    let fill: Color?
    let expandTouch: Bool

    private var shape: Capsule { Capsule(style: .continuous) }

    func body(content: Content) -> some View {
        let padded = content
            .padding(size.insets)
        return Group {
            if let h = size.minHeight {
                applyChrome(padded.frame(minHeight: h))
            } else {
                applyChrome(padded)
            }
        }
        .contentShape(touchShape)
    }

    @ViewBuilder
    private func applyChrome<V: View>(_ view: V) -> some View {
        if filled {
            view
                .background(fill ?? LiquidColor.tinta900, in: shape)
        } else {
            switch estilo {
            case .outline:
                // Papel regime: tinta10 (not vidrioBordeFuerte — white glass alfa is invisible on paper).
                view
                    .background(Color.clear, in: shape)
                    .overlay(shape.strokeBorder(LiquidColor.tinta10, lineWidth: 1))
            case .outlineSuave:
                view
                    .background(Color.clear, in: shape)
                    .overlay(shape.strokeBorder(LiquidColor.tinta7, lineWidth: 1))
            case .papel:
                view
                    .background(LiquidColor.papelTarjeta, in: shape)
                    .overlay(shape.strokeBorder(LiquidColor.tinta10, lineWidth: 1))
            case .vidrio:
                // Misma receta que `EntrenarHubHeroe.otraFormaPill`: papelTarjeta / vidrioEspecular
                // (no `Color.white` crudo) para que el héroe se vea idéntico vía este estilo.
                view
                    .background(
                        LiquidColor.papelTarjeta.opacity(EntrenarHubMetrics.otraFormaFondoAlfa),
                        in: shape)
                    .overlay(
                        shape.strokeBorder(
                            LiquidColor.vidrioEspecular.opacity(EntrenarHubMetrics.otraFormaHighlightAlfa),
                            lineWidth: 1))
                    .overlay(
                        shape.strokeBorder(
                            LiquidColor.tinta900.opacity(EntrenarHubMetrics.otraFormaCantoAlfa),
                            lineWidth: 0.5))
                    .liquidShadow([
                        LiquidShadowLayer(
                            color: LiquidColor.tinta900.opacity(EntrenarHubMetrics.otraFormaShadowAlfa),
                            radius: EntrenarHubMetrics.otraFormaShadowRadius,
                            y: EntrenarHubMetrics.otraFormaShadowY)
                    ])
            case .tenida(let tono):
                // Misma receta que `EntrenarHubHeroe.subPill`: highlight `papelTarjeta`, aro
                // `vidrioEspecular` inset 1 pt (no `Color.white`).
                view
                    .background(
                        tono.base.opacity(EntrenarHubMetrics.subPillFondoAlfa),
                        in: shape)
                    .overlay(
                        shape.strokeBorder(
                            LiquidColor.papelTarjeta.opacity(EntrenarHubMetrics.subPillHighlightAlfa),
                            lineWidth: 1))
                    .overlay(
                        shape.strokeBorder(
                            LiquidColor.vidrioEspecular.opacity(EntrenarHubMetrics.subPillAroAlfa),
                            lineWidth: 1)
                        .padding(1))
                    .overlay(
                        shape.strokeBorder(
                            tono.base.opacity(EntrenarHubMetrics.subPillCantoAlfa),
                            lineWidth: 0.5))
                    .liquidShadow([
                        LiquidShadowLayer(
                            color: tono.base.opacity(EntrenarHubMetrics.subPillShadowAlfa),
                            radius: EntrenarHubMetrics.subPillShadowRadius,
                            y: EntrenarHubMetrics.subPillShadowY)
                    ])
            }
        }
    }

    private var touchShape: some InsettableShape {
        let inset = (expandTouch && size.touchInset > 0) ? -size.touchInset : 0
        return shape.inset(by: inset)
    }
}

#if DEBUG
#Preview("OutlineCapsule") {
    VStack(alignment: .leading, spacing: 16) {
        Text("sm · outline").font(StrandFont.overline).foregroundStyle(LiquidColor.tinta500)
        HStack(spacing: 10) {
            OutlineCapsule(size: .sm, action: {}) {
                HStack(spacing: LiquidSpace.s150) {
                    Text(verbatim: "▲").foregroundStyle(LiquidColor.verdeProfundo)
                    Text("Take the raise").font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta900)
                }
            }
            OutlineCapsule("Start", size: .sm, weight: .bold, action: {})
            OutlineCapsule("Stop", size: .sm, weight: .bold, action: {})
        }
        Text("md · filtro").font(StrandFont.overline).foregroundStyle(LiquidColor.tinta500)
        HStack(spacing: 10) {
            OutlineCapsule("Equipment", size: .md, action: {})
            OutlineCapsule("Barbell", size: .md, filled: true, action: {})
        }
        Text("pressed = EntrenarPressStyle 0.97").font(StrandFont.caption)
            .foregroundStyle(LiquidColor.tinta500)
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("OutlineCapsule · estilos × tallas") {
    let estilos: [(String, OutlineCapsule<Text>.Estilo)] = [
        ("outline", .outline),
        ("papel", .papel),
        ("vidrio", .vidrio),
        ("teñida", .tenida(.verde)),
    ]
    let tallas: [(String, OutlineCapsule<Text>.Size)] = [
        ("sm", .sm), ("md", .md), ("lg", .lg), ("xl", .xl),
    ]
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(estilos, id: \.0) { nombre, estilo in
                Text(nombre).font(StrandFont.overline).foregroundStyle(LiquidColor.tinta500)
                HStack(spacing: 10) {
                    ForEach(tallas, id: \.0) { tallaNombre, size in
                        OutlineCapsule(LocalizedStringKey(stringLiteral: tallaNombre),
                                       size: size, estilo: estilo, action: {})
                    }
                    Text(verbatim: "Z2")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta900)
                        .outlineCapsule(estilo, size: .sm)
                }
            }
        }
        .padding(24)
    }
    .background(LiquidColor.fondoAlto)
}
#endif
