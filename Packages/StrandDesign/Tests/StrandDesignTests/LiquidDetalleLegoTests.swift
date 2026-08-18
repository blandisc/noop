import SwiftUI
import Testing
@testable import StrandDesign

// Los legos de la pantalla de detalle (FER-102). Lo que se fija aquí es lo que un cambio
// futuro NO puede romper en silencio: que el calado del campo pase WCAG AA **sobre toda la
// familia de tonos** (no solo sobre el índigo de Sueño, que es el único que pasa sin ayuda),
// el vocabulario del dato ausente, y que la franja sea un velo plano y no un encabezado.
//
// La matemática de contraste NO se re-implementa aquí: se llama a `LiquidColor.contraste`, la
// misma que usa `tonoCampo` para decidir cuánto oscurecer. Y los colores se resuelven de los
// TOKENS con `rgbaComponents`, no de hex copiados a mano — si alguien cambia `papelAlto` o un
// tono de la familia, estas pruebas se enteran.

@Suite("Liquid · legos de la pantalla de detalle")
struct LiquidDetalleLegoTests {

    /// La familia de tonos que puede teñir un campo, resuelta de los tokens vivos.
    /// `verdePrimario` entra porque el campo de Recuperación se tiñe por banda.
    private static let familia: [(String, Color)] = [
        ("indigo", LiquidColor.indigo),
        ("azul", LiquidColor.azul),
        ("cian", LiquidColor.cian),
        ("rosa", LiquidColor.rosa),
        ("atencion", LiquidColor.atencion),
        ("verdePrimario", LiquidColor.verdePrimario),
    ]

    private static func rgb(_ c: Color) -> (r: Double, g: Double, b: Double) {
        let k = c.rgbaComponents
        return (r: k.r, g: k.g, b: k.b)
    }

    // MARK: - Contraste del campo teñido

    @Test("El rótulo pasa AA sobre el campo de CADA tono de la familia")
    func rotuloPasaAAEnTodaLaFamilia() {
        for (nombre, tono) in Self.familia {
            let campo = Self.rgb(LiquidColor.tonoCampo(tono))
            let r = LiquidColor.contraste(calado: LiquidColor.papelAltoRGB,
                                          alfa: LiquidCampo.alfaRotulo, sobre: campo)
            #expect(r >= 4.5, "\(nombre): el rótulo del campo da \(r), bajo el mínimo AA de 4.5")
        }
    }

    @Test("El numeral calado pasa AA sobre el campo de cada tono")
    func numeralPasaAAEnTodaLaFamilia() {
        for (nombre, tono) in Self.familia {
            let campo = Self.rgb(LiquidColor.tonoCampo(tono))
            let r = LiquidColor.contraste(calado: LiquidColor.papelAltoRGB,
                                          alfa: 1.0, sobre: campo)
            #expect(r >= 4.5, "\(nombre): el numeral da \(r)")
        }
    }

    @Test("Sin oscurecer, la MAYORÍA de la familia NO pasaba — el arreglo hace algo")
    func elTonoCrudoFallaba() {
        // Si esto pasara, `tonoCampo` sería decorativo y la prueba de arriba no probaría nada.
        let fallan = Self.familia.filter { _, tono in
            LiquidColor.contraste(calado: LiquidColor.papelAltoRGB,
                                  alfa: LiquidCampo.alfaRotulo,
                                  sobre: Self.rgb(tono)) < 4.5
        }
        #expect(fallan.count >= 4,
                "sobre el tono crudo solo el índigo debería pasar; fallaron \(fallan.count)")
    }

    @Test("El índigo de Sueño NO se oscurece: el campo aprobado queda intacto")
    func indigoIntacto() {
        // El dueño aprobó el campo de Sueño tal cual. `tonoCampo` solo paga lo necesario, y
        // el índigo no necesita nada — si un día se oscurece, la pantalla cambió sin permiso.
        let a = Self.rgb(LiquidColor.indigo)
        let b = Self.rgb(LiquidColor.tonoCampo(LiquidColor.indigo))
        #expect(abs(a.r - b.r) < 0.005 && abs(a.g - b.g) < 0.005 && abs(a.b - b.b) < 0.005,
                "el índigo del campo se movió: \(a) → \(b)")
    }

    @Test("Un tono oscuro nunca se aclara")
    func nuncaAclara() {
        for (nombre, tono) in Self.familia {
            let a = Self.rgb(tono), b = Self.rgb(LiquidColor.tonoCampo(tono))
            #expect(b.r <= a.r + 0.001 && b.g <= a.g + 0.001 && b.b <= a.b + 0.001,
                    "\(nombre) se aclaró")
        }
    }

    // MARK: - El numeral no miente

    @Test("Un dato calibrando se marca ausente y lleva su motivo a VoiceOver")
    func datoCalibrando() {
        let d = LiquidCampoMetrica<EmptyView>.Dato.calibrando(
            rotulo: "Regularidad", motivo: "aún sin base, faltan 3 noches")
        #expect(d.ausente, "sin esto el «··» se pinta igual que una medición real")
        #expect(d.valor == "··")
        #expect(d.a11y == "aún sin base, faltan 3 noches")
    }

    @Test("Un dato medido NO se marca ausente")
    func datoMedido() {
        let d = LiquidCampoMetrica<EmptyView>.Dato(valor: "7:12", unidad: "h",
                                                   rotulo: "Dormido", a11y: "7 horas 12 minutos")
        #expect(!d.ausente)
        #expect(d.a11y == "7 horas 12 minutos", "«7:12» se dicta como hora del reloj")
    }

    // MARK: - Franja de sección

    @Test("El velo de la franja es del tono y es plano al 4 %")
    func velo() {
        // 4 % es el mismo alfa de LiquidVeil. Más alto vuelve la franja una barra de cabecera
        // teñida; la franja es una costura.
        #expect(LiquidColor.franjaVelo(LiquidColor.indigo) == LiquidColor.indigo.opacity(0.04))
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

    // MARK: - Tokens

    @Test("La franja es un escalón MÁS ALTA que el kicker, en TAMAÑO")
    func franjaSobreKicker() {
        // La versión anterior comparaba el tracking (1.6 > 1.5) y se llamaba «más alta»: si
        // alguien bajaba la franja a 11.5 dejando el tracking, seguía verde. Se compara el
        // tamaño renderizado, que es la invariante que el dueño pidió (2026-08-17).
        #expect(LiquidType.franjaTamano > LiquidType.kickerTamano,
                "franja \(LiquidType.franjaTamano) no es mayor que kicker \(LiquidType.kickerTamano)")
        #expect(LiquidType.franjaTamano >= 13,
                "el dueño la subió a 13; a 11.5 se leía como pie de página")
    }

    @Test("El capilar distingue sus dos ejes")
    func capilarHorizontal() {
        #expect(LiquidCapilar.Eje.horizontal != LiquidCapilar.Eje.vertical)
    }
}
