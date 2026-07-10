import SwiftUI

// MARK: - PaperMenu — «Instrumento» popover menu (handoff entrenamiento-v4 · 4b, FER-836)
//
// The native SwiftUI `Menu` cannot be themed, so the «···» menus use a real popover
// carrying a paper card: 250pt wide, hairline-divided rows (44+pt), an optional
// state subtitle («+2,5 kg cada 2 ✓»), the destructive row in `critical` at the end,
// and a submenu as a SECOND card that replaces the first.

/// One row of a `paperMenu`. A row either fires `action` or opens `children` as a
/// second card — never both.
public struct PaperMenuItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let systemImage: String?
    public let isDestructive: Bool
    public let action: () -> Void
    public let children: [PaperMenuItem]

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
                children: [PaperMenuItem]) {
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
    /// Anchors an «Instrumento» paper menu (spec 4b) to this view — the styled
    /// replacement for a native `Menu` on a «···» button.
    @available(iOS 16.4, macOS 13.3, *)
    func paperMenu(isPresented: Binding<Bool>, items: [PaperMenuItem]) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            PaperMenuCard(items: items, isPresented: isPresented)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// The menu card — exposed for previews/tests; screens use `.paperMenu`.
@available(iOS 16.4, macOS 13.3, *)
public struct PaperMenuCard: View {
    let items: [PaperMenuItem]
    @Binding var isPresented: Bool

    @Environment(\.instrumentoTheme) private var theme
    /// Submenu currently shown as the second card, if any.
    @State private var pushed: PaperMenuItem?

    public init(items: [PaperMenuItem], isPresented: Binding<Bool>) {
        self.items = items
        self._isPresented = isPresented
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let pushed {
                    row(back: pushed.title)
                    Rectangle().fill(theme.hairline).frame(height: 1)
                    list(pushed.children)
                } else {
                    list(items)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 250, height: estimatedHeight)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: theme.ink.opacity(0.16), radius: 16, y: 10)
        .presentationBackground(theme.surface)
        .animation(StrandMotion.fade, value: pushed?.id)
    }

    /// A popover must know its size up front, so the card estimates from its rows (45pt per row,
    /// +14 when a subtitle rides along) and caps at 420 — past that the ScrollView takes over.
    private var estimatedHeight: CGFloat {
        let rows = pushed.map { $0.children } ?? items
        let base: CGFloat = pushed != nil ? 41 : 0   // the submenu's back header row
        let content = rows.reduce(CGFloat(0)) { $0 + 45 + ($1.subtitle != nil ? 14 : 0) }
        return min(base + content, 420)
    }

    private func list(_ items: [PaperMenuItem]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Rectangle().fill(theme.hairline).frame(height: 1)
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
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundStyle(item.isDestructive ? theme.critical : theme.ink)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let symbol = item.systemImage {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(item.isDestructive ? theme.critical : theme.inkSecondary)
                    } else if !item.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PaperMenuRowStyle(theme: theme))
        }
    }

    /// The submenu's header row: taps back to the first card.
    private func row(back title: String) -> some View {
        Button {
            pushed = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkTertiary)
                Text(title)
                    .font(InstrumentoType.groteskOverline)
                    .tracking(InstrumentoType.groteskOverlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PaperMenuRowStyle(theme: theme))
    }
}

private struct PaperMenuRowStyle: ButtonStyle {
    let theme: InstrumentoTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.paper : .clear)
    }
}

// MARK: - Previews

#Preview("PaperMenu · ejercicio (4b)") {
    if #available(iOS 16.4, macOS 13.3, *) {
        PaperMenuCard(
            items: [
                .init("Agregar calentamiento", systemImage: "flame"),
                .init("Superserie con el siguiente", systemImage: "link"),
                .init("Sustituir ejercicio", systemImage: "arrow.left.arrow.right"),
                .init("Progresión", subtitle: "+2,5 kg cada 2 ✓", systemImage: "chart.line.uptrend.xyaxis"),
                .init("Quitar de la rutina", systemImage: "trash", isDestructive: true)
            ],
            isPresented: .constant(true)
        )
        .padding(40)
        .background(InstrumentoTheme.base.paper)
    }
}

#Preview("PaperMenu · con submenú") {
    if #available(iOS 16.4, macOS 13.3, *) {
        PaperMenuCard(
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
        .padding(40)
        .background(InstrumentoTheme.base.paper)
    }
}

#endif
