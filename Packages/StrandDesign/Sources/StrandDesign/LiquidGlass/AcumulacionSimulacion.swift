import Foundation
import CoreGraphics

// MARK: - AcumulacionSimulacion  ·  «el orbe se forma con tus noches» (FER-109)
//
// La física del onboarding. Hermana de `EntradaSimulacion` (que REÚNE de golpe) y de
// `EcosistemaSimulacion` (que ya tiene el orbe hecho): aquí las motas llegan de una en una y
// SE QUEDAN, así que el orbe se va armando en tiempo real y no se desarma nunca.
//
// Tres decisiones que el código no puede explicar solo:
//
//   · **La densidad significa EVIDENCIA, no descarga.** Es la única razón de que este archivo
//     reciba `densidad` de afuera en vez de contar el tiempo. Si el orbe se llenara por cuánto
//     miraste la pantalla, su plenitud codificaría paciencia y no datos: dos personas con
//     historias distintas verían el mismo orbe. En una app cuyo argumento entero es que no te
//     miente, la primera imagen sería falsa. Y hay un agravante: en Hoy un orbe llenándose YA
//     significa «todavía no te conozco» (`EcosistemaSimulacion.Coreografia.calibrando`), así que
//     usar el mismo dibujo para «estoy descargando» le enseñaría al usuario, en el minuto uno, a
//     leer mal la pantalla que va a ver todas las mañanas. Quien llama pasa
//     `OnboardingLanding.densidadHonesta`; esta simulación solo obedece.
//
//   · **El orden de encendido va HASHEADO, no por índice.** Si las motas latchearan en orden de
//     Fibonacci, el orbe se dibujaría como una concha en espiral de polo a polo y se leería
//     mecánico, «un shape siendo trazado». Hasheado, la materia condensa pareja y se lee físico.
//     Es la diferencia entre un loader y un fenómeno.
//
//   · **Función pura de `(indice, t, densidad, modo)`, sin estado acumulado por partícula.** No
//     es purismo: `EcosistemaSimulacion` documenta que su Fase B es un shader de Metal que evalúa
//     la partícula por índice en la GPU, y cualquier diseño con estado por mota cierra esa puerta
//     para siempre. Además deja la coreografía afirmable en `swift test` sin pantalla.
//
// Sin `Date()`, sin azar: la dispersión es un hash determinista del índice, igual que en
// `EntradaSimulacion`. El mismo `t` siempre da el mismo cuadro.

public enum AcumulacionSimulacion {

    // MARK: Geometría

    public enum Geometria {
        /// Las motas que ACABAN formando el orbe. Es exactamente `EcosistemaSimulacion.Geometria.nEsfera`
        /// y no un número propio: si el onboarding formara un orbe de otro N, el aterrizaje en el héroe
        /// de Hoy sería OTRO objeto y el fundido delataría la costura.
        public static let nEsfera = EcosistemaSimulacion.Geometria.nEsfera
        /// Las que nunca latchean: siguen flotando aunque el orbe ya esté completo. Son las señales que
        /// no votan, y son la respuesta al «si dejo pasar el tiempo, el orbe queda completo y también hay
        /// otras partículas flotando».
        public static let nFlotantes = 90
        public static var nTotal: Int { nEsfera + nFlotantes }
    }

    // MARK: Guion (tiempos)

    public enum Guion {
        /// Lo que tarda UNA mota en viajar de donde flotaba a su ranura.
        public static let viaje: TimeInterval = 0.9
        /// Escalón máximo entre motas que arrancan juntas, repartido por hash.
        public static let escalon: TimeInterval = 0.35
        /// Alfa de una mota en vuelo antes de empezar a materializarse.
        public static let alfaPiso: Double = 0.30
        /// La fracción FINAL del viaje donde la mota sube de `alfaPiso` a 1.
        public static let tramoMaterializa: Double = 0.40
        /// Vueltas por segundo del orbe ya formado (lenta: respira, no gira como ruleta).
        public static let rotacion: Double = 0.055
        /// Techo de densidad de `.sinRitmoEnReposo`: hay materia, nunca cuaja.
        public static let techoSinCuajar: Double = 0.34
    }

    // MARK: Modo

    /// Qué está haciendo el campo en cada acto del onboarding.
    public enum Modo: Equatable, Sendable {
        /// Acto 1: derivan sueltas y van latcheando de una en una.
        case disperso
        /// Acto 2: congelado. Nada avanza hasta que la persona decida el permiso.
        case quieto
        /// Acto 3: el latcheo lo manda el avance real de la sincronización.
        case convergencia
        /// Acto 4: la esfera formada, rotando despacio.
        case dentro
        /// Acto 5: las latcheadas salen de la esfera y se agrupan en tres pozos, uno por eje.
        case descomposicion
        /// Acto 6: viajan entre dos centros (Hoy ↔ Entrenar).
        case circulacion
    }

    // MARK: Mota

