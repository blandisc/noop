import XCTest
import CoreGraphics
@testable import CenitDesign

/// Las leyes de la acumulación (FER-109). Lo que se afirma aquí es lo que el onboarding promete
/// visualmente, así que romper una de estas pruebas es romper una promesa al usuario, no un detalle.
final class AcumulacionSimulacionTests: XCTestCase {

    private let lienzo = CGSize(width: 390, height: 770)
    private let centro = CGPoint(width: 195, height: 300).asPoint
    private let radio: CGFloat = 74

    // MARK: Determinismo

    func testMismoInstanteMismoCuadro() {
        let a = AcumulacionSimulacion.mota(indice: 42, t: 1.7, densidad: 0.8, modo: .dentro,
                                           centro: centro, radio: radio, lienzo: lienzo)
        let b = AcumulacionSimulacion.mota(indice: 42, t: 1.7, densidad: 0.8, modo: .dentro,
                                           centro: centro, radio: radio, lienzo: lienzo)
        XCTAssertEqual(a, b, "La simulación tiene que ser pura: mismo t, mismo cuadro, siempre.")
    }

    // MARK: El orden de encendido va hasheado, no por índice

    func testElOrdenDeEncendidoNoEsElDeFibonacci() {
        // Si `rango` fuera monótono en el índice, el orbe se dibujaría como una concha en espiral
        // (polo a polo) y se leería mecánico. Tiene que estar revuelto.
        let n = AcumulacionSimulacion.Geometria.nEsfera
        var inversiones = 0
        for i in 1..<n where AcumulacionSimulacion.rango(i) < AcumulacionSimulacion.rango(i - 1) {
            inversiones += 1
        }
        // Un orden aleatorio invierte ~la mitad de los pares consecutivos; uno monótono, cero.
        XCTAssertGreaterThan(inversiones, n / 4,
                             "El encendido está saliendo demasiado ordenado: se vería como un trazo.")
    }

    func testRangoEstaEnRangoYEsEstable() {
        for i in stride(from: 0, to: AcumulacionSimulacion.Geometria.nEsfera, by: 17) {
            let r = AcumulacionSimulacion.rango(i)
            XCTAssertGreaterThanOrEqual(r, 0)
            XCTAssertLessThanOrEqual(r, 1)
            XCTAssertEqual(r, AcumulacionSimulacion.rango(i))
        }
    }

    // MARK: La densidad honesta

    func testDensidadHonesta() {
        XCTAssertEqual(AcumulacionSimulacion.densidadHonesta(noches: 0, umbral: 14), 0)
        XCTAssertEqual(AcumulacionSimulacion.densidadHonesta(noches: 14, umbral: 14), 1)
        XCTAssertEqual(AcumulacionSimulacion.densidadHonesta(noches: 46, umbral: 14), 1,
                       "Más noches que el umbral no llenan más de lo lleno.")
        let ocho = AcumulacionSimulacion.densidadHonesta(noches: 8, umbral: 14)
        XCTAssertEqual(ocho, 8.0 / 14.0, accuracy: 0.0001)
        XCTAssertGreaterThan(ocho, AcumulacionSimulacion.densidadHonesta(noches: 4, umbral: 14),
                             "Tiene que crecer con las noches: si no, no codifica evidencia.")
        XCTAssertEqual(AcumulacionSimulacion.densidadHonesta(noches: -3, umbral: 14), 0)
        XCTAssertEqual(AcumulacionSimulacion.densidadHonesta(noches: 5, umbral: 0), 0)
    }

    // MARK: Cuántas latchean

    func testDensidadPlenaLatcheaLaEsferaCompleta() {
        let motas = AcumulacionSimulacion.cuadro(t: 30, densidad: 1, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 reduce: true)
        let latcheadas = motas.filter(\.latcheada).count
        XCTAssertEqual(latcheadas, AcumulacionSimulacion.Geometria.nEsfera,
                       "Con densidad 1 el orbe está completo, ni una mota menos.")
    }

