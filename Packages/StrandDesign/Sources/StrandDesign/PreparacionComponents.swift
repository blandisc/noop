import SwiftUI

// MARK: - Componentes de «Preparación» (FER-1030)
//
// El cúmulo de señales del héroe y el sello de confianza, en la disciplina «Instrumento diurno»:
// el color saturado vive SOLO en la palabra del veredicto (fuera de este archivo). Aquí todo es
// tinta — la posición y la forma cargan el significado, no el color, así que sobrevive monocromo y
// daltonismo. El copy (labels/a11y) lo pone el CALLER; el paquete se queda sin texto.

/// Una «aguja en tu banda»: un tick de tinta sobre un mini-riel con tu banda personal (p25–p75).
/// La POSICIÓN dice dentro/fuera de tu rango; el color por defecto es tinta. En día verde todo es
/// tinta (calma); en ámbar/rojo el caller pasa un `tint` para que el eje fuera salte a la vista.
public struct SenalEnBanda: View {

    public enum State: Sendable, Equatable { case inRange, low, high, noData }

    private let glyph: MetricGlyph
    private let name: Text
    private let a11y: Text
    /// 0…1 sobre el riel; 0.5 = centro de tu banda. Se clampa para no salirse del borde.
    private let position: Double
    private let state: State
    /// Acento del eje fuera de rango (ámbar/rojo). `nil` = todo tinta (día en calma).
    private let tint: Color?
    private let theme: InstrumentoTheme

    public init(glyph: MetricGlyph, name: Text, a11y: Text, position: Double,
                state: State, tint: Color? = nil, theme: InstrumentoTheme) {
        self.glyph = glyph; self.name = name; self.a11y = a11y
        self.position = position; self.state = state; self.tint = tint; self.theme = theme
    }

    private var markColor: Color {
        (state == .low || state == .high) ? (tint ?? theme.ink) : theme.ink
    }

    public var body: some View {
        VStack(spacing: 7) {
            Image(systemName: glyph.sfSymbol)
                .font(.system(size: 16))
                .foregroundStyle(state == .noData ? theme.inkTertiary : theme.ink)
            gauge
            name
                .font(.system(size: 9, weight: .semibold))   // token-exempt: overline micro de dato (9/semibold)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)
        }
        .frame(width: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private var gauge: some View {
        let w: CGFloat = 56, h: CGFloat = 18
        let x = min(max(position, 0.06), 0.94) * w
        return ZStack {
            Capsule().fill(theme.hairlineStrong).frame(width: w - 4, height: 2)          // eje
            RoundedRectangle(cornerRadius: 3, style: .continuous)                        // tu banda p25–p75
                .fill(theme.rangeBand).frame(width: 30, height: 7)
            if state == .noData {
                Capsule().fill(theme.hairlineStrong).frame(width: 6, height: 2)          // sin datos: guion tenue
            } else {
                Capsule().fill(markColor).frame(width: 2, height: 13)                    // tu tick de anoche
                    .position(x: x, y: h / 2)
                if state == .high || state == .low {
                    Image(systemName: state == .high ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 7)).foregroundStyle(markColor)
                        .position(x: x, y: 3)
                }
            }
        }
        .frame(width: w, height: h)
    }
}

/// El sello de confianza como ARCO de tinta: un arco abierto de 240° relleno a `nights`/`goal`
/// noches, con el número al centro. La confianza NUNCA lleva color de alarma (no es bueno/malo):
/// la fracción del arco + el numeral cargan el significado (misma disciplina que `ConfidenceSello`).
public struct SelloConfianzaArco: View {

    private let nights: Int
    private let goal: Int
    private let a11y: Text
    private let theme: InstrumentoTheme

    public init(nights: Int, goal: Int = 21, a11y: Text, theme: InstrumentoTheme) {
        self.nights = nights; self.goal = goal; self.a11y = a11y; self.theme = theme
    }

    public var body: some View {
        let frac = goal > 0 ? min(1, max(0, Double(nights) / Double(goal))) : 0
        ZStack {
            Circle().trim(from: 0, to: 0.667)                                            // pista (240° abierto)
                .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(150))
            Circle().trim(from: 0, to: 0.667 * frac)                                     // relleno (tinta, sin color)
                .stroke(theme.inkSecondary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(150))
            Text(verbatim: "\(nights)")
                .font(InstrumentoType.groteskNumber(14))
                .foregroundStyle(theme.ink)
        }
        .frame(width: 42, height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }
}

#Preview("Señales en banda") {
    let t = InstrumentoTheme.base
    return HStack(spacing: 8) {
        SenalEnBanda(glyph: .hrv, name: Text(verbatim: "HRV"),
                     a11y: Text(verbatim: "Variabilidad cardíaca: en tu rango"),
                     position: 0.54, state: .inRange, theme: t)
        SenalEnBanda(glyph: .restingHR, name: Text(verbatim: "Pulso"),
                     a11y: Text(verbatim: "Pulso en reposo: en tu rango"),
                     position: 0.46, state: .inRange, theme: t)
        SenalEnBanda(glyph: .sleep, name: Text(verbatim: "Sueño"),
                     a11y: Text(verbatim: "Sueño: en tu rango"),
                     position: 0.50, state: .inRange, theme: t)
        SenalEnBanda(glyph: .skinTemp, name: Text(verbatim: "Temp"),
                     a11y: Text(verbatim: "Temperatura: un poco arriba"),
                     position: 0.82, state: .high, tint: t.warning, theme: t)
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
}

#Preview("Arco de confianza") {
    let t = InstrumentoTheme.base
    return HStack(spacing: 20) {
        SelloConfianzaArco(nights: 14, a11y: Text(verbatim: "Confianza: 14 de 21 noches"), theme: t)
        SelloConfianzaArco(nights: 21, a11y: Text(verbatim: "Confianza: 21 de 21 noches"), theme: t)
        SelloConfianzaArco(nights: 5, a11y: Text(verbatim: "Confianza: 5 de 21 noches"), theme: t)
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
}
