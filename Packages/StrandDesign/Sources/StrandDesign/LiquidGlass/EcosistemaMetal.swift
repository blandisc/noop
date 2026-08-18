import SwiftUI

import simd

// MARK: - Uniformes (reflejo campo a campo de `EcosistemaShaders.metal`)

/// Las constantes de `particula(...)` que el shader NO puede inventarse: llegan de
/// `Geometria` / `LiquidEcosistemaMotion`, los mismos tokens que usa el Canvas.
struct EcosistemaFisicaU {
    var aplastamiento: Float
    var bandaMenisco: Float
    var pisoNivel: Float
    var ondaAmplitud: Float
    /// (t · `jitterVelocidad`) mod 2π.
    var faseJitter: Float
    /// (t · `nivelOndaVelocidad`) mod 2π.
    var faseOnda: Float
    var _p0: Float = 0
    var _p1: Float = 0

    /// ⚠️ El reloj de la app es `timeIntervalSinceReferenceDate` (~8.07·10⁸ s). A esa
    /// magnitud el ULP de un `Float` vale 32–128 rad: mandar `t` crudo a la GPU CONGELA
    /// la rotación por ~53 s de golpe y colapsa el jitter de 300 partículas a 6 fases.
    /// Por eso todo lo que entra a un `sin`/`cos` viaja **ya reducido a [0, 2π) en
    /// `Double`** — matemáticamente idéntico (difiere en múltiplos de 2π), y a esa escala
    /// un `Float` sí tiene resolución de sobra.
    init(t: TimeInterval) {
        aplastamiento = Float(EcosistemaSimulacion.Geometria.aplastamiento)
        bandaMenisco = Float(EcosistemaSimulacion.Geometria.bandaMenisco)
        pisoNivel = Float(EcosistemaSimulacion.Geometria.pisoNivel)
        ondaAmplitud = Float(LiquidEcosistemaMotion.nivelOndaAmplitud)
        faseJitter = Float(EcosistemaSimulacion.fase(t * LiquidEcosistemaMotion.jitterVelocidad))
        faseOnda = Float(EcosistemaSimulacion.fase(t * LiquidEcosistemaMotion.nivelOndaVelocidad))
    }
}

struct EcosistemaNubeU {
    var colorTinta: SIMD4<Float>
    var colorAmbar: SIMD4<Float>
    var colorBajo: SIMD4<Float>
    var lienzo: SIMD2<Float>
    var centro: SIMD2<Float>
    var radio: Float
    /// Ya reducida a [0, 2π) — ver `EcosistemaFisicaU.init(t:)`.
    var rot: Float
    var jitterAmp: Float
    var alfaK: Float
    var stretch: Float
    var nivel: Float
    var n: UInt32
    var paso: UInt32
    var nivelBajo: UInt32
    var capAmbar: UInt32
    /// 0 = esfera plena · 1 = gauge pleno (funde el modo nivel; era `_pad0`).
    var nivelMezcla: Float = 1
    /// Mezcla del morfo (FER-19): la porta el buffer A; `vsNube` la ignora (era `_pad1`).
    var mezcla: Float = 0
}

struct EcosistemaAtomoU {
    var color: SIMD4<Float>
    var centro: SIMD2<Float>
    var foco: SIMD2<Float>
    var radio: Float
    var radioIni: Float
    /// > 0 anillo (pt) · 0 disco · < 0 halo.
    var grosor: Float
    var _pad: Float = 0
}

struct EcosistemaMarcoU {
    var lienzo: SIMD2<Float>
    var _pad: SIMD2<Float> = .zero
}