    public struct Mota: Equatable, Sendable {
        public let punto: CGPoint
        public let radio: CGFloat
        public let alfa: Double
        /// 0 = cara de atrás de la esfera, 1 = cara de enfrente. Alimenta el bucketing de alfa.
        public let profundidad: Double
        public let latcheada: Bool
        /// 0/1/2 — el eje al que pertenece cuando el orbe se descompone.
        public let grupo: Int

        public init(punto: CGPoint, radio: CGFloat, alfa: Double,
                    profundidad: Double, latcheada: Bool, grupo: Int) {
            self.punto = punto; self.radio = radio; self.alfa = alfa
            self.profundidad = profundidad; self.latcheada = latcheada; self.grupo = grupo
        }
    }

    // MARK: Hash determinista

    /// 0…1 estable por índice. Mismo truco que `EntradaSimulacion.dispersa`: seno saturado, sin `Date()`.
    public static func hash01(_ i: Int, sal: Double = 127.1) -> Double {
        let x = sin(Double(i) * sal) * 43_758.5453
        return x - x.rounded(.down)
    }

    /// El lugar de la mota `i` en la fila de encendido, en 0…1. Hasheado a propósito (ver cabecera).
    public static func rango(_ i: Int) -> Double { hash01(i, sal: 78.233) }

    /// La densidad que la evidencia justifica. `noches >= umbral` → 1.
    public static func densidadHonesta(noches: Int, umbral: Int) -> Double {
        guard umbral > 0 else { return 0 }
        return min(1, max(0, Double(max(0, noches)) / Double(umbral)))
    }

    // MARK: El cuadro

    /// La mota `indice` en el instante `t`. `nil` cuando no hay nada que dibujar.
    ///
    /// - Parameters:
    ///   - densidad: 0…1, cuánta evidencia hay. Manda el corte de la fila de encendido.
    ///   - centro / radio: dónde y qué tan grande es el orbe en el lienzo.
    ///   - centroB: el segundo orbe, solo para `.circulacion`.
    ///   - reduce: con «reducir movimiento» no hay viaje ni deriva; la mota está en su destino o no está.
    public static func mota(indice i: Int,
                            t: TimeInterval,
                            densidad: Double,
                            modo: Modo,
                            centro: CGPoint,
                            radio: CGFloat,
                            lienzo: CGSize,
                            centroB: CGPoint? = nil,
                            reduce: Bool = false) -> Mota? {
        guard i >= 0, i < Geometria.nTotal, lienzo.width > 0, lienzo.height > 0 else { return nil }

        let esDeOrbe = i < Geometria.nEsfera
        let grupo = i % 3
        let base = 0.75 + hash01(i, sal: 53.7) * 1.05      // el radio NUNCA cambia después (ver abajo)
        let radioMota = CGFloat(base)

        // ── Las flotantes: nunca latchean, solo derivan. ────────────────────────────────────
        if !esDeOrbe {
            let p = puntoLibre(i, t: reduce ? 0 : t, lienzo: lienzo)
            let alfa = (0.14 + hash01(i, sal: 17.3) * 0.26) * (modo == .quieto ? 0.5 : 0.85)
            return Mota(punto: p, radio: radioMota, alfa: alfa,
                        profundidad: 0.5, latcheada: false, grupo: grupo)
        }

        // ── Las de orbe: ¿ya les tocó? ─────────────────────────────────────────────────────
        let corte = min(1, max(0, densidad))
        guard rango(i) <= corte else {
            // Todavía no le toca: flota suelta, como las flotantes.
            let p = puntoLibre(i, t: reduce ? 0 : t, lienzo: lienzo)
            let alfa = (0.14 + hash01(i, sal: 17.3) * 0.24) * (modo == .quieto ? 0.5 : 0.85)
            return Mota(punto: p, radio: radioMota, alfa: alfa,
                        profundidad: 0.5, latcheada: false, grupo: grupo)
        }

        // Ya latcheó. Su destino depende del modo.
        let destino = destinoLatcheada(i, t: t, modo: modo, centro: centro, radio: radio,
                                       centroB: centroB, reduce: reduce)

        // El progreso del viaje. Con reduce no hay viaje: ya llegó.
        let avance: Double = {
            guard !reduce else { return 1 }
            let retardo = hash01(i, sal: 41.9) * Guion.escalon
            // `t` corre desde que la mota entró a la fila; sin estado por mota, se aproxima con
            // el tiempo global: lo que importa visualmente es el escalón, no el origen exacto.
            let u = (t - retardo) / Guion.viaje
            return EntradaSimulacion.desacelera(min(1, max(0, u)))
        }()

        let origen = puntoLibre(i, t: reduce ? 0 : t, lienzo: lienzo)
        let punto = CGPoint(x: origen.x + (destino.punto.x - origen.x) * avance,
                            y: origen.y + (destino.punto.y - origen.y) * avance)

        // Alfa: piso mientras vuela, y se materializa en el último tramo. El TAMAÑO no cambia:
        // un «pop» de escala al posarse es el rebote de caricatura disfrazado, y el ADN lo prohíbe
        // (movimiento fisiológico: respirar, pulsar, fluir).
        let materializa = min(1, max(0, (avance - (1 - Guion.tramoMaterializa)) / Guion.tramoMaterializa))
        let cuerpo = Guion.alfaPiso + (1 - Guion.alfaPiso) * materializa
        let porProfundidad = 0.42 + 0.58 * destino.profundidad
        let base0 = 0.16 + hash01(i, sal: 17.3) * 0.28
        let alfa = min(1, base0 * cuerpo * porProfundidad * (modo == .quieto ? 0.5 : 1) * 2.1)

        return Mota(punto: punto, radio: radioMota, alfa: alfa,
                    profundidad: destino.profundidad, latcheada: avance >= 1, grupo: grupo)
    }

