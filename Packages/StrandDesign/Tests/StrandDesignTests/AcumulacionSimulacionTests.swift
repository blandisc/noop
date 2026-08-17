import XCTest
import CoreGraphics
@testable import StrandDesign

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
