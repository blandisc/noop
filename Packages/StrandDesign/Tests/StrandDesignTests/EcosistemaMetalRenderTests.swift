import XCTest
import SwiftUI
@testable import StrandDesign

#if canImport(Metal)
import Metal

/// El shader de Fase B (FER-13) RENDERIZADO de verdad, offscreen. Los tests del plan
/// cubren la coreografía; éstos cubren lo que sólo se ve ejecutando MSL: que el shader
/// compile, que el mapeo pt → clip esté bien (incluida la Y invertida), que el instancing
/// coloque las partículas donde el plan dijo, y que `still` sea determinista.
///
/// Se saltan solos donde no hay GPU o no está el Metal Toolchain (runners de CI sin él):
/// un skip honesto vale más que un test que sólo corre en una laptop.
final class EcosistemaMetalRenderTests: XCTestCase {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria

    private static let ancho = Int(G.lienzo.width)
    private static let alto = Int(G.lienzo.height)

    /// Un cuadro renderizado: cobertura de tinta por píxel (0…1) y color PREMULTIPLICADO
    /// por canal, en fila-mayor.
    private struct Cuadro {
        let alfa: [Float]
        let rojo: [Float]
        let verde: [Float]

        var tinta: Float { alfa.reduce(0, +) }

        /// Rojo contra verde. Es un cociente y no dos sumas sueltas A PROPÓSITO: el blanco
        /// (especular, destello) aporta IGUAL a los dos canales, así que el cociente aísla
        /// el TONO de la tinta. `particulaVerde` (#10694E) da R/G ≈ 0.15; el ámbar de
        /// atención (#C4631F) da ≈ 1.98 — dos órdenes de separación.
        var calidez: Float {
            rojo.reduce(0, +) / max(verde.reduce(0, +), .leastNonzeroMagnitude)
        }

        /// Tinta dentro de un disco (centro y radio en pt) — para preguntar «¿hay materia
        /// AQUÍ?» sin depender de un match pixel a pixel.
        func tinta(cerca centro: CGPoint, radio: CGFloat) -> Float {
            var suma: Float = 0
            for y in 0..<EcosistemaMetalRenderTests.alto {
                for x in 0..<EcosistemaMetalRenderTests.ancho {
                    let dx = CGFloat(x) - centro.x, dy = CGFloat(y) - centro.y
                    if dx * dx + dy * dy <= radio * radio {
                        suma += alfa[y * EcosistemaMetalRenderTests.ancho + x]
                    }
                }
            }
            return suma
        }
    }

    private func renderizar(escena: Sim.Escena, t: TimeInterval) throws -> Cuadro {
        guard let device = MTLCreateSystemDefaultDevice(), let cola = device.makeCommandQueue() else {
            throw XCTSkip("sin GPU de Metal en este entorno")
        }
        guard let url = Bundle.module.url(forResource: "EcosistemaShaders", withExtension: "msl"),
              let fuente = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("no se encontró EcosistemaShaders.msl en el bundle")
        }
        let libreria: MTLLibrary
        do {
            libreria = try device.makeLibrary(source: fuente, options: nil)
        } catch {
            // Sin Metal Toolchain el compilador de MSL no existe: no es un fallo del shader.
            throw XCTSkip("el compilador de MSL no está disponible: \(error)")
        }

