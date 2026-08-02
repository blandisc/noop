import XCTest
import CoreGraphics
@testable import StrandDesign

/// La física pura del Ecosistema (FER-10). El contrato clave: `particula(...)` es
/// DETERMINISTA y derivada solo de (dirección, parámetros, t) — esa función es la spec del
/// shader de la Fase B, y estos tests la validan gratis para ambas fases.
final class EcosistemaSimulacionTests: XCTestCase {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria
    typealias M = LiquidEcosistemaMotion

    // MARK: Fibonacci

    func test_fibonacci_conteoYNorma() {
        for n in [G.nEsfera, G.nLuna, G.nGuardian] {
            let dirs = Sim.fibonacci(n)
            XCTAssertEqual(dirs.count, n)
            for d in dirs {
                let norma = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
                XCTAssertEqual(norma, 1, accuracy: 1e-9)
            }
        }
        // Determinista: dos llamadas, el mismo resultado.
        XCTAssertEqual(Sim.fibonacci(50), Sim.fibonacci(50))
    }

    // MARK: Easings

    func test_backOut_extremosYOvershoot() {
        XCTAssertEqual(Sim.backOut(0), 0, accuracy: 1e-12)
        XCTAssertEqual(Sim.backOut(1), 1, accuracy: 1e-12)
        XCTAssertEqual(Sim.backOut(-1), 0)
        XCTAssertEqual(Sim.backOut(2), 1)
        // El back-out SOBREPASA 1 en el tramo final (esa es su firma física).
        let maxVal = stride(from: 0.0, through: 1.0, by: 0.01).map { Sim.backOut($0) }.max()!
        XCTAssertGreaterThan(maxVal, 1.0)
    }