/// El uniform del POLVO de «Hoy en atmósfera» (FER-118): espejo campo a campo de `PolvoU` en
/// `EcosistemaShaders.msl` (mismo orden, padding explícito a múltiplo de 16 B; el stride se
/// afirma en `EcosistemaPlanTests.testLayoutDeLosUniformes`). Los colores ya resueltos de la
/// paleta del héroe + CADA token de `PolvoSimulacion.Fisica`: el shader no tiene números propios.
struct EcosistemaPolvoU {
    var colorClima: SIMD4<Float>
    var colorNeutra: SIMD4<Float>
    var colorReposo: SIMD4<Float>
    var colorSueno: SIMD4<Float>
    var colorVigiaTemp: SIMD4<Float>
    var colorVigiaResp: SIMD4<Float>
    var lienzo: SIMD2<Float>
    /// Segundos desde que el fondo apareció (NUNCA el reloj absoluto: ver `EcosistemaFisicaU`).
    var t: Float
    var desplazamiento: Float
    var radioMin: Float
    var radioMax: Float
    var alfaBase: Float
    var alfaRango: Float
    var densidadPiso: Float
    var densidadDesde: Float
    var densidadHasta: Float
    var respiracionAmp: Float
    var respiracionWMin: Float
    var respiracionWRango: Float
    var derivaXMax: Float
    var derivaYMin: Float
    var derivaYRango: Float
    var parallax: Float
    var alfaNeutra: Float
    var umbralClima: Float
    var neutra: UInt32
    var still: UInt32
    var _p0: UInt32 = 0
    var _p1: UInt32 = 0

    init(paleta: EcosistemaPaleta, lienzo: CGSize, t: TimeInterval, desplazamiento: CGFloat,
         neutra: Bool, still: Bool) {
        typealias F = PolvoSimulacion.Fisica
        colorClima = paleta.clima
        colorNeutra = paleta.neutra
        colorReposo = paleta.reposo
        colorSueno = paleta.sueno
        colorVigiaTemp = paleta.vigiaTemp
        colorVigiaResp = paleta.vigiaResp
        self.lienzo = SIMD2<Float>(Float(lienzo.width), Float(lienzo.height))
        self.t = Float(t)
        self.desplazamiento = Float(max(0, desplazamiento))
        radioMin = Float(F.radioMin)
        radioMax = Float(F.radioMax)
        alfaBase = Float(F.alfaBase)
        alfaRango = Float(F.alfaRango)
        densidadPiso = Float(F.densidadPiso)
        densidadDesde = Float(F.densidadDesde)
        densidadHasta = Float(F.densidadHasta)
        respiracionAmp = Float(F.respiracionAmp)
        respiracionWMin = Float(F.respiracionWMin)
        respiracionWRango = Float(F.respiracionWRango)
        derivaXMax = Float(F.derivaXMax)
        derivaYMin = Float(F.derivaYMin)
        derivaYRango = Float(F.derivaYRango)
        parallax = Float(F.parallax)
        alfaNeutra = Float(F.alfaNeutra)
        umbralClima = Float(F.umbralClima)
        self.neutra = neutra ? 1 : 0
        self.still = still ? 1 : 0
    }
}

#if canImport(Metal)
import Metal

// MARK: - «El Ecosistema» · Fase B (FER-13) — el héroe de Hoy en Metal
//
// El Canvas de Fase A recorría el plan en CPU y pedía ~40 `fill` por cuadro con ~850
// elipses adentro. Aquí el MISMO plan (`EcosistemaSimulacion.plan`) se encodea como draws
// INSTANCIADOS: una nube = un draw, y la posición de cada partícula la deriva el vertex
// shader de su índice — la GPU nunca recibe una lista de partículas.
//
// Qué NO se movió a la GPU, a propósito:
//   · Los rótulos orbitales: el texto sigue siendo texto real del sistema de diseño,
//     dibujado por un `EcosistemaCanvas(soloEtiquetas: true)` encima (≤3 rótulos/cuadro,
//     ya resueltos una sola vez por FER-14 #1).
//   · El plan mismo: son ~20 structs por cuadro en CPU, ruido frente a lo que ahorra.
//
// El Canvas completo sigue siendo el camino de macOS/watchOS, de las previews y de los
// renders deterministas de QA — y el fallback si este dispositivo no da Metal.

/// Los tokens de partícula ya resueltos a RGBA lineal-de-textura para el shader.
struct EcosistemaPaleta: Equatable {
    var clima: SIMD4<Float>
    var atencion: SIMD4<Float>
    var negativo: SIMD4<Float>
    var neutra: SIMD4<Float>
    /// La voz de VIGILANDO (azul) — ver `Tinta.vigia`.
    var vigia: SIMD4<Float>
    var blanco: SIMD4<Float>
    /// Identidades de las decisoras (70 % identidad / 30 % clima) — espejo del Canvas.
    var sueno: SIMD4<Float>
    var reposo: SIMD4<Float>
    var vigiaTemp: SIMD4<Float>
    var vigiaResp: SIMD4<Float>

