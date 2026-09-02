import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-51 §12 — los valores en hue sobre `papelMatriz` deben leer: los tonos que se usan
/// como TEXTO normal (temp 13 pt) exigen AA 4.5:1; los votantes grandes (20–26 pt) AA-large
/// 3:1. `doradoTemp` nació oscurecido justo para pasar este gate (no bajarlo sin rojo aquí).
final class MatrizContrasteTests: XCTestCase {

    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Texto normal (el valor de temp del guardián va a 13 pt): AA pleno.
    func testDoradoTempPasaAATextoNormalSobrePapelMatriz() {
        XCTAssertGreaterThanOrEqual(contrast(LiquidColor.doradoTemp, LiquidColor.papelMatriz), 4.5)
    }

    /// Los hues de los votantes se usan a 20–26 pt (large text): AA-large.
    func testHuesDeVotantesPasanAALargeSobrePapelMatriz() {
        for (nombre, hue) in [("indigo", LiquidColor.indigo),
                              ("rosa", LiquidColor.rosa),
                              ("verdePrimario", LiquidColor.verdePrimario),
                              ("azul", LiquidColor.azul),
                              ("cian", LiquidColor.cian)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, LiquidColor.papelMatriz), 3.0,
                                        "\(nombre) por debajo de AA-large sobre papelMatriz")
        }
    }

    /// La identidad de temp y el ámbar de ATENCIÓN no pueden confundirse: exige una
    /// separación mínima de luminancia entre `doradoTemp` y `atencion`.
    /// Los cuatro tonos que los sellos reasignaron (ago-2026): siguen pintando el numeral
    /// de su fila, así que tienen que aguantar el mismo piso que el resto de los datos.
    /// `verdeCarga` se acuñó aquí y pasa incluso AA de texto normal. Estrés NO entra: se
    /// queda en `tinta500` por FER-59 (recede porque no vota), y su sello dice la identidad.
    func testHuesReasignadosPorLosSellosPasanAALargeSobrePapelMatriz() {
        for (nombre, hue) in [("verdeCarga · carga", LiquidColor.verdeCarga),
                              ("ambar · esfuerzo", LiquidColor.ambar),
                              ("teal · pasos", LiquidColor.teal)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, LiquidColor.papelMatriz), 3.0,
                                        "\(nombre) no pasa AA-large sobre el papel de la Matriz")
        }
    }

    /// FER-118 · Hoy en atmósfera: los módulos son vidrio blanco al 30 % sobre BLANCO PURO, así
    /// que el fondo efectivo de cada número es `papelTarjeta` (#FFFFFF). Todo hue que pinta un
    /// numeral (30/26 pt → AA-large 3:1) y los dos grises de texto normal (título/sublabel,
    /// 4.5:1) tienen que leer ahí. Es la misma garantía que sobre `papelMatriz`, fijada para el
    /// fondo nuevo: si alguien oscurece el vidrio o aclara un hue, este gate lo dice.
    func testHuesDeModulosPasanSobreElVidrioDeLaAtmosfera() {
        let fondo = LiquidColor.papelTarjeta
        for (nombre, hue) in [("indigo · sueño", LiquidColor.indigo),
                              ("rosa · FC", LiquidColor.rosa),
                              ("doradoTemp · guardián", LiquidColor.doradoTemp),
                              ("azul · resp", LiquidColor.azul),
                              ("verdeCarga · carga", LiquidColor.verdeCarga),
                              ("ambar · esfuerzo", LiquidColor.ambar),
                              ("cian · VFC", LiquidColor.cian),
                              ("teal · pasos", LiquidColor.teal),
                              ("verdePrimario · veredicto", LiquidColor.verdePrimario)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, fondo), 3.0,
                                        "\(nombre) no pasa AA-large sobre el vidrio de la atmósfera")
        }
        for (nombre, tinta) in [("tinta700 · título", LiquidColor.tinta700),
                                ("tinta500 · sublabel", LiquidColor.tinta500)] {
            XCTAssertGreaterThanOrEqual(contrast(tinta, fondo), 4.5,
                                        "\(nombre) no pasa AA texto normal sobre el vidrio de la atmósfera")
        }
        // Y el vidrio de veras es blanco al 30 %: compuesto sobre blanco sigue siendo blanco.
        XCTAssertEqual(LiquidColor.vidrioAtmosfera.rgbaComponents.a, 0.30, accuracy: 0.001)
        XCTAssertEqual(LiquidColor.vidrioCanto.rgbaComponents.a, 0.08, accuracy: 0.001)
    }

    /// El blanco puro es el fondo MÁS favorable, así que aquí se mide también el peor píxel
    /// TEÓRICO: el que cae justo encima de una mota roja a su alfa máximo (`alfaBase +
    /// alfaRango` = 0.31: hash, respiración y densidad a 1 a la vez), con el vidrio al 30 %
    /// encima y SIN contar el blanqueo propio del material (no modelable aquí):
    /// `0.30·blanco + 0.70·(0.31·rojo + 0.69·blanco)` = `0.783·blanco + 0.217·rojo`.
    ///
    /// Medido, ese píxel NO da AA pleno para todos: ámbar 2.85, teal 2.75, verdePrimario 2.86,
    /// `atencion` 2.85 y `tinta500` 3.86. Y no hace falta que lo dé — WCAG G18 mide los píxeles
    /// ADYACENTES a la letra, y una mota (≤ 4.6 pt de diámetro, una cada ~234 pt², a ese alfa
    /// casi nunca) no es el fondo de un numeral de 30 pt: el fondo es blanco (test de arriba).
    /// Este test es el PISO DE REGRESIÓN, con la holgura real y registrada (§13.29 del
    /// requerimiento): dispara si alguien sube el alfa del polvo, oscurece la partícula roja o
    /// aclara un hue más allá de lo que hoy se midió — no afirma AA sobre la mota.
    /// El ámbar del par (`atencion`) entra a la lista: pinta puntos y nudo, y es dato, no ambiente.
    func testHuesDeModulosAguantanElPeorPixelDeLaAtmosfera() {
        let alfaMota = PolvoSimulacion.Fisica.alfaBase + PolvoSimulacion.Fisica.alfaRango
        let alfaVidrio = LiquidColor.vidrioAtmosfera.rgbaComponents.a
        let pesoRojo = (1 - alfaVidrio) * alfaMota
        XCTAssertEqual(pesoRojo, 0.217, accuracy: 0.001, "la física del polvo o el vidrio cambiaron: re-medir")
        let peor = mezcla(LiquidColor.papelTarjeta, LiquidColor.particulaRoja, pesoRojo)
        let pisoNumeral = 2.7, pisoTexto = 3.8   // AA-large 3:1 y AA 4.5:1 sobre blanco; esto es la holgura medida
        for (nombre, hue) in [("indigo · sueño", LiquidColor.indigo),
                              ("rosa · FC", LiquidColor.rosa),
                              ("doradoTemp · guardián", LiquidColor.doradoTemp),
                              ("azul · resp", LiquidColor.azul),
                              ("verdeCarga · carga", LiquidColor.verdeCarga),
                              ("ambar · esfuerzo", LiquidColor.ambar),
                              ("cian · VFC", LiquidColor.cian),
                              ("teal · pasos", LiquidColor.teal),
                              ("verdePrimario · veredicto", LiquidColor.verdePrimario),
                              ("atencion · par del guardián", LiquidColor.atencion)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, peor), pisoNumeral,
                                        "\(nombre) bajó del piso medido sobre el peor píxel de la atmósfera")
        }
        for (nombre, tinta) in [("tinta700 · título", LiquidColor.tinta700),
                                ("tinta500 · sublabel", LiquidColor.tinta500)] {
            XCTAssertGreaterThanOrEqual(contrast(tinta, peor), pisoTexto,
                                        "\(nombre) bajó del piso medido sobre el peor píxel de la atmósfera")
        }
        // Y sobre blanco (el fondo real de los numerales) `atencion` sí da AA-large.
        XCTAssertGreaterThanOrEqual(contrast(LiquidColor.atencion, LiquidColor.papelTarjeta), 3.0)
    }

    /// Mezcla lineal en sRGB (lo que hace el compositor con alfa premultiplicado): `(1−k)·a + k·b`.
    private func mezcla(_ a: Color, _ b: Color, _ k: Double) -> Color {
        let ka = a.rgbaComponents, kb = b.rgbaComponents
        return Color(.sRGB, red: (1 - k) * ka.r + k * kb.r, green: (1 - k) * ka.g + k * kb.g,
                     blue: (1 - k) * ka.b + k * kb.b, opacity: 1)
    }

    /// La identidad de CARGA no puede ser la voz de marca: `verdePrimario` es el CTA y el
    /// veredicto, y además es la zona «bajo» del medidor de estrés — el mismo hex diciendo
    /// dos cosas a tres sellos de distancia.
    func testCargaNoVisteLaVozDeMarca() {
        XCTAssertNotEqual(LiquidColor.verdeCarga, LiquidColor.verdePrimario)
    }

    func testDoradoTempNoEsElAmbarDeAtencion() {
        let dl = abs(luminance(LiquidColor.doradoTemp) - luminance(LiquidColor.atencion))
        XCTAssertGreaterThan(dl, 0.03, "doradoTemp y atencion quedaron demasiado cerca")
    }

    // MARK: - FER-60 · Heatmap de estrés (contexto, NO vota)

    private func mismoColor(_ a: Color, _ b: Color) -> Bool {
        let ka = a.rgbaComponents, kb = b.rgbaComponents
        return abs(ka.r - kb.r) < 0.004 && abs(ka.g - kb.g) < 0.004 && abs(ka.b - kb.b) < 0.004
    }

    /// La rampa de calor son tres pasos DISTINTOS (bajo/medio/alto): el color, no solo la
    /// posición, transmite el nivel — si dos pasos colapsan, el heatmap no dice nada.
    func testColorNivelEsRampaDeTresPasosDistintos() {
        let c0 = MatrizEscalerita.colorNivel(0)
        let c1 = MatrizEscalerita.colorNivel(1)
        let c2 = MatrizEscalerita.colorNivel(2)
        XCTAssertFalse(mismoColor(c0, c1), "bajo y medio colapsaron")
        XCTAssertFalse(mismoColor(c1, c2), "medio y alto colapsaron")
        XCTAssertFalse(mismoColor(c0, c2), "bajo y alto colapsaron")
        // Clampa fuera de dominio (nunca crashea ni inventa un 4.º paso).
        XCTAssertTrue(mismoColor(MatrizEscalerita.colorNivel(-3), c0))
        XCTAssertTrue(mismoColor(MatrizEscalerita.colorNivel(9), c2))
    }

    /// El heatmap NO puede vestir el hue de ALERTA (`atencion`/`ambar` #C4631F, `negativo`)
    /// — ese naranja/rojo SÍ vota (guardián). Estrés es acompañante: token propio (CA-B).
    func testHeatmapDistintoDelHueDeAlerta() {
        for nivel in 0...2 {
            let c = MatrizEscalerita.colorNivel(nivel)
            XCTAssertFalse(mismoColor(c, LiquidColor.atencion), "nivel \(nivel) == atencion")
            XCTAssertFalse(mismoColor(c, LiquidColor.ambar), "nivel \(nivel) == ambar")
            XCTAssertFalse(mismoColor(c, LiquidColor.negativo), "nivel \(nivel) == negativo")
            // Ni verde (ese es el veredicto, no el estrés).
            XCTAssertFalse(mismoColor(c, LiquidColor.verdePrimario), "nivel \(nivel) == verde")
        }
    }

    /// El tope de la rampa (`estresAlto`) es AA pleno como TEXTO sobre `papelMatriz`: si el
    /// numeral o la palabra «Alto» alguna vez lo visten, siguen legibles (CA-B: AA-safe).
    func testEstresAltoPasaAATextoNormalSobrePapelMatriz() {
        XCTAssertGreaterThanOrEqual(contrast(LiquidColor.estresAlto, LiquidColor.papelMatriz), 4.5,
                                    "estresAlto no pasa AA como texto")
    }

    /// El paso medio, como PUNTO (objeto gráfico), pasa el piso 3:1 sobre el papel.
    func testEstresMedioVisibleComoPuntoSobrePapelMatriz() {
        XCTAssertGreaterThanOrEqual(contrast(LiquidColor.estresMedio, LiquidColor.papelMatriz), 3.0,
                                    "estresMedio se lava sobre papelMatriz")
    }
}
