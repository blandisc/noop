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
    /// Compensa el line-height 0.96 de la spec: la caja de línea de Grotesk mide ~1.28 em,
    /// así que las líneas del hero se apilan con spacing 54 × (0.96 − 1.28) ≈ −17
    /// (SwiftUI no permite reducir el line-height directo).
    public static let displayXLLineSpacing: CGFloat = -17

    /// `display/l` — 30/700, tracking −0.6. Títulos de sección grandes.
    public static let displayL = InstrumentoType.grotesk(30, weight: .bold)
    public static let displayLTracking: CGFloat = -0.6

    /// `display/m` — 40/700, tracking −1.4. Hero de Entrenar («Empuje»).
    public static let displayM = InstrumentoType.grotesk(40, weight: .bold)
    public static let displayMTracking: CGFloat = -1.4

    // MARK: Valores y títulos

    /// `valor/l` — 22/700 tabular (subido del 20 del handoff, elevación /inject: el
    /// dato manda en el tile). Escala con Dynamic Type (revote /inject): el dato
    /// protagonista no puede escalar menos que su delta.
    public static let valorL = InstrumentoType.groteskNumber(22, relativeTo: .title3)

    /// `numeral/hoja` — 34/700 tabular, escala con Dynamic Type. El dato héroe de la
    /// hoja de resumen (épico hoja Liquid, F0): manda sobre todo lo demás de la hoja.
    public static let numeralHoja = InstrumentoType.groteskNumber(34, relativeTo: .largeTitle)
    /// Unidad junto al numeral de hoja — 13 en el tamaño base, tinta/500. ESCALA con
    /// Dynamic Type (B4): el numeral es `.largeTitle` relativo, así que una unidad fija
    /// se quedaba enana junto a un numeral inflado. `.footnote` = 13 pt en `.large`,
    /// paridad exacta con el viejo `StrandFont.unit`.
    public static let numeralHojaUnidad = Font.system(.footnote)

    /// `título/hoja` — 17/700, escala con Dynamic Type. El nombre de la métrica en la
    /// cabecera de la hoja de resumen: manda sobre los títulos de sección (pasada UX H6;
    /// con `titulo` empataba con «Últimos 14 días» y además no crecía).
    public static let tituloHoja = InstrumentoType.grotesk(17, weight: .bold,
                                                           relativeTo: .headline)

    /// `título` — 15/700. Títulos de tarjeta.
    public static let titulo = InstrumentoType.grotesk(15, weight: .bold)

    /// `título/fila` — 13/600. Título de ListRow.
    public static let tituloFila = InstrumentoType.grotesk(13, weight: .semibold)

    // MARK: Cuerpo (SF)

    /// Glifo ⓘ de cabecera de hoja — 15 SF (QA F1-D5: fuera del inline).
    public static let infoGlifo = Font.system(size: 15)

    /// `lectura/hoja` — 14 SF, base del texto de lectura de la hoja de resumen (readings,
    /// subtítulo del héroe). Los consumidores lo escalan con @ScaledMetric(relativeTo:
    /// .footnote) — acuñado en el revote adversarial F2 (adiós 14 inline).
    public static let lecturaHojaBase: CGFloat = 14

    /// `cuerpo` — SF 400 12.5. Texto corrido, subtítulos hero.
    public static let cuerpo = Font.system(size: 12.5)
    /// Aproximación del line-height 1.55 de la spec (12.5 × 1.55 ≈ 19.4 pt de línea).
    public static let cuerpoLineSpacing: CGFloat = 4

    /// `cuerpo/lectura` — la variante que ESCALA con Dynamic Type del mismo 12.5.
    ///
    /// `Font.system(size:)` es de tamaño fijo (SF no acepta `relativeTo:`), así que la
    /// etiqueta de las filas de nivel/banda se quedaba clavada mientras su rango y su
    /// conteo —`captionLectura`, relativo a `.caption2`— sí crecían: a tamaños AX la fila
    /// invertía su jerarquía y el nombre del carril acababa más chico que su número.
    /// Se publica la BASE en puntos y el consumidor la escala con
    /// `@ScaledMetric(relativeTo: .footnote)`, el mismo patrón de `lecturaHojaBase`.
    public static let cuerpoLecturaBase: CGFloat = 12.5

    /// `unidad` — SF 400 11, color tinta/500. «ms», «lpm», «min» junto a valores.
    public static let unidad = Font.system(size: 11)
    /// La variante compacta (10.5) que usan los stats de Entrenar.
    public static let unidadCompacta = Font.system(size: 10.5)

    /// `tab` — SF 10; peso 600 si el tab está activo, 400 si no.
    public static func tab(active: Bool) -> Font {
        .system(size: 10, weight: active ? .semibold : .regular)
    }

    // MARK: Chrome chico (Space Grotesk)

    /// `kicker` — 11.5/600, tracking +1.5, MAYÚSCULAS. Fecha, cabeceras («MIÉ 22 DE JUL»).
    /// (kicker/label/micro son alias del escalón «rótulo» de la escala chica unificada.)
    public static let kicker = InstrumentoType.grotesk(11.5, weight: .semibold)
    public static let kickerTracking: CGFloat = 1.5

    // ESCALA CHICA UNIFICADA (revisión de tipos /inject 2026-07-22, pedido del dueño):
    // el handoff traía 7 tamaños casi iguales (9–11.5) que en device leían como
    // inconsistencia. Quedan TRES escalones: rótulos en caja alta 11.5/600 +1.5 (fecha,
    // labels de tiles/orbes/carga), lectura 10.5 (deltas, captions de estado, unidades) y
    // dato menor 15 tabular (ratio de carga). El estado de carga conserva su 700.

    /// `caption` — 10.5/500. Sin consumidor en componentes (los deltas usan
    /// `captionLectura`); se conserva para previews/debug.
    public static let caption = InstrumentoType.grotesk(10.5, weight: .medium)
    /// La variante de LECTURA del caption: escala con Dynamic Type (relativo a .caption2)
    /// — los deltas se leen, no son chrome (FER-1045).
    public static let captionLectura = InstrumentoType.grotesk(10.5, weight: .medium,
                                                               relativeTo: .caption2)

    /// `label` — rótulo 11.5/600 +1.5, MAYÚSCULAS. Labels de tile («FC EN REPOSO»).
    public static let label = InstrumentoType.grotesk(11.5, weight: .semibold,
                                                       relativeTo: .caption)
    public static let labelTracking: CGFloat = 1.5

    /// `micro` — rótulo 11.5/600 +1.5. Labels de orbe («AUTONÓMICO»).
    public static let micro = InstrumentoType.grotesk(11.5, weight: .semibold,
                                                       relativeTo: .caption)
    public static let microTracking: CGFloat = 1.5

    /// `micro/estado` — 9/600. Chips de estado («EN TU RANGO»).
    public static let microEstado = InstrumentoType.grotesk(10.5, weight: .semibold,
                                                            relativeTo: .caption2)

    /// `botón` — 14/600, tracking +0.2. GlassButton.
    public static let boton = InstrumentoType.grotesk(14, weight: .semibold)
    public static let botonTracking: CGFloat = 0.2

    // MARK: Specs de componente (no forman parte de la escala pública, pero son cerradas)

    /// Label de CargaBar — 10.5/600, tracking +1.6 (subido del 9 del handoff, /inject).
    public static let cargaLabel = InstrumentoType.grotesk(11.5, weight: .semibold,
                                                           relativeTo: .caption)
    public static let cargaLabelTracking: CGFloat = 1.5

    /// `dato/menor` — 15/700 tabular, escala con Dynamic Type. El tercer escalón de la
    /// escala chica: el ratio de CargaBar y el micro-valor de los orbes (revote /inject).
    public static let datoMenor = InstrumentoType.groteskNumber(15, relativeTo: .caption)
    /// Alias histórico de `datoMenor` (nombre original, acuñado para CargaBar).
    public static let cargaRatio = datoMenor

    /// Status de CargaBar — 11.5/700, tracking +1 (subido del 10 del handoff, /inject).
    public static let cargaStatus = InstrumentoType.grotesk(11.5, weight: .bold,
                                                            relativeTo: .caption)
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
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("66").font(LiquidType.numeralHoja).foregroundStyle(LiquidColor.cian)
                Text("ms").font(LiquidType.numeralHojaUnidad).foregroundStyle(LiquidColor.tinta500)
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