    func test_suave_extremos() {
        XCTAssertEqual(Sim.suave(0), 0)
        XCTAssertEqual(Sim.suave(1), 1)
        XCTAssertEqual(Sim.suave(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Sim.suave(-3), 0)
        XCTAssertEqual(Sim.suave(3), 1)
    }

    func test_settle_decae() {
        XCTAssertEqual(Sim.settle(0), 0)
        // A 1.5 s el asentamiento ya es residual (< 12 % de la amplitud).
        XCTAssertLessThan(abs(Sim.settle(1.5)), 0.12 * M.settleAmplitud)
        // Y decae monótonamente en envolvente.
        XCTAssertLessThan(abs(Sim.settle(3)), abs(0.05 * M.settleAmplitud))
    }

    // MARK: Cuadro (fases con transiciones implícitas)

    func test_cuadro_formando() {
        let fase = Sim.Fase.formando(inicio: 100)
        // Durante la espera: separada.
        let esperando = Sim.cuadro(t: 100.5, fase: fase)
        XCTAssertEqual(esperando.u, 0)
        XCTAssertTrue(esperando.separada)
        // A medio viaje: ni separada ni fundida.
        let viajando = Sim.cuadro(t: 100 + M.fusionIntroEspera + M.fusionDur * 0.5, fase: fase)
        XCTAssertGreaterThan(viajando.u, 0.05)
        XCTAssertFalse(viajando.separada)
        // Vencida la intro, se comporta como viva (u = 1, settle activo).
        let viva = Sim.cuadro(t: 100 + M.fusionIntroEspera + M.fusionDur + 0.01, fase: fase)
        XCTAssertEqual(viva.u, 1)
        XCTAssertTrue(viva.fundida)
    }

    func test_cuadro_separando_conAnticipacion() {
        let fase = Sim.Fase.separando(desde: 50)
        // La anticipación: sigue fundida pero con squeeze (stretch negativo).
        let ant = Sim.cuadro(t: 50 + M.anticipacion * 0.5, fase: fase)
        XCTAssertEqual(ant.u, 1)
        XCTAssertLessThan(ant.stretch, 0)
        // Al terminar: separada limpia.
        let fin = Sim.cuadro(t: 50 + M.anticipacion + M.fusionDur + 0.01, fase: fase)
        XCTAssertEqual(fin.u, 0)
        XCTAssertTrue(fin.separada)
    }

    func test_cuadro_uniendo_terminaViva() {
        let fase = Sim.Fase.uniendo(desde: 10)
        let fin = Sim.cuadro(t: 10 + M.fusionDur + 0.5, fase: fase)
        XCTAssertEqual(fin.u, 1)
        XCTAssertTrue(fin.fundida)
        let sep = Sim.cuadro(t: 200, fase: .separada)
        XCTAssertTrue(sep.separada)
    }

    func test_bump_viveEnElContacto() {
        XCTAssertGreaterThan(Sim.bumpEn(0.8), 0.95)
        XCTAssertLessThan(Sim.bumpEn(0.2), 0.01)
    }

    // MARK: Partícula (el contrato de la Fase B)

    func test_particula_determinista() {
        let dirs = Sim.fibonacci(G.nEsfera)
        for (i, dir) in dirs.enumerated() where i % 37 == 0 {
            let a = Sim.particula(dir: dir, indice: i, centro: G.centro, radio: 56,
                                  rotacion: 1.23, jitterAmp: 1.1, t: 4.56, alfaK: 0.9,
                                  stretch: 0.1, nivel: 0.78, nivelBajo: false,
                                  capAmbar: true)
            let b = Sim.particula(dir: dir, indice: i, centro: G.centro, radio: 56,
                                  rotacion: 1.23, jitterAmp: 1.1, t: 4.56, alfaK: 0.9,
                                  stretch: 0.1, nivel: 0.78, nivelBajo: false,
                                  capAmbar: true)
            XCTAssertEqual(a, b, "particula(\(i)) no es determinista")
        }
    }

    func test_particula_menisco() {
        // nivel 0.5 → umbral y = 0: una dirección en la banda (y = 0) es menisco.
        let enBanda = Sim.particula(dir: SIMD3(1, 0, 0), indice: 0, centro: G.centro,
                                    radio: 34, rotacion: 0, jitterAmp: 0, t: 0,
                                    nivel: 0.5)
        XCTAssertEqual(enBanda.clase, .menisco)
        // Debajo del nivel (y = +0.5, hacia abajo): líquido base.
        let liquido = Sim.particula(dir: SIMD3(0, 0.5, 0.866), indice: 1, centro: G.centro,
                                    radio: 34, rotacion: 0, jitterAmp: 0, t: 0,
                                    nivel: 0.5)
        XCTAssertEqual(liquido.clase, .base)
        // Encima (y = −0.5): vapor, con el alfa recortado.
        let vapor = Sim.particula(dir: SIMD3(0, -0.5, 0.866), indice: 2, centro: G.centro,
                                  radio: 34, rotacion: 0, jitterAmp: 0, t: 0,
                                  nivel: 0.5)
        XCTAssertEqual(vapor.clase, .vapor)
        XCTAssertLessThan(vapor.alfa, liquido.alfa)
        // Nivel fuera de rango: el líquido habla en rojo.
        let rojo = Sim.particula(dir: SIMD3(0, 0.5, 0.866), indice: 3, centro: G.centro,
                                 radio: 34, rotacion: 0, jitterAmp: 0, t: 0,
                                 nivel: 0.5, nivelBajo: true)
        XCTAssertEqual(rojo.clase, .liquidoBajo)
    }

    func test_particula_capAmbar() {
        // Sin rotación, x > 0.25 ∧ y < −0.15 → casquete ámbar (mira al guardián).
        let cap = Sim.particula(dir: SIMD3(0.8, -0.5, 0.33), indice: 0, centro: G.centro,
                                radio: 56, rotacion: 0, jitterAmp: 0, t: 0, capAmbar: true)
        XCTAssertEqual(cap.clase, .capAmbar)
        let fuera = Sim.particula(dir: SIMD3(-0.8, -0.5, 0.33), indice: 1, centro: G.centro,
                                  radio: 56, rotacion: 0, jitterAmp: 0, t: 0, capAmbar: true)
        XCTAssertEqual(fuera.clase, .base)
    }

    // MARK: Órbitas

    func test_guardian_eclipse() {
        // Con eclipse pleno: queda ATRÁS (z = −1), crecido y pegado a su destino.
        let orb = Sim.guardian(t: 0, eclipse: 1)
        XCTAssertEqual(orb.z, -1, accuracy: 1e-9)
        XCTAssertEqual(orb.radio, G.radioGuardianEclipse, accuracy: 1e-9)
        XCTAssertEqual(orb.centro.y, G.centro.y + G.eclipseOffset.height, accuracy: 0.001)
        XCTAssertEqual(orb.centro.x, G.centro.x + G.eclipseOffset.width, accuracy: 3.5)
        // Sin eclipse: en órbita, radio chico.
        let quieto = Sim.guardian(t: 0, eclipse: 0)
        XCTAssertLessThan(quieto.radio, G.radioGuardianEclipse)
    }

    func test_lunas_distintas() {
        let l1 = Sim.luna(1, t: 2, desgaste: false)
        let l2 = Sim.luna(2, t: 2, desgaste: false)
        XCTAssertNotEqual(l1.centro, l2.centro)
        XCTAssertEqual(Sim.luna(1, t: 2, desgaste: false), l1)   // determinista
    }

    // MARK: Acreción

    func test_espiral_convergeAlCentro() {
        for i in 0..<G.nEspirales {
            let m = Sim.espiral(i, t: 3.3)
            XCTAssertTrue(m.pos.x.isFinite && m.pos.y.isFinite)
            XCTAssertGreaterThanOrEqual(m.alfa, 0.1 - 1e-9)
            XCTAssertLessThanOrEqual(m.alfa, 0.4 + 1e-9)
        }
        XCTAssertEqual(Sim.espiral(5, t: 3.3), Sim.espiral(5, t: 3.3))
    }
}
