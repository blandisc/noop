import XCTest
import CoreGraphics
@testable import StrandDesign

/// El plan (FER-13) es la coreografía en datos: la MISMA que recorre el Canvas de Fase A y
/// que encodea el shader de Fase B. Estos tests son el contrato entre los dos backends —
/// si el plan cambia, los dos cambian juntos o esto truena.
final class EcosistemaPlanTests: XCTestCase {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria
    typealias M = LiquidEcosistemaMotion

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

    /// FER-22: fundida trae UN solo orbe (jamás dos esferas encimadas) + especular +
    /// las dos lunas decisoras + los dos vigías.
    func testFundidaTraeUnOrbeElEspecularYLasDosLunas() {
        let trazos = Sim.plan(t: 3, escena: escena())
        let esferas = nubes(trazos).filter { $0.n == G.nEsfera }
        XCTAssertEqual(esferas.count, 1, "un solo orbe: nunca se parte ni se dobla")
        XCTAssertEqual(esferas[0].paso, 1)
        XCTAssertEqual(esferas[0].centro.x, G.centro.x, accuracy: 0.001)
        XCTAssertEqual(esferas[0].alfaK, 1, accuracy: 0.001)
        // Sin gauge: el nivel solo se lee camino a / en el estado separado.
        XCTAssertNil(esferas[0].nivel)

        // FER-22: los vigías (dos, azules) no llevan rótulo orbital — sus títulos
        // viven en los overlays del estado separado.
        XCTAssertEqual(rotulos(trazos).sorted { "\($0)" < "\($1)" },
                       [Sim.RotuloOrbital.reposo, .sueno]
                        .sorted { "\($0)" < "\($1)" })
        XCTAssertTrue(trazos.contains { if case .halo = $0 { return true } else { return false } },
                      "el orbe fundido lleva su especular")
    }

    /// El orden de pintado ES la coreografía: lo que va DETRÁS del orbe se encodea
    /// antes. FER-22: DOS vigías en fases opuestas — cada uno se ordena por SU z.
    func testCadaVigiaSeOrdenaPorSuProfundidad() {
        for t in stride(from: 0.0, to: 20.0, by: 0.25) {
            let trazos = Sim.plan(t: t, escena: escena())
            guard let iOrbe = trazos.firstIndex(where: {
                if case .nube(let n) = $0 { return n.n == G.nEsfera } else { return false }
            }) else { return XCTFail("siempre hay orbe") }
            let esperados = (0..<2).map { g in
                Sim.orbita(G.orbitaGuardian,
                           angulo: t * M.orbitaGuardian + M.faseGuardian
                               + Double(g) * .pi,
                           radioBase: G.radioGuardian)
            }
            for (i, tr) in trazos.enumerated() {
                guard case .nube(let n) = tr, n.n == G.nGuardian else { continue }
                let z = esperados.min {
                    hypot($0.centro.x - n.centro.x, $0.centro.y - n.centro.y)
                        < hypot($1.centro.x - n.centro.x, $1.centro.y - n.centro.y)
                }!.z
                if z < 0 {
                    XCTAssertLessThan(i, iOrbe, "z<0 => detrás del orbe (t=\(t))")
                } else {
                    XCTAssertGreaterThan(i, iOrbe, "z>=0 => al frente (t=\(t))")
                }
            }
        }
    }

    // MARK: Separada

