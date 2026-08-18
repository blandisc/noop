import SwiftUI

// MARK: - ExerciseCard + RecetaLine (FER-83 · E2)
//
// Las dos formas de nombrar un ejercicio: la cabecera con la que se entrena (sesión y «Rutina») y
// la línea de receta que resume su plan.

/// La cabecera de un ejercicio. La identidad de la familia vive en el MARCO de la miniatura, no en
/// un fondo teñido: el hue no rellena chrome.
public struct ExerciseCard: View {
    private let family: EntrenarFamily?
    private let name: String
    private let meta: Text?
    private let thumb: Image?
    /// Miniatura con su propia vista (p.ej. una que resuelve la imagen de forma async por id) en vez
    /// de un `Image` ya resuelto — FER-89, ver el init `customThumb` abajo.
    private let customThumb: AnyView?
    private let onMenu: (() -> Void)?
    private let onTap: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(family: EntrenarFamily?, name: String, meta: LocalizedStringKey? = nil,
                thumb: Image? = nil, onMenu: (() -> Void)? = nil, onTap: (() -> Void)? = nil) {
        self.family = family; self.name = name; self.meta = meta.map { Text($0) }
        self.thumb = thumb; self.customThumb = nil; self.onMenu = onMenu; self.onTap = onTap
    }

    /// FER-89 (`ChangeExerciseSheet`): un `meta` ya compuesto por quien llama (mezcla catálogo + dato
    /// dinámico, p.ej. «Pecho · PR 82,5 kg» — un `LocalizedStringKey` trataría ese texto como clave de
    /// búsqueda, que es incorrecto) y una miniatura que se resuelve sola (`SessionRunThumb`: carga
    /// async por id, no un `Image` ya en mano). Aditivo — el init de arriba no cambia.
    public init<Thumb: View>(family: EntrenarFamily?, name: String, metaText: Text? = nil,
                             onMenu: (() -> Void)? = nil, onTap: (() -> Void)? = nil,
                             @ViewBuilder customThumb: () -> Thumb) {
        self.family = family; self.name = name; self.meta = metaText
        self.thumb = nil; self.customThumb = AnyView(customThumb())
        self.onMenu = onMenu; self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: CenitMetrics.gap) {
            if let onTap {
                Button(action: onTap) { identity }
                    .buttonStyle(EntrenarPressStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            } else {
                identity.accessibilityElement(children: .combine)
            }
            Spacer(minLength: CenitMetrics.space2)
            if let onMenu {
                Button(action: onMenu) {
                    Image(systemName: "ellipsis")
                        .font(StrandFont.glyph(.lead))
                        .foregroundStyle(theme.inkTertiary)
                        .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityLabel(Text("Exercise options"))
            }
        }
    }

    private var identity: some View {
        HStack(spacing: CenitMetrics.gap) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let meta {
                    meta
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
        if let customThumb {
            // La vista propia (p.ej. `SessionRunThumb`) ya dibuja su placeholder — solo se enmarca
            // con el mismo aro de familia que el resto de las miniaturas, sin repetir su fondo.
            customThumb
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                .clipShape(shape)
                .overlay(shape.strokeBorder(family?.tint(theme) ?? theme.hairlineStrong, lineWidth: 1.5))
                .accessibilityHidden(true)
        } else {
            Group {
                if let thumb {
                    thumb.resizable().scaledToFill()
                } else if let family {
                    RoutineRegionGlyph(family.glyph, tint: family.tint(theme)).padding(6)
                } else {
                    Image(systemName: "dumbbell")
                        .font(StrandFont.glyph(.lead))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
            .background(theme.paper, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(family?.tint(theme) ?? theme.hairlineStrong, lineWidth: 1.5))
            .accessibilityHidden(true)
        }
    }
}

/// La línea de receta de «Rutina»: «3 series · 80 kg × 8». El texto es DATO (grotesk tabular), no
/// prosa, porque son las cifras del plan.
public struct RecetaLine: View {
    private let text: String
    private let detail: LocalizedStringKey?
    private let action: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(_ text: String, detail: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.text = text; self.detail = detail; self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
            Text(verbatim: text)
                .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: CenitMetrics.space2)
            if action != nil {
                StrandIcon.disclosure.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
    }
}

#if DEBUG
#Preview("ExerciseCard · estados") {
    VStack(spacing: 0) {
        ExerciseCard(family: .legs, name: "Back squat", meta: "rest by heart rate · cap 2:30",
                     onMenu: {}, onTap: {})
        Divider().overlay(InstrumentoTheme.base.hairline)
        ExerciseCard(family: .push, name: "Bench press", meta: "3 × 8 · 82.5 kg", onMenu: {})
        Divider().overlay(InstrumentoTheme.base.hairline)
        ExerciseCard(family: .pull, name: "Barbell row", meta: nil)
        Divider().overlay(InstrumentoTheme.base.hairline)
        ExerciseCard(family: nil, name: "Farmer's walk with a very long name that wraps two lines",
                     meta: "4 × 40 m", onMenu: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("RecetaLine · estados") {
    VStack(spacing: 0) {
        RecetaLine("3 sets · 80 kg × 8", detail: "progression on", action: {})
        Divider().overlay(InstrumentoTheme.base.hairline)
        RecetaLine("4 sets · 12 reps")
        Divider().overlay(InstrumentoTheme.base.hairline)
        RecetaLine("5 sets · 100 kg × 5", detail: "warm-up 2 sets · rest 2:30", action: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("Ejercicio y receta · xxxLarge") {
    VStack(spacing: 12) {
        ExerciseCard(family: .legs, name: "Back squat", meta: "rest by heart rate · cap 2:30", onMenu: {})
        RecetaLine("3 sets · 80 kg × 8", detail: "progression on", action: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