    /// Todas las motas de un cuadro. Conveniencia para la vista y para las pruebas.
    public static func cuadro(t: TimeInterval, densidad: Double, modo: Modo,
                              centro: CGPoint, radio: CGFloat, lienzo: CGSize,
                              centroB: CGPoint? = nil, reduce: Bool = false) -> [Mota] {
        (0..<Geometria.nTotal).compactMap {
            mota(indice: $0, t: t, densidad: densidad, modo: modo, centro: centro,
                 radio: radio, lienzo: lienzo, centroB: centroB, reduce: reduce)
        }
    }

    // MARK: Destinos

    private static func destinoLatcheada(_ i: Int, t: TimeInterval, modo: Modo,
                                         centro: CGPoint, radio: CGFloat,
                                         centroB: CGPoint?, reduce: Bool)
    -> (punto: CGPoint, profundidad: Double) {
        switch modo {
        case .descomposicion:
            // Tres pozos, uno por eje: el número se desarma delante de ti.
            let g = i % 3
            let anchoTercio = radio * 2.4
            let cx = centro.x + CGFloat(g - 1) * anchoTercio
            let ang = hash01(i, sal: 23.1) * 2 * .pi + (reduce ? 0 : t * 0.5)
            let r = radio * 0.30 * (0.55 + hash01(i, sal: 61.3) * 0.75)
            return (CGPoint(x: cx + cos(ang) * r, y: centro.y + sin(ang) * r * 0.9), 0.55)

        case .circulacion:
            guard let b = centroB else { break }
            // Van y vienen entre los dos orbes: el ciclo, hecho movimiento.
            let fase = reduce ? hash01(i, sal: 71.7)
                              : (t * 0.13 + hash01(i, sal: 71.7)).truncatingRemainder(dividingBy: 1)
            let s = fase < 0.5 ? fase * 2 : (1 - fase) * 2
            let cx = centro.x + (b.x - centro.x) * CGFloat(s)
            let cy = centro.y + (b.y - centro.y) * CGFloat(s)
            let ang = hash01(i, sal: 23.1) * 2 * .pi + (reduce ? 0 : t * 0.7)
            let r = radio * 0.42 * CGFloat(0.35 + 0.65 * abs(0.5 - s) * 2)
            return (CGPoint(x: cx + cos(ang) * r, y: cy + sin(ang) * r * 0.8), 0.55)

        default:
            break
        }

        // La esfera: la MISMA dirección de Fibonacci que usa el héroe, rotada despacio en Y.
        let d = EcosistemaSimulacion.direccion(i, de: Geometria.nEsfera)
        let rot = reduce ? 0 : t * Guion.rotacion * 2 * .pi
        let cr = cos(rot), sr = sin(rot)
        let x = d.x * cr - d.z * sr
        let z = d.x * sr + d.z * cr
        return (CGPoint(x: centro.x + CGFloat(x) * radio,
                        y: centro.y + CGFloat(d.y) * radio * 0.97),
                (z + 1) / 2)
    }

    /// Dónde flota una mota que todavía no latcheó. Nace DENTRO del lienzo (nunca fuera de cuadro:
    /// entrar desde la orilla la hace aparecer cortada por el marco del teléfono) y deriva suave.
    private static func puntoLibre(_ i: Int, t: TimeInterval, lienzo: CGSize) -> CGPoint {
        let margen: CGFloat = 12
        let bx = margen + CGFloat(hash01(i, sal: 7.7)) * max(1, lienzo.width - margen * 2)
        let by = margen + CGFloat(hash01(i, sal: 31.3)) * max(1, lienzo.height - margen * 2)
        guard t > 0 else { return CGPoint(x: bx, y: by) }
        let fase = hash01(i, sal: 23.1) * 2 * .pi
        let vel = 0.3 + hash01(i, sal: 41.9) * 0.6
        let dx = CGFloat(cos(fase + t * 0.18 * vel)) * 7
        let dy = CGFloat(sin(fase * 1.7 + t * 0.15 * vel)) * 6
        return CGPoint(x: min(lienzo.width - margen, max(margen, bx + dx)),
                       y: min(lienzo.height - margen, max(margen, by + dy)))
    }
}
