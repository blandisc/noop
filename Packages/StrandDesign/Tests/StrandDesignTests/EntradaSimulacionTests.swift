import XCTest
@testable import StrandDesign

/// La coreografía de la entrada (FER-41), afirmada sin pantalla. `EntradaSimulacion` es una
/// función pura del tiempo, así que cada criterio de aceptación del acto I se puede probar
/// aquí: que las corrientes NAZCAN fuera de cuadro, que se reúnan antes del respiro, que el
/// orbe esté quieto durante el respiro, que rebase el cénit sin pasarse del tope declarado,
/// que entre neutro y se tiña al final, y que el especular vaya DESPUÉS del teñido.
final class EntradaSimulacionTests: XCTestCase {
    typealias E = EntradaSimulacion
    typealias G = EntradaSimulacion.Geometria
    typealias Guion = EntradaSimulacion.Guion

    private var total: Double { LiquidEntradaMotion.duracionTotal }

    /// Un instante a partir de la fracción del guion (que es como está escrito el guion).
    private func t(_ fraccion: Double) -> Double { fraccion * total }

    // MARK: El guion cierra

    /// Los hitos se derivan en cadena; si alguien mueve una duración y la suma se pasa de 1,
    /// la coreografía se cortaría a media animación. Aquí se entera antes que el usuario.
    func testGuionCabeEnLaDuracionTotal() {
        XCTAssertLessThan(Guion.llegadaFin, Guion.respiroFin)
        XCTAssertLessThan(Guion.respiroFin, Guion.ascensoFin)
        XCTAssertLessThanOrEqual(Guion.ascensoFin, 1.0)
        XCTAssertLessThanOrEqual(Guion.tinteFin, 1.0)
        XCTAssertLessThanOrEqual(Guion.especularFin, 1.0)
        XCTAssertEqual(Guion.retardos.count, G.corrientes)
        XCTAssertEqual(G.origenes.count, G.corrientes)
    }

    // MARK: CA-2.1 · las corrientes nacen FUERA del lienzo

    func testCadaCorrienteNaceFueraDelLienzo() {
        // El orbe reunido ocupa [centro ± radio]. Un origen está fuera de cuadro si, sumado
        // al orbe, cae del otro lado de algún borde del lienzo.
        for (i, o) in G.origenes.enumerated() {
            let x = G.cenit.x + o.width
            let y = G.reunionY + o.height
            let fuera = x + G.radio < 0 || x - G.radio > G.lienzo.width
                || y + G.radio < 0 || y - G.radio > G.lienzo.height
            XCTAssertTrue(fuera, "la corriente \(i) nace DENTRO de cuadro: (\(x), \(y))")
        }
    }

    /// El gesto que el dueño aprobó: el orbe se arma desde el pie de la pantalla. Ninguna
    /// corriente puede caer desde arriba.
    func testTodasLasCorrientesVienenDeAbajo() {
        for (i, o) in G.origenes.enumerated() {
            XCTAssertGreaterThan(o.height, 0, "la corriente \(i) viene de ARRIBA")
        }
    }

    func testEnCeroCadaCorrienteEstaEnSuOrigen() {
        let c = E.cuadro(t: 0)
        for i in 0..<G.corrientes {
            XCTAssertEqual(c.desvios[i].width, G.origenes[i].width, accuracy: 0.001)
            XCTAssertEqual(c.desvios[i].height, G.origenes[i].height, accuracy: 0.001)
        }
        // Las que aún no arrancan están invisibles: nada se materializa parado fuera de cuadro.
        for i in 0..<G.corrientes where Guion.retardos[i] > 0 {
            XCTAssertEqual(c.alfas[i], 0, accuracy: 0.001)
        }
    }