    /// FER-22: separado, LAS LUNAS SON LOS MEDIDORES — crecidas a radioSeparada en
    /// p1/p2 con gauge pleno — y el orbe NUNCA se parte: sigue al centro, retrocedido.
    func testSeparadaLasLunasSonLosMedidoresYElOrbeRetrocede() {
        let trazos = Sim.plan(t: 3, escena: escena(fase: .separada, fuera: [true, false]))
        let medidores = nubes(trazos).filter { $0.n == G.nLuna }
        XCTAssertEqual(medidores.count, 2)
        XCTAssertEqual(medidores[0].centro, G.p1)
        XCTAssertEqual(medidores[1].centro, G.p2)
        XCTAssertEqual(medidores[0].radio, G.radioSeparada)
        XCTAssertEqual(medidores[0].nivel, 0.7)
        XCTAssertEqual(medidores[1].nivel, 0.6)
        XCTAssertEqual(medidores[0].nivelMezcla, 1)
        let orbes = nubes(trazos).filter { $0.n == G.nEsfera }
        XCTAssertEqual(orbes.count, 1, "el orbe jamás se parte ni desaparece")
        XCTAssertEqual(orbes[0].centro, G.centro)
        XCTAssertLessThan(orbes[0].alfaK, 0.5, "retrocedido: tenue")
        let vigias = nubes(trazos).filter { $0.n == G.nGuardian }
        XCTAssertEqual(vigias.count, 2)
        XCTAssertEqual(Set(vigias.map(\.centro)),
                       [G.guardianSeparado1, G.guardianSeparado2])
        // Sin especular al fondo (el orbe retrocedido no brilla).
        XCTAssertFalse(trazos.contains { if case .halo = $0 { return true } else { return false } })
    }

    /// FER-22 (mapa de estados, decisión B): una decisora fuera de rango tiñe SU
    /// líquido de rojo en CUALQUIER veredicto — la mala noticia viaja con su luna.
    func testLiquidoRojoSiempreQueLaSenalEsteFuera() {
        let verde = Sim.plan(t: 1, escena: escena(fase: .separada, fuera: [true, false]))
        XCTAssertEqual(nubes(verde).filter { $0.nivelBajo }.count, 1)
        let rojo = Sim.plan(t: 1, escena: escena(coreo: .desgaste, fase: .separada,
                                                 fuera: [true, false]))
        XCTAssertEqual(nubes(rojo).filter { $0.nivelBajo }.count, 1)
    }

    // MARK: Honestidad del dato