    static func desde(clima: Color) -> EcosistemaPaleta {
        let c = rgba(clima)
        func besada(_ identidad: Color) -> SIMD4<Float> {
            let i = rgba(identidad)
            return i + (c - i) * 0.30
        }
        return EcosistemaPaleta(clima: c,
                                atencion: rgba(LiquidColor.atencion),
                                negativo: rgba(LiquidColor.negativo),
                                neutra: rgba(LiquidColor.particulaNeutra),
                                vigia: rgba(LiquidColor.azul),
                                blanco: SIMD4<Float>(1, 1, 1, 1),
                                sueno: besada(LiquidColor.indigo),
                                reposo: besada(LiquidColor.rosa),
                                vigiaTemp: besada(LiquidColor.doradoTemp),
                                vigiaResp: besada(LiquidColor.azul))
    }

    /// El token es la fuente de verdad; aquí solo se lee su valor sRGB. `resolve(in:)`
    /// evita bajar a UIKit/AppKit y deja la paleta compilable en las tres plataformas.
    private static func rgba(_ color: Color) -> SIMD4<Float> {
        let r = color.resolve(in: EnvironmentValues())
        return SIMD4<Float>(r.red, r.green, r.blue, r.opacity)
    }

    func color(_ tinta: EcosistemaSimulacion.Tinta) -> SIMD4<Float> {
        switch tinta {
        case .clima: return clima
        case .atencion: return atencion
        case .negativo: return negativo
        case .neutra: return neutra
        case .vigia: return vigia
        case .blanco: return blanco
        case .sueno: return sueno
        case .reposo: return reposo
        case .vigiaTemp: return vigiaTemp
        case .vigiaResp: return vigiaResp
        }
    }
}

// MARK: - Recursos de Metal (compilados una vez por proceso, fuera del hilo principal)

/// El shader viaja como fuente en el bundle y se compila en runtime (SwiftPM no compila
/// `.metal` de un target). El compilador de Metal tarda lo suficiente como para que
/// hacerlo en el primer cuadro se vea: se compila en background y, mientras tanto, el
/// héroe se dibuja con el Canvas de Fase A. Los dos recorren el mismo plan y el cambio no
/// se nota; lo que NO existe es una garantía pixel a pixel — el contrato compartido es el
/// plan, no el rasterizado (Core Graphics y Metal antialiasean distinto).
@MainActor
final class EcosistemaMetal: ObservableObject {
    struct Recursos {
        let device: MTLDevice
        let cola: MTLCommandQueue
        let nube: MTLRenderPipelineState
        let nubeMorfo: MTLRenderPipelineState
        let atomo: MTLRenderPipelineState
        /// El pipeline del POLVO de la atmósfera (FER-118). OPCIONAL a propósito: se arma
        /// aparte de los del héroe, así un fallo suyo manda solo al polvo al `Canvas` y el
        /// héroe conserva su Metal. (Ojo: la LIBRERÍA es una sola — un error de compilación
        /// en `vsPolvo` tumba todo el archivo; eso lo cazan el test offscreen y la assertion
        /// de DEBUG de `biblioteca(_:)`; este opcional cubre solo `makeRenderPipelineState`.)
        var polvo: MTLRenderPipelineState? = nil
    }

    static let compartido = EcosistemaMetal()

    @Published private(set) var recursos: Recursos?
    private var pedido = false

    /// El formato del drawable; fijo para que el pipeline se pueda construir sin la vista.
    /// `.bgra8Unorm` y no `_srgb` A PROPÓSITO: así el blending ocurre en sRGB, igual que en
    /// el `Canvas` de Fase A — con sRGB lineal los dos backends no se verían iguales.
    nonisolated static let formato: MTLPixelFormat = .bgra8Unorm

    private init() {}

    /// Arranca la compilación (idempotente). Si algo falla, `recursos` se queda en `nil` y
    /// el héroe vive para siempre en el Canvas — degradar es correcto, no un error.
    func preparar() {
        guard !pedido else { return }
        pedido = true
        Task.detached(priority: .utility) {
            let armados = Self.armar()
            await MainActor.run { self.recursos = armados }
        }
    }

