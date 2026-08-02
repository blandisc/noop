import Foundation
import CoreGraphics

// MARK: - «El Ecosistema» · Plan de dibujo (FER-13, Fase B)
//
// La COREOGRAFÍA de un instante, en datos: qué nubes, discos, anillos, halos y rótulos
// componen el cuadro `t`, en el orden en que se pintan. Pura como el resto de
// `EcosistemaSimulacion` — cero SwiftUI, cero Metal, cero color: el plan habla de TINTAS
// (roles), y cada backend las resuelve a sus tokens.
//
// Por qué existe: en Fase A la coreografía vivía dentro del `Canvas` (un método privado de
// la vista). El shader de Fase B necesita la MISMA secuencia, y dos copias de una
// coreografía divergen. Ahora hay una sola: `EcosistemaCanvas` la recorre con
// `GraphicsContext` y el renderer de Metal la recorre encodeando draws instanciados.
//
// El único trazo que NO va al shader es `.rotulo`: el texto sigue siendo texto real, con
// la tipografía del sistema de diseño, dibujado por la capa de arriba.
public extension EcosistemaSimulacion {

    /// El ROL de color de un trazo. El plan no conoce `Color` (vive fuera de SwiftUI);
    /// `.clima` es la tinta del veredicto (verde / roja / neutra) que resuelve el backend.
    enum Tinta: Equatable, Sendable {
        case clima
        case atencion
        case negativo
        case neutra
        case blanco
    }

    /// Los rótulos orbitales, como identidad — el DS no conoce locales (los strings los
    /// pone `EcosistemaRotulos`).
    enum RotuloOrbital: Equatable, Sendable {
        case reposo
        case sueno
        case guardian
    }

    /// Una nube de partículas: el shader la instancia por índice, el Canvas la recorre.
    /// `n`/`paso` describen la esfera fibonacci FUENTE: `paso` > 1 es la variante RALA de
    /// lo hueco (sin dato no se fabrica materia densa) — la partícula `i` toma la
    /// dirección `i·paso` de una esfera de `n`, y conserva `i` como índice de jitter.
    struct Nube: Equatable, Sendable {
        public var centro: CGPoint
        public var radio: CGFloat
        public var rotacion: Double
        public var jitterAmp: Double
        public var alfaK: Double
        public var stretch: Double
        public var nivel: Double?
        public var nivelBajo: Bool
        public var capAmbar: Bool
        public var n: Int
        public var paso: Int
        public var tinta: Tinta

        /// Cuántas partículas emite (= instancias del draw).
        public var cuenta: Int { (n + paso - 1) / paso }
    }

    /// Un trazo del cuadro, en orden de pintado.
    enum Trazo: Equatable, Sendable {
        case nube(Nube)
        /// Disco lleno: chispa del destello, mota del tributo, espiral de la acreción.
        case disco(centro: CGPoint, radio: CGFloat, tinta: Tinta, alfa: Double)
        /// Anillo trazado (el destello del contacto). `grosor` en pt.
        case anillo(centro: CGPoint, radio: CGFloat, grosor: CGFloat, tinta: Tinta, alfa: Double)
        /// Gradiente radial (el especular del orbe fundido): opaco en `foco`, nulo en el
        /// borde del círculo de radio `radio` centrado en `centro`.
        case halo(centro: CGPoint, radio: CGFloat, foco: CGPoint, radioIni: CGFloat,
                  tinta: Tinta, alfa: Double)
        /// Texto real — JAMÁS dibujado en partículas ni en el shader.
        case rotulo(RotuloOrbital, en: CGPoint, alfa: Double)
    }