    /// El ESCALONADO existe de verdad. Sin este test, aplanar `Guion.retardos` a un solo valor
    /// —que destruye el diseño entero: «cada corriente con su propio retardo»— dejaba la suite
    /// en verde, porque los demás solo miran los extremos (t = 0 y `llegadaFin`), donde todas
    /// coinciden por construcción. Lo cazó la revisión adversarial de FER-41.
    func testLasCorrientesLleganEscalonadas() {
        // A media llegada, la que arrancó primero tiene que ir MÁS adelantada que la última.
        let c = E.cuadro(t: t(Guion.escalonMax + Guion.viaje * 0.5))
        guard let primera = Guion.retardos.firstIndex(of: Guion.retardos.min() ?? 0),
              let ultima = Guion.retardos.firstIndex(of: Guion.escalonMax) else {
            return XCTFail("los retardos no tienen un primero y un último distinguibles")
        }
        func avance(_ i: Int) -> Double {
            let o = G.origenes[i], d = c.desvios[i]
            let magO = (o.width * o.width + o.height * o.height).squareRoot()
            let magD = (d.width * d.width + d.height * d.height).squareRoot()
            return magO > 0 ? 1 - Double(magD / magO) : 1
        }
        XCTAssertGreaterThan(avance(primera), avance(ultima) + 0.02,
                             "las corrientes viajan al unísono: el escalonado se perdió")
        XCTAssertNotEqual(Guion.retardos.min(), Guion.retardos.max(),
                          "todos los retardos son iguales: no hay escalonado que animar")
    }

    /// CA-2.1 de verdad: la corriente termina de ENCENDERSE mientras todavía viene de fuera de
    /// cuadro, así que cruza el borde ya opaca. La primera versión la dejaba llegar a opacidad
    /// plena con el 70 % del camino andado —o sea, ya bien adentro— y el usuario nunca la veía
    /// entrar, solo aparecer. El test fija el gesto, no la implementación.
    func testCadaCorrienteEstaFueraDeCuadroAlEncenderseDelTodo() {
        for i in 0..<G.corrientes {
            let uPlena = Guion.retardos[i] + Guion.viaje * Guion.alfaVentana
            let c = E.cuadro(t: t(uPlena))
            XCTAssertEqual(c.alfas[i], 1, accuracy: 0.01, "corriente \(i) no llegó a plena")
            // Su CENTRO todavía fuera del lienzo: puede asomar ya un canto —eso es justamente
            // «cruzar el borde»— pero el grueso de la corriente sigue afuera, así que se la ve
            // entrar. Exigirla entera afuera prohibiría el cruce, que es el gesto.
            let x = G.cenit.x + c.desvios[i].width
            let y = G.reunionY + c.desvios[i].height
            let fuera = x < 0 || x > G.lienzo.width || y < 0 || y > G.lienzo.height
            XCTAssertTrue(fuera,
                          "la corriente \(i) se enciende del todo YA DENTRO de cuadro: (\(x), \(y))")
        }
    }

    // MARK: CA-2.2 · reunión y respiro

    func testAlTerminarLaLlegadaTodasLasCorrientesEstanReunidas() {
        let c = E.cuadro(t: t(Guion.llegadaFin))
        for i in 0..<G.corrientes {
            XCTAssertEqual(c.desvios[i].width, 0, accuracy: 0.5, "corriente \(i) no llegó en x")
            XCTAssertEqual(c.desvios[i].height, 0, accuracy: 0.5, "corriente \(i) no llegó en y")
            XCTAssertEqual(c.alfas[i], 1, accuracy: 0.001, "corriente \(i) no está plena")
        }
    }

    /// El respiro es QUIETUD: entre el fin de la llegada y el arranque del ascenso el orbe no
    /// se mueve ni un punto. Es el beat que separa «se armó» de «sube».
    func testDuranteElRespiroElOrbeNoSeMueve() {
        let a = E.cuadro(t: t(Guion.llegadaFin))
        let b = E.cuadro(t: t((Guion.llegadaFin + Guion.respiroFin) / 2))
        let c = E.cuadro(t: t(Guion.respiroFin))
        XCTAssertEqual(a.centro.y, G.reunionY, accuracy: 0.001)
        XCTAssertEqual(b.centro.y, G.reunionY, accuracy: 0.001)
        XCTAssertEqual(c.centro.y, G.reunionY, accuracy: 0.001)
    }

    // MARK: CA-2.3 · el ascenso rebasa y asienta

    func testElAscensoAsientaExactamenteEnElCenit() {
        let c = E.cuadro(t: t(Guion.ascensoFin))
        XCTAssertEqual(c.centro.y, G.cenit.y, accuracy: 0.001)
        XCTAssertEqual(c.centro.x, G.cenit.x, accuracy: 0.001)
    }

