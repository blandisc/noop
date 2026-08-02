import XCTest
import CoreGraphics
@testable import StrandDesign

/// El plan (FER-13) es la coreografía en datos: la MISMA que recorre el Canvas de Fase A y
/// que encodea el shader de Fase B. Estos tests son el contrato entre los dos backends —
/// si el plan cambia, los dos cambian juntos o esto truena.
final class EcosistemaPlanTests: XCTestCase {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria

    private func escena(coreo: Sim.Coreografia = .enRango,
                        fase: Sim.Fase = .viva(desde: 0),
                        still: Bool = false,
                        niveles: [Double?] = [0.7, 0.6],
                        fuera: [Bool] = [false, false],
                        guardianJuntas: Bool = false,
                        guardianHueco: Bool = false,
                        eclipse: Double = 0) -> Sim.Escena {
        Sim.Escena(coreo: coreo, fase: fase, still: still, niveles: niveles, fuera: fuera,
                   guardianJuntas: guardianJuntas, guardianHueco: guardianHueco,
                   eclipse: eclipse)
    }

    private func nubes(_ trazos: [Sim.Trazo]) -> [Sim.Nube] {
        trazos.compactMap { if case .nube(let n) = $0 { return n } else { return nil } }
    }

    private func rotulos(_ trazos: [Sim.Trazo]) -> [Sim.RotuloOrbital] {
        trazos.compactMap { if case .rotulo(let r, _, _) = $0 { return r } else { return nil } }
    }

    // MARK: El índice del shader nunca se sale de la esfera fuente

    /// `cuenta` y `paso` son el contrato con `vsNube`: la partícula `i` lee la dirección
    /// `i·paso`, así que `(cuenta − 1)·paso` DEBE caer dentro de `n`. Si esto se rompe, el
    /// shader lee basura (Swift al menos crashea en el Canvas; la GPU no avisa).
    func testIndiceDeParticulaSiempreDentroDeLaEsferaFuente() {
        for (n, paso) in [(G.nEsfera, 1), (G.nLuna, 1), (G.nLuna, 3),
                          (G.nGuardian, 1), (G.nGuardian, 2)] {
            let nube = Sim.Nube(centro: .zero, radio: 10, rotacion: 0, jitterAmp: 0, alfaK: 1,
                                stretch: 0, nivel: nil, nivelBajo: false, capAmbar: false,
                                n: n, paso: paso, tinta: .clima)
            XCTAssertGreaterThan(nube.cuenta, 0)
            XCTAssertLessThan((nube.cuenta - 1) * paso, n,
                              "n=\(n) paso=\(paso) se sale de la esfera fuente")
        }
    }

    /// Las variantes ralas son las MISMAS que filtraba el Canvas de Fase A
    /// (`offset % 3 == 0` en las lunas, `offset % 2 == 0` en el guardián).
    func testCuentaDeLasVariantesRalas() {
        let luna = Sim.Nube(centro: .zero, radio: 1, rotacion: 0, jitterAmp: 0, alfaK: 1,
                            stretch: 0, nivel: nil, nivelBajo: false, capAmbar: false,
                            n: G.nLuna, paso: 3, tinta: .clima)
        let guardian = Sim.Nube(centro: .zero, radio: 1, rotacion: 0, jitterAmp: 0, alfaK: 1,
                                stretch: 0, nivel: nil, nivelBajo: false, capAmbar: false,
                                n: G.nGuardian, paso: 2, tinta: .clima)
        XCTAssertEqual(luna.cuenta, 30)
        XCTAssertEqual(guardian.cuenta, 35)
    }

    // MARK: Fundida y viva

    func testFundidaTraeDosEsferasElEspecularYLasDosLunas() {
        let trazos = Sim.plan(t: 3, escena: escena())
        let esferas = nubes(trazos).filter { $0.n == G.nEsfera }
        XCTAssertEqual(esferas.count, 2)
        XCTAssertEqual(esferas.map(\.paso), [1, 1])
        // Fundida: las dos esferas comparten centro (el orbe).
        XCTAssertEqual(esferas[0].centro.x, G.centro.x, accuracy: 0.001)
        XCTAssertEqual(esferas[1].centro.x, G.centro.x, accuracy: 0.001)
        // Sin gauge: el nivel solo se lee en el estado separado.
        XCTAssertNil(esferas[0].nivel)

        XCTAssertEqual(rotulos(trazos).sorted { "\($0)" < "\($1)" },
                       [Sim.RotuloOrbital.guardian, .reposo, .sueno]
                        .sorted { "\($0)" < "\($1)" })
        XCTAssertTrue(trazos.contains { if case .halo = $0 { return true } else { return false } },
                      "el orbe fundido lleva su especular")
    }

