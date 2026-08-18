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

    /// `display/s` — 22/700, tracking −0.5, escala con Dynamic Type. La palabra de
    /// CALIBRANDO del Ecosistema («Conociéndote»): habla más bajito que un veredicto
    /// (30 pt) porque todavía NO es un veredicto — la humildad se ve en el tamaño (FER-10).
    public static let displayS = InstrumentoType.grotesk(22, weight: .bold,
                                                         relativeTo: .title2)
    public static let displaySTracking: CGFloat = -0.5

    /// `órbita` — 8/600, tracking +2.2. SOLO para las etiquetas orbitales dibujadas dentro
    /// del canvas del Ecosistema (REPOSO · SUEÑO · GUARDIÁN): tamaño fijo, exenta de
    /// Dynamic Type como los glifos de `LiquidIcon` — la accesibilidad la lleva el elemento
    /// compuesto del héroe, nunca el canvas (FER-10).
    public static let orbita = InstrumentoType.grotesk(8, weight: .semibold)
    public static let orbitaTracking: CGFloat = 2.2

    // MARK: Valores y títulos

    /// `valor/l` — 22/700 tabular (subido del 20 del handoff, elevación /inject: el
    /// dato manda en el tile). Escala con Dynamic Type (revote /inject): el dato
    /// protagonista no puede escalar menos que su delta.
    public static let valorL = InstrumentoType.groteskNumber(22, relativeTo: .title3)
    /// `valor/m` — 17: cifras SECUNDARIAS de una tira de resumen (Promedio/Rango/Hoy del
    /// tri-stat de Carga), más chicas que `valorL` para no competir con el numeral héroe
    /// (#inject r5, pedido del dueño: «reduce el tamaño de la fuente»).
    public static let valorM = InstrumentoType.groteskNumber(17, relativeTo: .body)
    /// Numeral terciario (referencia/bitácora: VFC, pasos) — P7 del estudio en frío.
    public static let valorS = InstrumentoType.groteskNumber(14, relativeTo: .subheadline)

    /// `valor/tile·l` — 30/700 tabular: el número grande de un módulo de vidrio de Hoy en
    /// atmósfera (FER-118) para las decisoras (Sueño · FC en reposo). Escala con Dynamic Type.
    public static let valorTileL = InstrumentoType.groteskNumber(30, relativeTo: .title)
    /// `valor/tile·m` — 26/700 tabular: el número de los demás módulos (guardián, contexto,
    /// bitácora). El prototipo aprobado tiene DOS tamaños de número, no tres: las terciarias
    /// (VFC, pasos) también van en éste.
    public static let valorTileM = InstrumentoType.groteskNumber(26, relativeTo: .title2)
    /// Tracking de los dos numerales de módulo (mock `.cn { letter-spacing:-1px }`).
    public static let valorTileTracking: CGFloat = -1

    /// `nivel/título` — 18/700, escala. El nombre del nivel destacado en la tarjeta de la
    /// gráfica (mock `.titfila {18px/700}`); más chico que `valorL` (22) para no competir con
    /// el numeral del héroe (52). Auditoría de fidelidad Grok+DeepSeek 2026-08-03.
    public static let nivelTitulo = InstrumentoType.grotesk(18, weight: .bold,
                                                            relativeTo: .title3)

    /// `valor/l · separador` — el mismo `valorL` en peso REGULAR: los dos-puntos del tiempo de
    /// sueño («7:20») se leen como separador tenue, no como dígito. Token (FER-31) en vez de un
    /// `.fontWeight(.regular)` inline sobre `valorL`.
    public static let valorLSeparador = valorL.weight(.regular)

    /// Glifo de `LiquidIcon` sobre SF Symbol: `size × 0.78` (el símbolo respira dentro del cuadro
    /// del icono), semibold, tamaño FIJO como `orbita` — la accesibilidad la lleva el elemento
    /// compuesto, no el glifo. Token (FER-31) en vez de `.font(.system(size:weight:))` inline.
    public static func iconSF(size: CGFloat) -> Font {
        .system(size: size * 0.78, weight: .semibold)
    }

    /// `numeral/hoja` — 52/700 tabular, escala con Dynamic Type. El dato héroe de la
    /// hoja de resumen (épico hoja Liquid, F0): manda sobre todo lo demás de la hoja.
    /// Auditoría de fidelidad (2026-08-03, Grok+DeepSeek convergentes): el mock canónico
    /// pone el numeral en 56 px y con 34 la jerarquía se aplanaba —el dato no mandaba—.
    /// 52 respeta el line-height tenso de Grotesk sin desbordar la hoja en Dynamic Type.
    public static let numeralHoja = InstrumentoType.groteskNumber(52, relativeTo: .largeTitle)
    /// Unidad junto al numeral de hoja — ~20 en el tamaño base, tinta/500. ESCALA con
    /// Dynamic Type: el numeral es `.largeTitle` relativo, así que una unidad fija se
    /// quedaba enana junto a un numeral inflado. `.title3` = 20 pt en `.large` (el mock
    /// pide 19); antes era `.footnote` (13) y contra el numeral de 52 desaparecía.
    public static let numeralHojaUnidad = Font.system(.title3)

    /// `título/hoja` — 17/700, escala con Dynamic Type. El nombre de la métrica en la
    /// cabecera de la hoja de resumen: manda sobre los títulos de sección (pasada UX H6;
    /// con `titulo` empataba con «Últimos 14 días» y además no crecía).
    public static let tituloHoja = InstrumentoType.grotesk(17, weight: .bold,
                                                           relativeTo: .headline)

    /// `título` — 15/700. Títulos de tarjeta.
    public static let titulo = InstrumentoType.grotesk(15, weight: .bold)

    /// `título/fila` — 13/600. Título de ListRow.
    public static let tituloFila = InstrumentoType.grotesk(13, weight: .semibold)

    /// `título/gemela` — 15/600. El rótulo de las celdas gemelas destacadas de la Matriz
    /// (Sueño · Reposo): mismo peso callado que `tituloFila`, un punto más grande para que
    /// el par pese igual y se lea como gemelo (FER-56). Sube el tamaño, no la voz — el
    /// número sigue mandando (jerarquía «Instrumento»).
    public static let tituloGemela = InstrumentoType.grotesk(15, weight: .semibold)

    // MARK: Cuerpo (SF)

    /// `veredicto/hoja` — 30/700, tracking −0.6, escala (relativeTo `.title`). La
    /// palabra-dato de la hoja de la boleta («En rango»): manda sobre todo lo demás de la
    /// hoja (nada más pasa de 17) sin fingir numeral — el dato de esa hoja es una FRASE
    /// (boleta r3, spec /ui «acta de escrutinio»).
    public static let veredictoHoja = InstrumentoType.grotesk(30, weight: .bold,
                                                              relativeTo: .title)
    public static let veredictoHojaTracking: CGFloat = -0.6

    /// Glifo ⓘ de cabecera de hoja — 15 SF (QA F1-D5: fuera del inline).
    public static let infoGlifo = Font.system(size: 15)

    /// Glifo ⓘ COMPACTO — 12 SF: para cuando el ⓘ viaja pegado a un overline de caja alta
    /// (Regularidad); a 15 pesaba lo mismo que las letras del título y se leía como una
    /// letra más (#inject r2, pedido del dueño).
    public static let infoGlifoCompacto = Font.system(size: 12)

    /// Glifo ⓘ DEL TITULAR del héroe — 22 SF medium (dueño 2026-08-15, gate UX+UI): la puerta
    /// al acta deja de ser pastilla y pasa a ser un ⓘ pegado a la palabra del veredicto, en su
    /// tono. Es el peldaño GRANDE de la misma familia (12 «?» de sección → 15 de hoja → 22 en
    /// el titular displayL de 30): anillo ≈0.9 em ≈ la altura de caja del titular; `.medium`
    /// para que se lea como MARCA junto a la palabra, no como una letra más. Fijo como displayL.
    public static let infoGlifoTitular = Font.system(size: 22, weight: .medium)
    /// Su hermano para los titulares demotados (displayS, escala con Dynamic Type): callout.
    public static let infoGlifoTitularS = Font.system(.callout, weight: .medium)

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

    /// Rango de la fila de nivel — 13/semibold, escala (relativo a `.footnote`). Mock
    /// `.lvl .rng {13px/600}`. También lo usan los segmentos del selector de rango
    /// (`.rango {13px/600}`). Auditoría de fidelidad 2026-08-03: antes `captionLectura` (10.5).
    public static let filaRango = Font.system(.footnote, weight: .semibold)
    /// Conteo de la fila de nivel — 12/regular, escala (relativo a `.caption`). Mock
    /// `.lvl .cnt {12px/400}`. Auditoría 2026-08-03: antes `captionLectura` (10.5).
    public static let filaConteo = Font.system(.caption)

    /// `unidad` — SF 400 11, color tinta/500. «ms», «lpm», «min» junto a valores.
    public static let unidad = Font.system(size: 11)
    /// La variante compacta (10.5) que usan los stats de Entrenar.
    public static let unidadCompacta = Font.system(size: 10.5)

    /// `tab` — SF 10; peso 600 si el tab está activo, 400 si no.
    public static func tab(active: Bool) -> Font {
        .system(size: 10, weight: active ? .semibold : .regular)
    }

    // MARK: Chrome chico (Space Grotesk)

    // MARK: - Pantalla de detalle (FER-102)

    /// `franja` — 13/600, tracking +1.6, MAYÚSCULAS. El rótulo de la franja de sección a
    /// sangre de las pantallas de detalle («ANOCHE», «HISTORIAL»). Un escalón MÁS ALTO que
    /// `kicker` por pedido del dueño: a 11.5 la franja se leía como pie de página y no como
    /// la costura que parte la pantalla en secciones. Escala con Dynamic Type (`.footnote`).
    /// El tamaño de la franja, como token: la prueba compara ESTE número contra el del
    /// kicker. Comparar los `Font` no se puede (SwiftUI no expone su tamaño) y comparar los
    /// trackings dejaba pasar una franja encogida a 11.5 con el tracking intacto.
    public static let franjaTamano: CGFloat = 13
    public static let franja = InstrumentoType.grotesk(franjaTamano, weight: .semibold,
                                                        relativeTo: .footnote)
    public static let franjaTracking: CGFloat = 1.6

    /// `numeralCampo` — 56/700 tabular. El numeral del campo teñido de la pantalla de
    /// detalle. Gemelo de `numeralHoja` (52): el campo es más ancho que la hoja y el dueño
    /// lo subió un escalón (2026-08-17). Escala con Dynamic Type (`.largeTitle`).
    /// La unidad del campo: 30 % del numeral. A `numeralHojaUnidad` (title3, 20) pesaba
    /// demasiado junto a un numeral de 56 y el par se leía como dos datos; a 13 desaparecía.
    public static let unidadCampo = InstrumentoType.grotesk(17, weight: .medium,
                                                             relativeTo: .body)

    /// La cláusula del campo — la línea que explica el veredicto. Va en 13 (`.footnote`), no
    /// en `captionLectura` (10.5): es una frase completa, no un pie de foto, y a 10.5 quedaba
    /// dos escalones por debajo del veredicto (17) con nada en medio.
    public static let clausulaCampo = InstrumentoType.grotesk(13, relativeTo: .footnote)

    public static let numeralCampoTamano: CGFloat = 56
    public static let numeralCampo = InstrumentoType.groteskNumber(numeralCampoTamano,
                                                                    relativeTo: .largeTitle)
    /// Interlínea del numeral del campo: 56 pt con line-height 1 deja un hueco muerto
    /// arriba; −3 lo cierra sin recortar descendentes.
    public static let numeralCampoLineSpacing: CGFloat = -3

    /// `kicker` — 11.5/600, tracking +1.5, MAYÚSCULAS. Fecha, cabeceras («MIÉ 22 DE JUL»).
    /// (kicker/label/micro son alias del escalón «rótulo» de la escala chica unificada.)
    public static let kickerTamano: CGFloat = 11.5
    public static let kicker = InstrumentoType.grotesk(kickerTamano, weight: .semibold)
    public static let kickerTracking: CGFloat = 1.5

    // ESCALA CHICA UNIFICADA (revisión de tipos /inject 2026-07-22, pedido del dueño):
    // el handoff traía 7 tamaños casi iguales (9–11.5) que en device leían como
    // inconsistencia. Quedan TRES escalones: rótulos en caja alta 11.5/600 +1.5 (fecha,
    // labels de tiles/orbes/carga), lectura 10.5 (deltas, captions de estado, unidades) y
    // dato menor 15 tabular (ratio de carga). El estado de carga conserva su 700.

    /// `caption` — 10.5/500. Sin consumidor en componentes (los deltas usan
    /// `captionLectura`); se conserva para previews/debug.
    public static let caption = InstrumentoType.grotesk(10.5, weight: .medium)
    /// La etiqueta de eje dentro de una gráfica de la Matriz (los «0.8 · 1.3» de la campana de
    /// Carga): 8/500 tabular, la voz más chica del sistema — solo dentro de un `Canvas`.
    public static let etiquetaEje = InstrumentoType.grotesk(8, weight: .medium)
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

    /// `regla` — 10/600, tracking +2.2, MAYÚSCULAS, tinta/500. La cabecera-kicker de un
    /// módulo de «El Tablero» (FER-28): SOLO el rótulo, sin líneas ni chevrons ni resúmenes.
    /// «Silencio por defecto» — en día bueno no dice nada más. Más apretada y más chica que
    /// `label` porque manda menos que un dato: es el nombre de la casa, no su contenido.
    public static let regla = InstrumentoType.grotesk(10, weight: .semibold,
                                                      relativeTo: .caption2)
    public static let reglaTracking: CGFloat = 2.2

    /// `dato` — 8.5/600, tracking +1.6, MAYÚSCULAS, tinta/500. El rótulo de una COLUMNA de
    /// dato dentro de un módulo de «El Tablero» (FER-28): «SUEÑO», «FC REPOSO», «PASOS». Más
    /// chico que la regla del módulo porque manda aún menos — los dígitos del valor mandan.
    /// Escala con Dynamic Type (relativo a `.caption2`) para que a tallas AX no se quede enano.
    public static let dato = InstrumentoType.grotesk(8.5, weight: .semibold,
                                                     relativeTo: .caption2)
    public static let datoTracking: CGFloat = 1.6

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

    /// Cabecera-kicker de módulo (FER-28): regla 10/600 +2.2 MAYÚSCULAS. El color lo pone
    /// el caller (tinta/500 en día bueno; ámbar de una sola palabra cuando algo sale de rango).
    func liquidRegla() -> some View {
        self.font(LiquidType.regla).tracking(LiquidType.reglaTracking).textCase(.uppercase)
    }

    /// Rótulo de columna de dato (FER-28): dato 8.5/600 +1.6 MAYÚSCULAS, tinta/500.
    func liquidDato() -> some View {
        self.font(LiquidType.dato).tracking(LiquidType.datoTracking).textCase(.uppercase)
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
