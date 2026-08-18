import SwiftUI

// MARK: - FER-51 · Tokens de la familia Matriz (fuente única)
//
// Toda constante visual de la Matriz vive AQUÍ (regla de tokenización del repo:
// cambios a FAMILIAS, nunca por pantalla). La cara (`MatrizHoyFace`) y las gráficas
// (`MatrizChart`) consumen estos tokens; ningún número mágico inline. Los espaciados
// derivan de la escala `LiquidSpace` — un solo ritmo en toda la superficie.

public enum MatrizTokens {

    // MARK: Ritmo (escala LiquidSpace)

    /// Margen horizontal de la FRANJA de estado / aviso (24, alineada con el héroe): lo aplica el
    /// host solo a esa franja. Los módulos de vidrio llevan su propio `margenModulos` (16, = dock)
    /// y lo aplica la cara — cada elemento con UN solo dueño de su margen (hallazgo DeepSeek #14:
    /// el doble margen 24+16 desalineaba; ahora son dos márgenes distintos a propósito, FER-118).
    public static let margenH: CGFloat = LiquidSpace.s600       // 24
    /// Aire entre renglones nombrados (guardián: Temp / Resp).
    public static let renglonV: CGFloat = LiquidSpace.s200      // 8
    /// Aire sello → bloque de título.
    public static let selloTexto: CGFloat = LiquidSpace.s200    // 8

    // MARK: El sello (orbe vivo junto al título)

    public static let selloRadio: CGFloat = 8

    // MARK: Filos y referencias (tinta estructural)

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

    // MARK: Los módulos de vidrio y los estantes (FER-118 · Hoy en atmósfera)
    //
    // La cara dejó de ser tinta con filos: son módulos de vidrio (`.superficieAtmosfera`) en
    // cuadrícula de dos columnas dentro de tres estantes con «?». Medidas del prototipo aprobado,
    // llevadas a los tokens de espacio del sistema.

    /// El margen de los estantes al bisel: el mismo del dock (`LiquidSpace.dockSide`, 16), para
    /// que la columna de vidrio y el dock compartan filo. El héroe y la franja siguen en 24.
    public static let margenModulos: CGFloat = LiquidSpace.s400
    /// Padding interior del módulo (prototipo 18/18/14 → tokens 16/16/12).
    public static let moduloPadH: CGFloat = LiquidSpace.s400
    public static let moduloPadTop: CGFloat = LiquidSpace.s400
    public static let moduloPadBottom: CGFloat = LiquidSpace.s300
    /// El aire entre módulos (columnas y filas) y entre estantes.
    public static let moduloGap: CGFloat = LiquidSpace.s300
    public static let estanteGap: CGFloat = LiquidSpace.s550
    /// La cabecera de un estante (rótulo + «?») deja este aire antes de sus módulos.
    public static let estanteCabeceraPad: CGFloat = LiquidSpace.s250
    /// Pasos (ancho, horizontal): el ancho FIJO de la columna número + subtítulo. Fijo, no
    /// mínimo: si la columna midiera su texto, el subtítulo del scrub («mié 12 · sin lectura»)
    /// la ensancharía a media pasada del dedo, la gráfica se encogería debajo y `ScrubMapeo`
    /// mapearía la misma x a otro índice (revisión final). Cabe «12 345» a 30 pt y el subtítulo
    /// de scrub más largo en una línea.
    public static let moduloTextoAncho: CGFloat = 120
    /// El hint de barrido del guardián: una luz de `hintAncho` cruza la gráfica una vez, en
    /// `hintDuracion` s, `hintEspera` s después de aparecer.
    public static let hintAncho: CGFloat = 60
    public static let hintDuracion: Double = 1.4
    public static let hintEspera: Double = 0.9

    // MARK: Los dos hilos de puntos del guardián (FER-118)
    //
    // Sustituyen a la costura (FER-80): una fila de puntos por señal —temperatura arriba,
    // respiración abajo—, uno por noche, con la banda de tu rango detrás de cada hilo. Misma
    // regla de honestidad que la costura (el mapeo `MatrizCostura.fraccionFilo` sigue vivo);
    // otra figura, elegida por el dueño sobre el prototipo aprobado.

    /// El alto de la gráfica: dos hilos con su banda y aire para el nudo del par.
    public static let alturaHilos: CGFloat = 96
    /// La línea base (tu centro) de cada hilo, en puntos desde arriba.
    public static let hilosBaseTemp: CGFloat = 28
    public static let hilosBaseResp: CGFloat = 68
    /// Cuánto puede alejarse un punto de su base (fracción 1 de `fraccionFilo`).
    public static let hilosAmplitud: CGFloat = 16
    /// La banda de tu rango detrás de cada hilo: el hue de la señal a susurro (el prototipo
    /// aprobó «la banda de rango al 10 %»). Era `costuraFillAlfa`.
    public static let hilosFillAlfa: Double = 0.10
    /// La línea base al centro de la banda: el hue de la señal, tenue.
    public static let hilosBaseAlfa: Double = 0.30
    /// La noche en que el par se salió JUNTO: el único ámbar de la gráfica (columna + nudo).
    /// Era `costuraAlertaAlfa`; la columna se pinta a la mitad, como hacía la costura.
    public static let hilosAlertaAlfa: Double = 0.22
    /// Radios de los puntos: dentro de tu banda (tenue), fuera (lleno y mayor), y el que el
    /// dedo está leyendo.
    public static let hilosPuntoDentro: CGFloat = 3
    public static let hilosPuntoFuera: CGFloat = 4
    public static let hilosPuntoLeido: CGFloat = 5
    public static let hilosPuntoDentroAlfa: Double = 0.45
    /// El anillo de HOY (los dos puntos de anoche): radio, trazo, cuánto crece al latir y la
    /// frecuencia del latido (la misma del sello vivo en calma).
    public static let hilosAnillo: CGFloat = 5.2
    public static let hilosAnilloTrazo: CGFloat = 1.6
    public static let hilosAnilloLatido: CGFloat = 2
    public static let hilosLatidoW: Double = 1.15
    /// El inset horizontal de la gráfica: el anillo de HOY latiendo llega a `hilosAnillo +
    /// hilosAnilloLatido + hilosAnilloTrazo/2` = 8 pt del centro del último punto — el inset de la
    /// familia (5) lo cortaba. Es también el inset del DEDO (fuente única, P-3).
    public static let hilosInset: CGFloat = hilosAnillo + hilosAnilloLatido + hilosAnilloTrazo / 2
    /// El nudo del par (línea punteada entre los dos puntos ámbar) y la columna que lo resalta.
    public static let hilosNudoTrazo: CGFloat = 1.5
    public static let hilosNudoDash: [CGFloat] = [2, 2.5]
    public static let hilosColumnaFactor: CGFloat = 1.2
    /// El anillo de HOY late en alfa de 1 a `1 − hilosLatidoAlfa` (0.3) con la misma fase que
    /// crece `hilosAnilloLatido`.
    public static let hilosLatidoAlfa: Double = 0.7
    /// Sin lectura esa noche: una marca mínima sobre la base, del color de nadie (misma regla
    /// P-2 de la costura: un hueco es un hueco, no un punto en el centro de tu banda).
    public static let hilosHuecoRadio: CGFloat = 1.4
    public static let hilosHuecoAlfa: Double = 0.35
    public static let alturaRenglon: CGFloat = 32
    public static let alturaBarras: CGFloat = 40
    public static let alturaEscalera: CGFloat = alturaBarras   // gemela de Steps (banda Stress|Steps)
    public static let alturaRiel: CGFloat = 40   // gemela de barras: el riel centra en el mismo alto
}