    /// Todo lo que el plan necesita saber del modelo. La vista lo proyecta; la simulación
    /// no tiene reloj ni modelo propios.
    struct Escena: Equatable, Sendable {
        public var coreo: Coreografia
        public var fase: Fase
        /// Reduce Motion / motion deshabilitado: cuadro asentado, sin viajes ni chorros.
        public var still: Bool
        /// Nivel de cada señal decisora (`nil` = sin dato ⇒ luna hueca), en orden REPOSO, SUEÑO.
        public var niveles: [Double?]
        /// ¿La señal está fuera de rango? (casquete ámbar / líquido rojo).
        public var fuera: [Bool]
        public var guardianJuntas: Bool
        public var guardianHueco: Bool
        /// Progreso del eclipse 0…1 — lo ancla la vista (el guardián tarda `eclipseDur`).
        public var eclipse: Double

        public init(coreo: Coreografia, fase: Fase, still: Bool,
                    niveles: [Double?], fuera: [Bool],
                    guardianJuntas: Bool, guardianHueco: Bool, eclipse: Double) {
            self.coreo = coreo
            self.fase = fase
            self.still = still
            self.niveles = niveles
            self.fuera = fuera
            self.guardianJuntas = guardianJuntas
            self.guardianHueco = guardianHueco
            self.eclipse = eclipse
        }
    }

    /// Con Reduce Motion la fase se lee en su estado FINAL (sin viajes).
    static func faseEstable(_ fase: Fase) -> Fase {
        switch fase {
        case .formando, .uniendo, .viva: return .viva(desde: 0)
        case .separando, .separada: return .separada
        }
    }

    // MARK: El plan