    /// Rebasa de verdad (si no, no hay asentamiento) pero nunca más de lo declarado. El tope
    /// es el token, no un número que se coló: el pico del lóbulo vale EXACTAMENTE `sobrepaso`.
    func testElRebaseExisteYNoSePasaDelTope() {
        var minY = CGFloat.greatestFiniteMagnitude
        for paso in 0...400 {
            let u = Guion.respiroFin + (Guion.ascensoFin - Guion.respiroFin) * Double(paso) / 400
            minY = min(minY, E.cuadro(t: t(u)).centro.y)
        }
        let rebase = G.cenit.y - minY
        XCTAssertGreaterThan(rebase, 1, "no rebasa: el ascenso no se siente como asentamiento")
        XCTAssertLessThanOrEqual(rebase, G.sobrepaso + 0.01, "rebasa más de lo declarado")
        XCTAssertEqual(rebase, G.sobrepaso, accuracy: 0.05, "el pico del lóbulo no es el token")
        // Y el token mismo respeta el TOPE del criterio de aceptación. Sin este assert, subir
        // `sobrepaso` a 15 dejaba toda la suite en verde: los demás solo comparan el rebase
        // medido contra el token, que es autorreferencial.
        XCTAssertLessThanOrEqual(G.sobrepaso, 8, "CA-2.3: el rebase no puede pasar de 8 pt")
    }

    /// La curva del ascenso, aislada: arranca en la reunión, toca el punto rebasado EXACTO en
    /// su cima, termina en el cénit, y fuera de rango queda clampeada en vez de dispararse.
    func testLaCurvaDelAscensoTocaSusTresPuntos() {
        XCTAssertEqual(E.alturaAscenso(0), G.reunionY, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(Guion.cimaAscenso), G.cenit.y - G.sobrepaso, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(1), G.cenit.y, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(-3), G.reunionY, accuracy: 1e-9)
        XCTAssertEqual(E.alturaAscenso(7), G.cenit.y, accuracy: 1e-9)
        // Sube sin retroceder hasta la cima (un titubeo a media subida leería como un tirón).
        var previo = CGFloat.greatestFiniteMagnitude
        for paso in 0...200 {
            let y = E.alturaAscenso(Guion.cimaAscenso * Double(paso) / 200)
            XCTAssertLessThanOrEqual(y, previo + 1e-9)
            previo = y
        }
    }

    // MARK: CA-2.4 / CA-2.5 · entra neutro, se tiñe, y el especular va después

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

    /// El teñido es monótono: nunca retrocede a medio camino (leería como un parpadeo).
    func testElTeñidoNuncaRetrocede() {
        var previo = -1.0
        for paso in 0...300 {
            let v = E.cuadro(t: total * Double(paso) / 300).tinte
            XCTAssertGreaterThanOrEqual(v, previo - 1e-9, "el teñido retrocedió")
            previo = v
        }
    }

    // MARK: CA-2.10 · la salida

    func testLaEntradaSeApagaAlTerminarSuDuracion() {
        XCTAssertEqual(E.cuadro(t: total).alfa, 1, accuracy: 0.001)
        XCTAssertEqual(E.cuadro(t: E.duracion()).alfa, 0, accuracy: 0.001)
        XCTAssertEqual(E.duracion(),
                       LiquidEntradaMotion.duracionTotal + LiquidEntradaMotion.salida,
                       accuracy: 1e-12)
    }

    // MARK: CA-2.7 · Reducir movimiento

    /// Sin viaje: en CUALQUIER instante el orbe ya está en el cénit, pleno y teñido. Congelar
    /// la coreografía a media llegada enseñaría una composición que nadie diseñó.
    func testReducirMovimientoNoTieneViaje() {
        for paso in 0...20 {
            let c = E.cuadro(t: E.duracion(reduce: true) * Double(paso) / 20, reduce: true)
            XCTAssertEqual(c.centro.y, G.cenit.y, accuracy: 0.001)
            XCTAssertEqual(c.tinte, 1, accuracy: 0.001)
            XCTAssertEqual(c.especular, 1, accuracy: 0.001)
            XCTAssertEqual(c.rotacion, 0, accuracy: 0.001)
            for d in c.desvios { XCTAssertEqual(d.width, 0); XCTAssertEqual(d.height, 0) }
            for a in c.alfas { XCTAssertEqual(a, 1, accuracy: 0.001) }
        }
        XCTAssertEqual(E.cuadro(t: E.duracion(reduce: true), reduce: true).alfa, 0, accuracy: 0.001)
        XCTAssertLessThan(E.duracion(reduce: true), E.duracion())
    }

    // MARK: CA-2.6 · pureza y determinismo

