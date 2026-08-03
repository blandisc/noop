import Foundation
import CoreGraphics

// MARK: - «El Ecosistema» · Simulación (FER-10)
//
// La física PURA del héroe de Hoy: esferas de partículas que se funden en el orbe del
// veredicto, lunas en órbita, el guardián que asoma, la acreción de calibrando.
//
// CERO SwiftUI a propósito — esta es la frontera de la estrategia de dos fases:
//   · FASE A (esta): `EcosistemaCanvas` dibuja lo que estas funciones devuelven.
//   · FASE B (Metal): el shader evalúa `particula(...)` por índice en GPU. Por eso
//     `particula(...)` es PURA y derivada SOLO de (dirección, cuadro, t) — sin estado
//     acumulado por partícula, sin arreglos por-partícula en `Cuadro`.
//
// Todo tiempo llega de afuera (TimelineView / tests). Aquí no existe `Date()` ni azar.
public enum EcosistemaSimulacion {

    // MARK: Geometría (lienzo cerrado 364×324 — coordenadas del prototipo aprobado v6)
    //
    // Constantes de UN ensamble, no spacings reutilizables (mismo precedente que los paths
    // de los cables retirados): viven aquí, unit-testeadas, y el componente escala el
    // lienzo completo al ancho disponible.
    public enum Geometria {
        public static let lienzo = CGSize(width: 364, height: 324)
        /// Centros de las esferas decisoras separadas (EN REPOSO · SUEÑO).
        public static let p1 = CGPoint(x: 88, y: 122)
        public static let p2 = CGPoint(x: 274, y: 122)
        /// Centro del orbe fundido.
        public static let centro = CGPoint(x: 181, y: 136)
        /// Radios: decisora separada → orbe fundido (50 en desgaste).
        public static let radioSeparada: CGFloat = 34
        public static let radioOrbe: CGFloat = 56
        public static let radioOrbeDesgaste: CGFloat = 50
        /// Lunas (REPOSO · SUEÑO) y guardián (siempre presente; crece en eclipse).
        public static let radioLuna1: CGFloat = 13
        public static let radioLuna2: CGFloat = 11
        public static let radioGuardian: CGFloat = 8
        public static let radioGuardianEclipse: CGFloat = 26
        public static let radioGuardianSeparado: CGFloat = 17
        /// Órbitas (semiejes rx/ry + inclinación rad).
        public static let orbitaLuna1 = (rx: 92.0, ry: 34.0, tilt: -0.20)
        public static let orbitaLuna2 = (rx: 72.0, ry: 26.0, tilt: 0.32)
        public static let orbitaGuardian = (rx: 112.0, ry: 42.0, tilt: 0.12)
        /// Wobble de las órbitas en desgaste (±pt sobre rx).
        public static let wobbleDesgaste: Double = 10
        /// Destino del guardián en eclipse (offset desde `centro`).
        public static let eclipseOffset = CGSize(width: 30, height: -58)
        /// Posiciones del guardián partido en dos (estado separado).
        public static let guardianSeparado1 = CGPoint(x: 122, y: 34)
        public static let guardianSeparado2 = CGPoint(x: 240, y: 34)
        /// Conteos de partículas (esferas fibonacci).
        public static let nEsfera = 300
        public static let nLuna = 90
        public static let nGuardian = 70
        public static let nEspirales = 34
        /// Aplastamiento vertical de la proyección (esfera ligeramente achatada).
        public static let aplastamiento: CGFloat = 0.96
        /// Banda del menisco del nivel líquido (±en y de esfera unitaria).
        public static let bandaMenisco: Double = 0.05
        /// Piso visual del nivel (un nivel de 0 se dibuja como 8 %).
        public static let pisoNivel: Double = 0.08
        /// Umbrales de fase del factor de unión.
        public static let umbralSeparada: Double = 0.06
        public static let umbralFundida: Double = 0.94
        /// Desde dónde (en u) se FUNDE el séquito — lunas, estelas, especular — en la
        /// escena (oleada «costuras» /inject): antes entraba todo en el último 6 % del
        /// viaje (0.94→1) y leía como un pop al final; ahora se estrena a lo largo del
        /// último quinto.
        public static let umbralEstreno: Double = 0.82
        /// Embrión de calibrando.
        public static let radioEmbrion: CGFloat = 30
    }