    func testSiempreQuedanFlotantesAunqueElOrbeEsteLleno() {
        // El pedido explícito del dueño: si esperas lo suficiente el orbe queda completo Y
        // siguen quedando partículas flotando.
        let motas = AcumulacionSimulacion.cuadro(t: 30, densidad: 1, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 reduce: true)
        let sueltas = motas.filter { !$0.latcheada }.count
        XCTAssertEqual(sueltas, AcumulacionSimulacion.Geometria.nFlotantes)
        XCTAssertGreaterThan(sueltas, 0)
    }

    func testDensidadMediaLatcheaLaMitad() {
        let motas = AcumulacionSimulacion.cuadro(t: 30, densidad: 0.5, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 reduce: true)
        let latcheadas = motas.filter(\.latcheada).count
        let esperado = AcumulacionSimulacion.Geometria.nEsfera / 2
        XCTAssertEqual(Double(latcheadas), Double(esperado), accuracy: Double(esperado) * 0.12,
                       "El corte por hash tiene que repartir parejo, no amontonarse.")
    }

    // MARK: El orbe no se desarma

    func testLaAcumulacionEsMonotona() {
        // Una densidad mayor nunca puede latchear MENOS motas: un orbe que se desarma solo
        // sería una mentira distinta (y se leería como que la app perdió datos).
        var previas = -1
        for paso in stride(from: 0.0, through: 1.0, by: 0.1) {
            let n = AcumulacionSimulacion.cuadro(t: 30, densidad: paso, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 reduce: true).filter(\.latcheada).count
            XCTAssertGreaterThanOrEqual(n, previas)
            previas = n
        }
    }

    // MARK: El tamaño no cambia al posarse

    func testElRadioNoCambiaDuranteElViaje() {
        // Un «pop» de escala al posarse es rebote de caricatura disfrazado, y el ADN lo prohíbe.
        let i = 7
        let enVuelo = AcumulacionSimulacion.mota(indice: i, t: 0.1, densidad: 1, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo)
        let posada = AcumulacionSimulacion.mota(indice: i, t: 8, densidad: 1, modo: .dentro,
                                                centro: centro, radio: radio, lienzo: lienzo)
        XCTAssertEqual(enVuelo?.radio, posada?.radio,
                       "El radio cambió entre vuelo y reposo: eso es un pop de escala.")
    }

    // MARK: El viaje se mide contra la DENSIDAD, no contra el reloj (FER-111)
    //
    // La vista pasa `t = reloj de pared % 3600`. Cualquier avance medido contra `t` vale 1 en
    // 3598.75 de cada 3600 segundos, así que el viaje NO se pintaba nunca (las motas
    // teletransportaban a la esfera) y en cada frontera de hora las 300 lo replayeaban a la vez.
    // Estas pruebas corren en los `t` que la pantalla SÍ produce — los 0.1/1.7/3.3 s de las demás
    // son justo los que tapaban el defecto.

    func testAMediaHoraElViajeSeSiguePintando() {
        let densidad = 0.5
        let ancho = AcumulacionSimulacion.Guion.anchoFrente
        let motas = AcumulacionSimulacion.cuadro(t: 1800, densidad: densidad, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo)
        var enVuelo: [Int] = [], posadas: [Int] = []
        for i in 0..<AcumulacionSimulacion.Geometria.nEsfera {
            let paso = densidad - AcumulacionSimulacion.rango(i)
            if paso > 0, paso < ancho { enVuelo.append(i) } else if paso >= ancho { posadas.append(i) }
        }
        XCTAssertGreaterThan(enVuelo.count, 0,
                             "El frente de llegada quedó vacío: la prueba no está probando nada.")
        for i in enVuelo {
            XCTAssertFalse(motas[i].latcheada,
                           "La mota \(i) está DENTRO del frente y ya aparece posada: a media hora "
                           + "de reloj el viaje no se está pintando.")
        }
        for i in posadas {
            XCTAssertTrue(motas[i].latcheada,
                          "La mota \(i) ya rebasó el frente y sigue en vuelo: nunca aterrizaría.")
        }
        // Y el viaje se VE, no es solo una bandera: alguna de las que vienen en camino todavía
        // está fuera de la silueta de la esfera.
        let hayCamino = enVuelo.contains {
            hypot(motas[$0].punto.x - centro.x, motas[$0].punto.y - centro.y) > radio
        }
        XCTAssertTrue(hayCamino, "Ninguna mota en vuelo está lejos del orbe: están apareciendo ya "
                      + "en su ranura, que es el pop de POSICIÓN que el archivo prohíbe.")
    }