        func pipeline(_ vertex: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = try XCTUnwrap(libreria.makeFunction(name: vertex))
            d.fragmentFunction = try XCTUnwrap(libreria.makeFunction(name: "fsTrazo"))
            let a = try XCTUnwrap(d.colorAttachments[0])
            a.pixelFormat = EcosistemaMetal.formato
            a.isBlendingEnabled = true
            a.rgbBlendOperation = .add
            a.alphaBlendOperation = .add
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: d)
        }

        let recursos = EcosistemaMetal.Recursos(device: device, cola: cola,
                                                nube: try pipeline("vsNube"),
                                                nubeMorfo: try pipeline("vsNubeMorfo"),
                                                atomo: try pipeline("vsAtomo"))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: EcosistemaMetal.formato, width: Self.ancho, height: Self.alto,
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        #if os(macOS)
        descriptor.storageMode = .managed
        #endif
        let textura = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        let renderer = EcosistemaMetalRenderer(recursos: recursos)
        renderer.escena = escena
        renderer.t = t
        renderer.paleta = .desde(clima: escena.coreo.tintaClima)
        renderer.renderizar(en: textura)

        var bytes = [UInt8](repeating: 0, count: Self.ancho * Self.alto * 4)
        bytes.withUnsafeMutableBytes { crudo in
            textura.getBytes(crudo.baseAddress!, bytesPerRow: Self.ancho * 4,
                             from: MTLRegionMake2D(0, 0, Self.ancho, Self.alto), mipmapLevel: 0)
        }
        // BGRA: el canal alfa ES la cobertura y el color sale premultiplicado.
        return Cuadro(alfa: stride(from: 3, to: bytes.count, by: 4).map { Float(bytes[$0]) / 255 },
                      rojo: stride(from: 2, to: bytes.count, by: 4).map { Float(bytes[$0]) / 255 },
                      verde: stride(from: 1, to: bytes.count, by: 4).map { Float(bytes[$0]) / 255 })
    }

    private func escena(coreo: Sim.Coreografia = .enRango,
                        fase: Sim.Fase = .viva(desde: 0),
                        still: Bool = false,
                        niveles: [Double?] = [0.7, 0.6],
                        eclipse: Double = 0) -> Sim.Escena {
        Sim.Escena(coreo: coreo, fase: fase, still: still, niveles: niveles,
                   fuera: [false, false], guardianJuntas: false, guardianHueco: false,
                   eclipse: eclipse)
    }

    // MARK: El shader compila y pinta

    func testElShaderCompilaYPintaAlgo() throws {
        let cuadro = try renderizar(escena: escena(), t: 3)
        XCTAssertGreaterThan(cuadro.tinta, 100, "un cuadro vivo tiene materia")
    }

    /// El mapeo pt → clip lleva la Y del lienzo (hacia abajo) a la del clip (hacia arriba).
    /// El guardián partido es la sonda: vive ARRIBA (y = 34). Si el volteo se pierde o se
    /// duplica, aparece abajo (y = 290) y esto truena. El centroide global no sirve para
    /// esto — lunas y guardián en órbita lo jalan lejos del orbe.
    func testLaYDelLienzoVaHaciaAbajo() throws {
        let cuadro = try renderizar(escena: escena(fase: .separada), t: 3)
        let arriba = G.guardianSeparado1
        let espejo = CGPoint(x: arriba.x, y: G.lienzo.height - arriba.y)
        XCTAssertGreaterThan(cuadro.tinta(cerca: arriba, radio: G.radioGuardianSeparado), 10)
        XCTAssertLessThan(cuadro.tinta(cerca: espejo, radio: G.radioGuardianSeparado), 1,
                          "un flip de Y mal puesto pinta el guardián partido abajo")
    }

    /// Y en X no hay espejo: la esfera de REPOSO va a la izquierda (`p1`), no a la derecha.
    func testLaXNoSeEspeja() throws {
        let cuadro = try renderizar(escena: escena(fase: .separada, niveles: [0.9, nil]), t: 0)
        XCTAssertGreaterThan(cuadro.tinta(cerca: G.p1, radio: 24),
                             cuadro.tinta(cerca: CGPoint(x: G.lienzo.width - G.p1.x, y: G.p1.y),
                                          radio: 24) * 0.9)
    }

    /// Instancing: en separado las dos esferas se van a `p1` y `p2`, y el centro queda
    /// hueco. Es la prueba de que cada instancia lee SU dirección y no todas la misma.
    func testSeparadaPintaDosLobulosYVaciaElCentro() throws {
        let cuadro = try renderizar(escena: escena(fase: .separada), t: 3)
        let izq = cuadro.tinta(cerca: G.p1, radio: G.radioSeparada)
        let der = cuadro.tinta(cerca: G.p2, radio: G.radioSeparada)
        let medio = cuadro.tinta(cerca: G.centro, radio: 20)
        XCTAssertGreaterThan(izq, 20)
        XCTAssertGreaterThan(der, 20)
        XCTAssertLessThan(medio, min(izq, der) * 0.25, "el orbe se partió: el centro queda hueco")
    }

    func testFundidaConcentraLaMateriaEnElOrbe() throws {
        let cuadro = try renderizar(escena: escena(), t: 3)
        XCTAssertGreaterThan(cuadro.tinta(cerca: G.centro, radio: G.radioOrbe),
                             cuadro.tinta * 0.5, "fundida: la mayor parte de la tinta ES el orbe")
    }

    /// El modo gauge no es decorativo: un nivel bajo deja materia ARRIBA (vapor, alfa ×0.22)
    /// y un nivel alto la llena. La mitad inferior del orbe debe cargar más tinta con 0.9
    /// que con 0.1.
    func testElNivelDelLiquidoLlenaLaEsfera() throws {
        let bajo = try renderizar(escena: escena(fase: .separada, niveles: [0.1, 0.1]), t: 0)
        let alto = try renderizar(escena: escena(fase: .separada, niveles: [0.95, 0.95]), t: 0)
        XCTAssertGreaterThan(alto.tinta(cerca: G.p1, radio: G.radioSeparada),
                             bajo.tinta(cerca: G.p1, radio: G.radioSeparada) * 1.2,
                             "más nivel ⇒ más líquido opaco y menos vapor")
    }

    /// Reduce Motion: el contrato de FER-10 es el cuadro ASENTADO — una fusión en curso se
    /// lee ya terminada. La vista clava `t = 0` cuando hay `still`; lo que se prueba aquí
    /// es que, con ese `t`, `.formando` y `.viva` pintan EXACTAMENTE lo mismo.
    func testStillPintaElCuadroAsentado() throws {
        let formando = try renderizar(escena: escena(fase: .formando(inicio: 0), still: true), t: 0)
        let viva = try renderizar(escena: escena(fase: .viva(desde: 0), still: true), t: 0)
        XCTAssertTrue(formando.alfa == viva.alfa, "con Reduce Motion la fusión ya ocurrió")
    }

    /// El mismo instante pintado dos veces es el mismo cuadro (nada sin inicializar en el
    /// camino de la GPU) …
    func testElRenderEsDeterminista() throws {
        let a = try renderizar(escena: escena(), t: 3)
        let b = try renderizar(escena: escena(), t: 3)
        XCTAssertTrue(a.alfa == b.alfa)
    }

    /// … y dos instantes distintos NO lo son, si no lo de arriba pasaría por accidente.
    func testVivoSiSeMueve() throws {
        let a = try renderizar(escena: escena(), t: 3)
        let b = try renderizar(escena: escena(), t: 3.5)
        XCTAssertFalse(a.alfa == b.alfa)
    }

    // MARK: El reloj REAL de la app (donde un Float se rompe)
    //
    // `t` es `timeIntervalSinceReferenceDate` (~8.07·10⁸ s). Ahí el ULP de un `Float` vale
    // 32–128 rad: mandar `t` crudo a la GPU congela la rotación ~53 s y colapsa el jitter
    // de 300 partículas a 6 fases. Con `t` chiquito (0…4) el bug es INVISIBLE.
    //
    // Las dos sondas de abajo usan `.separada` A PROPÓSITO: ahí no hay lunas ni motas de
    // tributo, cuyas posiciones se calculan en `Double` en la CPU y se moverían aunque la
    // GPU estuviera congelada — un test sobre la escena fundida PASA con el bug puesto.
    // En separado, todo lo que se pinta sale del shader.

    /// El jitter: medio periodo de `jitterVelocidad` después, el cuadro debe cambiar.
    func testElJitterVibraConElRelojReal() throws {
        let ahora = Date().timeIntervalSinceReferenceDate
        XCTAssertGreaterThan(ahora, 7e8, "premisa del test: el reloj de la app es enorme")
        let quieta = escena(fase: .separada)
        let a = try renderizar(escena: quieta, t: ahora)
        let b = try renderizar(escena: quieta, t: ahora + .pi / LiquidEcosistemaMotion.jitterVelocidad)
        XCTAssertFalse(a.alfa == b.alfa, "el jitter perdió su fase al cruzar a Float")
    }

    /// La rotación, aislada: con `still` el jitter se apaga y los centros quedan fijos, así
    /// que lo ÚNICO que varía con `t` es `rot`. Media vuelta después, el cuadro debe cambiar.
    func testLaRotacionGiraConElRelojReal() throws {
        let ahora = Date().timeIntervalSinceReferenceDate
        let sinJitter = escena(fase: .separada, still: true)
        let a = try renderizar(escena: sinJitter, t: ahora)
        let b = try renderizar(escena: sinJitter,
                               t: ahora + .pi / LiquidEcosistemaMotion.rotacionEsfera)
        XCTAssertFalse(a.alfa == b.alfa, "la rotación perdió su fase al cruzar a Float")
    }

    // MARK: Los campos de COLOR del uniforme

    /// El readback de alfa no ve `colorAmbar` ni el flag `capAmbar`: un desfase de offset
    /// en esos campos del uniforme sería silencioso. El casquete del eclipse es la sonda.
    ///
    /// (`colorBajo` NO tiene sonda equivalente y no puede tenerla: `nivelBajo` solo existe
    /// en desgaste, donde la tinta base ya es `particulaRoja` #963426 y el líquido fuera de
    /// rango es `negativo` #B3402A — R/G 2.88 contra 2.80. Son el mismo tono por diseño, así
    /// que ningún test de color los distingue; su candado es `testLayoutDeLosUniformes`.)
    func testElCasqueteAmbarDelEclipseTiñeLaEsfera() throws {
        let sin = try renderizar(escena: escena(coreo: .atencion(eclipse: true), eclipse: 0), t: 3)
        let con = try renderizar(escena: escena(coreo: .atencion(eclipse: true), eclipse: 1), t: 3)
        // Margen medido: +7.3 % (0.823 → 0.883). El casquete cubre solo el gajo que mira
        // al guardián (x > 0.25 ∧ y < −0.15) y el especular blanco amortigua el cociente,
        // así que la señal real es ésa — no una inundación de ámbar.
        XCTAssertGreaterThan(con.calidez, sin.calidez * 1.05,
                             "el eclipse debe teñir de ámbar el casquete que mira al guardián")
    }

    /// El morfo (FER-19 · C.2) compila, pinta, es determinista y NO duplica materia:
    /// el cuadro a media convergencia queda en el orden del asentado — el crossfade
    /// viejo lo inflaba con una segunda esfera completa encima.
    func testMorfoRenderizaDeterministaYConservaMateria() throws {
        let antU = LiquidEcosistemaMotion.anticipacion * 0.6
        // suave(0.79) ≈ 0.89 → convergencia ≈ 0.55: dentro de la ventana del morfo.
        let t = antU + 0.79 * LiquidEcosistemaMotion.fusionDur
        let plan = Sim.plan(t: t, escena: escena(fase: .uniendo(desde: 0)))
        XCTAssertTrue(plan.contains {
            if case .nubeMorfo = $0 { return true } else { return false }
        }, "el instante elegido debe cruzar la ventana del morfo")
        let a = try renderizar(escena: escena(fase: .uniendo(desde: 0)), t: t)
        let b = try renderizar(escena: escena(fase: .uniendo(desde: 0)), t: t)
        XCTAssertGreaterThan(a.tinta, 100, "el morfo pinta materia")
        XCTAssertEqual(a.tinta, b.tinta, "mismo t ⇒ mismo cuadro (determinismo)")
        let asentado = try renderizar(escena: escena(), t: 3)
        XCTAssertLessThan(a.tinta, asentado.tinta * 1.25,
                          "conservación: el morfo no duplica materia (adiós crossfade)")
        XCTAssertGreaterThan(a.tinta, asentado.tinta * 0.5,
                             "y tampoco la evapora")
    }

    /// Calibrando es otro plan entero (espirales + embrión): que también llegue a la GPU.
    func testCalibrandoTambienRenderiza() throws {
        let cuadro = try renderizar(escena: escena(coreo: .calibrando(noche: 3, total: 5)), t: 2)
        XCTAssertGreaterThan(cuadro.tinta, 50)
        XCTAssertGreaterThan(cuadro.tinta(cerca: G.centro, radio: G.radioEmbrion + 4), 10,
                             "el embrión está en el centro")
    }
}
#endif
