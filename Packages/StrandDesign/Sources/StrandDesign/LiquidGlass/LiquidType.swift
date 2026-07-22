import SwiftUI

// MARK: - Liquid Glass · Tipografía (handoff §4.2)
//
// Dos familias: Space Grotesk (display, valores numéricos, labels, botones — la voz ya
// empaquetada del sistema, vía `InstrumentoType.grotesk`) y SF/system (cuerpo y captions).
// Cada token trae su tracking hermano cuando la spec lo fija; los MAYÚSCULAS se aplican con
// los helpers de `Text` de abajo para que ninguna pantalla re-derive el par fuente+tracking+caja.
//
// Nota de fidelidad: el line-height de CSS (0.96 / 1.0 / 1.55) no se puede fijar exacto en
// SwiftUI; el hero usa el alto natural de Grotesk (≈1.0) y `cuerpo` aproxima 1.55 con
// `cuerpoLineSpacing`. Documentado en docs/design-system/LIQUID-GLASS.md.

public enum LiquidType {

    // MARK: Display (Space Grotesk 700)

    /// `display/xl` — 54/700, tracking −1.9. Hero de veredicto («Dale con todo»).
    public static let displayXL = InstrumentoType.grotesk(54, weight: .bold)
    public static let displayXLTracking: CGFloat = -1.9

    /// `display/l` — 30/700, tracking −0.6. Títulos de sección grandes.
    public static let displayL = InstrumentoType.grotesk(30, weight: .bold)
    public static let displayLTracking: CGFloat = -0.6

    /// `display/m` — 40/700, tracking −1.4. Hero de Entrenar («Empuje»).
    public static let displayM = InstrumentoType.grotesk(40, weight: .bold)
    public static let displayMTracking: CGFloat = -1.4

    // MARK: Valores y títulos

    /// `valor/l` — 20/700 tabular. Valores de métricas (MetricTile).
    public static let valorL = InstrumentoType.groteskNumber(20)

    /// `título` — 15/700. Títulos de tarjeta.
    public static let titulo = InstrumentoType.grotesk(15, weight: .bold)

    /// `título/fila` — 13/600. Título de ListRow.
    public static let tituloFila = InstrumentoType.grotesk(13, weight: .semibold)

    // MARK: Cuerpo (SF)

    /// `cuerpo` — SF 400 12.5. Texto corrido, subtítulos hero.
    public static let cuerpo = Font.system(size: 12.5)
    /// Aproximación del line-height 1.55 de la spec (12.5 × 1.55 ≈ 19.4 pt de línea).
    public static let cuerpoLineSpacing: CGFloat = 4

    /// `unidad` — SF 400 11, color tinta/500. «ms», «lpm», «min» junto a valores.
    public static let unidad = Font.system(size: 11)
    /// La variante compacta (10.5) que usan los stats de Entrenar.
    public static let unidadCompacta = Font.system(size: 10.5)

    /// `tab` — SF 10; peso 600 si el tab está activo, 400 si no.
    public static func tab(active: Bool) -> Font {
        .system(size: 10, weight: active ? .semibold : .regular)
    }

    // MARK: Chrome chico (Space Grotesk)

    /// `kicker` — 11/600, tracking +2, MAYÚSCULAS. Fecha, cabeceras («MIÉ 22 DE JUL»).
    public static let kicker = InstrumentoType.grotesk(11, weight: .semibold)
    public static let kickerTracking: CGFloat = 2

    /// `caption` — 9/500. Deltas («+2 ms vs tu base»).
    public static let caption = InstrumentoType.grotesk(9, weight: .medium)

    /// `label` — 8.5/600, tracking +1.2, MAYÚSCULAS. Labels de tile («FC EN REPOSO»).
    public static let label = InstrumentoType.grotesk(8.5, weight: .semibold)
    public static let labelTracking: CGFloat = 1.2

    /// `micro` — 8/700, tracking +0.8. Labels de orbe («AUTONÓMICO»).
    public static let micro = InstrumentoType.grotesk(8, weight: .bold)
    public static let microTracking: CGFloat = 0.8

    /// `micro/estado` — 7.5/600. Chips de estado («EN TU RANGO»).
    public static let microEstado = InstrumentoType.grotesk(7.5, weight: .semibold)

    /// `botón` — 14/600, tracking +0.2. GlassButton.
    public static let boton = InstrumentoType.grotesk(14, weight: .semibold)
    public static let botonTracking: CGFloat = 0.2

    // MARK: Specs de componente (no forman parte de la escala pública, pero son cerradas)

    /// Label de CargaBar — 9/600, tracking +1.6.
    public static let cargaLabel = InstrumentoType.grotesk(9, weight: .semibold)
    public static let cargaLabelTracking: CGFloat = 1.6

    /// Status de CargaBar — 10/700, tracking +1.
    public static let cargaStatus = InstrumentoType.grotesk(10, weight: .bold)
    public static let cargaStatusTracking: CGFloat = 1
}

// MARK: - Helpers de Text (fuente + tracking + caja en un solo gesto)

public extension Text {
    /// Hero de veredicto: display/xl con su tracking. El color lo pone el caller
    /// (tinta/900 con la palabra clave en verde/primario).
    func liquidDisplayXL() -> Text {
        self.font(LiquidType.displayXL).tracking(LiquidType.displayXLTracking)
    }

    /// Kicker MAYÚSCULAS 11/600 +2.
    func liquidKicker() -> some View {
        self.font(LiquidType.kicker).tracking(LiquidType.kickerTracking).textCase(.uppercase)
    }

    /// Label de tile MAYÚSCULAS 8.5/600 +1.2.
    func liquidLabel() -> some View {
        self.font(LiquidType.label).tracking(LiquidType.labelTracking).textCase(.uppercase)
    }

    /// Label de orbe 8/700 +0.8 (ya llega en MAYÚSCULAS desde el copy).
    func liquidMicro() -> some View {
        self.font(LiquidType.micro).tracking(LiquidType.microTracking).textCase(.uppercase)
    }
}

#if DEBUG
#Preview("Liquid · Tipografía") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            (Text("Dale\ncon ").liquidDisplayXL().foregroundStyle(LiquidColor.tinta900)
             + Text("todo").liquidDisplayXL().foregroundStyle(LiquidColor.verdePrimario))
            Text("Empuje").font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                .foregroundStyle(LiquidColor.tinta900)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("56").font(LiquidType.valorL).foregroundStyle(LiquidColor.cian)
                Text("ms").font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
            }
            Text("MIÉ 22 DE JUL").liquidKicker().foregroundStyle(LiquidColor.tinta700)
            Text("FC EN REPOSO").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Text("AUTONÓMICO").liquidMicro().foregroundStyle(LiquidColor.tinta900)
            Text("EN TU RANGO").font(LiquidType.microEstado).foregroundStyle(LiquidColor.verdeProfundo)
            Text("+2 ms vs tu base").font(LiquidType.caption).foregroundStyle(LiquidColor.positivo)
            Text("Tus 3 señales amanecieron dentro de tu rango.")
                .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(LiquidColor.papelGradient)
}
#endif