    func testLaFronteraDeHoraNoDesarmaElOrbe() {
        // La vista envuelve el reloj cada hora. Medido contra `t`, ese instante hacía que las 300
        // motas replayearan su viaje a la vez: el orbe se desarmaba y se rearmaba solo.
        let densidad = 0.8
        let ancho = AcumulacionSimulacion.Guion.anchoFrente
        let antes = AcumulacionSimulacion.cuadro(t: 3599.9, densidad: densidad, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo)
        let despues = AcumulacionSimulacion.cuadro(t: 0.1, densidad: densidad, modo: .dentro,
                                                   centro: centro, radio: radio, lienzo: lienzo)
        for i in 0..<AcumulacionSimulacion.Geometria.nEsfera {
            XCTAssertEqual(antes[i].latcheada, despues[i].latcheada,
                           "La mota \(i) cambió de estado al cruzar la hora: el orbe se desarma.")
        }
        // Las que ya se posaron tampoco se MUEVEN: la rotación es continua en la frontera
        // (0.055 × 3600 = 198 vueltas exactas), así que solo queda su avance de ~4°.
        for i in 0..<AcumulacionSimulacion.Geometria.nEsfera
        where AcumulacionSimulacion.rango(i) <= densidad - ancho {
            let salto = hypot(antes[i].punto.x - despues[i].punto.x,
                              antes[i].punto.y - despues[i].punto.y)
            XCTAssertLessThan(salto, 8,
                              "La mota \(i) saltó \(salto) pt al cruzar la hora: eso es el estallido.")
        }
    }

    func testConDensidadPlenaNadieSeQuedaAMedioVuelo() {
        // `corte` no puede pasar de 1, así que a la cola de la fila le faltaría densidad que ya
        // no existe para terminar de llegar: el frente se estrecha al final (`frente`) para que la
        // ÚLTIMA mota aterrice EXACTAMENTE en densidad 1. Sin eso, un orbe «completo» se queda con
        // un 5 % de sus motas colgadas a medio vuelo para siempre — y
        // `testDensidadPlenaLatcheaLaEsferaCompleta` no lo vería, porque corre con `reduce`.
        let motas = AcumulacionSimulacion.cuadro(t: 1800, densidad: 1, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo)
        let deOrbe = motas.prefix(AcumulacionSimulacion.Geometria.nEsfera)
        XCTAssertTrue(deOrbe.allSatisfy(\.latcheada),
                      "Con densidad 1 hay motas todavía en vuelo: el orbe lleno se ve poroso.")
    }

    func testLaMaterializacionDeAlfaSePinta() {
        // `alfaPiso` y `tramoMaterializa` eran código muerto en pantalla mientras el avance se
        // medía contra el reloj: la mota aparecía de golpe ya a su alfa final. Entrar cuesta.
        guard let i = (0..<AcumulacionSimulacion.Geometria.nEsfera)
            .first(where: { AcumulacionSimulacion.rango($0) < 0.5 }) else {
            return XCTFail("No hay ninguna mota con umbral bajo: el hash está mal repartido.")
        }
        let umbral = AcumulacionSimulacion.rango(i)
        let ancho = AcumulacionSimulacion.Guion.anchoFrente
        let entrando = AcumulacionSimulacion.mota(indice: i, t: 1800, densidad: umbral + ancho * 0.1,
                                                  modo: .dentro, centro: centro, radio: radio,
                                                  lienzo: lienzo)
        let posada = AcumulacionSimulacion.mota(indice: i, t: 1800, densidad: umbral + ancho * 2,
                                                modo: .dentro, centro: centro, radio: radio,
                                                lienzo: lienzo)
        XCTAssertLessThan(entrando?.alfa ?? 1, posada?.alfa ?? 0,
                          "La mota entra ya a alfa final: no se materializa, aparece.")
    }

