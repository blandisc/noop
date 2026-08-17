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
        /// Ancho, en densidad, del frente de llegada: la franja donde una mota está a medio camino
        /// entre su deriva y su ranura. Sustituye a `viaje`/`escalon`, que se medían contra el reloj
        /// de pared y por eso no se pintaban nunca. Es también la fracción del orbe que está en
        /// vuelo en cualquier instante: 0.05 → una de cada veinte.
        public static let anchoFrente: Double = 0.05
        /// Alfa de una mota en vuelo antes de empezar a materializarse.
        public static let alfaPiso: Double = 0.30
        /// La fracción FINAL del viaje donde la mota sube de `alfaPiso` a 1.
        public static let tramoMaterializa: Double = 0.40
        /// Vueltas por segundo del orbe ya formado (lenta: respira, no gira como ruleta).
        /// 0.055 × 3600 = 198 vueltas EXACTAS: por eso el reloj de la vista puede envolverse cada
        /// hora sin que la rotación dé un brinco.
        public static let rotacion: Double = 0.055
        /// Cuánto se aleja y se acerca una mota de su ranura durante `.convergencia`, en fracción
        /// del radio: la materia ya cayó hacia la esfera pero todavía no cuaja.
        public static let respiroConvergencia: Double = 0.10
        /// Vueltas por segundo de ese respiro.
        public static let respiroFrecuencia: Double = 0.28
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

    /// El ancho del frente para ESTA mota: `Guion.anchoFrente`, salvo para la cola de la fila.
    /// `corte` no puede pasar de 1, así que a quien enciende en 0.98 le faltaría densidad que ya no
    /// existe para terminar de llegar: el orbe «completo» se vería poroso para siempre. Estrechar
    /// el frente en el último tramo las hace aterrizar más rápido —que es justo lo que el ojo
    /// espera del final— y deja intacto el reparto de la fila, que es lo que codifica la evidencia.
    /// Comprimir los umbrales en vez del frente habría latcheado el 57 % del orbe con la evidencia
    /// del 50 %: barato de escribir, y una mentira sobre cuántas noches hay.
    public static func frente(_ i: Int) -> Double {
        max(0.000_001, min(Guion.anchoFrente, 1 - rango(i)))
    }

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

        // El progreso del viaje. NO se mide contra el reloj, sino contra cuánto pasó el frente de
        // densidad por encima del umbral de ESTA mota. Medirlo contra `t` era mentira dos veces:
        // la vista pasa el reloj de pared, así que `t` ya llegaba enorme y el viaje nunca se
        // pintaba (las motas teletransportaban a la esfera en un cuadro); y en cada frontera de
        // hora `t` volvía a cero y las 300 motas replayeaban el vuelo a la vez — el orbe se
        // desarmaba y se rearmaba solo. Contra la densidad, el viaje se pinta siempre y el escalón
        // entre motas sale gratis del hash: cada una cruza el frente en su turno.
        // Con reduce no hay viaje: ya llegó.
        let avance: Double = reduce
            ? 1
            : EntradaSimulacion.desacelera(min(1, max(0, (corte - rango(i)) / frente(i))))

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
        // Cuánto se separa la mota de su ranura en la esfera. 1 = posada; solo `.convergencia` lo
        // mueve (ver su caso).
        var pulso: Double = 1

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

        case .convergencia:
            // La esfera existe, pero la materia todavía cae hacia ella: cada mota orbita su ranura
            // a un radio que respira y no acaba de cuajar. Al revelar, `.dentro` deja el radio en 1
            // y la esfera cuaja: ese aquietamiento ES el gesto físico del veredicto llegando, y sin
            // él el acto 3 y el acto 4 pintaban el mismo cuadro bit a bit. Misma proyección de
            // Fibonacci (abajo), radio × pulso; la fase es hash del índice, así que no hay estado
            // por mota ni `Date()` — el respiro sigue siendo portable al shader.
            let fase = hash01(i, sal: 23.1) * 2 * .pi
            pulso = 1 + Guion.respiroConvergencia
                * sin(fase + (reduce ? 0 : t * Guion.respiroFrecuencia * 2 * .pi))

        default:
            break
        }

        // La esfera: la MISMA dirección de Fibonacci que usa el héroe, rotada despacio en Y.
        let d = EcosistemaSimulacion.direccion(i, de: Geometria.nEsfera)
        let rot = reduce ? 0 : t * Guion.rotacion * 2 * .pi
        let cr = cos(rot), sr = sin(rot)
        let x = d.x * cr - d.z * sr
        let z = d.x * sr + d.z * cr
        return (CGPoint(x: centro.x + CGFloat(x * pulso) * radio,
                        y: centro.y + CGFloat(d.y * pulso) * radio * 0.97),
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