    /// La secuencia de trazos del instante `t`. Determinista: (t, escena) → [Trazo].
    static func plan(t: TimeInterval, escena e: Escena) -> [Trazo] {
        if case .calibrando(let noche, let total) = e.coreo {
            return planAcrecion(t: t, still: e.still, noche: noche, total: total)
        }
        var trazos: [Trazo] = []
        let cuadro = cuadro(t: t, fase: e.still ? faseEstable(e.fase) : e.fase)
        let eclipse = e.eclipse
        let flicker = e.coreo == .desgaste && !e.still
            ? 0.9 + 0.1 * sin(t * LiquidEcosistemaMotion.flickerDesgaste) : 1.0
        // Rampa de estreno del séquito: lunas/guardián/especular se FUNDEN en la escena en
        // la última parte del viaje en vez de aparecer de golpe en u = 0.94.
        let alfaFundida = min(1, max(0, (cuadro.u - Geometria.umbralFundida)
                                     / (1 - Geometria.umbralFundida)))

        // 1 · El guardián atrás (órbita con z<0, o el eclipse asomándose). En separado el
        // orbital NO se dibuja: el guardián «se partió» en sus dos mini-orbes.
        let orbGuardian = guardian(t: t, eclipse: eclipse)
        if !cuadro.separada, orbGuardian.z < 0 || eclipse > 0.5 {
            trazos += trazosGuardian(t: t, orb: orbGuardian, eclipse: eclipse,
                                     hueco: e.guardianHueco,
                                     alfa: eclipse > 0 ? 1 : alfaFundida)
        }

        // 2 · Lunas: una por señal — HUECA si su eje no tiene dato, con CASQUETE ámbar si
        // su eje está fuera. Si NINGUNA señal tiene dato no se fabrican lunas, ni huecas.
        var lunas: [(orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool, fuera: Bool)] = []
        let algunaConDato = e.niveles.prefix(2).contains { $0 != nil }
        if cuadro.fundida, algunaConDato {
            for i in 0..<min(2, e.niveles.count) {
                lunas.append((orb: luna(i + 1, t: t, desgaste: e.coreo == .desgaste),
                              rotulo: i == 0 ? .reposo : .sueno,
                              rotK: i == 0 ? LiquidEcosistemaMotion.rotacionLuna1
                                           : LiquidEcosistemaMotion.rotacionLuna2,
                              hueca: e.niveles[i] == nil,
                              fuera: e.fuera.indices.contains(i) && e.fuera[i]))
            }
            for l in lunas where l.orb.z < 0 {
                trazos += trazosLuna(t: t, luna: l, still: e.still, alfa: alfaFundida)
            }
        }

        // 3 · Las esferas decisoras (separadas / viajando / fundidas).
        let capAmbar = eclipse > 0.5 && cuadro.fundida
        let radio = (lerp(Double(Geometria.radioSeparada), Double(e.coreo.radioOrbe),
                          min(1, cuadro.u))
                     * (1 + 0.02 * sin(t * LiquidEcosistemaMotion.respiracionEsfera) * cuadro.u)
                     + cuadro.settle) * (1 + min(0, cuadro.stretch))
        let jitter = e.still ? 0 : e.coreo.jitter
        let sep = cuadro.separada
        for i in 0..<2 {
            let origen = i == 0 ? Geometria.p1 : Geometria.p2
            trazos.append(.nube(Nube(
                centro: puntoLerp(origen, Geometria.centro, cuadro.u),
                radio: CGFloat(radio),
                rotacion: i == 0 ? t * LiquidEcosistemaMotion.rotacionEsfera : -t * 0.5,
                jitterAmp: jitter,
                alfaK: flicker,
                stretch: max(0, cuadro.stretch),
                nivel: sep ? e.niveles.indices.contains(i) ? e.niveles[i] : nil : nil,
                nivelBajo: sep && e.fuera.indices.contains(i) && e.fuera[i]
                    && e.coreo == .desgaste,
                capAmbar: capAmbar,
                n: Geometria.nEsfera, paso: 1, tinta: .clima)))
        }

        // 4 · Destello + chispas del contacto.
        if cuadro.bump > 0.25, !e.still {
            trazos += trazosDestello(t: t, bump: cuadro.bump, radio: CGFloat(radio))
        }

        // 5 · Especular del orbe fundido (entra con la rampa, no de golpe).
        if cuadro.fundida {
            let r = CGFloat(radio)
            trazos.append(.halo(centro: Geometria.centro, radio: r * 1.05,
                                foco: CGPoint(x: Geometria.centro.x - r * 0.3,
                                              y: Geometria.centro.y - r * 0.36),
                                radioIni: 3, tinta: .blanco, alfa: 0.5 * alfaFundida))
        }

        // 6 · Lunas al frente + guardián al frente (órbita con z≥0, sin eclipse).
        for l in lunas where l.orb.z >= 0 {
            trazos += trazosLuna(t: t, luna: l, still: e.still, alfa: alfaFundida)
        }
        if orbGuardian.z >= 0, eclipse <= 0.5, cuadro.fundida, !cuadro.separada {
            trazos += trazosGuardian(t: t, orb: orbGuardian, eclipse: eclipse,
                                     hueco: e.guardianHueco, alfa: alfaFundida)
        }

        // 7 · Mini-esferas del guardián en el estado separado (fondo de los badges).
        if sep {
            let tinta: Tinta = e.guardianJuntas ? .atencion : .neutra
            for (k, centro) in [Geometria.guardianSeparado1, Geometria.guardianSeparado2].enumerated() {
                trazos.append(.nube(Nube(
                    centro: centro, radio: Geometria.radioGuardianSeparado,
                    rotacion: k == 0 ? t * 0.9 : -t * 0.8,
                    jitterAmp: 0.4, alfaK: 0.9, stretch: 0,
                    nivel: nil, nivelBajo: false, capAmbar: false,
                    n: Geometria.nGuardian, paso: 1, tinta: tinta)))
            }
        }
        return trazos
    }

    // MARK: Piezas

