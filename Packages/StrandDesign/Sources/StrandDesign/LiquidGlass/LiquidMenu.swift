import SwiftUI

// MARK: - LiquidMenu — menú «···» en vidrio El Eje (FER-281)
//
// Reemplazo Liquid del PaperMenu (FER-836 / FER-951). Misma geometría y contrato de
// interacción (popover 250pt, filas con icono/título/subtítulo, submenú como segunda
// carta, acción disparada en el next runloop tras cerrar), pintado con tokens Liquid.
//
// Fondo: `.presentationBackground` con material + `LiquidColor.vidrioSuperficie` —
// SIN stroke/clip propio en la tarjeta. El contenedor del popover dibuja la carta Y
// su flecha ancla desde ese fondo; un borde dibujado en el contenido cruza la junta
// de la flecha y se lee como costura rota (misma razón FER-951 que PaperMenu).
// Radio de intención: `LiquidRadius.modulo` (20) — el popover ya recorta; no hace
// falta `clipShape` manual. Elevación: el sistema proyecta la sombra del popover;
// no se fuerza `LiquidElevation.e3` sobre `presentationBackground` (no hay forma de
// aplicar `.shadow` ahí sin volver a cruzar la flecha).

/// Constantes de geometría del menú — fuera de la View para que los tests no toquen MainActor.
enum LiquidMenuMetrics {
    /// Ancho fijo del popover (paridad PaperMenu / handoff 4b).
    static let cardWidth: CGFloat = 250
    /// Estimación por fila sin subtítulo (incluye el divisor implícito en el promedio).
    static let rowEstimate: CGFloat = 49
    /// Extra cuando la fila lleva subtítulo.
    static let subtitleExtra: CGFloat = 14
    /// Fila de regreso del submenú (chevron + título en mayúsculas).
    static let backRowEstimate: CGFloat = 41
    /// Respiro vertical que limpia el redondeo del contenedor (`.padding(.vertical, 6)` × 2).
    static let verticalBreathing: CGFloat = 12
    /// Tope: past that the ScrollView takes over.
    static let heightCap: CGFloat = 420
    /// Hit mínimo de fila (paridad PaperMenu; no hay token de hitTarget más específico).
    static let rowMinHeight: CGFloat = 48
    /// Hit mínimo de la fila de regreso.
    static let backRowMinHeight: CGFloat = 40
    /// Tamaño del SF Symbol leading.
    static let iconPointSize: CGFloat = 15
    /// Tamaño de los chevrons (derecha / regreso).
    static let chevronPointSize: CGFloat = 12
    /// Columna fija del icono — alinea títulos.
    static let iconColumn: CGFloat = LiquidSpace.s600
    /// Divider entre filas.
    static let dividerHeight: CGFloat = LiquidSpace.s025
    /// Stack de filas + divisores — cero aire; el divisor es el único respiro.
    static let stackSpacing: CGFloat = 0

    /// Misma matemática que `PaperMenuCard.estimatedHeight` (FER-836/951).
    static func estimatedHeight(rowCount: Int,
                                       subtitleCount: Int,
                                       hasBackRow: Bool) -> CGFloat {
        let base: CGFloat = hasBackRow ? backRowEstimate : 0
        let content = CGFloat(rowCount) * rowEstimate
            + CGFloat(subtitleCount) * subtitleExtra
        return min(base + content + verticalBreathing, heightCap)
    }
}

/// One row of a `liquidMenu`. A row either fires `action` or opens `children` as a
/// second card — never both.
public struct LiquidMenuItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let systemImage: String?
    public let isDestructive: Bool
    public let action: () -> Void
    public let children: [LiquidMenuItem]

    public init(_ title: String, subtitle: String? = nil, systemImage: String? = nil,
                isDestructive: Bool = false, action: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
        self.children = []
    }

    /// A submenu row — opens its children as a second card.
    public init(_ title: String, subtitle: String? = nil, systemImage: String? = nil,
                children: [LiquidMenuItem]) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isDestructive = false
        self.action = {}
        self.children = children
    }
}

#if !os(watchOS)

public extension View {
    /// Anchors a Liquid Glass «···» menu to this view — the El Eje replacement for
    /// `paperMenu` (FER-281). Screens still on Paper keep calling `.paperMenu`.
    @available(iOS 16.4, macOS 13.3, *)
    func liquidMenu(isPresented: Binding<Bool>, items: [LiquidMenuItem]) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            LiquidMenuCard(items: items, isPresented: isPresented)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The menu card — exposed for previews/tests; screens use `.liquidMenu`.
@available(iOS 16.4, macOS 13.3, *)
struct LiquidMenuCard: View {
    let items: [LiquidMenuItem]
    @Binding var isPresented: Bool

    /// Submenu currently shown as the second card, if any.
    @State private var pushed: LiquidMenuItem?

