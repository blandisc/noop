import SwiftUI

// MARK: - FER-51 · Tokens de la familia Matriz (fuente única)
//
// Toda constante visual de la Matriz vive AQUÍ (regla de tokenización del repo:
// cambios a FAMILIAS, nunca por pantalla). La cara (`MatrizHoyFace`) y las gráficas
// (`MatrizChart`) consumen estos tokens; ningún número mágico inline. Los espaciados
// derivan de la escala `LiquidSpace` — un solo ritmo en toda la superficie.

public enum MatrizTokens {

    // MARK: Ritmo (escala LiquidSpace)

    /// Aire vertical de cada banda (arriba y abajo del contenido).
    public static let bandaV: CGFloat = LiquidSpace.s300        // 12
    /// Margen horizontal del instrumento completo — UN solo dueño (el host);
    /// la cara no vuelve a sangrar (hallazgo DeepSeek #14: doble margen 24+16).
    public static let margenH: CGFloat = LiquidSpace.s600       // 24
    /// Aire entre renglones nombrados (guardián: Temp / Resp).
    public static let renglonV: CGFloat = LiquidSpace.s200      // 8
    /// Aire sello → bloque de título.
    public static let selloTexto: CGFloat = LiquidSpace.s200    // 8
    /// Canal entre columnas de una banda dividida (a cada lado del filo).
    public static let colGap: CGFloat = LiquidSpace.s300        // 12

    // MARK: El sello (orbe vivo junto al título)

    public static let selloRadio: CGFloat = 8

    // MARK: Filos y referencias (tinta estructural)

    /// Filo separador de bandas (1 px).
    public static let filoAlfa: Double = 0.08
    /// Punteada de referencia («tu base», «7 h»).
    public static let refAlfa: Double = 0.28
    /// Bordes punteados de banda ± (guardián).
    public static let bandaRefAlfa: Double = 0.18

    // MARK: El dato (historia serena, HOY presente)

    /// Historia: barras/puntos del pasado.
    public static let histAlfa: Double = 0.32
    /// Trazo de la curva protagonista (FC/VFC).
    public static let lineaAlfa: Double = 0.75
    /// Trazo de la curva serena (guardián — casi plana a propósito).
    public static let lineaSerenaAlfa: Double = 0.55
    /// Trazo de la escalerita (estrés — geometría sin juicio; la curva conectora queda
    /// NEUTRA para que el color viva en los puntos, no en la línea — FER-60).
    public static let lineaEscaleraAlfa: Double = 0.40
    /// Puntos de historia del HEATMAP de estrés (FER-60): más presentes que `histAlfa`
    /// (0.32) porque en el heatmap el COLOR de cada día ES el dato — a 0.32 el ocre/siena
    /// se lavaba. HOY sigue en `hoyAlfa`; el par mantiene «historia serena, HOY presente».
    public static let heatHistAlfa: Double = 0.60
    /// Relleno de gradiente bajo la curva (arranque; muere a ~10 %).
    public static let rellenoAlfa: Double = 0.20
    /// HOY: el único elemento saturado — NUNCA multiplicado por el alfa de sección.
    public static let hoyAlfa: Double = 0.95
    /// Carriles de FC (FER-55): presencia del carril «tu rango», los de fuera, y sus
    /// rieles-susurro. El borde inferior del blend muere a 0 (papel blanco detrás).
    /// La regla al margen (FER-55, diseño final de FC): zona reservada a la derecha
    /// de la curva, el aire de la regla al borde, y sus alfas (capilar de dominio,
    /// tramo de tu rango, relleno bajo la curva que muere a 0 sobre el papel).
    public static let reglaZona: CGFloat = 24
    public static let reglaAire: CGFloat = 8
    public static let reglaCapilarAlfa: Double = 0.14
    public static let reglaTramoAlfa: Double = 0.60
    public static let reglaRellenoAlfa: Double = 0.16

    // MARK: Marcadores (un solo radio de HOY en toda la familia)

    public static let hoyRadio: CGFloat = 3.0
    public static let histRadio: CGFloat = 1.8

