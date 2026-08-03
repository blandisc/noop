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

    /// La reunión es seamless: u jamás sobrepasa 1 (los centros no se cruzan) y el
    /// VIAJE no lleva stretch. La micro-anticipación previa (oleada «costuras»,
    /// /inject 2026-08-02) sí lleva squeeze — es el gesto gemelo de la separación:
    /// u se queda en 0 mientras las esferas toman aire, y solo entonces viajan.
    func test_cuadro_uniendo_sinSobrepasoNiStretchEnViaje() {
        let fase = Sim.Fase.uniendo(desde: 0)
        let antU = M.anticipacion * 0.6
        // Anticipación: u clavada en 0, squeeze (stretch ≤ 0) permitido.
        for paso in 0...10 {
            let c = Sim.cuadro(t: Double(paso) / 10 * antU * 0.999, fase: fase)
            XCTAssertEqual(c.u, 0, "en la anticipación aún no hay viaje")
            XCTAssertLessThanOrEqual(c.stretch, 0, "la anticipación inhala, no estira")
        }
        // Viaje: monótono, sin sobrepaso, sin stretch.
        var previo = -1.0
        for paso in 0...40 {
            let c = Sim.cuadro(t: antU + Double(paso) / 40 * M.fusionDur, fase: fase)
            XCTAssertGreaterThanOrEqual(c.u, 0)
            XCTAssertLessThanOrEqual(c.u, 1)
            XCTAssertGreaterThanOrEqual(c.u, previo, "u debe ser monótona (sin rebotes)")
            XCTAssertEqual(c.stretch, 0)
            previo = c.u
        }
    }

    // MARK: Tributo (las lunas alimentan el orbe)

    func test_tributo_deterministaYAbsorbido() {
        let luna = CGPoint(x: 88, y: 122)
        let a = Sim.tributo(2, t: 7.25, luna: luna, radioLuna: 13)
        let b = Sim.tributo(2, t: 7.25, luna: luna, radioLuna: 13)
        XCTAssertEqual(a, b, "mismo instante → misma mota (sin estado)")
        // Alfa acotada y con fade (nace y muere apagándose).
        for k in 0..<M.tributoParticulas {
            for paso in 0...20 {
                let m = Sim.tributo(k, t: Double(paso) * 0.17, luna: luna, radioLuna: 13)
                XCTAssertGreaterThanOrEqual(m.alfa, 0)
                XCTAssertLessThanOrEqual(m.alfa, 0.71)
                XCTAssertGreaterThan(m.tamano, 0)
            }
        }
        // El viaje ACERCA la mota al orbe: comparar dos fracciones del mismo ciclo.
        // fr = frac(t/periodo): t1 → fr≈0.15, t2 → fr≈0.75 (misma mota k=0).
        let t1 = M.tributoPeriodo * 0.15, t2 = M.tributoPeriodo * 0.75
        let temprano = Sim.tributo(0, t: t1, luna: luna, radioLuna: 13)
        let tarde = Sim.tributo(0, t: t2, luna: luna, radioLuna: 13)
        func dist(_ p: CGPoint) -> Double {
            let dx = Double(p.x - Sim.Geometria.centro.x)
            let dy = Double(p.y - Sim.Geometria.centro.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        XCTAssertLessThan(dist(tarde.pos), dist(temprano.pos),
                          "la mota viaja de la luna HACIA el orbe")
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

    // MARK: Fase efectiva (una fase vencida ES su sucesora al decidir un tap)

    func test_faseEfectiva_resuelveVencidas() {
        let viaje = M.anticipacion + M.fusionDur
        // Separando vencida → separada (el primer tap de unir debe ACTUAR, no
        // re-etiquetar — el tap muerto cazado en simulador).
        XCTAssertEqual(Sim.faseEfectiva(.separando(desde: 0), t: viaje + 5), .separada)
        // A media separación sigue siendo separando (tap = completar al instante).
        XCTAssertEqual(Sim.faseEfectiva(.separando(desde: 0), t: viaje * 0.4),
                       .separando(desde: 0))
        // Uniendo vencida → viva (el fin incluye la micro-anticipación de la reunión);
        // formando vencida → viva.
        XCTAssertEqual(Sim.faseEfectiva(.uniendo(desde: 0),
                                        t: M.anticipacion * 0.6 + M.fusionDur + 3),
                       .viva(desde: M.anticipacion * 0.6 + M.fusionDur))
        XCTAssertEqual(
            Sim.faseEfectiva(.formando(inicio: 0), t: M.fusionIntroEspera + M.fusionDur + 1),
            .viva(desde: M.fusionIntroEspera + M.fusionDur))
        // Los estados de reposo son puntos fijos.
        XCTAssertEqual(Sim.faseEfectiva(.separada, t: 99), .separada)
        XCTAssertEqual(Sim.faseEfectiva(.viva(desde: 2), t: 99), .viva(desde: 2))
    }

    // MARK: C.3 Acrecion unificada (FER-20)

    private var embrionPrueba: Sim.Nube {
        Sim.Nube(centro: G.centro, radio: G.radioEmbrion, rotacion: 1.2, jitterAmp: 0.5,
                 alfaK: 0.9, stretch: 0, nivel: 0.5, nivelBajo: false, capAmbar: false,
                 n: G.nEsfera, paso: 1, tinta: .clima)
    }

    /// El contrato del aterrizaje: en ph -> 1 la mota COINCIDE con su particula del
    /// embrion (misma t: rotacion, jitter y ola incluidos). Nada muere en el aire.
    func test_acrecion_aterrizaEnParticulaDelEmbrion() {
        let e = embrionPrueba
        for i in [0, 7, 19, 33] {
            // t tal que ph(i) este casi en 1: ph = frac(t*caida + i*0.0294).
            let base = Double(i) * 0.0294
            let t = (ceil(base) - base + 0.999) / LiquidEcosistemaMotion.acrecionCaida
            let ph = (t * LiquidEcosistemaMotion.acrecionCaida + base)
                .truncatingRemainder(dividingBy: 1)
            XCTAssertGreaterThan(ph, 0.99, "el instante elegido debe estar aterrizando")
            let m = Sim.motaAcrecion(i, t: t, embrion: e, nivel: 0.5)
            let d = Sim.acrecionDestino(i, t: t, nivel: 0.5)
            let pd = Sim.particula(dir: Sim.direccion(d, de: e.n), indice: d,
                                   centro: e.centro, radio: e.radio, rotacion: e.rotacion,
                                   jitterAmp: e.jitterAmp, t: t, alfaK: e.alfaK,
                                   stretch: 0, nivel: e.nivel, nivelBajo: false)
            XCTAssertEqual(m.pos.x, pd.pos.x, accuracy: 0.5)
            XCTAssertEqual(m.pos.y, pd.pos.y, accuracy: 0.5)
        }
    }

    /// El remapeo es determinista y SOLO alimenta materia liquida (prefijo fibonacci):
    /// jamas vapor, y sin division por cero en los extremos de nivel.
    func test_acrecionDestino_deterministaYSoloLiquido() {
        for nivel in [0.0, 0.08, 0.5, 1.0] {
            let nLiquido = max(1, Int(Double(G.nEsfera) * max(G.pisoNivel, min(1, nivel))))
            for i in 0..<G.nEspirales {
                for t in stride(from: 0.0, to: 400, by: 37.7) {
                    let d = Sim.acrecionDestino(i, t: t, nivel: nivel)
                    XCTAssertEqual(d, Sim.acrecionDestino(i, t: t, nivel: nivel))
                    XCTAssertGreaterThanOrEqual(d, 0)
                    XCTAssertLessThan(d, nLiquido, "nivel \(nivel): indice en vapor")
                }
            }
        }
    }

    /// Antes del umbral de aterrizaje la mota ES la espiral clasica, intacta.
    func test_acrecion_antesDelAterrizajeEsLaEspiral() {
        let e = embrionPrueba
        for i in [2, 11] {
            let base = Double(i) * 0.0294
            let t = (ceil(base) - base + 0.3) / LiquidEcosistemaMotion.acrecionCaida
            let m = Sim.motaAcrecion(i, t: t, embrion: e, nivel: 0.5)
            let cruda = Sim.espiral(i, t: t)
            XCTAssertEqual(m.pos, cruda.pos)
            XCTAssertEqual(m.alfa, cruda.alfa)
        }
    }

}