    public init(items: [LiquidMenuItem], isPresented: Binding<Bool>) {
        self.items = items
        self._isPresented = isPresented
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: LiquidMenuMetrics.stackSpacing) {
                if let pushed {
                    row(back: pushed.title)
                    Rectangle().fill(LiquidColor.tinta10)
                        .frame(height: LiquidMenuMetrics.dividerHeight)
                    list(pushed.children)
                } else {
                    list(items)
                }
            }
            // Clears the popover container's system corner curve so the first/last row's
            // text never rides into the rounding (FER-951 feedback).
            .padding(.vertical, LiquidSpace.s150)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: LiquidMenuMetrics.cardWidth, height: estimatedHeight)
        // Chromeless card: background lives on presentationBackground only — no stroke/
        // clip here (FER-951; see file header). System popover supplies elevation.
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(LiquidColor.vidrioSuperficie)
            }
        }
        .animation(LiquidMotion.glassOut(LiquidMotion.quick), value: pushed?.id)
    }

    /// A popover must know its size up front, so the card estimates from its rows and
    /// caps at `LiquidMenuMetrics.heightCap` — past that the ScrollView takes over.
    private var estimatedHeight: CGFloat {
        let rows = pushed.map { $0.children } ?? items
        return LiquidMenuMetrics.estimatedHeight(
            rowCount: rows.count,
            subtitleCount: rows.filter { $0.subtitle != nil }.count,
            hasBackRow: pushed != nil)
    }

    private func list(_ items: [LiquidMenuItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Rectangle().fill(LiquidColor.tinta10)
                    .frame(height: LiquidMenuMetrics.dividerHeight)
            }
            Button {
                if item.children.isEmpty {
                    isPresented = false
                    // Next runloop tick, so an action that presents a sheet doesn't race
                    // the popover's teardown.
                    DispatchQueue.main.async { item.action() }
                } else {
                    pushed = item
                }
            } label: {
                // Icon LEADS the row — fixed column so titles align; trailing edge stays
                // clean (only a chevron when the row pushes a submenu).
                HStack(spacing: LiquidSpace.s300) {
                    if let symbol = item.systemImage {
                        Image(systemName: symbol)
                            .font(.system(size: LiquidMenuMetrics.iconPointSize, weight: .medium))
                            .foregroundStyle(item.isDestructive
                                             ? LiquidColor.negativo
                                             : LiquidColor.tinta700)
                            .frame(width: LiquidMenuMetrics.iconColumn, alignment: .center)
                    }
                    VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                        Text(item.title)
                            .font(LiquidType.tituloGemela)
                            .foregroundStyle(item.isDestructive
                                             ? LiquidColor.negativo
                                             : LiquidColor.tinta900)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(LiquidType.captionLectura)
                                .foregroundStyle(LiquidColor.tinta500)
                        }
                    }
                    Spacer(minLength: 0)
                    if !item.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: LiquidMenuMetrics.chevronPointSize, weight: .medium))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .padding(.horizontal, LiquidSpace.s400)
                .frame(minHeight: LiquidMenuMetrics.rowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidMenuRowStyle())
        }
    }

    /// The submenu's header row: taps back to the first card.
    private func row(back title: String) -> some View {
        Button {
            pushed = nil
        } label: {
            HStack(spacing: LiquidSpace.s200) {
                Image(systemName: "chevron.left")
                    .font(.system(size: LiquidMenuMetrics.chevronPointSize, weight: .medium))
                    .foregroundStyle(LiquidColor.tinta500)
                Text(title)
                    .font(LiquidType.kicker)
                    .tracking(LiquidType.kickerTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LiquidSpace.handoff14)
            .frame(minHeight: LiquidMenuMetrics.backRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(LiquidMenuRowStyle())
    }
}

private struct LiquidMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? LiquidColor.tinta7 : .clear)
    }
}

// MARK: - Previews

#Preview("LiquidMenu · simple") {
    if #available(iOS 16.4, macOS 13.3, *) {
        LiquidMenuCard(
            items: [
                .init("Agregar calentamiento", systemImage: "flame"),
                .init("Superserie con el siguiente", systemImage: "link"),
                .init("Sustituir ejercicio", systemImage: "arrow.left.arrow.right"),
                .init("Duplicar", systemImage: "plus.square.on.square")
            ],
            isPresented: .constant(true)
        )
        .padding(LiquidSpace.s1400)
        .background(Color.white)
    }
}

#Preview("LiquidMenu · subtítulo + destructiva") {
    if #available(iOS 16.4, macOS 13.3, *) {
        LiquidMenuCard(
            items: [
                .init("Agregar calentamiento", systemImage: "flame"),
                .init("Superserie con el siguiente", systemImage: "link"),
                .init("Sustituir ejercicio", systemImage: "arrow.left.arrow.right"),
                .init("Progresión", subtitle: "+2,5 kg cada 2 ✓",
                      systemImage: "chart.line.uptrend.xyaxis"),
                .init("Quitar de la rutina", systemImage: "trash", isDestructive: true)
            ],
            isPresented: .constant(true)
        )
        .padding(LiquidSpace.s1400)
        .background(Color.white)
    }
}

#Preview("LiquidMenu · con submenú") {
    if #available(iOS 16.4, macOS 13.3, *) {
        LiquidMenuCard(
            items: [
                .init("Renombrar", systemImage: "pencil"),
                .init("Mover a carpeta", children: [
                    .init("Empuje y jalón"),
                    .init("Pierna"),
                    .init("Sin carpeta")
                ]),
                .init("Borrar rutina", systemImage: "trash", isDestructive: true)
            ],
            isPresented: .constant(true)
        )
        .padding(LiquidSpace.s1400)
        .background(Color.white)
    }
}

#Preview("LiquidMenu · lista larga") {
    if #available(iOS 16.4, macOS 13.3, *) {
        LiquidMenuCard(
            items: (1...14).map { i in
                .init("Opción \(i)",
                      subtitle: i.isMultiple(of: 3) ? "Detalle \(i)" : nil,
                      systemImage: "circle")
            },
            isPresented: .constant(true)
        )
        .padding(LiquidSpace.s1400)
        .background(Color.white)
    }
}

#endif