    // MARK: Cada acto pinta lo suyo

    func testConvergenciaYDentroNoPintanElMismoCuadro() {
        // El acto 3 → 4 tiene que ser un GESTO: la materia que orbitaba su ranura se aquieta y la
        // esfera cuaja. Si los dos modos dan el mismo punto, el reveal del veredicto es un no-op.
        let n = AcumulacionSimulacion.Geometria.nEsfera
        let conv = AcumulacionSimulacion.cuadro(t: 1800, densidad: 1, modo: .convergencia,
                                                centro: centro, radio: radio, lienzo: lienzo)
        let dentro = AcumulacionSimulacion.cuadro(t: 1800, densidad: 1, modo: .dentro,
                                                  centro: centro, radio: radio, lienzo: lienzo)
        let distintas = (0..<n).filter { conv[$0].punto != dentro[$0].punto }.count
        XCTAssertGreaterThan(distintas, n * 3 / 4,
                             "`.convergencia` y `.dentro` pintan el mismo cuadro: el acto 3 no "
                             + "tiene gesto propio y el veredicto llega sin que nada se aquiete.")
        // Y el gesto es RADIAL: mientras no cuaja, algo queda por fuera de la silueta — imposible
        // en `.dentro`, donde toda mota está exactamente en su ranura.
        func fuera(_ ms: [AcumulacionSimulacion.Mota]) -> Int {
            (0..<n).filter { hypot(ms[$0].punto.x - centro.x, ms[$0].punto.y - centro.y) > radio }.count
        }
        XCTAssertEqual(fuera(dentro), 0, "En `.dentro` la esfera ya cuajó: nada sobresale.")
        XCTAssertGreaterThan(fuera(conv), 0, "En `.convergencia` la materia todavía cae: el radio "
                             + "respira y algo tiene que quedar fuera de la silueta.")
    }

    // MARK: Reduce Motion

    func testConReduceNadieQuedaAMedioViaje() {
        let motas = AcumulacionSimulacion.cuadro(t: 0.2, densidad: 1, modo: .dentro,
                                                 centro: centro, radio: radio, lienzo: lienzo,
                                                 reduce: true)
        let deOrbe = motas.prefix(AcumulacionSimulacion.Geometria.nEsfera)
        XCTAssertTrue(deOrbe.allSatisfy(\.latcheada),
                      "Con reducir movimiento no hay viaje: la mota está en su sitio o no está.")
    }

    // MARK: Todo cae dentro del lienzo

    func testNadaSeDibujaFueraDelLienzo() {
        for modo in [AcumulacionSimulacion.Modo.disperso, .quieto, .convergencia, .dentro] {
            let motas = AcumulacionSimulacion.cuadro(t: 3.3, densidad: 0.6, modo: modo,
                                                     centro: centro, radio: radio, lienzo: lienzo)
            for m in motas where !m.latcheada {
                XCTAssertTrue((0...lienzo.width).contains(m.punto.x), "\(modo): x fuera de cuadro")
                XCTAssertTrue((0...lienzo.height).contains(m.punto.y), "\(modo): y fuera de cuadro")
            }
        }
    }

    // MARK: Índices inválidos

    func testIndiceFueraDeRangoDevuelveNil() {
        XCTAssertNil(AcumulacionSimulacion.mota(indice: -1, t: 1, densidad: 1, modo: .dentro,
                                                centro: centro, radio: radio, lienzo: lienzo))
        XCTAssertNil(AcumulacionSimulacion.mota(indice: AcumulacionSimulacion.Geometria.nTotal,
                                                t: 1, densidad: 1, modo: .dentro,
                                                centro: centro, radio: radio, lienzo: lienzo))
    }
}

private extension CGPoint {
    init(width: CGFloat, height: CGFloat) { self.init(x: width, y: height) }
    var asPoint: CGPoint { self }
}
