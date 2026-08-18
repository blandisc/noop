import XCTest
@testable import StrandDesign

// MARK: - El polvo de la atmósfera (FER-118): la spec que el shader espeja
//
// `PolvoSimulacion.particula` es el contrato compartido entre el `Canvas` de respaldo y
// `vsPolvo`. Aquí se fijan sus propiedades: determinismo, marco infinito (wrap), continuidad,
// densidad por altura, reparto de tonos, la tinta neutra, Reduce Motion y el parallax.

final class PolvoSimulacionTests: XCTestCase {
    typealias P = PolvoSimulacion
    typealias F = PolvoSimulacion.Fisica

    private let lienzo = CGSize(width: 402, height: 874)   // iPhone 17 Pro, en puntos

    private func p(_ i: Int, t: TimeInterval = 0, desplazamiento: CGFloat = 0,
                   neutra: Bool = false, still: Bool = false) -> P.Particula {
        P.particula(indice: i, t: t, lienzo: lienzo, desplazamiento: desplazamiento,
                    neutra: neutra, still: still)
    }

    // MARK: Hash

    func test_hashEnCeroUno_yDistintoEntreVecinos() {
        var vistos = Set<Double>()
        for i in 0..<500 {
            for k in 0..<9 {
                let h = P.hash(UInt32(i), UInt32(k))
                XCTAssertGreaterThanOrEqual(h, 0); XCTAssertLessThan(h, 1)
                vistos.insert(h)
            }
        }
        XCTAssertGreaterThan(vistos.count, 4400, "el hash tiene que separar (i, k) vecinos")
        XCTAssertNotEqual(P.hash(7, 0), P.hash(8, 0))
        XCTAssertNotEqual(P.hash(7, 0), P.hash(7, 1))
    }

    /// El hash es aritmética `uint32` con wrap: índices grandes no truenan ni colapsan.
    func test_hashAguantaIndicesGrandes() {
        _ = P.hash(UInt32.max, UInt32.max)
        XCTAssertNotEqual(P.hash(UInt32.max, 0), P.hash(UInt32.max - 1, 0))
    }

    // MARK: Determinismo y cuenta

    func test_esDeterminista() {
        XCTAssertEqual(p(42, t: 3.7), p(42, t: 3.7))
        XCTAssertNotEqual(p(42, t: 3.7), p(43, t: 3.7))
    }

    func test_cuentaEsAreaEntrePtPorParticula_acotada() {
        XCTAssertEqual(P.cuenta(lienzo: lienzo), Int(402.0 * 874.0 / Double(F.ptPorParticula)))
        XCTAssertEqual(P.cuenta(lienzo: CGSize(width: 10, height: 10)), F.nMin)
        XCTAssertEqual(P.cuenta(lienzo: CGSize(width: 4000, height: 4000)), F.nMax)
        XCTAssertEqual(P.cuenta(lienzo: .zero), 0, "sin lienzo no hay motas")
    }

    // MARK: Marco infinito

    /// Tras mucho tiempo (y mucho scroll) todas siguen dentro del lienzo: el campo envuelve.
    func test_wrapMantieneTodoDentroDelLienzo() {
        for i in 0..<300 {
            for (t, d) in [(0.0, 0.0), (600.0, 0.0), (36_000.0, 4_000.0), (86_000.0, 12.0)] {
                let q = p(i, t: t, desplazamiento: CGFloat(d))
                XCTAssertGreaterThanOrEqual(q.centro.x, 0, "i=\(i) t=\(t)")
                XCTAssertLessThan(q.centro.x, lienzo.width, "i=\(i) t=\(t)")
                XCTAssertGreaterThanOrEqual(q.centro.y, 0, "i=\(i) t=\(t)")
                XCTAssertLessThan(q.centro.y, lienzo.height, "i=\(i) t=\(t)")
                XCTAssertGreaterThanOrEqual(q.radio, F.radioMin)
                XCTAssertLessThanOrEqual(q.radio, F.radioMax)
                XCTAssertGreaterThanOrEqual(q.alfa, 0)
                XCTAssertLessThan(q.alfa, 0.5)
            }
        }
    }

