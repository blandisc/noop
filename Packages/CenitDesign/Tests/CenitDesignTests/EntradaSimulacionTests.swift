import XCTest
@testable import CenitDesign

/// La coreografía de la entrada (FER-41 · rediseño FER-entrada), afirmada sin pantalla.
/// `EntradaSimulacion` es una función pura del tiempo, así que cada tiempo del acto I se prueba
/// aquí: que las partículas NAZCAN dispersas dentro del lienzo, que se reúnan antes del respiro,
/// que el orbe esté quieto durante el respiro, que rebase el cénit sin pasarse del tope, que
/// entre neutro y se tiña al final, y que el especular vaya DESPUÉS del teñido.
final class EntradaSimulacionTests: XCTestCase {
    typealias E = EntradaSimulacion
    typealias G = EntradaSimulacion.Geometria
    typealias Guion = EntradaSimulacion.Guion

    private var total: Double { LiquidEntradaMotion.duracionTotal }
    /// Un instante a partir de la fracción del guion (que es como está escrito el guion).
    private func t(_ fraccion: Double) -> Double { fraccion * total }

    // MARK: El guion cierra

    func testGuionCabeEnLaDuracionTotal() {
        XCTAssertLessThan(Guion.flotarFin, Guion.reunirFin)
        XCTAssertLessThan(Guion.reunirFin, Guion.respiroFin)
        XCTAssertLessThan(Guion.respiroFin, Guion.ascensoFin)
        XCTAssertLessThanOrEqual(Guion.ascensoFin, 1.0)
        XCTAssertLessThanOrEqual(Guion.tinteFin, 1.0)
        XCTAssertLessThanOrEqual(Guion.especularFin, 1.0)
        XCTAssertGreaterThan(Guion.reunirStagger, 0)
        XCTAssertLessThan(Guion.reunirStagger, 1)
    }

    // MARK: La dispersión (el «flotar»)

    /// Cada partícula NACE dentro del lienzo, en la caja de dispersión: el gesto es «flotando
    /// por la pantalla», no «entrando desde fuera». (El rediseño invirtió justo esto.)
    func testCadaParticulaNaceDentroDelLienzo() {
        for i in 0..<G.n {
            let p = E.dispersa(i)
            XCTAssertTrue(p.x >= G.lienzo.width * G.dispersionX.lowerBound - 0.01
                       && p.x <= G.lienzo.width * G.dispersionX.upperBound + 0.01,
                          "partícula \(i) fuera de la caja en x: \(p.x)")
            XCTAssertTrue(p.y >= G.lienzo.height * G.dispersionY.lowerBound - 0.01
                       && p.y <= G.lienzo.height * G.dispersionY.upperBound + 0.01,
                          "partícula \(i) fuera de la caja en y: \(p.y)")
        }
    }

    /// La dispersión es DETERMINISTA (la misma partícula nace siempre en el mismo punto) y
    /// VARIADA (no se apelotonan en un punto: el campo cubre la pantalla).
    func testLaDispersionEsDeterministaYVariada() {
        for i in stride(from: 0, to: G.n, by: 13) {
            XCTAssertEqual(E.dispersa(i), E.dispersa(i))
        }
        let xs = (0..<G.n).map { E.dispersa($0).x }
        let ys = (0..<G.n).map { E.dispersa($0).y }
        // Un campo real cubre buena parte del ancho y del alto de su caja.
        XCTAssertGreaterThan((xs.max()! - xs.min()!), G.lienzo.width * 0.6, "dispersión angosta en x")
        XCTAssertGreaterThan((ys.max()! - ys.min()!), G.lienzo.height * 0.4, "dispersión angosta en y")
    }

    /// La deriva de flotación está ACOTADA por su amplitud: el campo respira, no se dispara.
    func testLaDerivaEstaAcotada() {
        for i in stride(from: 0, to: G.n, by: 7) {
            for paso in 0...20 {
                let d = E.deriva(i, t: Double(paso) * 0.3)
                let mag = (d.width * d.width + d.height * d.height).squareRoot()
                XCTAssertLessThanOrEqual(mag, G.flotaAmplitud * 1.4143 + 0.01)
            }
        }
    }

    // MARK: La reunión