    /// FER-22: las lunas son cuerpos PERMANENTES — sin dato no desaparecen, se
    /// vuelven huecas (ralas). La honestidad vive en la densidad, no en la ausencia.
    func testSinDatoLasLunasSonHuecasPeroExisten() {
        let trazos = Sim.plan(t: 3, escena: escena(niveles: [nil, nil]))
        let lunas = nubes(trazos).filter { $0.n == G.nLuna }
        XCTAssertEqual(lunas.count, 2)
        XCTAssertTrue(lunas.allSatisfy { $0.paso == 3 }, "sin dato = materia RALA")
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

    /// `still` = cuadro asentado: sin destello de contacto y sin brillos de cruce. Las
    /// ESTELAS orbitales sí existen en still — como anillos tenues completos y
    /// estáticos (el contrato del «sistema orbital», sesión /inject 2026-08-02, que
    /// retiró el tributo): el plan de un t es idéntico al de cualquier otro t.
    func testStillEstelasEstaticasSinDestello() {
        let vivo = Sim.plan(t: 4, escena: escena())
        XCTAssertTrue(vivo.contains { if case .disco = $0 { return true } else { return false } },
                      "vivo: las estelas orbitales dejan motas")
        let quieto = Sim.plan(t: 4, escena: escena(still: true))
        // Sin destellos ni brillos de cruce en still: cero anillos.
        XCTAssertFalse(quieto.contains { if case .anillo = $0 { return true } else { return false } })
        // Las estelas de still existen como anillo tenue: hay discos, y ninguno
        // rebasa el alfa de susurro (el dato manda, la órbita susurra).
        let discos = quieto.compactMap { t -> Double? in
            if case .disco(_, _, _, let alfa) = t { return alfa } else { return nil }
        }
        XCTAssertFalse(discos.isEmpty, "still: el anillo estático debe existir")
        XCTAssertTrue(discos.allSatisfy { $0 <= 0.25 },
                      "still: todo disco es susurro (≤ 0.25 — estelas y conexiones)")
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
    // MARK: Morfo (FER-19 · C.2 «Materia continua»)

    private func nubeMorfable(rotacion: Double,
                              centro: CGPoint = CGPoint(x: 100, y: 100)) -> Sim.Nube {
        Sim.Nube(centro: centro, radio: 40, rotacion: rotacion, jitterAmp: 0.4, alfaK: 1,
                 stretch: 0, nivel: 0.6, nivelBajo: false, capAmbar: false,
                 n: G.nEsfera, paso: 1, tinta: .clima)
    }

    /// El contrato del morfo: en mezcla 0/1 es BIT-IGUAL a `particula` simple, y a 0.5
    /// la posición/alfa son exactamente el punto medio (lerp lineal por índice).
    func testMorfoEquivalenciaEnExtremosYLinealidad() {
        let a = nubeMorfable(rotacion: 0.4)
        let b = nubeMorfable(rotacion: 1.9, centro: CGPoint(x: 140, y: 90))
        let dirs = Sim.fibonacci(G.nEsfera)
        func simple(_ n: Sim.Nube, _ i: Int) -> Sim.Particula {
            Sim.particula(dir: dirs[i], indice: i, centro: n.centro, radio: n.radio,
                          rotacion: n.rotacion, jitterAmp: n.jitterAmp, t: 2,
                          alfaK: n.alfaK, stretch: n.stretch, nivel: n.nivel,
                          nivelMezcla: n.nivelMezcla, nivelBajo: n.nivelBajo,
                          capAmbar: n.capAmbar)
        }
        for i in stride(from: 0, to: G.nEsfera, by: 37) {
            let pa = simple(a, i), pb = simple(b, i)
            XCTAssertEqual(Sim.particulaMorfo(dir: dirs[i], indice: i,
                                              a: a, b: b, mezcla: 0, t: 2), pa)
            XCTAssertEqual(Sim.particulaMorfo(dir: dirs[i], indice: i,
                                              a: a, b: b, mezcla: 1, t: 2), pb)
            let pm = Sim.particulaMorfo(dir: dirs[i], indice: i, a: a, b: b,
                                        mezcla: 0.5, t: 2)
            XCTAssertEqual(pm.pos.x, (pa.pos.x + pb.pos.x) / 2, accuracy: 1e-9)
            XCTAssertEqual(pm.pos.y, (pa.pos.y + pb.pos.y) / 2, accuracy: 1e-9)
            XCTAssertEqual(pm.alfa, (pa.alfa + pb.alfa) / 2, accuracy: 1e-12)
        }
    }

    /// FER-22: a media apertura las LUNAS viajan — creciendo y revelando su gauge —
    /// el orbe sigue entero al centro, y NO existe morfo alguno fuera de la graduación.
    func testAperturaLasLunasViajanSinMorfo() {
        let fase = Sim.Fase.separando(desde: 0)
        let ant = LiquidEcosistemaMotion.anticipacion
        var visto = false
        for paso in 0...60 {
            let t = ant + Double(paso) / 60 * LiquidEcosistemaMotion.fusionDur
            let trazos = Sim.plan(t: t, escena: escena(fase: fase))
            let medidores = nubes(trazos).filter { $0.n == G.nLuna }
            guard let m = medidores.first,
                  m.nivelMezcla > 0.2, m.nivelMezcla < 0.8 else { continue }
            visto = true
            XCTAssertEqual(medidores.count, 2)
            XCTAssertGreaterThan(m.radio, G.radioLuna1)
            XCTAssertLessThan(m.radio, G.radioSeparada)
            XCTAssertEqual(nubes(trazos).filter { $0.n == G.nEsfera }.count, 1,
                           "el orbe no se parte ni a medio viaje")
            XCTAssertFalse(trazos.contains {
                if case .nubeMorfo = $0 { return true } else { return false }
            }, "sin morfos fuera de la graduación")
        }
        XCTAssertTrue(visto, "el barrido debió cruzar la ventana de apertura")
    }

    /// Reduce Motion jamás ve un morfo: los cuadros asentados son configuraciones puras.
    func testStillSinMorfo() {
        for fase: Sim.Fase in [.viva(desde: 0), .separada, .uniendo(desde: 0),
                               .separando(desde: 0), .formando(inicio: 0)] {
            let trazos = Sim.plan(t: 3, escena: escena(fase: fase, still: true))
            XCTAssertFalse(trazos.contains {
                if case .nubeMorfo = $0 { return true } else { return false }
            })
        }
    }

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
        let f = EcosistemaFisicaU(t: 0)
        XCTAssertEqual(f.aplastamiento, Float(G.aplastamiento))
        XCTAssertEqual(f.bandaMenisco, Float(G.bandaMenisco))
        XCTAssertEqual(f.pisoNivel, Float(G.pisoNivel))
        XCTAssertEqual(f.ondaAmplitud, Float(LiquidEcosistemaMotion.nivelOndaAmplitud))
    }

    // MARK: Las fases que cruzan a la GPU

    /// El reloj de la app (`timeIntervalSinceReferenceDate`, ~8.07·10⁸ s) NO cabe en un
    /// `Float` como ángulo: el ULP a esa magnitud vale decenas de radianes. Todo lo que
    /// entra a un `sin`/`cos` del shader viaja reducido a [0, 2π) en `Double`.
    func testLasFasesLleganReducidasYConResolucionEnFloat() {
        let ahora = Date().timeIntervalSinceReferenceDate
        for k in [LiquidEcosistemaMotion.jitterVelocidad,
                  LiquidEcosistemaMotion.nivelOndaVelocidad,
                  LiquidEcosistemaMotion.rotacionEsfera] {
            let crudo = ahora * k
            let reducido = Sim.fase(crudo)
            XCTAssertGreaterThanOrEqual(reducido, 0)
            XCTAssertLessThan(reducido, 2 * .pi)
            // Mismo ángulo (difieren en múltiplos de 2π) …
            XCTAssertEqual(sin(reducido), sin(crudo), accuracy: 1e-6)
            // … pero UNO cabe en Float y el otro no: un cuadro (1/60 s) después, el
            // ángulo crudo en Float ni se mueve.
            let sigue = Sim.fase((ahora + 1.0 / 60) * k)
            XCTAssertNotEqual(Float(reducido), Float(sigue))
            XCTAssertEqual(Float(crudo), Float((ahora + 1.0 / 60) * k),
                           "premisa: en Float el ángulo crudo se congela — por eso se reduce")
        }
    }

    func testFaseNormalizaAngulosNegativos() {
        // `rotacionLuna2` y `rotacionGuardian` giran al revés: la fase no puede salir < 0.
        let r = Sim.fase(-3 * Double.pi)
        XCTAssertEqual(r, Double.pi, accuracy: 1e-9)
        XCTAssertEqual(Sim.fase(0), 0)
    }

    // MARK: C.3 Acrecion unificada + graduacion (FER-20)

    /// Reduce Motion en calibrando = SOLO el embrion asentado: cero motas cayendo
    /// (congelarlas a media caida era un cuadro deshonesto).
    func testAcrecionStillSoloEmbrion() {
        let quieto = Sim.plan(t: 5, escena: escena(coreo: .calibrando(noche: 3, total: 7),
                                                   still: true))
        XCTAssertFalse(quieto.contains { if case .disco = $0 { return true } else { return false } })
        XCTAssertEqual(nubes(quieto).count, 1)
    }

    /// El embrion usa la MISMA esfera fuente del veredicto (continuidad entre dias por
    /// construccion) y el plan vivo trae exactamente nEspirales motas.
    func testEmbrionEsLaEsferaDelVeredicto() {
        let vivo = Sim.plan(t: 5, escena: escena(coreo: .calibrando(noche: 3, total: 7)))
        let embrion = nubes(vivo)[0]
        XCTAssertEqual(embrion.n, G.nEsfera)
        XCTAssertEqual(embrion.paso, 1)
        XCTAssertEqual(embrion.centro, G.centro)
        let discos = vivo.filter { if case .disco = $0 { return true } else { return false } }
        XCTAssertEqual(discos.count, G.nEspirales)
    }

    /// La graduacion en vivo es UN morfo embrion->orbe (mismo conteo, la ley C.2):
    /// las dos decisoras nunca aparecen, y el sequito entra al compas de g.
    func testGraduacionEsMorfoDelEmbrionAlOrbe() {
        var e = escena(fase: .viva(desde: 0))
        e.graduacion = 0.5
        let trazos = Sim.plan(t: 3, escena: e)
        let morfos = trazos.compactMap { tr -> (Sim.Nube, Sim.Nube, Double)? in
            if case .nubeMorfo(let a, let b, let m) = tr { return (a, b, m) }
            return nil
        }
        XCTAssertEqual(morfos.count, 1)
        let (a, b, _) = morfos[0]
        XCTAssertEqual(a.radio, G.radioEmbrion, "la config A es el embrion")
        XCTAssertGreaterThan(b.radio, 40, "la config B es el orbe del veredicto")
        XCTAssertEqual(a.n, b.n)
        XCTAssertTrue(nubes(trazos).filter { $0.n == G.nEsfera }.isEmpty,
                      "las decisoras nunca aparecen durante la graduacion")
    }

    /// Con Reduce Motion la graduacion no existe: corte honesto al cuadro asentado.
    func testGraduacionStillEsCorteHonesto() {
        var e = escena(fase: .viva(desde: 0), still: true)
        e.graduacion = 0.5
        let trazos = Sim.plan(t: 3, escena: e)
        XCTAssertFalse(trazos.contains {
            if case .nubeMorfo = $0 { return true } else { return false }
        })
    }


    // MARK: C.4 Exhalacion + siembra (FER-21)

    /// El soplo hacia la pastilla: determinista, acotado, y solo en la ventana viva.
    func testExhalacionDeterministaYAcotada() {
        var e = escena(fase: .viva(desde: 0))
        e.exhalacion = 0.5
        let a = Sim.plan(t: 3, escena: e)
        let b = Sim.plan(t: 3, escena: e)
        XCTAssertEqual(a, b, "mismo (t, escena) => mismo plan")
        // El soplo agrega discos extra respecto al mismo cuadro sin exhalar.
        var e0 = escena(fase: .viva(desde: 0))
        e0.exhalacion = nil
        let sin = Sim.plan(t: 3, escena: e0)
        func discos(_ tr: [Sim.Trazo]) -> Int {
            tr.filter { if case .disco = $0 { return true } else { return false } }.count
        }
        let extra = discos(a) - discos(sin)
        XCTAssertGreaterThan(extra, 0, "el soplo existe")
        XCTAssertLessThanOrEqual(extra, 18, "presupuesto del soplo")
        // Fuera de la ventana (0 o 1) el soplo no se fabrica.
        e.exhalacion = 1
        XCTAssertEqual(discos(Sim.plan(t: 3, escena: e)), discos(sin))
    }

    /// Reduce Motion jamas ve el soplo.
    func testExhalacionStillNoExiste() {
        var e = escena(fase: .viva(desde: 0), still: true)
        e.exhalacion = 0.5
        var e0 = escena(fase: .viva(desde: 0), still: true)
        e0.exhalacion = nil
        XCTAssertEqual(Sim.plan(t: 3, escena: e), Sim.plan(t: 3, escena: e0))
    }

    /// La constelacion de la siembra es pura: misma semilla => mismos puntos,
    /// dentro del presupuesto y del lienzo normalizado.
    func testSiembraPuntosDeterministasYAcotados() {
        let a = LiquidSiembraMotas.puntos(semilla: 7, cuenta: 70)
        let b = LiquidSiembraMotas.puntos(semilla: 7, cuenta: 70)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 70)
        for p in a {
            XCTAssertTrue((0...1).contains(p.destinoX) && (0...1).contains(p.destinoY))
            XCTAssertTrue((0...1).contains(p.origenX))
            XCTAssertTrue(p.retraso >= 0 && p.retraso <= LiquidSiembraMotas.Receta.escalon)
        }
        XCTAssertNotEqual(a, LiquidSiembraMotas.puntos(semilla: 8, cuenta: 70),
                          "semillas distintas => constelaciones distintas")
    }

}