    private nonisolated static func armar() -> Recursos? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let cola = device.makeCommandQueue(),
              let libreria = biblioteca(device),
              let nube = pipeline(device, libreria, vertex: "vsNube"),
              let nubeMorfo = pipeline(device, libreria, vertex: "vsNubeMorfo"),
              let atomo = pipeline(device, libreria, vertex: "vsAtomo")
        else { return nil }
        return Recursos(device: device, cola: cola, nube: nube, nubeMorfo: nubeMorfo,
                        atomo: atomo,
                        // Fuera del `guard`: si el polvo no arma, el héroe sigue en Metal.
                        polvo: pipeline(device, libreria, vertex: "vsPolvo"))
    }

    /// El shader viaja con extensión `.msl`, no `.metal`, A PROPÓSITO: Xcode compila
    /// cualquier `.metal` que encuentre en un target o en sus recursos, y eso vuelve el
    /// **Metal Toolchain** (componente aparte desde Xcode 26) un requisito para compilar la
    /// app entera. Con `.msl` el build no depende de él y el shader se compila en runtime,
    /// que es donde de todos modos vive en el iPhone.
    private nonisolated static func biblioteca(_ device: MTLDevice) -> MTLLibrary? {
        guard let url = Bundle.module.url(forResource: "EcosistemaShaders", withExtension: "msl"),
              let fuente = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        do {
            return try device.makeLibrary(source: fuente, options: nil)
        } catch {
            // En producción degradar al Canvas es correcto; en desarrollo, un shader que no
            // compila DEBE verse — si no, se envía como «el héroe se ve un poco distinto».
            #if DEBUG
            assertionFailure("EcosistemaShaders.msl no compiló: \(error)")
            #endif
            return nil
        }
    }

    private nonisolated static func pipeline(_ device: MTLDevice, _ libreria: MTLLibrary,
                                             vertex: String) -> MTLRenderPipelineState? {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = libreria.makeFunction(name: vertex)
        d.fragmentFunction = libreria.makeFunction(name: "fsTrazo")
        guard let attachment = d.colorAttachments[0] else { return nil }
        attachment.pixelFormat = formato
        // Premultiplicado: el fragmento ya devuelve rgb·a.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: d)
    }
}

// MARK: - El renderer (recorre el plan y encodea)

final class EcosistemaMetalRenderer: NSObject {
    typealias Sim = EcosistemaSimulacion

    let recursos: EcosistemaMetal.Recursos
    /// Un draw de átomos cabe en `setVertexBytes` (4 KB): 80 × 48 B = 3 840 B.
    static let atomosPorDraw = 80

    var escena = Sim.Escena(coreo: .neutra(lunaSueno: false), fase: .viva(desde: 0),
                            still: true, niveles: [nil, nil], fuera: [false, false],
                            guardianJuntas: false, guardianHueco: true, eclipse: 0)
    var t: TimeInterval = 0
    var paleta = EcosistemaPaleta.desde(clima: LiquidColor.particulaNeutra)

    init(recursos: EcosistemaMetal.Recursos) {
        self.recursos = recursos
    }

    /// Encodea el cuadro en un render pass YA abierto: recorre el plan en orden y lo
    /// traduce a draws instanciados. El orden de pintado del plan es la ley.
    func encodar(en enc: MTLRenderCommandEncoder) {
        let lienzo = SIMD2<Float>(Float(Sim.Geometria.lienzo.width),
                                  Float(Sim.Geometria.lienzo.height))
        var fisica = EcosistemaFisicaU(t: t)
        var marco = EcosistemaMarcoU(lienzo: lienzo)
        var atomos: [EcosistemaAtomoU] = []
        atomos.reserveCapacity(Self.atomosPorDraw)

        func vaciar() {
            guard !atomos.isEmpty else { return }
            enc.setRenderPipelineState(recursos.atomo)
            enc.setVertexBytes(atomos, length: MemoryLayout<EcosistemaAtomoU>.stride * atomos.count,
                               index: 0)
            enc.setVertexBytes(&marco, length: MemoryLayout<EcosistemaMarcoU>.stride, index: 1)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: atomos.count)
            atomos.removeAll(keepingCapacity: true)
        }

