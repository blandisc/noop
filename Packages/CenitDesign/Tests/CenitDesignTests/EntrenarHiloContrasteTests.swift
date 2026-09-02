import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-83/85 — el hilo del veredicto perdió su pastilla (el handoff v3 la revierte y el ADN la
/// prohibía: el hue no llena fondos). Sin relleno de por medio, la palabra cae sobre el PAPEL, y es
/// ahí donde hay que medirle el contraste. Este es el tipo de defecto que ningún ojo dictamina con
/// seguridad — se mide.
final class EntrenarHiloContrasteTests: XCTestCase {

    private let theme = InstrumentoTheme.base
    private let tonos: [EntrenarHilo.Tone] = [.clear, .caution, .ease, .hollow]

    func testLaPalabraCumpleAAsobreElPapel() {
        for tone in tonos {
            let ratio = OKLab.contrastRatio(tone.word(theme), theme.paper)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(tone) da \(ratio):1 sobre el papel")
        }
    }

    /// El par «hue de dato / tono de lectura» tiene que ser de verdad un par: si el oscurecido
    /// devolviera el hue tal cual, la prueba de arriba pasaría por accidente el día que el hue ya
    /// cumpliera, y callaría el día que no. Se ancla que el oscurecido HACE algo donde hace falta.
    func testDondeElHueNoAlcanzaElTonoDeLecturaLoOscurece() {
        var oscurecioAlMenosUno = false
        for tone in [EntrenarHilo.Tone.clear, .caution, .ease] {
            let hue = tone.hue(theme)
            guard OKLab.contrastRatio(hue, theme.paper) < 4.5 else { continue }
            oscurecioAlMenosUno = true
            XCTAssertLessThan(OKLab.relativeLuminance(tone.word(theme)),
                              OKLab.relativeLuminance(hue),
                              "\(tone): el tono de lectura tiene que ser más oscuro que su hue")
        }
        XCTAssertTrue(oscurecioAlMenosUno,
                      "ningún hue del veredicto reprueba sobre papel: la prueba dejó de probar algo")
    }

    /// El hue saturado nunca es el color del texto. Es la regla de color 1:1 del ADN, y es la que
    /// se rompió al dibujar la pastilla; que quede clavada aquí y no solo en la revisión de nadie.
    func testElHueSaturadoNuncaPintaLaPalabra() {
        for tone in [EntrenarHilo.Tone.clear, .caution, .ease] {
            let deHue = OKLab.contrastRatio(tone.hue(theme), theme.paper)
            guard deHue < 4.5 else { continue }
            XCTAssertGreaterThan(OKLab.contrastRatio(tone.word(theme), theme.paper), deHue,
                                 "\(tone): la palabra está pintada con el hue saturado")
        }
    }

    /// FER-316 · Watch: con `sobreOLED: true` la palabra, el consejo y el chrome de tinta
    /// pasan AA (≥ 4.5:1) sobre `LiquidOLED.fondo`. Sin pastilla ni theme.watch de por medio.
    func testTextosSobreOLEDCumplenAAsobreNegro() {
        let fondo = LiquidOLED.fondo
        for tone in tonos {
            let palabra = tone.word(sobreOLED: true)
            let ratio = OKLab.contrastRatio(palabra, fondo)
            XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                        "\(tone) palabra da \(ratio):1 sobre LiquidOLED.fondo")
        }
        XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(LiquidOLED.tintaSecundaria, fondo), 4.5,
                                    "consejo (tintaSecundaria) bajo AA sobre OLED")
        XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(LiquidOLED.tintaTerciaria, fondo), 4.5,
                                    "chevron/aro (tintaTerciaria) bajo AA sobre OLED")
        XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(LiquidOLED.tinta, fondo), 4.5,
                                    "hollow palabra (tinta) bajo AA sobre OLED")
    }
}