    /// El orden de pintado ES la coreografía: lo que va DETRÁS del orbe se encodea antes.
    func testElGuardianDetrasSeDibujaAntesQueLasEsferas() {
        // `faseGuardian` = 2.4 rad ⇒ sin(2.4) > 0 (al frente) y media órbita después, atrás.
        for t in stride(from: 0.0, to: 20.0, by: 0.25) {
            let trazos = Sim.plan(t: t, escena: escena())
            guard let iEsfera = trazos.firstIndex(where: {
                if case .nube(let n) = $0 { return n.n == G.nEsfera } else { return false }
            }) else { return XCTFail("siempre hay esferas decisoras") }
            let iGuardian = trazos.firstIndex {
                if case .nube(let n) = $0 { return n.n == G.nGuardian } else { return false }
            }
            guard let iGuardian else { continue }
            let z = Sim.guardian(t: t, eclipse: 0).z
            if z < 0 {
                XCTAssertLessThan(iGuardian, iEsfera, "z<0 ⇒ el guardián va detrás (t=\(t))")
            } else {
                XCTAssertGreaterThan(iGuardian, iEsfera, "z≥0 ⇒ el guardián va al frente (t=\(t))")
            }
        }
    }

    // MARK: Separada

    func testSeparadaAbreElGaugeYParteAlGuardianEnDos() {
        let trazos = Sim.plan(t: 3, escena: escena(fase: .separada, fuera: [true, false]))
        let esferas = nubes(trazos).filter { $0.n == G.nEsfera }
        XCTAssertEqual(esferas.count, 2)
        XCTAssertEqual(esferas[0].nivel, 0.7)
        XCTAssertEqual(esferas[1].nivel, 0.6)
        XCTAssertEqual(esferas[0].centro, G.p1)
        XCTAssertEqual(esferas[1].centro, G.p2)
        // El guardián se parte en dos mini-orbes y abandona su órbita.
        let guardianes = nubes(trazos).filter { $0.n == G.nGuardian }
        XCTAssertEqual(guardianes.count, 2)
        XCTAssertEqual(Set(guardianes.map(\.centro)),
                       [G.guardianSeparado1, G.guardianSeparado2])
        // Sin orbe fundido no hay lunas, ni especular.
        XCTAssertTrue(nubes(trazos).filter { $0.n == G.nLuna }.isEmpty)
        XCTAssertFalse(trazos.contains { if case .halo = $0 { return true } else { return false } })
    }

    /// El líquido rojo es de DESGASTE: en verde, una señal fuera de rango no tiñe el gauge.
    func testLiquidoBajoSoloEnDesgaste() {
        let verde = Sim.plan(t: 1, escena: escena(fase: .separada, fuera: [true, false]))
        XCTAssertFalse(nubes(verde).contains { $0.nivelBajo })
        let rojo = Sim.plan(t: 1, escena: escena(coreo: .desgaste, fase: .separada,
                                                 fuera: [true, false]))
        XCTAssertEqual(nubes(rojo).filter { $0.nivelBajo }.count, 1)
    }

    // MARK: Honestidad del dato

    func testSinDatoEnNingunaSenalNoSeFabricanLunas() {
        let trazos = Sim.plan(t: 3, escena: escena(niveles: [nil, nil]))
        XCTAssertTrue(nubes(trazos).filter { $0.n == G.nLuna }.isEmpty)
        XCTAssertFalse(rotulos(trazos).contains(.reposo))
    }

