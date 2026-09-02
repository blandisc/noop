#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Barra de instrumento» — the bottom tab bar (FER-163)
//
// Replaces the native dark `TabView` chrome (a heavy bar, green `.tint` painting
// the icons) with a quiet bar in Liquid Glass · El Eje: warm `papelDock` fill
// (dock glass fill token), a single hairline, ink labels. The dark legacy variant
// was retired in FER-430 — every screen is paper now. FER-305 migrates the fill
// from Instrumento paper fill to `LiquidColor.papelDock` (receta `.dock` no
// existe; el dock vivo en RootTabView ya usa `LiquidTabBar` + `.liquidGlass(.lente)`).
//
// The active tab is marked by INK + a now-dot (the green datum), never by a green
// fill — color stays on the datum, not the chrome. The now-dot reuses the
// DiurnalDial's marker and breathes, honoring Reduce Motion.

/// How a tab draws its icon.
enum InstrumentTabIcon {
    /// A thin-stroke SF Symbol (non-fill).
    case system(String)
    /// The 24-hour `DialTabGlyph` (the «Hoy» mark).
    case dial
    /// The two-linked-circles `PatronesGlyph` (the «Patrones» mark).
    case linkedCircles
    /// The curve-with-nodes `TendenciasGlyph` (the «Tendencias» mark).
    case curveNodes
}

/// The custom bottom bar. Mounted via `.safeAreaInset(edge: .bottom)` on the
/// `TabView` (whose native bar is hidden), so it reserves its own space and pins
/// to the bottom across every page.
struct InstrumentTabBar<Tag: Hashable>: View {

    struct Item {
        let tag: Tag
        let label: LocalizedStringKey
        let icon: InstrumentTabIcon
        init(_ tag: Tag, _ label: LocalizedStringKey, _ icon: InstrumentTabIcon) {
            self.tag = tag; self.label = label; self.icon = icon
        }
    }

    let items: [Item]
    @Binding var selection: Tag
    /// True when the visible screen speaks light paper (Hoy): kept only as the
    /// appear-animation trigger; it no longer switches palettes (FER-430).
    let isLight: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Dock fill + hairline + inks — Liquid Glass · El Eje (FER-305). Same height /
    // hit-targets as before; only the token source changed.
    private var surface: Color { LiquidColor.papelDock }
    private var rule: Color { LiquidColor.vidrioBorde }
    private var activeInk: Color { LiquidColor.tinta900 }
    private var idleInk: Color { LiquidColor.tinta500 }
    private var nowDotColor: Color { LiquidColor.verdePrimario }

    var body: some View {
        HStack(alignment: .top, spacing: .zero) {
            ForEach(items, id: \.tag) { item in tab(item) }
        }
        .padding(.top, LiquidSpace.s200)
        // Baja el contenido de la barra ~10pt hacia la zona del home-indicator (FER-490): los iconos/labels
        // se apoyaban arriba y dejaban un hueco vacío grande debajo, así que la barra «se veía muy arriba».
        // El padding negativo reduce la altura medida (`BarHeightKey`) → la reserva por pestaña (`barReservation`)
        // baja lo mismo, de modo que TODO el conjunto (barra + frontera del contenido) se desplaza junto: ni
        // solapes, ni hueco nuevo arriba, sin encimar la línea del home-indicator (~24pt de holgura). 5 pestañas.
        .padding(.bottom, -10)
        .frame(maxWidth: .infinity)
        // The surface (and its top hairline) extend through the home-indicator area;
        // the buttons sit above it in the safe region.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                surface
                Rectangle().fill(rule).frame(height: LiquidSpace.hairline)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .strandAnimation(LiquidMotion.toque, value: isLight)
        .strandAnimation(LiquidMotion.toque, value: selection)
    }

    private func tab(_ item: Item) -> some View {
        let active = item.tag == selection
        let ink = active ? activeInk : idleInk
        return Button {
            selection = item.tag
        } label: {
            VStack(spacing: LiquidSpace.s125) {
                glyph(item.icon, ink: ink).frame(height: 23)
                // Dock rótulo: mismo rol que `LiquidTabBar` (`LiquidType.tab`).
                Text(item.label)
                    .font(LiquidType.tab(active: active))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(ink)
                NowDot(color: nowDotColor, active: active, animates: !reduceMotion)
                    .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func glyph(_ icon: InstrumentTabIcon, ink: Color) -> some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                // `infoGlifoTitular` (22) is the closest Liquid dock-glyph size; no 21/regular token.
                .font(LiquidType.infoGlifoTitular.weight(.regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
        case .dial:
            DialTabGlyph(size: 23, color: ink)
        case .linkedCircles:
            // Default lineWidth is 1.9 — omit the literal (no-spacing-literal).
            PatronesGlyph(color: ink).frame(width: 22, height: 22)
        case .curveNodes:
            // Default lineWidth is 1.8 — omit the literal (no-spacing-literal).
            TendenciasGlyph(color: ink).frame(width: 23, height: 23)
        }
    }
}

/// The selection mark: a small dot under the active label, in the datum hue. It
/// breathes (echoing the DiurnalDial's now-dot) when motion is allowed, and is a
/// static dot otherwise. Decorative — the selected state is announced by the
/// button's `.isSelected` trait.
private struct NowDot: View {
    let color: Color
    let active: Bool
    let animates: Bool
    @State private var breathing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .scaleEffect(active ? (breathing ? 1.15 : 0.9) : 0.2)
            .opacity(active ? 1 : 0)
            .animation(animates && active ? StrandMotion.breathe : nil, value: breathing)
            .animation(LiquidMotion.toque, value: active)
            .onAppear { breathing = animates }
            .onChange(of: active) { _, now in if now { breathing = animates } }
            .accessibilityHidden(true)
    }
}
#endif
