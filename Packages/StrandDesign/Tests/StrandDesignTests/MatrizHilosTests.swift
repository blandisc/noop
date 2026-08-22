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

    /// La banda: arriba `A·filoBanda` (0.58, el borde de adentro del hueco del filo — NO
    /// `fraccionFilo(1)` = 0.75, que dejaría a lo marcado 0.07 pt «fuera», o sea dentro a ojo) y
    /// abajo `y(−1)`, apretado. Todo lo no marcado (≤ 0.98) cae dentro; todo lo marcado (≥ 1.02)
    /// cae fuera con su CENTRO a ≥ 2.5 pt del borde: el hueco del filo se ve.
    func test_laBandaDejaFueraLoQueElMotorMarco() {
        let banda = G.banda(base: base)
        XCTAssertEqual(banda.lowerBound, base - MatrizCostura.filoBanda * A, accuracy: 0.0001)
        XCTAssertEqual(banda.upperBound, G.y(-1, base: base), accuracy: 0.0001)
        XCTAssertGreaterThan(base - banda.lowerBound, (banda.upperBound - base) * 3,
                             "arriba (el filo) es el lado ancho; abajo el apretado")
        for v in [0.0, 0.3, 0.6, 0.9, 0.98] {
            XCTAssertTrue(banda.contains(G.y(v, base: base)), "\(v) dentro de la banda")
        }
        for v in [1.02, 1.1, 1.5, 3, 500] {
            let y = G.y(v, base: base)
            XCTAssertFalse(banda.contains(y), "\(v) fuera de la banda")
            XCTAssertGreaterThan(banda.lowerBound - y, 2.5, "\(v): el centro queda ≥ 2.5 pt fuera del borde")
        }
        XCTAssertTrue(banda.contains(G.y(-0.9, base: base)), "el lado frío vive dentro")
    }

    /// El inset de la gráfica deja sitio al anillo de HOY latiendo (8 pt) — y es el MISMO que
    /// usa el dedo (fuente única P-3).
    func test_elInsetDejaSitioAlAnilloDeHoy() {
        let inset = MatrizHoyFace.chartInset(.costura(noches: []))
        XCTAssertGreaterThanOrEqual(inset, MatrizTokens.hilosAnillo + MatrizTokens.hilosAnilloLatido
                                            + MatrizTokens.hilosAnilloTrazo / 2)
        XCTAssertEqual(inset, MatrizTokens.hilosInset)
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

    /// Q-19 (quisquilloso): con una sola señal legible el hilo se centra en el lienzo; con las
    /// dos, cada una en su base — y la costura/el dedo no cambian (solo mapean en x).
    func test_unSoloHiloSeCentraEnElLienzo() {
        typealias G = MatrizHilos.Geometria
        XCTAssertEqual(G.baseTemp(hayResp: true), MatrizTokens.hilosBaseTemp)
        XCTAssertEqual(G.baseResp(hayTemp: true), MatrizTokens.hilosBaseResp)
        XCTAssertEqual(G.baseTemp(hayResp: false), MatrizTokens.alturaHilos / 2)
        XCTAssertEqual(G.baseResp(hayTemp: false), MatrizTokens.alturaHilos / 2)
        // Centrado, la banda entera sigue dentro del lienzo.
        let banda = G.banda(base: MatrizTokens.alturaHilos / 2)
        XCTAssertGreaterThanOrEqual(banda.lowerBound, 0)
        XCTAssertLessThanOrEqual(banda.upperBound, MatrizTokens.alturaHilos)
    }

    /// FER-128 (explorador Grok): una lectura aislada entre huecos NO desaparece — `tramos` la
    /// devuelve como tramo de un punto (el consumidor la pinta como punto suelto).
    func test_tramos_conservaPuntosAislados() {
        let serie: [Double?] = [nil, 50, nil, 60, 61, nil, 70]
        let tramos = MatrizChartDraw.tramos(serie, count: serie.count, width: 300, dominio: 40...80, height: 40)
        XCTAssertEqual(tramos.count, 3, "50 · [60, 61] · 70")
        XCTAssertEqual(tramos.map(\.count), [1, 2, 1])
    }

    /// FER-128 (explorador r2): con UNA lectura `xAt` la pone al FINAL del ancho útil — como la regla
    /// y las columnas ponen a HOY — no al centro (el guardián y la regla se contradecían).
    func test_xAt_unaSolaLectura_vaAlFinal() {
        XCTAssertEqual(MatrizChartDraw.xAt(index: 0, count: 1, width: 300, inset: 8), 292, accuracy: 0.001)
        XCTAssertEqual(MatrizChartDraw.xAt(index: 0, count: 1, width: 300), 300 - MatrizTokens.chartInset, accuracy: 0.001)
    }
}
