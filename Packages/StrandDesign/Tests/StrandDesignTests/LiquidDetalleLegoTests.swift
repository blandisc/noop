import SwiftUI
import Testing
@testable import StrandDesign

// Los legos de la pantalla de detalle (FER-102). Lo que se fija aquí es lo que un cambio
// futuro NO puede romper en silencio: los pisos de contraste que /ui midió contra WCAG AA,
// el vocabulario del dato ausente, y que la franja sea un velo plano y no un encabezado.

@Suite("Liquid · legos de la pantalla de detalle")
struct LiquidDetalleLegoTests {

    // MARK: - Contraste del campo teñido

    /// Luminancia relativa (WCAG 2.1) de un color sRGB.
    private static func luminancia(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func canal(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b)
    }

    /// Razón de contraste entre dos colores sRGB.
    private static func razon(_ a: (r: Double, g: Double, b: Double),
                              _ b: (r: Double, g: Double, b: Double)) -> Double {
        let la = luminancia(a), lb = luminancia(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Compone `frente` al alfa dado sobre `fondo` (sin alfa) — lo que el ojo ve de un
    /// `.opacity()` de SwiftUI sobre una masa opaca.
    private static func sobre(_ frente: (r: Double, g: Double, b: Double), alfa: Double,
                              fondo: (r: Double, g: Double, b: Double))
    -> (r: Double, g: Double, b: Double) {
        (r: frente.r * alfa + fondo.r * (1 - alfa),
         g: frente.g * alfa + fondo.g * (1 - alfa),
         b: frente.b * alfa + fondo.b * (1 - alfa))
    }

    /// `#F8F6EF` — `LiquidColor.papelAlto`, la tinta calada del campo.
    private static let papel = (r: 248.0 / 255, g: 246.0 / 255, b: 239.0 / 255)
    /// `#5D5A9E` — `LiquidColor.indigo`, el tono más oscuro que tiñe un campo hoy.
    private static let indigo = (r: 93.0 / 255, g: 90.0 / 255, b: 158.0 / 255)

    @Test("Los rótulos del campo pasan AA sobre el tono pleno")
    func rotulosPasanAA() {
        // El alfa que /ui fijó tras medir: a .75 daban 3.99:1 y no pasaban.
        let alfa = LiquidCampoMetrica<EmptyView>.alfaRotulo
        #expect(alfa >= 0.84, "el alfa del rótulo no puede bajar sin re-medir el contraste")

        let compuesto = Self.sobre(Self.papel, alfa: alfa, fondo: Self.indigo)
        let r = Self.razon(compuesto, Self.indigo)
        #expect(r >= 4.5, "rótulo del campo: \(r) contra el mínimo AA de 4.5")
    }

    @Test("El alfa viejo de .75 NO pasaba — la prueba puede fallar")
    func elAlfaViejoFallaba() {
        // Sin esto, la prueba de arriba pasaría con cualquier alfa y no probaría nada.
        let compuesto = Self.sobre(Self.papel, alfa: 0.75, fondo: Self.indigo)
        #expect(Self.razon(compuesto, Self.indigo) < 4.5)
    }

    @Test("El numeral calado pleno pasa AA con holgura")
    func numeralPasaAA() {
        #expect(Self.razon(Self.papel, Self.indigo) >= 4.5)
    }

    // MARK: - Franja de sección

    @Test("El velo de la franja es del tono y es plano al 4 %")
    func velo() {
        // 4 % es el mismo alfa de LiquidVeil. Más alto (el 7.5 % del proto) vuelve la franja
        // una barra de cabecera teñida; la franja es una costura.
        let velo = LiquidColor.franjaVelo(LiquidColor.indigo)
        #expect(velo == LiquidColor.indigo.opacity(0.04))
    }

    @Test("La franja hereda el tono de cada métrica, no un gris fijo")
    func veloPorMetrica() {
        #expect(LiquidColor.franjaVelo(LiquidColor.indigo)
                != LiquidColor.franjaVelo(LiquidColor.verdeProfundo))
    }

    // MARK: - Cajita

    @Test("El dato ausente es un guion, nunca un cero")
    func sinDato() {
        #expect(LiquidCajita.sinDato == "—")
    }

    // MARK: - Lectura de selección

    @Test("Sin selección, la lectura conserva su invitación")
    func lecturaVacia() {
        let vacia = LiquidLecturaSeleccion(nil, invitacion: "Toca una noche",
                                           ayuda: "para ver cuánto dormiste")
        #expect(vacia != nil)
    }

    @Test("La lectura distingue dos días distintos")
    func lecturaEquatable() {
        let a = LiquidLecturaSeleccion.Lectura(foco: "Mié 12 ago", palabra: "Suficiente",
                                               valor: "7:12")
        let b = LiquidLecturaSeleccion.Lectura(foco: "Jue 13 ago", palabra: "Suficiente",
                                               valor: "7:12")
        #expect(a != b, "si dos días se comparan iguales, la animación no corre al cambiar")
        #expect(a == LiquidLecturaSeleccion.Lectura(foco: "Mié 12 ago", palabra: "Suficiente",
                                                    valor: "7:12"))
    }

    // MARK: - Tokens

    @Test("La franja es un escalón MÁS ALTA que el kicker")
    func franjaSobreKicker() {
        // El dueño la subió de 11.5 a 13: a 11.5 se leía como pie de página (2026-08-17).
        #expect(LiquidType.franjaTracking > LiquidType.kickerTracking)
    }

    @Test("El capilar horizontal existe y es distinto del vertical")
    func capilarHorizontal() {
        #expect(LiquidCapilar(eje: .horizontal) != nil)
        #expect(LiquidCapilar.Eje.horizontal != LiquidCapilar.Eje.vertical)
    }
}
