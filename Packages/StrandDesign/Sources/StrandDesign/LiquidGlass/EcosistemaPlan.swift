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
        /// La voz propia de VIGILANDO (decisión del dueño /inject: el gris lo hacía
        /// mueble). Cada backend la resuelve a su token azul.
        case vigia
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
        /// Fundido del modo gauge (0 = esfera plena · 1 = gauge pleno): el nivel se
        /// revela GRADUAL durante el viaje de separación en vez de saltar al final.
        public var nivelMezcla: Double = 1
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
        /// MORFO de materia (FER-19 · C.2): la misma dirección `i` evaluada en la
        /// config A y en la B con lerp por índice — migración, no crossfade.
        /// Precondición: `a.n == b.n && a.paso == b.paso`.
        case nubeMorfo(a: Nube, b: Nube, mezcla: Double)
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
        /// Progreso 0…1 de la GRADUACIÓN en vivo (FER-20): la base se completó con la
        /// pantalla abierta y el embrión madura al orbe del veredicto — un morfo
        /// mismo-conteo (la ley C.2), no un corte al ritual de fusión. `nil` = sin
        /// graduación (el caso normal: el veredicto llega entre días).
        public var graduacion: Double?
        /// Progreso 0…1 de la EXHALACIÓN (FER-21 · C.4): el orbe sopla materia hacia la
        /// pastilla «Cómo llegué a esto» al tocarla — la mitad-héroe de la ilusión en
        /// dos mitades (la hoja siembra la otra). `nil` = sin soplo.
        public var exhalacion: Double?

        public init(coreo: Coreografia, fase: Fase, still: Bool,
                    niveles: [Double?], fuera: [Bool],
                    guardianJuntas: Bool, guardianHueco: Bool, eclipse: Double,
                    graduacion: Double? = nil, exhalacion: Double? = nil) {
            self.coreo = coreo
            self.fase = fase
            self.still = still
            self.niveles = niveles
            self.fuera = fuera
            self.guardianJuntas = guardianJuntas
            self.guardianHueco = guardianHueco
            self.eclipse = eclipse
            self.graduacion = graduacion
            self.exhalacion = exhalacion
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
        // Rampa de estreno del séquito: lunas/guardián/especular/estelas se FUNDEN en la
        // escena a lo largo del último quinto del viaje (u 0.82→1, oleada «costuras») —
        // antes entraban en el 6 % final y leían como pop.
        var alfaFundida = min(1, max(0, (cuadro.u - Geometria.umbralEstreno)
                                     / (1 - Geometria.umbralEstreno)))
        // GRADUACIÓN en vivo (FER-20): mientras el embrión madura al orbe, el séquito
        // entra al compás de la maduración, no de golpe con u = 1.
        let graduando = !e.still && e.coreo.conFusion
            && (e.graduacion.map { $0 < 1 } ?? false)
        if graduando, let g = e.graduacion {
            alfaFundida = min(alfaFundida, suave(g))
        }

        // El radio del orbe se deriva antes de dibujar: las estelas orbitales lo
        // necesitan para ocultarse al pasar DETRÁS del orbe.
        let radio = (lerp(Double(Geometria.radioSeparada), Double(e.coreo.radioOrbe),
                          min(1, cuadro.u))
                     * (1 + 0.02 * sin(t * LiquidEcosistemaMotion.respiracionEsfera) * cuadro.u)
                     + cuadro.settle) * (1 + min(0, cuadro.stretch))

        // 0 · Lunas (posiciones): una por señal — HUECA si su eje no tiene dato, con
        // CASQUETE ámbar si su eje está fuera. Si NINGUNA señal tiene dato no se
        // fabrican lunas, ni huecas. (Se derivan antes del pintado: las estelas
        // orbitales las leen.)
        var lunas: [(orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool, fuera: Bool)] = []
        let algunaConDato = e.niveles.prefix(2).contains { $0 != nil }
        // C.1 «Materia continua» (FER-16): el séquito NACE del limbo del orbe — cada
        // luna emerge de la superficie que mira a su lugar orbital y VIAJA a su órbita
        // durante el estreno, creciendo en el camino. La reversa (separar) la regresa
        // al cuerpo. Nada aparece por alpha puro: la materia se reconfigura.
        let emergencia = suave(alfaFundida)
        func emerger(_ o: Orbital) -> Orbital {
            guard emergencia < 1 else { return o }
            var o2 = o
            let dxl = Double(o.centro.x - Geometria.centro.x)
            let dyl = Double(o.centro.y - Geometria.centro.y)
            let dl = max(1, (dxl * dxl + dyl * dyl).squareRoot())
            let limbo = CGPoint(x: Geometria.centro.x + CGFloat(dxl / dl) * CGFloat(radio),
                                y: Geometria.centro.y + CGFloat(dyl / dl) * CGFloat(radio) * 0.96)
            o2.centro = puntoLerp(limbo, o.centro, emergencia)
            o2.radio *= CGFloat(0.35 + 0.65 * emergencia)
            return o2
        }
        if alfaFundida > 0.01, algunaConDato {
            for i in 0..<min(2, e.niveles.count) {
                lunas.append((orb: emerger(luna(i + 1, t: t, desgaste: e.coreo == .desgaste)),
                              rotulo: i == 0 ? .reposo : .sueno,
                              rotK: i == 0 ? LiquidEcosistemaMotion.rotacionLuna1
                                           : LiquidEcosistemaMotion.rotacionLuna2,
                              hueca: e.niveles[i] == nil,
                              fuera: e.fuera.indices.contains(i) && e.fuera[i]))
            }
        }

        // 1 · El guardián atrás (órbita con z<0, o el eclipse asomándose). En separado el
        // orbital NO se dibuja: el guardián «se partió» en sus dos mini-orbes. También
        // EMERGE del limbo (C.1, FER-16) — salvo en eclipse, donde su viaje es otro.
        let orbGuardian = eclipse > 0 ? guardian(t: t, eclipse: eclipse)
                                      : emerger(guardian(t: t, eclipse: 0))
        if !cuadro.separada, orbGuardian.z < 0 || eclipse > 0.5 {
            trazos += trazosGuardian(t: t, orb: orbGuardian, eclipse: eclipse,
                                     hueco: e.guardianHueco,
                                     alfa: eclipse > 0 ? 1 : alfaFundida)
        }

        // 1.5 · Estelas orbitales, mitad TRASERA («el sistema orbital», /inject): la
        // órbita revelada por la estela de cometa de su cuerpo — hereda la profundidad
        // (z) y desaparece tras el disco del orbe. Sustituyen al tributo: la conexión
        // de los cuatro cuerpos es gravedad compartida, no manguera.
        trazos += trazosEstelas(t: t, escena: e, lunas: lunas,
                                radioOrbe: CGFloat(radio), frente: false,
                                alfa: alfaFundida * alfaFundida)

        // 2 · Lunas atrás (z<0).
        for l in lunas where l.orb.z < 0 {
            trazos += trazosLuna(t: t, luna: l, still: e.still, alfa: alfaFundida)
        }

        // 3 · Las esferas decisoras (separadas / viajando / fundidas).
        let capAmbar = eclipse > 0.5 && cuadro.fundida
        let jitter = e.still ? 0 : e.coreo.jitter
        let sep = cuadro.separada
        // El viaje ARQUEA (pulido /inject): las esferas no corren por un riel recto —
        // se elevan apenas a media ruta, como cuerpos con peso. Cero en los extremos.
        let arco = CGFloat(sin(.pi * min(1, max(0, cuadro.u))) * 9)
        // El nivel se REVELA gradual durante los viajes de separar/unir (revisión del
        // dueño: saltaba de esfera llena al nivel real en el último momento). En
        // formando/viva el gauge solo existe plenamente separado (comportamiento
        // clásico del intro).
        let mezclaGauge: Double
        switch e.fase {
        case .separando, .uniendo, .separada:
            mezclaGauge = 1 - suave(min(1, cuadro.u / 0.85))
        case .formando, .viva:
            mezclaGauge = sep ? 1 : 0
        }
        // REUNIFICACIÓN de partículas (pedido del dueño: «que sean las partículas
        // reunificándose», no dos figuras que se traslapan): en el último cuarto del
        // viaje la nube 2 CONVERGE a la orientación de la nube 1 — los dos enjambres
        // se entrelazan hasta quedar alineados mota a mota; al separar se des-fasan.
        let convergencia = suave(min(1, max(0, (cuadro.u - 0.75) / 0.25)))
        if graduando, let g = e.graduacion {
            // GRADUACIÓN (FER-20, decisión del dueño): el embrión de calibrando madura
            // EN VIVO al orbe del veredicto — un `nubeMorfo` mismo-conteo (la ley C.2:
            // ambos son la esfera fibonacci de nEsfera). Las dos decisoras nunca
            // aparecen: el veredicto llega como maduración, no como fusión.
            let embrion = Nube(
                centro: Geometria.centro, radio: Geometria.radioEmbrion,
                rotacion: t * 0.35, jitterAmp: 0.5, alfaK: 0.9, stretch: 0,
                nivel: nil, nivelBajo: false, capAmbar: false,
                n: Geometria.nEsfera, paso: 1, tinta: .clima)
            let orbe = Nube(
                centro: Geometria.centro, radio: CGFloat(radio),
                rotacion: t * LiquidEcosistemaMotion.rotacionEsfera,
                jitterAmp: jitter, alfaK: flicker, stretch: 0,
                nivel: nil, nivelBajo: false, capAmbar: capAmbar,
                n: Geometria.nEsfera, paso: 1, tinta: .clima)
            trazos.append(.nubeMorfo(a: embrion, b: orbe, mezcla: suave(g)))
        } else {
        for i in 0..<2 {
            let origen = i == 0 ? Geometria.p1 : Geometria.p2
            var centroEsfera = puntoLerp(origen, Geometria.centro, cuadro.u)
            centroEsfera.y -= arco
            let nivelE: Double? = mezclaGauge > 0.02
                ? (e.niveles.indices.contains(i) ? e.niveles[i] : nil) : nil
            let bajoE = nivelE != nil && e.fuera.indices.contains(i) && e.fuera[i]
                && e.coreo == .desgaste
            func esfera(rotacion: Double) -> Nube {
                Nube(centro: centroEsfera,
                     radio: CGFloat(radio),
                     rotacion: rotacion,
                     jitterAmp: jitter,
                     alfaK: flicker,
                     stretch: max(0, cuadro.stretch),
                     nivel: nivelE, nivelMezcla: mezclaGauge,
                     nivelBajo: bajoE,
                     capAmbar: capAmbar,
                     n: Geometria.nEsfera, paso: 1, tinta: .clima)
            }
            let rotPropia = i == 0 ? t * LiquidEcosistemaMotion.rotacionEsfera : -t * 0.5
            if i == 0 || convergencia <= 0.02 {
                trazos.append(.nube(esfera(rotacion: rotPropia)))
            } else if convergencia >= 0.98 {
                // Fundida: la nube 2 quedó mota a mota con la 1 — un solo enjambre.
                trazos.append(.nube(esfera(rotacion: t * LiquidEcosistemaMotion.rotacionEsfera)))
            } else {
                // MORFO real (FER-19 · C.2): las motas de la nube 2 MIGRAN por índice de
                // su orientación propia a la alineada — antes esto era un crossfade de
                // dos nubes superpuestas (900 instancias y materia duplicada en
                // pantalla); ahora son 600 instancias y cada mota viaja de verdad.
                trazos.append(.nubeMorfo(
                    a: esfera(rotacion: rotPropia),
                    b: esfera(rotacion: t * LiquidEcosistemaMotion.rotacionEsfera),
                    mezcla: convergencia))
            }
        }
        }

        // 4 · Destello + chispas del contacto. Gate bajísimo (0.25 → 0.02, pulido del
        // brinco): el alfa ya es ∝ bump, así que el anillo se DESVANECE solo en vez de
        // cortarse en seco con ~20 % de alfa restante al final del viaje.
        if cuadro.bump > 0.02, !e.still {
            trazos += trazosDestello(t: t, bump: cuadro.bump, radio: CGFloat(radio))
        }

        // 5 · Especular del orbe fundido (entra con la rampa de estreno, no de golpe).
        if alfaFundida > 0.01 {
            let r = CGFloat(radio)
            trazos.append(.halo(centro: Geometria.centro, radio: r * 1.05,
                                foco: CGPoint(x: Geometria.centro.x - r * 0.3,
                                              y: Geometria.centro.y - r * 0.36),
                                radioIni: 3, tinta: .blanco, alfa: 0.5 * alfaFundida))
        }

        // 5.5 · El destello del LIMBO (la historia del tributo, contada por física):
        // máximo justo cuando la luna CRUZA el borde del orbe — entrando o saliendo de
        // su cara — que es donde el ojo ya la está siguiendo. (El intento anterior
        // pulsaba en z máximo: la luna quedaba ENCIMA de la cara y se tapaba sola.)
        if cuadro.fundida, !e.still {
            let r = CGFloat(radio)
            for l in lunas where !l.hueca {
                let dx = l.orb.centro.x - Geometria.centro.x
                let dy = l.orb.centro.y - Geometria.centro.y
                let d = max(1, (dx * dx + dy * dy).squareRoot())
                let cruce = exp(-pow(Double(d - r) / EstelaOrbital.cruceAncho, 2))
                let p = cruce * (l.orb.z > 0 ? 1 : 0.35)
                guard p > 0.06 else { continue }
                // El punto del limbo hacia la luna: ahí brilla el casquete y se
                // expande una onda — la superficie ACUSA el paso de la señal.
                let s = CGPoint(x: Geometria.centro.x + dx / d * r,
                                y: Geometria.centro.y + dy / d * r)
                trazos.append(.halo(centro: s, radio: r * 0.5, foco: s, radioIni: 1.5,
                                    tinta: .clima, alfa: 0.42 * p * alfaFundida))
                trazos.append(.anillo(centro: s, radio: 7 + CGFloat(1 - p) * 9,
                                      grosor: 1.2, tinta: .blanco,
                                      alfa: 0.5 * p * alfaFundida))
            }
        }

        // 5.7 · EXHALACIÓN (FER-21 · C.4): al tocar «Cómo llegué a esto» el orbe sopla
        // un puñado de motas hacia la pastilla (abajo, de donde nace la hoja) — la
        // mitad-héroe de la ilusión; la hoja siembra la suya al abrir. Con Reduce
        // Motion no hay soplo.
        if let ex = e.exhalacion, ex > 0, ex < 1, !e.still, cuadro.fundida {
            trazos += trazosExhalacion(t: t, progreso: ex, radio: CGFloat(radio))
        }

        // 6 · Lunas al frente + guardián al frente (órbita con z≥0, sin eclipse).
        for l in lunas where l.orb.z >= 0 {
            trazos += trazosLuna(t: t, luna: l, still: e.still, alfa: alfaFundida)
        }
        if orbGuardian.z >= 0, eclipse <= 0.5, cuadro.fundida, !cuadro.separada {
            trazos += trazosGuardian(t: t, orb: orbGuardian, eclipse: eclipse,
                                     hueco: e.guardianHueco, alfa: alfaFundida)
        }

        // 6.5 · Estelas orbitales, mitad FRONTAL: cruzan por delante del orbe, como sus
        // cuerpos (que también le pasan por la cara cuando z ≥ 0).
        trazos += trazosEstelas(t: t, escena: e, lunas: lunas,
                                radioOrbe: CGFloat(radio), frente: true,
                                alfa: alfaFundida * alfaFundida)

        // 7 · El guardián se PARTE en sus dos vigías — y regresa. Viaje CONTINUO entre su
        // posición orbital y las dos esquinas (pulido /inject: antes los mini-orbes
        // aparecían de golpe mientras el orbital solo se esfumaba). En formando/viva el
        // comportamiento clásico (solo el estado plenamente separado los muestra).
        let faseSep: Double
        switch e.fase {
        case .separando, .separada, .uniendo: faseSep = 1 - suave(min(1, max(0, cuadro.u)))
        case .formando, .viva: faseSep = sep ? 1 : 0
        }
        if faseSep > 0.02 {
            let tinta: Tinta = e.guardianJuntas ? .atencion : .vigia
            for (k, esquina) in [Geometria.guardianSeparado1, Geometria.guardianSeparado2].enumerated() {
                // El viaje de los vigías también ARQUEA (exigencia 4 del pulido: ningún
                // cuerpo de esta escena corre por riel recto).
                var centroVigia = puntoLerp(orbGuardian.centro, esquina, faseSep)
                centroVigia.y -= CGFloat(sin(.pi * faseSep) * 6)
                trazos.append(.nube(Nube(
                    centro: centroVigia,
                    radio: Geometria.radioGuardian
                        + (Geometria.radioGuardianSeparado - Geometria.radioGuardian)
                        * CGFloat(faseSep),
                    rotacion: k == 0 ? t * 0.9 : -t * 0.8,
                    jitterAmp: 0.4, alfaK: 0.9 * (0.35 + 0.65 * faseSep), stretch: 0,
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
        // El tributo se retiró («el sistema orbital», /inject): la conexión luna→orbe la
        // cuentan ahora la estela orbital y el pulso de perihelio, no un chorro.
        _ = still
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
        let tinta: Tinta = eclipse > 0 ? .atencion : .vigia
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

    // MARK: Estelas orbitales («el sistema orbital», /inject 2026-08-02)

    /// Recetas de la estela. Viven aquí (junto a su única consumidora) durante la sesión
    /// /inject; al cierre se promueven a `LiquidEcosistemaMotion` como el resto.
    private enum EstelaOrbital {
        /// Motas por estela (~84 discos por cuadro con las 3 órbitas: irrelevante vs
        /// las ~300 partículas de la esfera).
        static let motas = 28
        /// Largo angular de la cola (rad) detrás del cuerpo.
        static let largo = 1.9
        /// Alfa de la mota pegada al cuerpo (decae cuadrático hacia la cola). Subido de
        /// 0.30 (revisión del dueño: «menos sutil») — aún por debajo del dato.
        static let alfaMax = 0.45
        /// Radio base de la mota (pt), modulado por profundidad.
        static let tamano: CGFloat = 1.25
        /// Ganancia del brillo de la estela durante el cruce del limbo.
        static let pulsoGanancia = 0.7
        /// Ancho (pt) de la campana del destello de limbo: máximo cuando el cuerpo
        /// cruza el BORDE del orbe — donde el ojo ya está mirando.
        static let cruceAncho = 13.0
    }

    /// Las estelas de las TRES órbitas (reposo, sueño, vigilando) en una mitad de
    /// profundidad (`frente`): la trasera se dibuja bajo los cuerpos y se oculta tras el
    /// disco del orbe; la frontal cruza por delante, como sus cuerpos.
    private static func trazosEstelas(
        t: TimeInterval, escena e: Escena,
        lunas: [(orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool, fuera: Bool)],
        radioOrbe: CGFloat, frente: Bool, alfa: Double) -> [Trazo] {
        guard alfa > 0.05 else { return [] }
        var trazos: [Trazo] = []
        let w = e.coreo == .desgaste ? Geometria.wobbleDesgaste * sin(t * 2.2) : 0
        for (i, l) in lunas.enumerated() {
            let o = i == 0 ? Geometria.orbitaLuna1 : Geometria.orbitaLuna2
            let ang = i == 0
                ? t * LiquidEcosistemaMotion.orbitaLuna1
                : t * LiquidEcosistemaMotion.orbitaLuna2 + LiquidEcosistemaMotion.faseLuna2
            // El brillo extra de la estela acompaña al destello del limbo (mismo factor).
            let dxl = Double(l.orb.centro.x - Geometria.centro.x)
            let dyl = Double(l.orb.centro.y - Geometria.centro.y)
            let dl = (dxl * dxl + dyl * dyl).squareRoot()
            let pulso = exp(-pow((dl - Double(radioOrbe)) / EstelaOrbital.cruceAncho, 2))
            trazos += estela(o: o, angulo: ang, wobble: i == 0 ? w : -w, tinta: .clima,
                             radioOrbe: radioOrbe, still: e.still, ralo: l.hueca,
                             pulso: pulso, frente: frente, alfa: alfa)
        }
        // El guardián también deja estela — SU órbita vacía es la alerta: al partir al
        // eclipse la estela se apaga. Sin dato (hueco), estela rala.
        if e.eclipse < 0.5 {
            let alfaG = alfa * max(0, 1 - e.eclipse * 2) * 0.8
            trazos += estela(o: Geometria.orbitaGuardian,
                             angulo: t * LiquidEcosistemaMotion.orbitaGuardian
                                 + LiquidEcosistemaMotion.faseGuardian,
                             wobble: 0, tinta: .vigia, radioOrbe: radioOrbe,
                             still: e.still, ralo: e.guardianHueco, pulso: 0,
                             frente: frente, alfa: alfaG)
        }
        return trazos
    }

    /// UNA estela: motas sobre la elipse detrás del ángulo actual, apagándose
    /// cuadráticamente y heredando la profundidad de la órbita (z). `ralo` (cuerpo sin
    /// dato) emite una de cada tres — la misma gramática rala de la luna hueca. Con
    /// Reduce Motion (`still`) el anillo completo, tenue y estático: un cuadro asentado.
    private static func estela(o: (rx: Double, ry: Double, tilt: Double), angulo: Double,
                               wobble: Double, tinta: Tinta, radioOrbe: CGFloat,
                               still: Bool, ralo: Bool, pulso: Double, frente: Bool,
                               alfa: Double) -> [Trazo] {
        var trazos: [Trazo] = []
        for k in 1...EstelaOrbital.motas {
            if ralo, k % 3 != 0 { continue }
            let fr = Double(k) / Double(EstelaOrbital.motas)
            let a = angulo - (still ? 2 * .pi : EstelaOrbital.largo) * fr
            let z = sin(a)
            if (z >= 0) != frente { continue }
            let ox = cos(a) * (o.rx + wobble)
            let oy = sin(a) * o.ry
            let px = Geometria.centro.x + CGFloat(ox * cos(o.tilt) - oy * sin(o.tilt))
            let py = Geometria.centro.y + CGFloat(ox * sin(o.tilt) + oy * cos(o.tilt))
            // Oclusión: la mitad trasera desaparece dentro del disco proyectado del orbe
            // — el anillo se ve ENVOLVER la esfera, no atravesarla.
            if !frente {
                let dx = px - Geometria.centro.x, dy = py - Geometria.centro.y
                if dx * dx + dy * dy < radioOrbe * radioOrbe { continue }
            }
            let dep = (z + 1) / 2
            var av = still ? 0.10 : EstelaOrbital.alfaMax * (1 - fr) * (1 - fr)
            av *= 0.25 + 0.75 * dep
            if !still { av *= 1 + EstelaOrbital.pulsoGanancia * pulso * (1 - fr) }
            trazos.append(.disco(centro: CGPoint(x: px, y: py),
                                 radio: EstelaOrbital.tamano * (0.7 + 0.5 * CGFloat(dep)),
                                 tinta: tinta, alfa: av * alfa))
        }
        return trazos
    }

    /// El SOPLO del orbe hacia la pastilla (FER-21): ~18 motas nacen en el limbo
    /// inferior y vuelan hacia el punto de donde emerge la hoja (borde inferior,
    /// centrado — la causalidad legible que eligió el dueño). Determinista; cada mota
    /// escalona su salida y se apaga al llegar.
    private static func trazosExhalacion(t: TimeInterval, progreso: Double,
                                         radio: CGFloat) -> [Trazo] {
        var trazos: [Trazo] = []
        let destino = CGPoint(x: Geometria.centro.x, y: Geometria.lienzo.height + 12)
        for k in 0..<18 {
            let s = Double((k * 37) % 89) / 89
            let p = min(1, max(0, (progreso * 1.35 - s * 0.35)))
            guard p > 0, p < 1 else { continue }
            // Nace en el casquete inferior del orbe (±0.55 rad alrededor de +π/2).
            let ang = Double.pi / 2 + (s - 0.5) * 1.1
            let origen = CGPoint(
                x: Geometria.centro.x + CGFloat(cos(ang)) * radio,
                y: Geometria.centro.y + CGFloat(sin(ang)) * radio * 0.96)
            let e = suave(p)
            let lat = sin(p * 2 * .pi + s * 6.28) * 3 * sin(.pi * p)
            trazos.append(.disco(
                centro: CGPoint(
                    x: origen.x + (destino.x - origen.x) * CGFloat(e) + CGFloat(lat),
                    y: origen.y + (destino.y - origen.y) * CGFloat(e)),
                radio: 1.4 + CGFloat(s) * 1.2,
                tinta: .clima,
                alfa: sin(.pi * p) * 0.55))
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
        let nivel = total > 0 ? Double(noche) / Double(total) : 0
        // El embrión PRIMERO como config (es el blanco de los aterrizajes, C.3): solo
        // sus franjas de abajo pobladas (noche/total), respirando apenas. Usa la MISMA
        // esfera fuente del veredicto (nEsfera, centro) — continuidad por construcción.
        let embrion = Nube(
            centro: Geometria.centro,
            radio: Geometria.radioEmbrion + CGFloat(still ? 0 : 1.6 * sin(t * 0.8)),
            rotacion: t * 0.35, jitterAmp: still ? 0 : 0.5, alfaK: 0.9, stretch: 0,
            nivel: nivel, nivelBajo: false, capAmbar: false,
            n: Geometria.nEsfera, paso: 1, tinta: .clima)
        // C.3 «Acreción unificada» (FER-20): cada mota ATERRIZA en su partícula del
        // embrión (motaAcrecion) — nada se desvanece en el aire. Con Reduce Motion,
        // SOLO el embrión asentado: congelar motas a media caída era deshonesto.
        var trazos: [Trazo] = []
        if !still {
            trazos = (0..<Geometria.nEspirales).map { i in
                let m = motaAcrecion(i, t: t, embrion: embrion, nivel: nivel)
                return .disco(centro: m.pos, radio: m.tamano, tinta: .clima, alfa: m.alfa)
            }
        }
        trazos.append(.nube(embrion))
        return trazos
    }

    static func puntoLerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(u), y: a.y + (b.y - a.y) * CGFloat(u))
    }

    /// Un ángulo reducido a [0, 2π), calculado en `Double`. Existe por el backend de GPU:
    /// el reloj de la app es `timeIntervalSinceReferenceDate` (~8.07·10⁸ s) y cualquier
    /// ángulo derivado de él NO cabe en un `Float` con resolución útil (el ULP a esa
    /// magnitud vale decenas de radianes). Reducir aquí es matemáticamente inocuo —
    /// `sin`/`cos` tienen periodo 2π — y deja el ángulo en un rango donde `Float` sobra.
    static func fase(_ angulo: Double) -> Double {
        let r = angulo.truncatingRemainder(dividingBy: 2 * .pi)
        return r < 0 ? r + 2 * .pi : r
    }
}
