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
        /// ¿CADA vigía está fuera de rango? (temperatura, respiración) — enciende su
        /// pulso ámbar en la mirada (FER-22). `guardianJuntas` sigue mandando eclipse.
        public var vigiaFuera: [Bool]
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
                    vigiaFuera: [Bool] = [false, false],
                    graduacion: Double? = nil, exhalacion: Double? = nil) {
            self.coreo = coreo
            self.fase = fase
            self.still = still
            self.niveles = niveles
            self.fuera = fuera
            self.guardianJuntas = guardianJuntas
            self.guardianHueco = guardianHueco
            self.eclipse = eclipse
            self.vigiaFuera = vigiaFuera
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
    ///
    /// FER-22 «las lunas se adelantan»: el orbe del veredicto JAMÁS se parte. Las
    /// cuatro orbitantes (reposo, sueño y los DOS vigías de nacimiento) son cuerpos
    /// permanentes: al separar, las decisoras viajan al frente y crecen hasta sus
    /// estaciones —revelando su gauge en el camino— y cada vigía vuela a SU esquina,
    /// mientras el orbe retrocede: chico y tenue al fondo, nunca ausente. El intro usa
    /// la misma física en reversa. Las CONEXIONES viven siempre: cordón que fluye (las
    /// decisoras alimentan; rojo si votaron mal) y mirada punteada (los vigías vigilan;
    /// pulso ámbar solo al alertar). Dos verbos, dos dibujos.
    static func plan(t: TimeInterval, escena e: Escena) -> [Trazo] {
        if case .calibrando(let noche, let total) = e.coreo {
            return planAcrecion(t: t, still: e.still, noche: noche, total: total)
        }
        var trazos: [Trazo] = []
        let cuadro = cuadro(t: t, fase: e.still ? faseEstable(e.fase) : e.fase)
        let eclipse = e.eclipse
        let flicker = e.coreo == .desgaste && !e.still
            ? 0.9 + 0.1 * sin(t * LiquidEcosistemaMotion.flickerDesgaste) : 1.0
        // Apertura 0 = fundido → 1 = separado: el eje de toda la coreografía.
        let u = min(1, max(0, cuadro.u))
        let apertura = suave(1 - u)
        // Rampa de estreno (estelas, especular, rótulos orbitales, destello de limbo).
        var alfaFundida = min(1, max(0, (cuadro.u - Geometria.umbralEstreno)
                                     / (1 - Geometria.umbralEstreno)))
        let graduando = !e.still && e.coreo.conFusion
            && (e.graduacion.map { $0 < 1 } ?? false)
        if graduando, let g = e.graduacion {
            alfaFundida = min(alfaFundida, suave(g))
        }

        // El orbe principal: siempre al centro. Pleno al frente cuando está fundido;
        // al separar RETROCEDE — más chico y más tenue — pero jamás se parte.
        let radio = lerp(Double(Geometria.radioOrbeFondo), Double(e.coreo.radioOrbe), u)
            * (1 + 0.02 * sin(t * LiquidEcosistemaMotion.respiracionEsfera) * u)
            + cuadro.settle
        let alfaOrbe = lerp(0.38, 1, u) * flicker
        let capAmbar = eclipse > 0.5

        // 0 · Las DECISORAS: cuerpos permanentes que fusionan órbita ↔ estación con la
        // apertura, creciendo (13/11 → 34) y ganando su gauge de nivel en el camino.
        var lunas: [(orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool,
                     fuera: Bool, nivel: Double?)] = []
        for i in 0..<2 {
            let orbital = luna(i + 1, t: t, desgaste: e.coreo == .desgaste)
            let estacion = i == 0 ? Geometria.p1 : Geometria.p2
            var c = puntoLerp(orbital.centro, estacion, apertura)
            c.y -= CGFloat(sin(.pi * apertura) * 9)   // el viaje arquea
            lunas.append((orb: Orbital(
                              centro: c,
                              z: lerp(orbital.z, 1, apertura),
                              radio: orbital.radio
                                  + (Geometria.radioSeparada - orbital.radio)
                                  * CGFloat(apertura)),
                          rotulo: i == 0 ? .reposo : .sueno,
                          rotK: i == 0 ? LiquidEcosistemaMotion.rotacionLuna1
                                       : LiquidEcosistemaMotion.rotacionLuna2,
                          hueca: !(e.niveles.indices.contains(i) && e.niveles[i] != nil),
                          fuera: e.fuera.indices.contains(i) && e.fuera[i],
                          nivel: e.niveles.indices.contains(i) ? e.niveles[i] : nil))
        }

        // 0b · Los VIGÍAS: DOS lunas de nacimiento (temperatura · respiración) en la
        // órbita externa, fases opuestas (FER-22: ya no hay «guardián que se parte»).
        // Al separar, cada una vuela a su esquina; en eclipse ambas se ciernen detrás.
        var vigias: [Orbital] = []
        for g in 0..<2 {
            var orb = orbita(Geometria.orbitaGuardian,
                             angulo: t * LiquidEcosistemaMotion.orbitaGuardian
                                 + LiquidEcosistemaMotion.faseGuardian + Double(g) * .pi,
                             radioBase: Geometria.radioGuardian)
            if eclipse > 0, apertura < 0.02 {
                let ec = suave(eclipse)
                let destino = CGPoint(
                    x: Geometria.centro.x + Geometria.eclipseOffset.width
                        + CGFloat(g == 0 ? -14 : 14) + CGFloat(3 * sin(t * 0.9)),
                    y: Geometria.centro.y + Geometria.eclipseOffset.height)
                orb = Orbital(centro: puntoLerp(orb.centro, destino, ec),
                              z: lerp(orb.z, -1, ec),
                              radio: lerpCG(orb.radio,
                                            Geometria.radioGuardianEclipse * 0.8,
                                            CGFloat(ec)))
            } else {
                let esquina = g == 0 ? Geometria.guardianSeparado1
                                     : Geometria.guardianSeparado2
                var c = puntoLerp(orb.centro, esquina, apertura)
                c.y -= CGFloat(sin(.pi * apertura) * 6)
                orb = Orbital(centro: c,
                              z: lerp(orb.z, 1, apertura),
                              radio: orb.radio
                                  + (Geometria.radioGuardianSeparado - orb.radio)
                                  * CGFloat(apertura))
            }
            vigias.append(orb)
        }
        let vigiaAlerta: [Bool] = [
            e.guardianJuntas || (e.vigiaFuera.indices.contains(0) && e.vigiaFuera[0]),
            e.guardianJuntas || (e.vigiaFuera.indices.contains(1) && e.vigiaFuera[1]),
        ]

        // 1 · Las CONEXIONES — debajo de todos los cuerpos y SIEMPRE vivas.
        for (i, l) in lunas.enumerated() where !l.hueca {
            trazos += trazosCordon(t: t, desde: l.orb.centro, radioDesde: l.orb.radio,
                                   radioOrbe: CGFloat(radio),
                                   semilla: Double(i) * 0.4,
                                   malo: l.fuera, still: e.still)
        }
        if eclipse <= 0.5 {
            for (g, v) in vigias.enumerated() {
                trazos += trazosMirada(t: t, desde: v.centro, radioDesde: v.radio,
                                       radioOrbe: CGFloat(radio),
                                       alerta: vigiaAlerta[g] && !e.still,
                                       hueco: e.guardianHueco)
            }
        }

        // 2 · Estelas (solo mientras se orbita) + cuerpos TRASEROS (z < 0).
        let alfaEstela = alfaFundida * alfaFundida * (1 - apertura)
        let lunasEstela = lunas.map { (orb: $0.orb, rotulo: $0.rotulo, rotK: $0.rotK,
                                       hueca: $0.hueca, fuera: $0.fuera) }
        trazos += trazosEstelas(t: t, escena: e, lunas: lunasEstela,
                                radioOrbe: CGFloat(radio), frente: false,
                                alfa: alfaEstela)
        for (g, v) in vigias.enumerated() where v.z < 0 {
            trazos.append(nubeVigia(v, g: g, t: t, alerta: vigiaAlerta[g],
                                    hueco: e.guardianHueco, eclipse: eclipse))
        }
        for l in lunas where l.orb.z < 0 {
            trazos += trazosLuna(t: t, luna: l, apertura: apertura,
                                 still: e.still, alfa: max(apertura, alfaFundida))
        }

        // 3 · EL ORBE (o su graduación: el embrión madurando en vivo, FER-20).
        if graduando, let g = e.graduacion {
            let embrion = Nube(centro: Geometria.centro, radio: Geometria.radioEmbrion,
                               rotacion: t * 0.35, jitterAmp: 0.5, alfaK: 0.9, stretch: 0,
                               nivel: nil, nivelBajo: false, capAmbar: false,
                               n: Geometria.nEsfera, paso: 1, tinta: .clima)
            let orbe = Nube(centro: Geometria.centro, radio: CGFloat(radio),
                            rotacion: t * LiquidEcosistemaMotion.rotacionEsfera,
                            jitterAmp: e.still ? 0 : e.coreo.jitter, alfaK: flicker,
                            stretch: 0, nivel: nil, nivelBajo: false, capAmbar: capAmbar,
                            n: Geometria.nEsfera, paso: 1, tinta: .clima)
            trazos.append(.nubeMorfo(a: embrion, b: orbe, mezcla: suave(g)))
        } else {
            trazos.append(.nube(Nube(
                centro: Geometria.centro, radio: CGFloat(radio),
                rotacion: t * LiquidEcosistemaMotion.rotacionEsfera,
                jitterAmp: e.still ? 0 : e.coreo.jitter,
                alfaK: alfaOrbe, stretch: 0,
                nivel: nil, nivelBajo: false, capAmbar: capAmbar,
                n: Geometria.nEsfera, paso: 1, tinta: .clima)))
        }

        // 4 · Especular del orbe (se apaga al retroceder).
        if alfaFundida > 0.01 {
            let r = CGFloat(radio)
            trazos.append(.halo(centro: Geometria.centro, radio: r * 1.05,
                                foco: CGPoint(x: Geometria.centro.x - r * 0.3,
                                              y: Geometria.centro.y - r * 0.36),
                                radioIni: 3, tinta: .blanco, alfa: 0.5 * alfaFundida))
        }

        // 5 · Destello de LIMBO: la luna que cruza el borde del orbe (solo orbitando).
        if apertura < 0.02, !e.still {
            let r = CGFloat(radio)
            for l in lunas where !l.hueca {
                let dx = l.orb.centro.x - Geometria.centro.x
                let dy = l.orb.centro.y - Geometria.centro.y
                let d = max(1, (dx * dx + dy * dy).squareRoot())
                let cruce = exp(-pow(Double(d - r) / EstelaOrbital.cruceAncho, 2))
                let p = cruce * (l.orb.z > 0 ? 1 : 0.35)
                guard p > 0.06 else { continue }
                let sp = CGPoint(x: Geometria.centro.x + dx / d * r,
                                 y: Geometria.centro.y + dy / d * r)
                trazos.append(.halo(centro: sp, radio: r * 0.5, foco: sp, radioIni: 1.5,
                                    tinta: .clima, alfa: 0.42 * p * alfaFundida))
                trazos.append(.anillo(centro: sp, radio: 7 + CGFloat(1 - p) * 9,
                                      grosor: 1.2, tinta: .blanco,
                                      alfa: 0.5 * p * alfaFundida))
            }
        }

        // 5.7 · EXHALACIÓN (FER-21) — sin cambios.
        if let ex = e.exhalacion, ex > 0, ex < 1, !e.still, cuadro.fundida {
            trazos += trazosExhalacion(t: t, progreso: ex, radio: CGFloat(radio))
        }

        // 6 · Cuerpos FRONTALES (z ≥ 0) + estelas frontales.
        for l in lunas where l.orb.z >= 0 {
            trazos += trazosLuna(t: t, luna: l, apertura: apertura,
                                 still: e.still, alfa: max(apertura, alfaFundida))
        }
        for (g, v) in vigias.enumerated() where v.z >= 0 {
            trazos.append(nubeVigia(v, g: g, t: t, alerta: vigiaAlerta[g],
                                    hueco: e.guardianHueco, eclipse: eclipse))
        }
        trazos += trazosEstelas(t: t, escena: e, lunas: lunasEstela,
                                radioOrbe: CGFloat(radio), frente: true,
                                alfa: alfaEstela)
        return trazos
    }

    // MARK: Piezas

    private static func trazosLuna(
        t: TimeInterval,
        luna l: (orb: Orbital, rotulo: RotuloOrbital, rotK: Double, hueca: Bool,
                 fuera: Bool, nivel: Double?),
        apertura: Double, still: Bool, alfa: Double) -> [Trazo] {
        var trazos: [Trazo] = []
        let dep = (l.orb.z + 1) / 2
        // El gauge se revela con la apertura (nivelMezcla): en órbita la luna es
        // materia pura; camino a su estación se vuelve el medidor. Fuera de rango,
        // el líquido va ROJO (mapa de estados FER-22) — en cualquier veredicto.
        trazos.append(.nube(Nube(
            centro: l.orb.centro, radio: l.orb.radio, rotacion: t * l.rotK,
            jitterAmp: 0.4,
            alfaK: (0.5 + 0.5 * dep) * (l.hueca ? 0.45 : 1) * alfa,
            stretch: 0,
            nivel: apertura > 0.02 ? l.nivel : nil,
            nivelMezcla: apertura,
            nivelBajo: l.fuera,
            capAmbar: false,
            n: Geometria.nLuna, paso: l.hueca ? 3 : 1, tinta: .clima)))
        // El rótulo orbital CEDE a los overlays al parquearse (allí viven las
        // etiquetas de estación con su valor sólido).
        let alfaRotulo = (0.35 + 0.5 * dep) * alfa * (1 - apertura)
        if alfaRotulo > 0.02 {
            trazos.append(.rotulo(l.rotulo,
                                  en: CGPoint(x: l.orb.centro.x,
                                              y: l.orb.centro.y + l.orb.radio + 13),
                                  alfa: alfaRotulo))
        }
        return trazos
    }

    /// UN vigía (FER-22: dos de nacimiento — ya no hay guardián que se parta).
    private static func nubeVigia(_ orb: Orbital, g: Int, t: TimeInterval,
                                  alerta: Bool, hueco: Bool,
                                  eclipse: Double) -> Trazo {
        let dep = (orb.z + 1) / 2
        let tinta: Tinta = (alerta || eclipse > 0) ? .atencion : .vigia
        let alfaK = eclipse > 0
            ? 0.85 * max(0.4, eclipse)
            : (0.5 + 0.5 * dep) * (hueco ? 0.55 : 0.95)
        return .nube(Nube(
            centro: orb.centro, radio: orb.radio,
            rotacion: g == 0 ? t * 0.9 : -t * 0.8,
            jitterAmp: 0.4, alfaK: alfaK, stretch: 0,
            nivel: nil, nivelBajo: false, capAmbar: false,
            n: Geometria.nGuardian, paso: hueco ? 2 : 1, tinta: tinta))
    }

    /// El CORDÓN de alimentación (FER-22): motas fluyendo de la decisora al orbe —
    /// siempre vivo (órbita, viaje y estación). Rojo cuando la señal votó mal: el
    /// flujo no se detiene (votar es su naturaleza), cambia la noticia que lleva.
    /// Con Reduce Motion: dos motas ASENTADAS, sin flujo (cuadro honesto).
    private static func trazosCordon(t: TimeInterval, desde: CGPoint,
                                     radioDesde: CGFloat, radioOrbe: CGFloat,
                                     semilla: Double, malo: Bool,
                                     still: Bool) -> [Trazo] {
        let dx = Double(Geometria.centro.x - desde.x)
        let dy = Double(Geometria.centro.y - desde.y)
        let d = max(1, (dx * dx + dy * dy).squareRoot())
        let a0 = Double(radioDesde) + 3
        let a1 = d - Double(radioOrbe) - 3
        guard a1 > a0 + 6 else { return [] }
        let ux = dx / d, uy = dy / d
        let tinta: Tinta = malo ? .negativo : .clima
        var trazos: [Trazo] = []
        if still {
            for f in [0.35, 0.7] {
                let sd = a0 + (a1 - a0) * f
                trazos.append(.disco(
                    centro: CGPoint(x: desde.x + CGFloat(ux * sd),
                                    y: desde.y + CGFloat(uy * sd)),
                    radio: 1.4, tinta: tinta, alfa: 0.12 * sin(.pi * f)))
            }
            return trazos
        }
        for k in 0..<4 {
            let f = (t * 0.5 + Double(k) * 0.25 + semilla)
                .truncatingRemainder(dividingBy: 1)
            let sd = a0 + (a1 - a0) * f
            trazos.append(.disco(
                centro: CGPoint(x: desde.x + CGFloat(ux * sd),
                                y: desde.y + CGFloat(uy * sd)),
                radio: 1.8 - CGFloat(f) * 0.7,
                tinta: tinta,
                alfa: 0.5 * sin(.pi * f)))
        }
        return trazos
    }

    /// La MIRADA del vigía (FER-22): punteado ESTÁTICO hacia el orbe — vigila, no
    /// entrega materia. Solo al alertar (fuera de rango) un pulso ámbar corre por la
    /// línea: así habla un vigía. Hueco = punteado más ralo.
    private static func trazosMirada(t: TimeInterval, desde: CGPoint,
                                     radioDesde: CGFloat, radioOrbe: CGFloat,
                                     alerta: Bool, hueco: Bool) -> [Trazo] {
        let dx = Double(Geometria.centro.x - desde.x)
        let dy = Double(Geometria.centro.y - desde.y)
        let d = max(1, (dx * dx + dy * dy).squareRoot())
        let a0 = Double(radioDesde) + 3
        let a1 = d - Double(radioOrbe) - 3
        guard a1 > a0 + 6 else { return [] }
        let ux = dx / d, uy = dy / d
        let pasoPunteado: Double = hueco ? 22 : 11
        var trazos: [Trazo] = []
        var sd = a0
        while sd <= a1 {
            trazos.append(.disco(
                centro: CGPoint(x: desde.x + CGFloat(ux * sd),
                                y: desde.y + CGFloat(uy * sd)),
                // 0.9/0.22 → 1.15/0.32 (revisión del dueño: la mirada no se veía).
                radio: 1.15, tinta: .vigia, alfa: 0.32))
            sd += pasoPunteado
        }
        if alerta {
            let f = (t * 0.9).truncatingRemainder(dividingBy: 1)
            let sp = a0 + (a1 - a0) * f
            trazos.append(.disco(
                centro: CGPoint(x: desde.x + CGFloat(ux * sp),
                                y: desde.y + CGFloat(uy * sp)),
                radio: 2.4, tinta: .atencion, alfa: 0.85 * sin(.pi * f)))
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
        // Los DOS vigías también dejan estela (FER-22: fases opuestas en la órbita
        // externa) — al partir al eclipse se apagan. Sin dato (hueco), estela rala.
        if e.eclipse < 0.5 {
            let alfaG = alfa * max(0, 1 - e.eclipse * 2) * 0.8
            for g in 0..<2 {
                trazos += estela(o: Geometria.orbitaGuardian,
                                 angulo: t * LiquidEcosistemaMotion.orbitaGuardian
                                     + LiquidEcosistemaMotion.faseGuardian
                                     + Double(g) * .pi,
                                 wobble: 0, tinta: .vigia, radioOrbe: radioOrbe,
                                 still: e.still, ralo: e.guardianHueco, pulso: 0,
                                 frente: frente, alfa: alfaG)
            }
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
