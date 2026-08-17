import SwiftUI

// MARK: - Behavior dumbbell — with / without comparison (FER-292 v2)
//
// A flat «Instrumento» comparison for a behaviour lever: the outcome mean on days WITH vs WITHOUT the
// habit, drawn as two dots on a shared track (positioned by value, so the gap reads at a glance) joined
// by a hairline. The BETTER group (respecting the metric's direction) carries the data hue as a filled
// dot; the other stays a hollow ink ring. Below, the two values with quiet «SIN / CON» labels — the
// better one colored, the other ink. Color only on the datum (the winning mean and its dot).
//
// Tokens-only, theme injected (the Bucle passes it explicitly — it doesn't cross a `.sheet`). Values are
// pre-formatted by the caller (it owns the unit), so this view stays unit-agnostic.

public struct BehaviorDumbbell: View {

    public var meanWith: Double
    public var meanWithout: Double
    /// Pre-formatted display strings (the caller owns units, e.g. "48", "56 lpm", "7.9 h").
    public var withText: String
    public var withoutText: String
    /// Los tres rótulos, DESDE EL APP (FER-112). Nacían escritos aquí, en español, y este
    /// paquete no tiene catálogo: habrían llegado a la pantalla en español pasara lo que
    /// pasara con el idioma del teléfono. El default conserva el texto de siempre.
    public var etiquetaSin: String = "SIN"
    public var etiquetaCon: String = "CON"
    /// Formato del rótulo de VoiceOver, con los dos valores: «Sin el hábito %@, con el hábito %@».
    public var a11yFormato: String = "Sin el hábito %@, con el hábito %@"
    /// True when the WITH-habit mean is the better outcome (already resolved for metric direction).
    public var withIsBetter: Bool
    /// The metric's data hue — the only color, carried by the better mean.
    public var hue: Color
    public var theme: InstrumentoTheme

    public init(meanWith: Double, meanWithout: Double, withText: String, withoutText: String,
                withIsBetter: Bool, hue: Color, theme: InstrumentoTheme,
                etiquetaSin: String = "SIN", etiquetaCon: String = "CON",
                a11yFormato: String = "Sin el hábito %@, con el hábito %@") {
        self.meanWith = meanWith
        self.meanWithout = meanWithout
        self.withText = withText
        self.withoutText = withoutText
        self.withIsBetter = withIsBetter
        self.hue = hue
        self.theme = theme
        self.etiquetaSin = etiquetaSin
        self.etiquetaCon = etiquetaCon
        self.a11yFormato = a11yFormato
    }

    private let dotR: CGFloat = 4.5

    public var body: some View {
        VStack(spacing: 4) {
            track
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                valueLabel(etiquetaSin, withoutText, colored: !withIsBetter, align: .leading)
                Spacer(minLength: 8)
                valueLabel(etiquetaCon, withText, colored: withIsBetter, align: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(format: a11yFormato, withoutText, withText)))
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let y = geo.size.height / 2
            let inset = dotR + 1
            let lo = Swift.min(meanWith, meanWithout)
            let hi = Swift.max(meanWith, meanWithout)
            let span = Swift.max(hi - lo, 0.0001)
            let xWithout = inset + (w - 2 * inset) * CGFloat((meanWithout - lo) / span)
            let xWith = inset + (w - 2 * inset) * CGFloat((meanWith - lo) / span)
            ZStack {
                Capsule().fill(theme.hairline).frame(width: w, height: 1).position(x: w / 2, y: y)
                Path { p in
                    p.move(to: CGPoint(x: xWithout, y: y)); p.addLine(to: CGPoint(x: xWith, y: y))
                }
                .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                dot(better: !withIsBetter).position(x: xWithout, y: y)
                dot(better: withIsBetter).position(x: xWith, y: y)
            }
        }
        .frame(height: 14)
    }

    @ViewBuilder private func dot(better: Bool) -> some View {
        if better {
            Circle().fill(hue).frame(width: dotR * 2, height: dotR * 2)
        } else {
            Circle().fill(theme.paper)
                .overlay(Circle().stroke(theme.hairlineStrong, lineWidth: 2))
                .frame(width: dotR * 2, height: dotR * 2)
        }
    }

    private func valueLabel(_ tag: String, _ text: String, colored: Bool, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 1) {
            Text(tag).font(.system(size: 9.5, weight: .medium)).tracking(0.6)
                .foregroundStyle(theme.inkTertiary)
            Text(text).font(StrandFont.number(11, weight: colored ? .semibold : .regular))
                .foregroundStyle(colored ? hue : theme.inkTertiary)
        }
    }
}

#if DEBUG
#Preview("BehaviorDumbbell") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 26) {
        BehaviorDumbbell(meanWith: 48, meanWithout: 56, withText: "48", withoutText: "56 lpm",
                         withIsBetter: true, hue: t.dataHeart, theme: t)
        BehaviorDumbbell(meanWith: 7.9, meanWithout: 6.8, withText: "7.9 h", withoutText: "6.8 h",
                         withIsBetter: true, hue: t.dataSleep, theme: t)
        BehaviorDumbbell(meanWith: 61, meanWithout: 68, withText: "61", withoutText: "68",
                         withIsBetter: false, hue: t.dataRecovery, theme: t)
    }
    .padding(40)
    .frame(width: 320)
    .background(t.paper)
}
#endif
