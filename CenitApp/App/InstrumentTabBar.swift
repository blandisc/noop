#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Barra de instrumento» — the bottom tab bar (FER-163)
//
// Replaces the native dark `TabView` chrome (a heavy bar, green `.tint` painting
// the icons) with a quiet bar in the app's «Instrumento diurno» language: warm
// `paper` (read from `\.instrumentoTheme`), a single hairline, ink labels. The
// dark legacy variant was retired in FER-430 — every screen is paper now.
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
    /// True when the visible screen speaks «Instrumento diurno» (Hoy): the bar
    /// dresses in warm paper/ink; otherwise it stays in the dark `StrandPalette`.
    let isLight: Bool

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The bar is always warm «Instrumento» paper now (the dark legacy was retired — FER-430).
    // `isLight` is kept only as the appear-animation trigger; it no longer switches palettes.
    private var surface: Color { theme.paper }
    private var rule: Color { theme.hairline }
    private var activeInk: Color { theme.ink }
    private var idleInk: Color { theme.inkTertiary }
    private var nowDotColor: Color { theme.dataRecovery }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items, id: \.tag) { item in tab(item) }
        }
        .padding(.top, 6)
        // FER-475: el dock se sienta MÁS ABAJO. Antes los botones respetaban TODA el área del
        // home-indicator (~34pt de papel vacío bajo las etiquetas); ahora la barra ignora ese inset y
        // deja una holgura fija y cómoda (14pt) sobre el indicador → dock más compacto, sin taparlo.
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        // The surface (and its top hairline) fill the whole bar down to the screen edge.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                surface
                Rectangle().fill(rule).frame(height: 0.5)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: isLight)
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: selection)
    }

    private func tab(_ item: Item) -> some View {
        let active = item.tag == selection
        let ink = active ? activeInk : idleInk
        return Button {
            selection = item.tag
        } label: {
            VStack(spacing: 5) {
                glyph(item.icon, ink: ink).frame(height: 23)
                // `StrandFont.footnote` (11pt) is the app's quiet-label token; the
                // whole app is fixed-size, so the bar matches it and degrades with
                // grace (single line, shrink-to-fit) at large Dynamic Type rather
                // than being the one element that grows out of the row.
                Text(item.label)
                    .font(StrandFont.footnote).fontWeight(active ? .medium : .regular)
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
                .font(.system(size: 21, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
        case .dial:
            DialTabGlyph(size: 23, color: ink)
        case .linkedCircles:
            PatronesGlyph(color: ink, lineWidth: 1.9).frame(width: 22, height: 22)
        case .curveNodes:
            TendenciasGlyph(color: ink, lineWidth: 1.8).frame(width: 23, height: 23)
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
            .animation(StrandMotion.interactive, value: active)
            .onAppear { breathing = animates }
            .onChange(of: active) { _, now in if now { breathing = animates } }
            .accessibilityHidden(true)
    }
}
#endif