    func test_wrapEsModuloPositivo() {
        XCTAssertEqual(P.wrap(-3, 10), 7, accuracy: 1e-9)
        XCTAssertEqual(P.wrap(13, 10), 3, accuracy: 1e-9)
        XCTAssertEqual(P.wrap(10, 10), 0, accuracy: 1e-9)
        XCTAssertEqual(P.wrap(5, 0), 0)
    }

    /// Entre dos cuadros consecutivos a 20 Hz una mota se mueve menos de 0.3 pt (salvo cuando
    /// cruza el borde y reaparece por el otro lado): a esa velocidad el reloj lento no se ve.
    func test_continuidadEntreCuadros() {
        for i in 0..<300 {
            let a = p(i, t: 10), b = p(i, t: 10 + 1.0 / 20)
            let dx = abs(a.centro.x - b.centro.x), dy = abs(a.centro.y - b.centro.y)
            let cruzaX = dx > lienzo.width / 2, cruzaY = dy > lienzo.height / 2
            if !cruzaX { XCTAssertLessThan(dx, 0.3, "i=\(i)") }
            if !cruzaY { XCTAssertLessThan(dy, 0.3, "i=\(i)") }
        }
    }

    /// El polvo sube: la deriva vertical es siempre negativa (hacia arriba en coordenadas de vista).
    func test_derivaSiempreHaciaArriba() {
        var subieron = 0
        for i in 0..<300 {
            let a = p(i, t: 0), b = p(i, t: 0.5)
            let dy = b.centro.y - a.centro.y
            if dy < 0 { subieron += 1 } else { XCTAssertGreaterThan(dy, lienzo.height / 2, "i=\(i): si no subió es porque envolvió") }
        }
        XCTAssertGreaterThan(subieron, 280)
    }

    // MARK: Densidad, alfa y respiración

    /// Detrás de la cuadrícula (abajo) hay más polvo que detrás del héroe (arriba): el alfa medio
    /// del tercio inferior supera al del tercio superior.
    func test_masDensoAbajoQueArriba() {
        var arriba: [Double] = [], abajo: [Double] = []
        for i in 0..<2000 {
            let q = p(i, still: true)
            if q.centro.y < lienzo.height * 0.23 { arriba.append(q.alfa) }
            if q.centro.y > lienzo.height * 0.80 { abajo.append(q.alfa) }
        }
        let mArriba = arriba.reduce(0, +) / Double(arriba.count)
        let mAbajo = abajo.reduce(0, +) / Double(abajo.count)
        XCTAssertGreaterThan(mAbajo, mArriba * 1.8, "abajo \(mAbajo) vs arriba \(mArriba)")
    }

    /// La respiración multiplica el alfa por `(1 − amp) + amp·sin(…)`, o sea entre 1 − 2·amp
    /// (0.44) y 1: en un periodo completo la razón máximo/mínimo es ≈ 1/(1 − 2·0.28) = 2.27 (la
    /// del prototipo aprobado). Se muestrea sobre 12.6 s (el periodo más largo, w = 0.5 rad/s); en
    /// ese lapso la mota deriva ≤ 50 pt y la densidad por altura mueve el alfa < 7 %, así que la
    /// razón cae en ±12 % de 2.27 — y NO en 1 (quieta) ni en 5 (otra cosa).
    func test_laRespiracionMueveElAlfaEnSuBanda() {
        for i in [3, 11, 47, 130] {
            var minimo = Double.infinity, maximo = -Double.infinity
            var muestras = 0
            for k in 0..<252 {
                let q = p(i, t: Double(k) * 0.05)
                // Lejos de los bordes (ahí el fade del wrap manda, no la respiración).
                let d = min(q.centro.x, lienzo.width - q.centro.x, q.centro.y, lienzo.height - q.centro.y)
                guard d > F.bordeFade else { continue }
                muestras += 1
                minimo = min(minimo, q.alfa); maximo = max(maximo, q.alfa)
            }
            guard muestras > 200 else { continue }   // esa mota cruzó un borde: no sirve de muestra
            let razon = maximo / minimo
            let esperada = 1 / (1 - 2 * F.respiracionAmp)
            XCTAssertGreaterThan(razon, esperada * 0.88, "i=\(i) razón \(razon)")
            XCTAssertLessThan(razon, esperada * 1.12, "i=\(i) razón \(razon)")
        }
        // Y con `still` no respira: alfa constante en el tiempo.
        XCTAssertEqual(p(11, t: 0, still: true).alfa, p(11, t: 5, still: true).alfa)
    }