    // MARK: Easings (la matemática de las recetas de `LiquidEcosistemaMotion`)

    /// back-out: sobrepasa y asienta. `s` = `LiquidEcosistemaMotion.fusionOvershoot`.
    public static func backOut(_ u: Double, s: Double = LiquidEcosistemaMotion.fusionOvershoot) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        let v = u - 1
        return 1 + v * v * ((s + 1) * v + s)
    }

    /// smoothstep clampeado.
    public static func suave(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        return c * c * (3 - 2 * c)
    }

    /// Asentamiento amortiguado (pt sumados al radio) τ segundos después de unirse.
    public static func settle(_ tau: Double) -> Double {
        guard tau > 0 else { return 0 }
        return LiquidEcosistemaMotion.settleAmplitud
            * exp(-LiquidEcosistemaMotion.settleAmortiguacion * tau)
            * sin(LiquidEcosistemaMotion.settleFrecuencia * tau)
    }

    /// Interpolación lineal.
    public static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

    // MARK: Coreografía (la proyección SEMÁNTICA del modelo — sin tocar la API del modelo)

    /// Qué historia cuenta el héroe hoy. Derivada de campos que YA existen en
    /// `LiquidHoyModel` (`Coreografia.proyectar` en `LiquidEcosistema` hace el mapeo).
    public enum Coreografia: Equatable, Sendable {
        /// Veredicto verde: fusión + orbe vivo + lunas + guardián en órbita.
        case enRango
        /// Veredicto ámbar. `eclipse` SOLO cuando el guardián empuja en pareja (.juntas).
        case atencion(eclipse: Bool)
        /// Veredicto rojo: orbe más chico y agitado.
        case desgaste
        /// Héroe demotado con señales (lectura de día / leyendo): orbe neutro quieto.
        /// `lunaSueno` = false cuando el eje de sueño no tiene dato (la luna no se fabrica).
        case neutra(lunaSueno: Bool)
        /// Sin base: acreción honesta, noche `noche` de `total`. Sin tap.
        case calibrando(noche: Int, total: Int)

        /// ¿El tap de separar/unir está disponible? (calibrando no tiene nada que separar).
        public var separable: Bool {
            if case .calibrando = self { return false }
            return true
        }

        /// ¿Corre la fusión de apertura? (default confirmado FER-10: con CUALQUIER
        /// veredicto — el ritual es «tu veredicto llegó», no «tu veredicto es bueno»).
        public var conFusion: Bool {
            switch self {
            case .enRango, .atencion, .desgaste: return true
            case .neutra, .calibrando: return false
            }
        }

        public var radioOrbe: CGFloat {
            self == .desgaste ? Geometria.radioOrbeDesgaste : Geometria.radioOrbe
        }

        public var jitter: Double {
            self == .desgaste ? LiquidEcosistemaMotion.jitterDesgaste
                              : LiquidEcosistemaMotion.jitterAmplitud
        }
    }

    // MARK: Fase (la máquina de interacción; los anclajes son instantes del reloj del canvas)

    /// La fase la mueve SOLO el usuario (tap) o el arranque; las transiciones temporales
    /// son implícitas — `cuadro(t:fase:)` deriva el estado post-transición sin mutar nada.
    public enum Fase: Equatable, Sendable {
        /// Intro: espera `fusionIntroEspera`, viaja `fusionDur`, y a partir de ahí ES viva.
        case formando(inicio: TimeInterval)
        /// Fundida y viva (asentada desde `desde` — para el settle).
        case viva(desde: TimeInterval)
        /// Separándose (anticipación + apertura); al terminar ES separada.
        case separando(desde: TimeInterval)
        case separada
        /// Uniéndose; al terminar ES viva.
        case uniendo(desde: TimeInterval)
    }

    // MARK: Cuadro (el estado ANALÍTICO de un instante — sin arreglos por-partícula)

    public struct Cuadro: Equatable, Sendable {
        /// Factor de unión 0 (separada) → 1 (fundida).
        public var u: Double
        /// Estiramiento direccional (squash & stretch) del viaje; negativo = squeeze.
        public var stretch: Double
        /// pt sumados al radio por el asentamiento.
        public var settle: Double
        /// Destello del contacto 0–1 (anillo + chispas).
        public var bump: Double
        /// ¿Se dibujan las esferas separadas con sus valores? (`u < umbralSeparada`)
        public var separada: Bool
        /// ¿Se dibuja el orbe fundido con lunas y palabra? (`u > umbralFundida`)
        public var fundida: Bool

        public init(u: Double, stretch: Double, settle: Double, bump: Double) {
            self.u = u
            self.stretch = stretch
            self.settle = settle
            self.bump = bump
            self.separada = u < Geometria.umbralSeparada
            self.fundida = u > Geometria.umbralFundida
        }
    }

    /// La fase EFECTIVA en `t`: una fase con viaje vencido ES su sucesora. La máquina
    /// nunca muta sola — esto resuelve la etiqueta al decidir un tap, para que el
    /// primer toque sobre un estado asentado SIEMPRE actúe (sin él, un `.separando`
    /// vencido se re-etiquetaba `.separada` y el tap moría — cazado en simulador).
    public static func faseEfectiva(_ fase: Fase, t: TimeInterval) -> Fase {
        switch fase {
        case .formando(let inicio):
            let fin = inicio + LiquidEcosistemaMotion.fusionIntroEspera
                + LiquidEcosistemaMotion.fusionDur
            return t >= fin ? .viva(desde: fin) : fase
        case .separando(let desde):
            let fin = desde + LiquidEcosistemaMotion.anticipacion
                + LiquidEcosistemaMotion.fusionDur
            return t >= fin ? .separada : fase
        case .uniendo(let desde):
            let fin = desde + LiquidEcosistemaMotion.anticipacion * 0.6
                + LiquidEcosistemaMotion.fusionDur
            return t >= fin ? .viva(desde: fin) : fase
        case .viva, .separada:
            return fase
        }
    }

    /// El cuadro del instante `t` para la fase dada. Determinista; las transiciones
    /// temporales son implícitas (una fase «vencida» se comporta como su sucesora).
    public static func cuadro(t: TimeInterval, fase: Fase) -> Cuadro {
        let dur = LiquidEcosistemaMotion.fusionDur
        switch fase {
        case .formando(let inicio):
            let espera = LiquidEcosistemaMotion.fusionIntroEspera
            let tm = t - inicio
            if tm < espera { return Cuadro(u: 0, stretch: 0, settle: 0, bump: 0) }
            if tm < espera + dur {
                let pr = (tm - espera) / dur
                return Cuadro(u: backOut(pr),
                              stretch: LiquidEcosistemaMotion.fusionStretch * sin(.pi * pr),
                              settle: 0, bump: bumpEn(backOut(pr)))
            }
            // Vencida → viva desde el final del viaje.
            return cuadro(t: t, fase: .viva(desde: inicio + espera + dur))
        case .viva(let desde):
            return Cuadro(u: 1, stretch: 0, settle: settle(t - desde), bump: 0)
        case .separando(let desde):
            let ant = LiquidEcosistemaMotion.anticipacion
            let tm = t - desde
            if tm < ant {
                // Anticipación: sigue fundida, tomando aire (squeeze).
                return Cuadro(u: 1, stretch: -LiquidEcosistemaMotion.squeeze * sin(.pi * tm / ant),
                              settle: 0, bump: 0)
            }
            if tm < ant + dur {
                // Apertura SEAMLESS (pulido /inject): smoothstep sin el backOut invertido
                // — que sobrepasaba en NEGATIVO (u < 0: radios extrapolados, centros más
                // allá de su casa). El squeeze de la anticipación se LIBERA en un
                // lanzamiento (oleada «costuras»): estiramiento sutil que pica temprano
                // (~⅓ del viaje) y muere antes de aterrizar — la energía tomada al
                // inhalar se gasta en el arranque, no se evapora en la costura.
                let pr = (tm - ant) / dur
                let lanzamiento = LiquidEcosistemaMotion.fusionStretch * 0.35
                    * sin(.pi * min(1, pr * 1.6)) * pow(1 - pr, 1.5)
                return Cuadro(u: 1 - suave(pr), stretch: lanzamiento, settle: 0, bump: 0)
            }
            // Aterrizaje con asentamiento: la fase conserva su timestamp hasta el
            // próximo tap, así que el settle amortiguado sale gratis de `tm`.
            return Cuadro(u: 0, stretch: 0, settle: settle(tm - ant - dur), bump: 0)
        case .separada:
            return Cuadro(u: 0, stretch: 0, settle: 0, bump: 0)
        case .uniendo(let desde):
            // Reunión con MICRO-ANTICIPACIÓN (pulido /inject): las esferas toman aire
            // (squeeze breve) antes de viajar — el gesto gemelo de la separación, más
            // corto. El viaje sigue smoothstep sin sobrepaso; el carácter orgánico lo
            // pone el settle amortiguado al aterrizar en `.viva`.
            let antU = LiquidEcosistemaMotion.anticipacion * 0.6
            let tm = t - desde
            if tm < antU {
                return Cuadro(u: 0,
                              stretch: -LiquidEcosistemaMotion.squeeze * 0.7
                                  * sin(.pi * tm / antU),
                              settle: 0, bump: 0)
            }
            let tv = tm - antU
            if tv < dur {
                let pr = tv / dur
                // Bump al 60 %: con la reunificación de partículas el contacto ya se
                // CUENTA solo — el destello pleno encima leía como brinco (revisión).
                return Cuadro(u: suave(pr), stretch: 0,
                              settle: 0, bump: bumpEn(suave(pr)) * 0.6)
            }
            // Aterrizaje de la REUNIÓN casi sin settle (0.5 → 0.25, segunda pasada del
            // dueño: aún se asomaba): apenas una exhalación — el carácter del cierre lo
            // ponen la convergencia de enjambres y la respiración, no el rebote. El
            // settle pleno queda solo para el ritual del intro.
            return Cuadro(u: 1, stretch: 0,
                          settle: settle(tv - dur) * 0.25, bump: 0)
        }
    }

    /// El destello vive alrededor del contacto (u ≈ 0.8 del viaje).
    static func bumpEn(_ u: Double) -> Double {
        exp(-pow((u - 0.8) * 8, 2))
    }

    // MARK: Esferas fibonacci (direcciones unitarias precomputables)

    /// `n` direcciones unitarias distribuidas uniformemente (espiral de Fibonacci).
    public static func fibonacci(_ n: Int) -> [SIMD3<Double>] {
        let dorado = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let r = (1 - y * y).squareRoot()
            let th = dorado * Double(i)
            return SIMD3(cos(th) * r, y, sin(th) * r)
        }
    }

    // MARK: Partícula (⭐ la función que ES la spec del shader de Fase B)

    public enum ClaseParticula: Equatable, Sendable {
        /// Tinta del clima (verde/roja/neutra).
        case base
        /// La superficie del nivel líquido (más brillante y grande).
        case menisco
        /// Por encima del nivel (apenas visible).
        case vapor
        /// El casquete teñido por el guardián en eclipse (ámbar).
        case capAmbar
        /// Líquido de un nivel FUERA de rango (rojo `negativo`).
        case liquidoBajo
    }

    public struct Particula: Equatable, Sendable {
        public var pos: CGPoint
        public var tamano: CGFloat
        public var alfa: Double
        public var clase: ClaseParticula
    }

    /// Proyecta UNA dirección de la esfera al lienzo. Pura: (dir, índice, parámetros, t) →
    /// partícula. `nivel` activa el modo gauge (líquido/menisco/vapor); `capAmbar` tiñe el
    /// casquete que mira al guardián (x > 0.25 ∧ y < −0.15 tras la rotación).
    public static func particula(dir: SIMD3<Double>, indice: Int, centro: CGPoint,
                                 radio: CGFloat, rotacion: Double, jitterAmp: Double,
                                 t: TimeInterval, alfaK: Double = 1, stretch: Double = 0,
                                 nivel: Double? = nil, nivelMezcla: Double = 1,
                                 nivelBajo: Bool = false,
                                 capAmbar: Bool = false) -> Particula {
        let x = dir.x * cos(rotacion) + dir.z * sin(rotacion)
        let z = -dir.x * sin(rotacion) + dir.z * cos(rotacion)
        let y = dir.y
        let j = jitterAmp == 0 ? 0
            : sin(t * LiquidEcosistemaMotion.jitterVelocidad + Double(indice) * 2.1) * jitterAmp
        let kx = 1 + stretch
        let ky = 1 - stretch * 0.55
        let sx = centro.x + CGFloat(x) * (radio + CGFloat(j)) * CGFloat(kx)
        var sy = centro.y + CGFloat(y) * (radio + CGFloat(j)) * Geometria.aplastamiento * CGFloat(ky)
        let dep = (z + 1) / 2
        var tam: CGFloat = 0.7 + CGFloat(dep) * 1.5
        var alfa = (0.15 + dep * 0.5) * alfaK
        var clase: ClaseParticula = .base

        if let nivel {
            // Modo gauge: y ∈ [−1 arriba, +1 abajo]; líquido si y > umbral. `nivelMezcla`
            // FUNDE el gauge (0 = esfera plena, 1 = gauge pleno): durante el viaje de
            // separación el nivel se revela gradualmente en vez de saltar de lleno al
            // real en el último momento (revisión del dueño /inject). Espejo en .msl.
            let m = max(0, min(1, nivelMezcla))
            let umbral = 1 - 2 * max(Geometria.pisoNivel, min(1, nivel))
            if y > umbral + Geometria.bandaMenisco {
                clase = nivelBajo ? .liquidoBajo : .base
            } else if y > umbral - Geometria.bandaMenisco {
                alfa *= 1 + 0.5 * m
                tam *= 1 + 0.2 * m
                clase = nivelBajo ? .liquidoBajo : .menisco
                // La ola del menisco: la superficie del líquido ondula (recetas del
                // Ecosistema `nivelOnda*`; con t = 0 queda una ondulación estática).
                sy += CGFloat(sin(Double(sx) * 0.09 + t * LiquidEcosistemaMotion.nivelOndaVelocidad)
                              * LiquidEcosistemaMotion.nivelOndaAmplitud * m)
            } else {
                // El vapor a 0.12 (opción A «aire del gauge») — fundido por la mezcla.
                alfa *= 1 - 0.88 * m
                clase = .vapor
            }
        }
        if capAmbar, x > 0.25, y < -0.15 {
            clase = .capAmbar
        }
        return Particula(pos: CGPoint(x: sx, y: sy), tamano: tam, alfa: alfa, clase: clase)
    }

    // MARK: Morfo (FER-19 · C.2 «Materia continua»)

    /// La ley del MORFO: la MISMA dirección `i` evaluada en la configuración A y en la
    /// B, con lerp de posición/tamaño/alfa por índice — migración real de materia,
    /// nunca crossfade. En mezcla 0/1 es BIT-IGUAL a `particula` simple (ese es el
    /// contrato testeado). La clase es discreta (los backends bucketizan por clase):
    /// gana la configuración dominante. Precondición del trazo: a.n == b.n && a.paso
    /// == b.paso — misma esfera fuente, mismos índices.
    public static func particulaMorfo(dir: SIMD3<Double>, indice: Int,
                                      a: Nube, b: Nube, mezcla: Double,
                                      t: TimeInterval) -> Particula {
        let pa = particula(dir: dir, indice: indice, centro: a.centro, radio: a.radio,
                           rotacion: a.rotacion, jitterAmp: a.jitterAmp, t: t,
                           alfaK: a.alfaK, stretch: a.stretch, nivel: a.nivel,
                           nivelMezcla: a.nivelMezcla, nivelBajo: a.nivelBajo,
                           capAmbar: a.capAmbar)
        if mezcla <= 0 { return pa }
        let pb = particula(dir: dir, indice: indice, centro: b.centro, radio: b.radio,
                           rotacion: b.rotacion, jitterAmp: b.jitterAmp, t: t,
                           alfaK: b.alfaK, stretch: b.stretch, nivel: b.nivel,
                           nivelMezcla: b.nivelMezcla, nivelBajo: b.nivelBajo,
                           capAmbar: b.capAmbar)
        if mezcla >= 1 { return pb }
        return Particula(
            pos: CGPoint(x: pa.pos.x + (pb.pos.x - pa.pos.x) * CGFloat(mezcla),
                         y: pa.pos.y + (pb.pos.y - pa.pos.y) * CGFloat(mezcla)),
            tamano: pa.tamano + (pb.tamano - pa.tamano) * CGFloat(mezcla),
            alfa: pa.alfa + (pb.alfa - pa.alfa) * mezcla,
            clase: mezcla < 0.5 ? pa.clase : pb.clase)
    }

    // MARK: Órbitas (lunas y guardián — posiciones deterministas por t)

    public struct Orbital: Equatable, Sendable {
        public var centro: CGPoint
        /// Profundidad −1 (atrás) … +1 (frente).
        public var z: Double
        public var radio: CGFloat
    }

    static func orbita(_ o: (rx: Double, ry: Double, tilt: Double), angulo: Double,
                       radioBase: CGFloat, wobble: Double = 0) -> Orbital {
        let ox = cos(angulo) * (o.rx + wobble)
        let oy = sin(angulo) * o.ry
        let mx = Geometria.centro.x + CGFloat(ox * cos(o.tilt) - oy * sin(o.tilt))
        let my = Geometria.centro.y + CGFloat(ox * sin(o.tilt) + oy * cos(o.tilt))
        let z = sin(angulo)
        let dep = (z + 1) / 2
        return Orbital(centro: CGPoint(x: mx, y: my), z: z,
                       radio: radioBase * CGFloat(0.85 + 0.15 * dep))
    }

    /// Luna 1 = REPOSO · Luna 2 = SUEÑO. `wobbleT` ≠ nil activa el wobble de desgaste.
    public static func luna(_ cual: Int, t: TimeInterval, desgaste: Bool) -> Orbital {
        let w = desgaste ? Geometria.wobbleDesgaste * sin(t * 2.2) : 0
        if cual == 1 {
            return orbita(Geometria.orbitaLuna1, angulo: t * LiquidEcosistemaMotion.orbitaLuna1,
                          radioBase: Geometria.radioLuna1, wobble: w)
        }
        return orbita(Geometria.orbitaLuna2,
                      angulo: t * LiquidEcosistemaMotion.orbitaLuna2 + LiquidEcosistemaMotion.faseLuna2,
                      radioBase: Geometria.radioLuna2, wobble: -w)
    }

    /// El guardián: en órbita externa siempre; con `eclipse` (0→1) deja la órbita, crece y
    /// se coloca DETRÁS del orbe (offset `eclipseOffset`).
    public static func guardian(t: TimeInterval, eclipse: Double) -> Orbital {
        let enOrbita = orbita(Geometria.orbitaGuardian,
                              angulo: t * LiquidEcosistemaMotion.orbitaGuardian + LiquidEcosistemaMotion.faseGuardian,
                              radioBase: Geometria.radioGuardian)
        guard eclipse > 0 else { return enOrbita }
        let e = suave(eclipse)
        let destino = CGPoint(x: Geometria.centro.x + Geometria.eclipseOffset.width + CGFloat(3 * sin(t * 0.9)),
                              y: Geometria.centro.y + Geometria.eclipseOffset.height)
        return Orbital(
            centro: CGPoint(x: lerpCG(enOrbita.centro.x, destino.x, e),
                            y: lerpCG(enOrbita.centro.y, destino.y, e)),
            // En eclipse queda atrás (z negativa) para dibujarse ANTES del orbe.
            z: lerp(enOrbita.z, -1, e),
            radio: lerpCG(enOrbita.radio, Geometria.radioGuardianEclipse, CGFloat(e)))
    }

    static func lerpCG(_ a: CGFloat, _ b: CGFloat, _ u: CGFloat) -> CGFloat { a + (b - a) * u }

    // MARK: Tributo (las lunas decisoras ALIMENTAN el orbe — revisión de usuario)

    /// La mota `k` (0..<`tributoParticulas`) del chorro que fluye de la luna al orbe en
    /// el instante `t`. Nace en la superficie de la luna, muere ya adentro del borde del
    /// orbe (absorbida: encoge y se apaga en ambos extremos). La deriva lateral rompe la
    /// línea recta — es un fluido, no un láser. Determinista; se calcula desde la
    /// posición ACTUAL de la luna, así el chorro se curva solo con la órbita.
    /// El guardián NO tributa (vigila, no vota) y una luna hueca no tiene qué dar.
    public static func tributo(_ k: Int, t: TimeInterval,
                               luna: CGPoint, radioLuna: CGFloat) -> Mota {
        let fr = (t / LiquidEcosistemaMotion.tributoPeriodo + Double(k) * 0.618)
            .truncatingRemainder(dividingBy: 1)
        let dx = Double(Geometria.centro.x - luna.x)
        let dy = Double(Geometria.centro.y - luna.y)
        let d = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / d, uy = dy / d
        let s = lerp(Double(radioLuna) + 2, d - Double(Geometria.radioOrbe) * 0.82, suave(fr))
        let lat = sin(fr * 2 * .pi + Double(k) * 2.1) * 2.2 * sin(.pi * fr)
        return Mota(pos: CGPoint(x: Double(luna.x) + ux * s - uy * lat,
                                 y: Double(luna.y) + uy * s + ux * lat),
                    alfa: sin(.pi * fr) * 0.7,
                    tamano: CGFloat(2.6 - 1.2 * fr))
    }

    // MARK: Acreción (calibrando: espirales que caen al embrión)

    public struct Mota: Equatable, Sendable {
        public var pos: CGPoint
        public var alfa: Double
        public var tamano: CGFloat
    }

    /// La espiral `i` (0..<nEspirales) en el instante `t`: nace en el borde y cae al
    /// embrión con giro; su alfa y tamaño crecen conforme se acerca.
    public static func espiral(_ i: Int, t: TimeInterval) -> Mota {
        let ph = (t * LiquidEcosistemaMotion.acrecionCaida + Double(i) * 0.0294)
            .truncatingRemainder(dividingBy: 1)
        let ang = t * LiquidEcosistemaMotion.acrecionGiro + Double(i) * 1.9 - ph * 5.2
        let rr = lerp(168, 30, suave(ph))
        return Mota(pos: CGPoint(x: Geometria.centro.x + CGFloat(cos(ang) * rr * 1.18),
                                 y: Geometria.centro.y + CGFloat(sin(ang) * rr * 0.55)),
                    alfa: 0.10 + 0.30 * ph,
                    tamano: CGFloat(0.9 + ph * 0.9))
    }
}