    /// El progreso global de reunión: 0 mientras flotan, 1 al terminar de reunirse, y monótono.
    func testLaReunionCorreDeCeroAUno() {
        XCTAssertEqual(E.cuadro(t: 0).reunion, 0, accuracy: 0.001, "en t=0 el orbe ya está armado")
        XCTAssertEqual(E.cuadro(t: t(Guion.flotarFin)).reunion, 0, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: t(Guion.reunirFin)).reunion, 1, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: t(Guion.respiroFin)).reunion, 1, accuracy: 0.001)
        var previo = -1.0
        for paso in 0...200 {
            let v = E.cuadro(t: total * Double(paso) / 200).reunion
            XCTAssertGreaterThanOrEqual(v, previo - 1e-9, "la reunión retrocedió")
            previo = v
        }
    }

    /// El ESCALONADO por-partícula existe: a media reunión, unas ya están casi en el orbe y
    /// otras apenas salen de su punto — si todas viajaran al unísono, el gesto sería un bloque.
    func testLaReunionEsEscalonadaPorParticula() {
        let g = 0.5
        let progresos = (0..<G.n).map { E.reunionParticula($0, global: g) }
        XCTAssertGreaterThan(progresos.max()! - progresos.min()!, 0.15,
                             "todas se reúnen al unísono: el escalonado se perdió")
        // En los extremos, todas coinciden por construcción.
        for i in stride(from: 0, to: G.n, by: 11) {
            XCTAssertEqual(E.reunionParticula(i, global: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(E.reunionParticula(i, global: 1), 1, accuracy: 1e-9)
        }
    }

    /// El respiro es QUIETUD: entre el fin de la reunión y el arranque del ascenso el orbe no
    /// se mueve. Es el beat que separa «se armó» de «sube».
    func testDuranteElRespiroElOrbeNoSeMueve() {
        let a = E.cuadro(t: t(Guion.reunirFin))
        let b = E.cuadro(t: t((Guion.reunirFin + Guion.respiroFin) / 2))
        let c = E.cuadro(t: t(Guion.respiroFin))
        XCTAssertEqual(a.centro.y, G.reunionY, accuracy: 0.001)
        XCTAssertEqual(b.centro.y, G.reunionY, accuracy: 0.001)
        XCTAssertEqual(c.centro.y, G.reunionY, accuracy: 0.001)
        XCTAssertEqual(c.ascenso, 0, accuracy: 0.001, "el ascenso arrancó durante el respiro")
    }

    // MARK: El ascenso rebasa y asienta

    func testElAscensoAsientaExactamenteEnElCenit() {
        let c = E.cuadro(t: t(Guion.ascensoFin))
        XCTAssertEqual(c.centro.y, G.cenit.y, accuracy: 0.001)
        XCTAssertEqual(c.centro.x, G.cenit.x, accuracy: 0.001)
        XCTAssertEqual(c.ascenso, 1, accuracy: 0.001)
    }

    func testElRebaseExisteYNoSePasaDelTope() {
        var minY = CGFloat.greatestFiniteMagnitude
        for paso in 0...400 {
            let u = Guion.respiroFin + (Guion.ascensoFin - Guion.respiroFin) * Double(paso) / 400
            minY = min(minY, E.cuadro(t: t(u)).centro.y)
        }
        let rebase = G.cenit.y - minY
        XCTAssertGreaterThan(rebase, 1, "no rebasa: el ascenso no se siente como asentamiento")
        XCTAssertEqual(rebase, G.sobrepaso, accuracy: 0.05, "el pico del lóbulo no es el token")
        XCTAssertLessThanOrEqual(G.sobrepaso, 8, "el rebase no puede pasar de 8 pt")
    }

    func testLaCurvaDelAscensoTocaSusTresPuntos() {
        XCTAssertEqual(E.alturaAscenso(0), G.reunionY, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(Guion.cimaAscenso), G.cenit.y - G.sobrepaso, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(1), G.cenit.y, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(-3), G.reunionY, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(7), G.cenit.y, accuracy: 1e-9)
        var previo = CGFloat.greatestFiniteMagnitude
        for paso in 0...200 {
            let y = E.alturaAscenso(Guion.cimaAscenso * Double(paso) / 200)
            XCTAssertLessThanOrEqual(y, previo + 1e-9)
            previo = y
        }
    }

    // MARK: Entra neutro, se tiñe, y el especular va después

    func testEntraNeutroYTermineTeñido() {
        XCTAssertEqual(E.cuadro(t: 0).tinte, 0, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: t(Guion.respiroFin)).tinte, 0, accuracy: 0.001,
                       "el orbe ya venía de color antes de asentarse")
        XCTAssertEqual(E.cuadro(t: total).tinte, 1, accuracy: 0.001)
    }

    func testElEspecularSeEnciendeDespuesDelTeñido() {
        XCTAssertGreaterThan(Guion.especularIni, Guion.tinteIni)
        XCTAssertEqual(E.cuadro(t: t(Guion.tinteIni)).especular, 0, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: total).especular, 1, accuracy: 0.001)
    }

    func testElTeñidoNuncaRetrocede() {
        var previo = -1.0
        for paso in 0...300 {
            let v = E.cuadro(t: total * Double(paso) / 300).tinte
            XCTAssertGreaterThanOrEqual(v, previo - 1e-9, "el teñido retrocedió")
            previo = v
        }
    }

    // MARK: La salida

    func testLaEntradaSeApagaAlTerminarSuDuracion() {
        XCTAssertEqual(E.cuadro(t: total).alfa, 1, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: E.duracion()).alfa, 0, accuracy: 0.001)
        XCTAssertEqual(E.duracion(),
                       LiquidEntradaMotion.duracionTotal + LiquidEntradaMotion.salida,
                       accuracy: 1e-12)
    }

    // MARK: Reducir movimiento

    /// Sin viaje: en CUALQUIER instante el orbe ya está reunido, en el cénit, pleno y teñido.
    func testReducirMovimientoNoTieneViaje() {
        for paso in 0...20 {
            let c = E.cuadro(t: E.duracion(reduce: true) * Double(paso) / 20, reduce: true)
            XCTAssertEqual(c.centro.y, G.cenit.y, accuracy: 0.001)
            XCTAssertEqual(c.reunion, 1, accuracy: 0.001)
            XCTAssertEqual(c.ascenso, 1, accuracy: 0.001)
            XCTAssertEqual(c.tinte, 1, accuracy: 0.001)
            XCTAssertEqual(c.especular, 1, accuracy: 0.001)
            XCTAssertEqual(c.rotacion, 0, accuracy: 0.001)
        }
        XCTAssertEqual(E.cuadro(t: E.duracion(reduce: true), reduce: true).alfa, 0, accuracy: 0.001)
        XCTAssertLessThan(E.duracion(reduce: true), E.duracion())
    }

    // MARK: Pureza y determinismo

    func testElMismoInstanteDaElMismoCuadro() {
        for f in [0.0, 0.17, 0.42, 0.7, 0.93, 1.0] {
            XCTAssertEqual(E.cuadro(t: t(f)), E.cuadro(t: t(f)))
        }
    }

    /// «Función pura del tiempo» vale para CUALQUIER tiempo: un `t` no finito se trata como cero.
    func testCualquierTiempoDaUnCuadroDefinido() {
        for raro in [TimeInterval.nan, .infinity, -.infinity, -1, -1e9, 1e9] {
            let c = E.cuadro(t: raro)
            XCTAssertTrue(c.centro.x.isFinite && c.centro.y.isFinite, "centro no finito con t=\(raro)")
            XCTAssertTrue(c.rotacion.isFinite, "rotación no finita con t=\(raro)")
            XCTAssertTrue(c.reunion.isFinite && c.ascenso.isFinite)
            XCTAssertTrue(c.tinte.isFinite && c.especular.isFinite && c.alfa.isFinite)
        }
        XCTAssertEqual(E.cuadro(t: .nan), E.cuadro(t: 0))
        let antes = E.cuadro(t: -1), cero = E.cuadro(t: 0)
        XCTAssertEqual(antes.centro, cero.centro)
        XCTAssertEqual(antes.reunion, cero.reunion)
        XCTAssertEqual(antes.tinte, cero.tinte)
        XCTAssertEqual(E.cuadro(t: 1e6).alfa, 0, accuracy: 0.001)
    }

    /// Las guardas degeneradas (`rampa` / `lineal` con hitos invertidos o iguales) devuelven un
    /// escalón, no un NaN por dividir entre cero.
    func testLasRampasSoportanHitosDegenerados() {
        XCTAssertEqual(E.rampa(0.4, de: 0.5, a: 0.5), 0)
        XCTAssertEqual(E.rampa(0.6, de: 0.5, a: 0.5), 1)
        XCTAssertEqual(E.rampa(0.9, de: 0.8, a: 0.2), 1)
        XCTAssertEqual(E.lineal(0.4, de: 0.5, a: 0.5), 0)
        XCTAssertEqual(E.lineal(0.6, de: 0.5, a: 0.5), 1)
        XCTAssertEqual(E.lineal(0.3, de: 0.0, a: 1.0), 0.3, accuracy: 1e-12)
    }
}