    /// Los bordes se desvanecen: una mota pegada al borde tiene alfa ≈ 0 y a 40 pt ya vale su
    /// alfa pleno — así el wrap no «parpadea» (arriba densidad 0.35, abajo 1: sin fade el salto
    /// era 3× en un cuadro).
    func test_losBordesSeDesvanecen() {
        var pegadas = 0, plenas = 0
        for i in 0..<2000 {
            let q = p(i, still: true)
            let d = min(q.centro.x, lienzo.width - q.centro.x, q.centro.y, lienzo.height - q.centro.y)
            if d < 3 { pegadas += 1; XCTAssertLessThan(q.alfa, 0.01, "i=\(i) a \(d) pt del borde") }
            if d > F.bordeFade { plenas += 1; XCTAssertGreaterThan(q.alfa, 0.02, "i=\(i)") }
        }
        XCTAssertGreaterThan(pegadas, 5, "la muestra tiene motas pegadas al borde")
        XCTAssertGreaterThan(plenas, 1000)
    }

    // MARK: Tonos

    /// 80 % clima · 4 × 5 % satélites, dentro de tolerancia sobre 2 000 motas.
    func test_repartoDeTonos() {
        var conteo: [P.Tono: Int] = [:]
        for i in 0..<2000 { conteo[p(i).tono, default: 0] += 1 }
        let clima = Double(conteo[.clima] ?? 0) / 2000
        XCTAssertEqual(clima, F.umbralClima, accuracy: 0.03)
        for tono in [P.Tono.reposo, .sueno, .vigiaTemp, .vigiaResp] {
            XCTAssertEqual(Double(conteo[tono] ?? 0) / 2000, 0.05, accuracy: 0.02, "\(tono)")
        }
        XCTAssertNil(conteo[.neutra])
    }

    /// Sin veredicto: TODAS neutras y el alfa multiplicado por 0.55 — la posición no cambia.
    func test_neutraFuerzaTintaNeutraYBajaElAlfa() {
        for i in 0..<200 {
            let color = p(i, t: 2), gris = p(i, t: 2, neutra: true)
            XCTAssertEqual(gris.tono, .neutra)
            XCTAssertEqual(gris.centro, color.centro)
            XCTAssertEqual(gris.alfa, color.alfa * F.alfaNeutra, accuracy: 1e-9)
        }
    }

    // MARK: Reduce Motion y parallax

    /// `still`: sin tiempo (misma partícula en t=0 y t=99), sin respiración y sin parallax.
    func test_stillIgnoraTiempoYParallax() {
        for i in 0..<200 {
            let a = p(i, t: 0, still: true)
            XCTAssertEqual(a, p(i, t: 99, still: true))
            XCTAssertEqual(a, p(i, t: 99, desplazamiento: 500, still: true))
            XCTAssertEqual(a.centro, p(i, t: 0).centro, "en t=0 la posición coincide con la viva")
        }
    }

    /// El parallax mueve el campo hacia arriba 0.22 × desplazamiento (envuelto).
    func test_parallaxMueveElCampoUn22PorCiento() {
        for i in 0..<200 {
            let a = p(i, t: 5), b = p(i, t: 5, desplazamiento: 100)
            let esperado = P.wrap(Double(a.centro.y) - Double(F.parallax) * 100, Double(lienzo.height))
            XCTAssertEqual(Double(b.centro.y), esperado, accuracy: 1e-6, "i=\(i)")
            XCTAssertEqual(a.centro.x, b.centro.x, accuracy: 1e-9)
        }
        // Y el desplazamiento negativo (overscroll del pull) NO mueve nada.
        XCTAssertEqual(p(3, t: 5).centro, p(3, t: 5, desplazamiento: -80).centro)
    }
}