    func testElMismoInstanteDaElMismoCuadro() {
        for f in [0.0, 0.17, 0.42, 0.7, 0.93, 1.0] {
            XCTAssertEqual(E.cuadro(t: t(f)), E.cuadro(t: t(f)))
        }
    }

    /// «Función pura del tiempo» tiene que valer para CUALQUIER tiempo, no solo para los
    /// razonables: un `t` no finito se colaba por las comparaciones con NaN (que siempre son
    /// falsas) y salía por el giro, dejando el orbe sin rotación definida.
    func testCualquierTiempoDaUnCuadroDefinido() {
        for raro in [TimeInterval.nan, .infinity, -.infinity, -1, -1e9, 1e9] {
            let c = E.cuadro(t: raro)
            XCTAssertTrue(c.centro.x.isFinite && c.centro.y.isFinite, "centro no finito con t=\(raro)")
            XCTAssertTrue(c.rotacion.isFinite, "rotación no finita con t=\(raro)")
            XCTAssertTrue(c.tinte.isFinite && c.especular.isFinite && c.alfa.isFinite)
            for d in c.desvios { XCTAssertTrue(d.width.isFinite && d.height.isFinite) }
            for a in c.alfas { XCTAssertTrue(a.isFinite) }
        }
        // Un tiempo sin sentido se trata como el instante cero, exactamente.
        XCTAssertEqual(E.cuadro(t: .nan), E.cuadro(t: 0))
        // Antes de empezar, la COMPOSICIÓN es la del instante cero. El giro no: es un ángulo
        // del reloj, y a t negativo vale su ángulo negativo — correcto, no un estado previo.
        let antes = E.cuadro(t: -1), cero = E.cuadro(t: 0)
        XCTAssertEqual(antes.centro, cero.centro)
        XCTAssertEqual(antes.desvios, cero.desvios)
        XCTAssertEqual(antes.alfas, cero.alfas)
        XCTAssertEqual(antes.tinte, cero.tinte)
        // Mucho después ya se apagó.
        XCTAssertEqual(E.cuadro(t: 1e6).alfa, 0, accuracy: 0.001)
    }

    /// Un desalineo entre `corrientes` y sus tablas tiene que degradar a una animación fea,
    /// nunca a un crash: indexar con `count - 1` sobre una tabla vacía da −1, e indexar con −1
    /// en Swift no clampa, revienta — y reventaría en el primer frame del arranque.
    func testLaLecturaDeTablasSoportaTablasVaciasYCortas() {
        XCTAssertEqual(E.enTabla([Double](), 3, porDefecto: 7), 7)
        XCTAssertEqual(E.enTabla([1.0, 2.0], 9, porDefecto: 0), 2)
        XCTAssertEqual(E.enTabla([1.0, 2.0], -4, porDefecto: 0), 1)
    }

    /// La guarda degenerada de `rampa` (hitos invertidos o iguales) devuelve un escalón, no un
    /// NaN por dividir entre cero.
    func testLaRampaSoportaHitosDegenerados() {
        XCTAssertEqual(E.rampa(0.4, de: 0.5, a: 0.5), 0)
        XCTAssertEqual(E.rampa(0.6, de: 0.5, a: 0.5), 1)
        XCTAssertEqual(E.rampa(0.9, de: 0.8, a: 0.2), 1)
    }

    // MARK: El reparto en corrientes

    /// Cada corriente es un GAJO real: todas se usan y ninguna se queda con la esfera entera.
    func testElRepartoUsaTodasLasCorrientesYEsBalanceado() {
        var cuenta = [Int](repeating: 0, count: G.corrientes)
        for i in 0..<G.n { cuenta[E.corriente(i, de: G.n)] += 1 }
        XCTAssertEqual(cuenta.reduce(0, +), G.n)
        for (c, k) in cuenta.enumerated() {
            XCTAssertGreaterThan(k, 0, "la corriente \(c) quedó vacía")
            // Reparto por ángulo sobre una esfera proyectada: ninguna se lleva más del doble
            // de su parte justa (si una acaparara, la llegada leería como un solo bloque).
            XCTAssertLessThan(k, 2 * G.n / G.corrientes, "la corriente \(c) acapara")
        }
    }

    func testElRepartoEsEstable() {
        for i in stride(from: 0, to: G.n, by: 17) {
            XCTAssertEqual(E.corriente(i, de: G.n), E.corriente(i, de: G.n))
            XCTAssertTrue((0..<G.corrientes).contains(E.corriente(i, de: G.n)))
        }
    }
}