        func agregar(_ a: EcosistemaAtomoU) {
            atomos.append(a)
            if atomos.count == Self.atomosPorDraw { vaciar() }
        }

        for trazo in Sim.plan(t: t, escena: escena) {
            switch trazo {
            // El texto NO va al shader: lo pinta la capa de rótulos encima.
            case .rotulo:
                continue

            case .nube(let nube):
                vaciar()
                var u = uniforme(nube, lienzo: lienzo)
                enc.setRenderPipelineState(recursos.nube)
                enc.setVertexBytes(&u, length: MemoryLayout<EcosistemaNubeU>.stride, index: 0)
                enc.setVertexBytes(&fisica, length: MemoryLayout<EcosistemaFisicaU>.stride, index: 1)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: nube.cuenta)

            // MORFO (FER-19): dos uniforms de nube — A en buffer 0 (porta la mezcla),
            // B en buffer 2 — y `vsNubeMorfo` lerpa por índice. Misma cuenta que A.
            case .nubeMorfo(let na, let nb, let mezcla):
                vaciar()
                var ua = uniforme(na, lienzo: lienzo)
                ua.mezcla = Float(min(1, max(0, mezcla)))
                var ub = uniforme(nb, lienzo: lienzo)
                enc.setRenderPipelineState(recursos.nubeMorfo)
                enc.setVertexBytes(&ua, length: MemoryLayout<EcosistemaNubeU>.stride, index: 0)
                enc.setVertexBytes(&fisica, length: MemoryLayout<EcosistemaFisicaU>.stride,
                                   index: 1)
                enc.setVertexBytes(&ub, length: MemoryLayout<EcosistemaNubeU>.stride, index: 2)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: na.cuenta)

            case .disco(let centro, let radio, let tinta, let alfa):
                agregar(EcosistemaAtomoU(color: teñir(tinta, alfa), centro: punto(centro),
                                         foco: punto(centro), radio: Float(radio),
                                         radioIni: 0, grosor: 0))

            case .anillo(let centro, let radio, let grosor, let tinta, let alfa):
                agregar(EcosistemaAtomoU(color: teñir(tinta, alfa), centro: punto(centro),
                                         foco: punto(centro), radio: Float(radio),
                                         radioIni: 0, grosor: Float(grosor)))

            case .halo(let centro, let radio, let foco, let radioIni, let tinta, let alfa):
                agregar(EcosistemaAtomoU(color: teñir(tinta, alfa), centro: punto(centro),
                                         foco: punto(foco), radio: Float(radio),
                                         radioIni: Float(radioIni), grosor: -1))
            }
        }
        vaciar()
    }

    /// Un cuadro completo a una textura. Es el camino de los tests offscreen — el mismo
    /// `encodar` que usa la vista, sin `MTKView` de por medio.
    func renderizar(en textura: MTLTexture) {
        let paso = MTLRenderPassDescriptor()
        paso.colorAttachments[0].texture = textura
        paso.colorAttachments[0].loadAction = .clear
        paso.colorAttachments[0].storeAction = .store
        paso.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let buffer = recursos.cola.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: paso) else { return }
        encodar(en: enc)
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    // MARK: Traducción plan → uniformes

    private func uniforme(_ nube: Sim.Nube, lienzo: SIMD2<Float>) -> EcosistemaNubeU {
        EcosistemaNubeU(
            colorTinta: paleta.color(nube.tinta),
            colorAmbar: paleta.atencion,
            colorBajo: paleta.negativo,
            lienzo: lienzo,
            centro: punto(nube.centro),
            radio: Float(nube.radio),
            rot: Float(Sim.fase(nube.rotacion)),
            jitterAmp: Float(nube.jitterAmp),
            alfaK: Float(nube.alfaK),
            stretch: Float(nube.stretch),
            // `nivel` negativo ES la ausencia de gauge (el shader no tiene opcionales).
            nivel: nube.nivel.map(Float.init) ?? -1,
            n: UInt32(nube.n),
            paso: UInt32(nube.paso),
            nivelBajo: nube.nivelBajo ? 1 : 0,
            capAmbar: nube.capAmbar ? 1 : 0,
            nivelMezcla: Float(nube.nivelMezcla))
    }

    private func teñir(_ tinta: Sim.Tinta, _ alfa: Double) -> SIMD4<Float> {
        var c = paleta.color(tinta)
        c.w *= Float(min(1, max(0, alfa)))
        return c
    }

    private func punto(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2<Float>(Float(p.x), Float(p.y))
    }
}