    // MARK: Estructura de gráfica (tinta que no es dato)

    /// Relleno sólido de la banda ± (guardián).
    public static let bandaFillAlfa: Double = 0.08
    /// Filo central (cero / base de la señal serena).
    public static let filoCentralAlfa: Double = 0.22
    /// Riel base de la carga.
    public static let rielAlfa: Double = 0.14
    /// Rieles fantasma de la escalerita.
    public static let rielFantasmaAlfa: Double = 0.08
    /// Aro de alerta (trazo).
    public static let aroAlfa: Double = 0.8
    /// Separación del aro de alerta respecto al marcador (y del segundo aro).
    public static let aroGap: CGFloat = 2.4
    public static let aroGap2: CGFloat = 4.6
    /// Inset horizontal estándar de las gráficas de serie.
    public static let chartInset: CGFloat = 4
    /// Aire vertical estándar del trazo dentro de su lienzo (un solo pad para toda la familia).
    public static let chartPadV: CGFloat = 4
    /// Canal superior de columnas: territorio del tag de referencia («7 h»).
    public static let tagCanal: CGFloat = 16
    /// Altura mínima del encabezado de sección (título + línea de sublabel reservada).
    public static let encabezadoMinH: CGFloat = 34
    /// Inset del riel de carga (deja aire al punto HOY + su aro).
    public static let rielInset: CGFloat = 8
    /// Canal entre barras (columnas de sueño Y barras mini — un solo ritmo).
    public static let barraGap: CGFloat = 2
    /// Media altura de la cápsula de zona dulce (carga).
    public static let zonaAlto: CGFloat = 14
    /// Media altura de los ticks que rematan la zona dulce.
    public static let zonaTickAlto: CGFloat = 6

    // MARK: La mini-colina de carga (FER-60)

    /// Aire bajo/sobre la silueta de la colina en la celda (la cima y el aro de HOY
    /// necesitan cancha arriba; el pie deja sitio a la barra-susurro abajo).
    public static let colinaPadAlto: CGFloat = 8
    public static let colinaPadBajo: CGFloat = 5
    /// Barra-susurro de la zona de equilibrio (al pie): alto y alfa — un hint, no un juicio.
    public static let colinaZonaAlto: CGFloat = 3
    public static let colinaZonaAlfa: Double = 0.20
    /// Área tenue bajo la colina (tinta chrome) y su trazo.
    public static let colinaAreaAlfa: Double = 0.05
    public static let colinaLineaAlfa: Double = 0.55
    /// Pad vertical de la escalerita (un pelo más de aire que la familia:
    /// sus puntos viven en 3 rieles fijos y el aro de HOY necesita cancha).
    public static let escaleraPadV: CGFloat = chartPadV + 2

    // MARK: Alturas de gráfica por forma

    public static let alturaLinea: CGFloat = 56
    /// FER-80 · La COSTURA del par (temp + resp espejadas). Más alta que una línea suelta
    /// porque lleva DOS orillas y el espacio entre ellas — pero menos que las dos filas que
    /// sustituye (56 + 56 + su encabezado), así que la sección respira mejor.
    /// 58 y no 74: con varas —y no orillas— el alto sobrante se leía como una gráfica vacía.
    /// Las noches serenas dibujan poco por definición, así que el marco tiene que apretarse a
    /// ellas en vez de dejarlas nadando (revisión del dueño 2026-08-17).
    public static let alturaCostura: CGFloat = 58
    /// El relleno de la boca de la costura: tinta neutra a susurro. No es color de juicio —
    /// el juicio lo pone el ámbar del tramo donde el par votó.
    public static let costuraFillAlfa: Double = 0.10
    /// El tramo donde el par se salió JUNTO: el único ámbar de la costura.
    public static let costuraAlertaAlfa: Double = 0.22
    public static let alturaRenglon: CGFloat = 32
    public static let alturaBarras: CGFloat = 40
    public static let alturaEscalera: CGFloat = alturaBarras   // gemela de Steps (banda Stress|Steps)
    public static let alturaRiel: CGFloat = 40   // gemela de barras: el riel centra en el mismo alto
}
