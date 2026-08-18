import XCTest
@testable import StrandDesign

// MARK: - Los dos hilos de puntos (FER-118): la geometría que hace honesta la figura
//
// La costura murió como dibujo, pero sus invariantes siguen vivos en el mapeo
// (`MatrizCosturaMapeoTests`) y aquí se fija cómo los hilos los USAN: dónde cae un punto, dónde
// termina la banda, cuándo hay banda y cómo se distingue lo que el motor marcó fuera.

final class MatrizHilosTests: XCTestCase {
    typealias G = MatrizHilos.Geometria
    private let base = MatrizTokens.hilosBaseTemp        // 28
    private let A = MatrizTokens.hilosAmplitud           // 16

    /// Lo que el motor marcó fuera (≥ 1.02) cae MÁS LEJOS de la base que lo que no marcó
    /// (≤ 0.98), y la diferencia mide más que el grosor de un trazo: el hueco del filo se ve.
    func test_loMarcadoFueraSeVeMasLejosQueLoNoMarcado() {
        let dentro = base - G.y(0.98, base: base)
        let fuera = base - G.y(1.02, base: base)
        XCTAssertGreaterThan(fuera, dentro)
        XCTAssertGreaterThan(fuera - dentro, 2.2, "el hueco del filo tiene que medir más que un trazo")
    }

    /// El marco es inviolable: ninguna noche —ni la más fría ni la más caliente del año— sale del
    /// lienzo de 96 pt, en ninguno de los dos hilos.
    func test_ningunPuntoSaleDelLienzo() {
        for b in [MatrizTokens.hilosBaseTemp, MatrizTokens.hilosBaseResp] {
            for v in [-900.0, -3, -1, -0.5, 0, 0.5, 0.98, 1, 1.02, 3, 500] {
                let y = G.y(v, base: b)
                XCTAssertGreaterThanOrEqual(y, 0, "v=\(v) base=\(b)")
                XCTAssertLessThanOrEqual(y, MatrizTokens.alturaHilos, "v=\(v) base=\(b)")
                XCTAssertLessThanOrEqual(abs(y - b), A, "nunca más lejos que la amplitud")
            }
        }
    }

    /// Caliente/rápido ARRIBA de la base; frío/lento ABAJO y apretado (el centinela nunca marca
    /// una noche fría): −0.5 queda más cerca de la base que +0.5.
    func test_elLadoBajoExistePeroNoGrita() {
        let caliente = G.y(0.5, base: base), frio = G.y(-0.5, base: base)
        XCTAssertLessThan(caliente, base, "caliente arriba")
        XCTAssertGreaterThan(frio, base, "frío abajo")
        XCTAssertLessThan(frio - base, base - caliente, "y apretado")
        XCTAssertGreaterThan(frio - base, 0, "pero existe: no se aplasta contra la base")
        XCTAssertEqual(G.y(0, base: base), base, accuracy: 0.0001)
    }

    /// La banda es el tramo entre |v| = 1 de cada lado CON EL MISMO MAPEO: asimétrica, y sus
    /// bordes son exactamente donde cae una noche al filo — no hay pixel donde un punto «al
    /// filo» quede fuera de la banda ni uno «fuera» quede dentro.
    func test_laBandaTerminaDondeCaeElFilo() {
        let banda = G.banda(base: base)
        XCTAssertEqual(banda.lowerBound, G.y(1, base: base), accuracy: 0.0001)
        XCTAssertEqual(banda.upperBound, G.y(-1, base: base), accuracy: 0.0001)
        XCTAssertLessThan(base - banda.lowerBound, banda.upperBound - base + A,
                          "arriba (el filo) es el lado ancho…")
        XCTAssertGreaterThan(base - banda.lowerBound, (banda.upperBound - base) * 3,
                             "…y abajo el lado apretado")
        XCTAssertTrue(banda.contains(G.y(0.98, base: base)), "0.98 dentro de la banda")
        XCTAssertFalse(banda.contains(G.y(1.02, base: base)), "1.02 fuera de la banda")
        XCTAssertTrue(banda.contains(G.y(-0.9, base: base)))
    }

    /// Sin ninguna noche con valor NO hay base (ni banda ni hilo central); con una sola, sí.
    func test_hayBaseSoloConAlgunaLectura() {
        XCTAssertFalse(G.hayBase([nil, nil, nil]))
        XCTAssertFalse(G.hayBase([]))
        XCTAssertTrue(G.hayBase([nil, 0.4, nil]))
    }

    /// Estilos: dentro (tenue, chico) · fuera (lleno, mayor) · par (ámbar, lleno) · leído (mayor).
    func test_estiloDeLosPuntos() {
        XCTAssertEqual(G.estilo(v: 0.5, parFuera: false, leido: false), .dentro)
        XCTAssertEqual(G.estilo(v: 1.5, parFuera: false, leido: false), .fuera)
        XCTAssertEqual(G.estilo(v: 1.0, parFuera: false, leido: false), .fuera, "el filo cuenta como fuera")
        XCTAssertEqual(G.estilo(v: 0.99, parFuera: false, leido: false), .dentro)
        XCTAssertEqual(G.estilo(v: 1.5, parFuera: true, leido: false), .par)
        XCTAssertEqual(G.estilo(v: 1.5, parFuera: true, leido: true), .leido, "el dedo manda")
        XCTAssertEqual(G.radio(.dentro), MatrizTokens.hilosPuntoDentro)
        XCTAssertEqual(G.radio(.fuera), MatrizTokens.hilosPuntoFuera)
        XCTAssertEqual(G.radio(.par), MatrizTokens.hilosPuntoFuera)
        XCTAssertEqual(G.radio(.leido), MatrizTokens.hilosPuntoLeido)
        XCTAssertEqual(G.alfa(.dentro), MatrizTokens.hilosPuntoDentroAlfa)
        XCTAssertEqual(G.alfa(.fuera), 1); XCTAssertEqual(G.alfa(.par), 1); XCTAssertEqual(G.alfa(.leido), 1)
        XCTAssertLessThan(G.radio(.dentro), G.radio(.fuera))
        XCTAssertLessThan(G.radio(.fuera), G.radio(.leido))
    }

    /// El latido de HOY: fase en [0, 1], y con `quieto` (Reduce Motion / pausa / render) es 0
    /// siempre — anillo fijo, gráfica completa.
    func test_laFaseDelLatidoEsQuietaBajoReduceMotion() {
        for t in stride(from: 0.0, to: 10, by: 0.37) {
            let f = G.fase(t, quieto: false)
            XCTAssertGreaterThanOrEqual(f, 0); XCTAssertLessThanOrEqual(f, 1)
            XCTAssertEqual(G.fase(t, quieto: true), 0)
        }
        XCTAssertNotEqual(G.fase(0.5, quieto: false), G.fase(1.5, quieto: false), "late")
    }

    /// Los dos hilos caben en el alto con su amplitud completa y no se tocan.
    func test_losDosHilosNoSeTocan() {
        let tempAbajo = MatrizTokens.hilosBaseTemp + A * MatrizCostura.fraccionFilo(-900)
        let respArriba = MatrizTokens.hilosBaseResp - A * MatrizCostura.fraccionFilo(900)
        XCTAssertLessThan(tempAbajo, respArriba)
        XCTAssertGreaterThanOrEqual(MatrizTokens.hilosBaseTemp - A, 0)
        XCTAssertLessThanOrEqual(MatrizTokens.hilosBaseResp + A, MatrizTokens.alturaHilos)
    }
}