    private static func trazosLuna(
        t: TimeInterval,
        luna l: (orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool, fuera: Bool),
        still: Bool, alfa: Double) -> [Trazo] {
        var trazos: [Trazo] = []
        let dep = (l.orb.z + 1) / 2
        // Tributo: la luna ALIMENTA el orbe. Una luna hueca no tiene qué dar; con Reduce
        // Motion el chorro no se fabrica (motas congeladas a media ruta leerían como basura).
        if !l.hueca, !still, alfa > 0.05 {
            for k in 0..<LiquidEcosistemaMotion.tributoParticulas {
                let m = tributo(k, t: t, luna: l.orb.centro, radioLuna: l.orb.radio)
                trazos.append(.disco(centro: m.pos, radio: m.tamano, tinta: .clima,
                                     alfa: m.alfa * alfa))
            }
        }
        trazos.append(.nube(Nube(
            centro: l.orb.centro, radio: l.orb.radio, rotacion: t * l.rotK,
            jitterAmp: 0.4,
            alfaK: (0.5 + 0.5 * dep) * (l.hueca ? 0.45 : 1) * alfa,
            stretch: 0, nivel: nil, nivelBajo: false, capAmbar: l.fuera,
            n: Geometria.nLuna, paso: l.hueca ? 3 : 1, tinta: .clima)))
        trazos.append(.rotulo(l.rotulo,
                              en: CGPoint(x: l.orb.centro.x, y: l.orb.centro.y + l.orb.radio + 13),
                              alfa: (0.35 + 0.5 * dep) * alfa))
        return trazos
    }

    private static func trazosGuardian(t: TimeInterval, orb: Orbital, eclipse: Double,
                                       hueco: Bool, alfa: Double) -> [Trazo] {
        let dep = (orb.z + 1) / 2
        let tinta: Tinta = eclipse > 0 ? .atencion : .neutra
        let alfaK = (eclipse > 0 ? 0.85 * max(0.4, eclipse) : (0.4 + 0.6 * dep) * 0.75)
            * (hueco ? 0.55 : 1) * alfa
        var trazos: [Trazo] = [.nube(Nube(
            centro: orb.centro, radio: orb.radio,
            rotacion: t * LiquidEcosistemaMotion.rotacionGuardian,
            jitterAmp: 0.4, alfaK: alfaK, stretch: 0,
            nivel: nil, nivelBajo: false, capAmbar: false,
            n: Geometria.nGuardian, paso: hueco ? 2 : 1, tinta: tinta))]
        if eclipse < 0.5 {
            trazos.append(.rotulo(.guardian,
                                  en: CGPoint(x: orb.centro.x, y: orb.centro.y + orb.radio + 13),
                                  alfa: dep * 0.8 * alfa))
        }
        return trazos
    }

    private static func trazosDestello(t: TimeInterval, bump: Double, radio: CGFloat) -> [Trazo] {
        let r = radio + 6 + CGFloat(bump) * 10
        var trazos: [Trazo] = [.anillo(centro: Geometria.centro, radio: r, grosor: 1.5,
                                       tinta: .blanco, alfa: bump * 0.8)]
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi + t
            let sr = Double(radio) + 10 + bump * 22
            trazos.append(.disco(centro: CGPoint(x: Geometria.centro.x + CGFloat(cos(a) * sr),
                                                 y: Geometria.centro.y + CGFloat(sin(a) * sr * 0.9)),
                                 radio: 1.3, tinta: .blanco, alfa: bump * 0.75))
        }
        return trazos
    }

    private static func planAcrecion(t: TimeInterval, still: Bool,
                                     noche: Int, total: Int) -> [Trazo] {
        var trazos: [Trazo] = (0..<Geometria.nEspirales).map { i in
            let m = espiral(i, t: t)
            return .disco(centro: m.pos, radio: m.tamano, tinta: .clima, alfa: m.alfa)
        }
        // El embrión: solo sus franjas de abajo pobladas (noche/total), respirando apenas.
        trazos.append(.nube(Nube(
            centro: Geometria.centro,
            radio: Geometria.radioEmbrion + CGFloat(still ? 0 : 1.6 * sin(t * 0.8)),
            rotacion: t * 0.35, jitterAmp: still ? 0 : 0.5, alfaK: 0.9, stretch: 0,
            nivel: total > 0 ? Double(noche) / Double(total) : 0,
            nivelBajo: false, capAmbar: false,
            n: Geometria.nEsfera, paso: 1, tinta: .clima)))
        return trazos
    }

    static func puntoLerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(u), y: a.y + (b.y - a.y) * CGFloat(u))
    }
}