// MARK: - El polvo de la atmósfera (FER-118): un draw instanciado a pantalla completa

/// Recorre `PolvoSimulacion` en la GPU: UN draw de `n` quads cuya posición deriva el vertex
/// shader del índice (`vsPolvo`). Hermano de `EcosistemaMetalRenderer` (no un trazo más del
/// plan del héroe): el héroe vive en un lienzo de 364×324 dentro del scroll a 60 Hz; el polvo es
/// fijo, a pantalla completa y a 20 Hz. Comparten `Recursos` (una sola compilación del shader).
final class EcosistemaPolvoRenderer: NSObject {
    let recursos: EcosistemaMetal.Recursos
    let pipeline: MTLRenderPipelineState

    var t: TimeInterval = 0
    var desplazamiento: CGFloat = 0
    var neutra = false
    var still = false

    /// El crossfade del clima (1.6 s, `LiquidEcosistemaMotion.ambienteCrossfade`) vive aquí y no
    /// en SwiftUI: la paleta es un uniform, y `withAnimation` no interpola un `SIMD4`.
    private var paletaDesde: EcosistemaPaleta
    private var paletaHacia: EcosistemaPaleta
    private var inicioCrossfade: TimeInterval = 0
    private var duracionCrossfade: TimeInterval = 0

    /// `nil` si `recursos.polvo` no armó (el llamador cae al `Canvas`).
    init?(recursos: EcosistemaMetal.Recursos, paleta: EcosistemaPaleta) {
        guard let pipeline = recursos.polvo else { return nil }
        self.recursos = recursos
        self.pipeline = pipeline
        self.paletaDesde = paleta
        self.paletaHacia = paleta
    }

    /// Cambia el clima: desde la paleta VISIBLE en `t` (aunque un crossfade previo siga a
    /// medias) hacia `nueva`, en `duracion` segundos (0 = instantáneo, p. ej. Reduce Motion).
    func fijar(paleta nueva: EcosistemaPaleta, en t: TimeInterval, duracion: TimeInterval) {
        guard nueva != paletaHacia else { return }
        paletaDesde = paleta(en: t)
        paletaHacia = nueva
        inicioCrossfade = t
        duracionCrossfade = max(0, duracion)
    }

    /// La paleta que se ve en `t`: lerp lineal en sRGB entre `desde` y `hacia`, como el
    /// `ambienteCrossfadeAnim` del héroe.
    func paleta(en t: TimeInterval) -> EcosistemaPaleta {
        guard duracionCrossfade > 0 else { return paletaHacia }
        let k = Float(min(1, max(0, (t - inicioCrossfade) / duracionCrossfade)))
        guard k < 1 else { return paletaHacia }
        func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> { a + (b - a) * k }
        let a = paletaDesde, b = paletaHacia
        return EcosistemaPaleta(clima: mix(a.clima, b.clima), atencion: mix(a.atencion, b.atencion),
                                negativo: mix(a.negativo, b.negativo), neutra: mix(a.neutra, b.neutra),
                                vigia: mix(a.vigia, b.vigia), blanco: mix(a.blanco, b.blanco),
                                sueno: mix(a.sueno, b.sueno), reposo: mix(a.reposo, b.reposo),
                                vigiaTemp: mix(a.vigiaTemp, b.vigiaTemp),
                                vigiaResp: mix(a.vigiaResp, b.vigiaResp))
    }