    func testUnaSolaSenalConDatoDejaLaOtraLunaHueca() {
        let trazos = Sim.plan(t: 3, escena: escena(niveles: [0.7, nil]))
        let lunas = nubes(trazos).filter { $0.n == G.nLuna }
        XCTAssertEqual(lunas.count, 2)
        XCTAssertEqual(lunas.filter { $0.paso == 3 }.count, 1, "la luna sin dato es RALA")
    }

    func testElGuardianHuecoEsRalo() {
        let trazos = Sim.plan(t: 3, escena: escena(guardianHueco: true))
        let guardianes = nubes(trazos).filter { $0.n == G.nGuardian }
        XCTAssertFalse(guardianes.isEmpty)
        XCTAssertTrue(guardianes.allSatisfy { $0.paso == 2 })
    }

    // MARK: Reduce Motion

    /// `still` = cuadro asentado: sin chorro de tributo y sin destello de contacto — y el
    /// plan de t = 0 es idéntico al de cualquier otro t (el contrato de FER-10).
    func testStillNoFabricaTributoNiDestello() {
        let vivo = Sim.plan(t: 4, escena: escena())
        XCTAssertTrue(vivo.contains { if case .disco = $0 { return true } else { return false } },
                      "vivo: las lunas tributan")
        let quieto = Sim.plan(t: 4, escena: escena(still: true))
        XCTAssertFalse(quieto.contains { if case .disco = $0 { return true } else { return false } })
    }

    func testStillEnFormandoSeLeeYaFundido() {
        let quieto = Sim.plan(t: 0, escena: escena(fase: .formando(inicio: 0), still: true))
        let esferas = nubes(quieto).filter { $0.n == G.nEsfera }
        XCTAssertEqual(esferas[0].centro.x, G.centro.x, accuracy: 0.001,
                       "con Reduce Motion la fusión ya ocurrió")
    }

    // MARK: Calibrando

    func testCalibrandoEsAcrecionMasEmbrion() {
        let trazos = Sim.plan(t: 2, escena: escena(coreo: .calibrando(noche: 3, total: 5)))
        let discos = trazos.filter { if case .disco = $0 { return true } else { return false } }
        XCTAssertEqual(discos.count, G.nEspirales)
        let embrion = nubes(trazos)
        XCTAssertEqual(embrion.count, 1)
        XCTAssertEqual(embrion[0].nivel, 0.6, "el nivel del embrión ES noche/total")
        XCTAssertTrue(rotulos(trazos).isEmpty, "calibrando no tiene séquito que rotular")
    }

    // MARK: El reflejo Swift ↔ Metal

    /// Los uniformes se pasan con `setVertexBytes`: si el layout de Swift deja de calzar
    /// con el de `EcosistemaShaders.metal`, el shader lee campos corridos y no hay error —
    /// solo un héroe roto. Estos tamaños son el candado.
    func testLayoutDeLosUniformes() {
        XCTAssertEqual(MemoryLayout<EcosistemaFisicaU>.stride, 32)
        XCTAssertEqual(MemoryLayout<EcosistemaNubeU>.stride, 112)
        XCTAssertEqual(MemoryLayout<EcosistemaAtomoU>.stride, 48)
        XCTAssertEqual(MemoryLayout<EcosistemaMarcoU>.stride, 16)
        // Y un draw de átomos debe caber en el límite de 4 KB de `setVertexBytes`.
        XCTAssertLessThanOrEqual(MemoryLayout<EcosistemaAtomoU>.stride * 80, 4096)
    }

    /// La física que viaja al shader sale de los MISMOS tokens que usa el Canvas.
    func testLaFisicaDelShaderSaleDeLosTokens() {
        let f = EcosistemaFisicaU.tokens
        XCTAssertEqual(f.aplastamiento, Float(G.aplastamiento))
        XCTAssertEqual(f.bandaMenisco, Float(G.bandaMenisco))
        XCTAssertEqual(f.pisoNivel, Float(G.pisoNivel))
        XCTAssertEqual(f.jitterVelocidad, Float(LiquidEcosistemaMotion.jitterVelocidad))
        XCTAssertEqual(f.ondaVelocidad, Float(LiquidEcosistemaMotion.nivelOndaVelocidad))
        XCTAssertEqual(f.ondaAmplitud, Float(LiquidEcosistemaMotion.nivelOndaAmplitud))
    }
}
