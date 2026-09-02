import XCTest
import SwiftUI
@testable import CenitDesign

/// `LiquidColor.ParticulaRGB` duplica —a propósito— las tintas de partícula en componentes,
/// porque la entrada (FER-41) necesita INTERPOLAR y un `Color` no expone sus números de forma
/// portátil. Duplicar invita a que las dos copias se separen en silencio el día que alguien
/// retoque un hex, así que aquí se amarran: si dejan de coincidir, esto falla.
final class LiquidColorTintaTests: XCTestCase {

    private func componentes(_ c: Color) -> (Double, Double, Double) {
        let r = c.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue))
    }

    private func iguales(_ color: Color, _ rgb: (r: Double, g: Double, b: Double),
                         _ nombre: String, file: StaticString = #filePath, line: UInt = #line) {
        let (r, g, b) = componentes(color)
        XCTAssertEqual(r, rgb.r, accuracy: 0.004, "\(nombre): rojo", file: file, line: line)
        XCTAssertEqual(g, rgb.g, accuracy: 0.004, "\(nombre): verde", file: file, line: line)
        XCTAssertEqual(b, rgb.b, accuracy: 0.004, "\(nombre): azul", file: file, line: line)
    }

    func testLosComponentesCoincidenConSuHex() {
        iguales(LiquidColor.particulaVerde, LiquidColor.ParticulaRGB.verde, "particulaVerde")
        iguales(LiquidColor.particulaRoja, LiquidColor.ParticulaRGB.roja, "particulaRoja")
        iguales(LiquidColor.particulaAmbar, LiquidColor.ParticulaRGB.ambar, "particulaAmbar")
        iguales(LiquidColor.particulaNeutra, LiquidColor.ParticulaRGB.neutra, "particulaNeutra")
    }

    /// Cada clima del ambiente apunta a la tinta de partícula que le toca (la misma que el
    /// héroe le pone a su orbe): si alguien cruza dos, la entrada se teñiría del color de otro
    /// veredicto — la mentira más cara de esta pieza.
    func testCadaClimaApuntaASuTinta() {
        iguales(LiquidColor.particulaVerde, LiquidAmbiente.bien.particulaRGB, "clima bien")
        iguales(LiquidColor.particulaAmbar, LiquidAmbiente.atencion.particulaRGB, "clima atención")
        iguales(LiquidColor.particulaRoja, LiquidAmbiente.alerta.particulaRGB, "clima alerta")
        iguales(LiquidColor.particulaNeutra, LiquidAmbiente.neutro.particulaRGB, "clima neutro")
    }

    /// El teñido toca sus dos extremos exactos y queda clampeado fuera de rango: en k = 0 el
    /// orbe es EXACTAMENTE el gris de «aún no sé», y en k = 1 exactamente el del veredicto.
    func testElTeñidoTocaSusExtremos() {
        iguales(LiquidColor.particulaTeñida(hacia: LiquidAmbiente.bien.particulaRGB, k: 0),
                LiquidColor.ParticulaRGB.neutra, "k = 0")
        iguales(LiquidColor.particulaTeñida(hacia: LiquidAmbiente.bien.particulaRGB, k: 1),
                LiquidColor.ParticulaRGB.verde, "k = 1")
        iguales(LiquidColor.particulaTeñida(hacia: LiquidAmbiente.bien.particulaRGB, k: -5),
                LiquidColor.ParticulaRGB.neutra, "k negativo queda clampeado")
        iguales(LiquidColor.particulaTeñida(hacia: LiquidAmbiente.bien.particulaRGB, k: 9),
                LiquidColor.ParticulaRGB.verde, "k > 1 queda clampeado")
    }

    /// LA invariante cara de esta pieza: para el MISMO veredicto, el orbe de la entrada tiene
    /// que asentarse EXACTAMENTE del color con el que el héroe de Hoy lo va a pintar un segundo
    /// después. Si se separan, el usuario ve el orbe cambiar de color al desaparecer la
    /// entrada — que es justo el salto que todo el diseño del teñido existe para evitar.
    func testLaEntradaSeTiñeDelMismoColorQueElHeroe() {
        let heroe = LiquidHoyModel.Hero.veredicto(title: "x", highlight: "x",
                                                  highlightTone: .black, subtitle: "x",
                                                  confianza: nil)
        for ambiente in [LiquidAmbiente.bien, .atencion, .alerta, .neutro] {
            let coreo = LiquidEcosistema.coreografia(hero: heroe, ambiente: ambiente,
                                                     guardianEstado: nil, lunaSueno: false,
                                                     calibracion: nil)
            iguales(coreo.tintaClima, ambiente.particulaRGB, "clima \(ambiente)")
        }
    }

    /// A medio camino el resultado cae ENTRE los dos extremos en cada canal — o sea, es una
    /// interpolación de verdad y no un salto disfrazado.
    func testElTeñidoIntermedioQuedaEntreLosExtremos() {
        let (r, g, b) = componentes(
            LiquidColor.particulaTeñida(hacia: LiquidAmbiente.alerta.particulaRGB, k: 0.5))
        let n = LiquidColor.ParticulaRGB.neutra
        let d = LiquidColor.ParticulaRGB.roja
        XCTAssertEqual(r, (n.r + d.r) / 2, accuracy: 0.004)
        XCTAssertEqual(g, (n.g + d.g) / 2, accuracy: 0.004)
        XCTAssertEqual(b, (n.b + d.b) / 2, accuracy: 0.004)
    }
}