    /// Encodea el cuadro en un render pass YA abierto sobre un lienzo de `lienzo` puntos.
    func encodar(en enc: MTLRenderCommandEncoder, lienzo: CGSize) {
        let n = PolvoSimulacion.cuenta(lienzo: lienzo)
        var u = EcosistemaPolvoU(paleta: paleta(en: t), lienzo: lienzo, t: t,
                                 desplazamiento: desplazamiento, neutra: neutra, still: still)
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<EcosistemaPolvoU>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: n)
    }

    /// Un cuadro completo a una textura (el camino de los tests offscreen). El lienzo en puntos
    /// es el tamaño de la textura.
    func renderizar(en textura: MTLTexture) {
        let paso = MTLRenderPassDescriptor()
        paso.colorAttachments[0].texture = textura
        paso.colorAttachments[0].loadAction = .clear
        paso.colorAttachments[0].storeAction = .store
        paso.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let buffer = recursos.cola.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: paso) else { return }
        encodar(en: enc, lienzo: CGSize(width: textura.width, height: textura.height))
        enc.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
    }
}

#if os(iOS) && canImport(MetalKit)
import MetalKit

// MARK: - El lienzo de Metal en SwiftUI

extension EcosistemaMetalRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let paso = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = recursos.cola.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: paso) else { return }
        encodar(en: enc)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// `MTKView` manejada por SwiftUI: sin reloj propio (`isPaused`), redibuja cuando el
/// `TimelineView` de arriba entrega un `t` nuevo. Así hay UN solo reloj para las
/// partículas y los rótulos, y `paused` (Reduce Motion, fuera de viewport, background)
/// apaga los dos a la vez.
struct EcosistemaMetalLienzo: UIViewRepresentable {
    let recursos: EcosistemaMetal.Recursos
    let escena: EcosistemaSimulacion.Escena
    let t: TimeInterval
    let paleta: EcosistemaPaleta

    func makeCoordinator() -> EcosistemaMetalRenderer {
        EcosistemaMetalRenderer(recursos: recursos)
    }

    func makeUIView(context: Context) -> MTKView {
        let vista = MTKView(frame: .zero, device: recursos.device)
        vista.delegate = context.coordinator
        vista.colorPixelFormat = EcosistemaMetal.formato
        vista.isPaused = true
        vista.enableSetNeedsDisplay = true
        vista.isOpaque = false
        vista.backgroundColor = .clear
        vista.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        vista.isUserInteractionEnabled = false
        return vista
    }

    func updateUIView(_ vista: MTKView, context: Context) {
        let renderer = context.coordinator
        renderer.escena = escena
        renderer.t = t
        renderer.paleta = paleta
        vista.setNeedsDisplay()
    }
}

extension EcosistemaPolvoRenderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let paso = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = recursos.cola.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: paso) else { return }
        // El lienzo en PUNTOS: `drawableSize` ya trae la escala; el shader convierte pt → clip.
        encodar(en: enc, lienzo: view.bounds.size)
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// El polvo de la atmósfera como `MTKView` manejada por SwiftUI (misma receta que
/// `EcosistemaMetalLienzo`): sin reloj propio, redibuja cuando `LiquidAtmosfera` entrega un `t`
/// nuevo (20 Hz) o cambia el desplazamiento del scroll (parallax bajo demanda).
struct AtmosferaMetalLienzo: UIViewRepresentable {
    let recursos: EcosistemaMetal.Recursos
    let paleta: EcosistemaPaleta
    let t: TimeInterval
    let desplazamiento: CGFloat
    let neutra: Bool
    let still: Bool
    /// Duración del crossfade al cambiar de clima (0 = instantáneo).
    let crossfade: TimeInterval

    final class Coordinador {
        var renderer: EcosistemaPolvoRenderer?
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeUIView(context: Context) -> MTKView {
        let vista = MTKView(frame: .zero, device: recursos.device)
        let renderer = EcosistemaPolvoRenderer(recursos: recursos, paleta: paleta)
        context.coordinator.renderer = renderer
        vista.delegate = renderer
        vista.colorPixelFormat = EcosistemaMetal.formato
        vista.isPaused = true
        vista.enableSetNeedsDisplay = true
        vista.isOpaque = false
        vista.layer.isOpaque = false
        vista.backgroundColor = .clear
        vista.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        vista.isUserInteractionEnabled = false
        return vista
    }

    func updateUIView(_ vista: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.fijar(paleta: paleta, en: t, duracion: crossfade)
        renderer.t = t
        renderer.desplazamiento = desplazamiento
        renderer.neutra = neutra
        renderer.still = still
        vista.setNeedsDisplay()
    }
}
#endif
#endif
