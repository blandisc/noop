import Foundation
import CoreGraphics

// MARK: - «El orbe en tres actos» · Acto I — la ENTRADA (FER-41 · rediseño FER-entrada)
//
// La física PURA de la animación de arranque. Rediseño aprobado por el dueño (prototipo
// interactivo): las partículas FLOTAN dispersas por la pantalla, se REÚNEN en el orbe al
// centro-bajo, respiran un momento, SUBEN al orbe principal y se tiñen del clima del
// veredicto. Antes entraban en seis corrientes desde fuera de cuadro; ahora nacen
// esparcidas DENTRO del lienzo y convergen — una por una, escalonadas.
//
// CERO SwiftUI a propósito — la misma frontera que `EcosistemaSimulacion`: aquí se calculan
// números y `LiquidOrbeEntrada` los dibuja. Todo tiempo llega de afuera (TimelineView /
// tests); no existe `Date()` ni azar (la dispersión es un hash determinista de `i`), así que
// el mismo `t` siempre da el mismo cuadro y la coreografía se afirma en `swift test` sin
// pantalla.
//
// Dos decisiones que el código no puede explicar solo:
//
//   · La esfera es la MISMA del héroe (`EcosistemaSimulacion.direccion` sobre `nEsfera`)
//     pero PLENA — sin el gauge de nivel. El nivel del héroe codifica un dato; la entrada
//     corre ANTES de que ese dato exista, así que fabricarle un nivel sería mentir. El orbe
//     entra como OBJETO (el mismo del ícono) y la superficie de Hoy lo muestra como LECTURA.
//
//   · El orbe entra NEUTRO y se tiñe al asentarse. Al arrancar la app el veredicto todavía
//     se está calculando, así que cualquier color de entrada sería una apuesta. El gris es lo
//     único honesto que se puede decir a los 0 ms, y el color llega como REVELACIÓN.
//
//   · El «destino» del ascenso (la posición real del orbe principal) NO vive aquí: es
//     geometría de pantalla que `LiquidOrbeEntrada` resuelve con el frame que publica el
//     héroe. Aquí solo se produce el PROGRESO del ascenso (`Cuadro.ascenso`); la vista lo usa
//     para aterrizar sin costura sobre el héroe, o sobre el cénit fijo si el frame no llegó.
enum EntradaSimulacion {

    // MARK: Geometría (lienzo de referencia 364×720 — la vista lo escala al alto disponible)

    enum Geometria {
        /// El ancho se DERIVA del lienzo del Ecosistema (no se copia): la esfera reusa su
        /// MISMA proyección. El alto es propio — da aire para dispersar las partículas.
        static let lienzo = CGSize(width: EcosistemaSimulacion.Geometria.lienzo.width,
                                          height: 720)
        /// La esfera plena del veredicto: las mismas direcciones.
        static let n = EcosistemaSimulacion.Geometria.nEsfera
        /// El radio, un 29 % sobre el del héroe (ver nota histórica: peso de héroe sobre blanco).
        static let radio = EcosistemaSimulacion.Geometria.radioOrbe * 1.29
        /// Dónde ASIENTA el orbe (el cénit por defecto, si no hay frame del héroe) y a qué
        /// altura se REÚNEN antes de subir. La reunión es solo una `y`: el viaje es vertical.
        static let cenit = CGPoint(x: 182, y: 250)
        /// FER-73 (dueño): la reunión ocurre en el CENTRO del teléfono. El lienzo se centra
        /// verticalmente en la pantalla, así que la mitad del lienzo ES la mitad de la pantalla:
        /// las partículas se juntan donde el ojo ya está, y de ahí el orbe sube a su sitio en
        /// Hoy. Antes se reunían en y=430 (a dos tercios), abajo del centro.
        static let reunionY: CGFloat = lienzo.height / 2
        /// Cuánto REBASA el orbe al cénit antes de asentar, en pt (pico del lóbulo).
        static let sobrepaso: CGFloat = 7
        /// Autorrotación del orbe (rad/s) — el mismo giro lento de la esfera del héroe.
        static let giro = LiquidEcosistemaMotion.rotacionEsfera * 0.5
        /// La caja donde nacen las partículas dispersas, como fracción del lienzo (deja
        /// margen a los bordes para que ninguna nazca pegada al filo de la pantalla).
        static let dispersionX: ClosedRange<CGFloat> = 0.08...0.92
        static let dispersionY: ClosedRange<CGFloat> = 0.06...0.78
        /// Amplitud de la deriva de flotación (pt del lienzo).
        static let flotaAmplitud: CGFloat = 7
    }

    // MARK: Guion (los hitos, en FRACCIÓN de `LiquidEntradaMotion.duracionTotal`)

    /// El guion en cuatro tiempos: flotar → reunir → respirar → subir. El teñido y el
    /// especular se solapan con la cola del ascenso (el color llega mientras se posa).
    enum Guion {
        /// Las partículas flotan dispersas, a la deriva, encendiéndose.
        static let flotarFin = 0.22
        /// La reunión: cada partícula viaja de su punto disperso al orbe (escalonada).
        static let reunirFin = 0.54
        /// El respiro: el orbe ya armado se sostiene abajo, quieto.
        static let respiroFin = 0.66
        /// El ascenso al cénit / destino.
        /// FER-73 (dueño): el ascenso TERMINA antes (0.86) para que el orbe se quede QUIETO en
        /// su destino mientras ocurre el relevo. Un cruce de fundido entre dos dibujos que se
        /// mueven se lee como brinco; entre dos dibujos parados, como un solo elemento.
        static let ascensoFin = 0.86
        /// En qué punto del ascenso queda el REBASE (y de ahí el orbe se posa).
        static let cimaAscenso = 0.78
        /// Cuánto se ESCALONA la reunión entre partículas (fracción del tramo de reunión):
        /// las primeras salen a converger de inmediato, las últimas esperan hasta este tope.
        static let reunirStagger = 0.34
        /// El teñido ARRANCA antes de que termine el ascenso (se solapa con su cola).
        static let tinteIni = 0.78
        static let tinteFin = 0.94
        /// El especular se enciende DESPUÉS del teñido (CA-2.5).
        static let especularIni = 0.86
        static let especularFin = 0.98
    }

    // MARK: Curvas

    /// Desaceleración pura (easeOutCubic): la partícula converge rápido y se posa.
    static func desacelera(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        let v = 1 - c
        return 1 - v * v * v
    }

    /// La altura del orbe durante el ascenso, en y del lienzo: sube del punto de reunión
    /// hasta REBASAR el cénit por `sobrepaso` pt y de ahí se posa. Dos smoothsteps
    /// encadenados (el rebase vale EXACTAMENTE el token, no el residuo de restar curvas).
    static func alturaAscenso(_ u: Double) -> CGFloat {
        let c = min(1, max(0, u))
        let cima = Guion.cimaAscenso
        let rebasado = Geometria.cenit.y - Geometria.sobrepaso
        if c <= cima {
            let v = CGFloat(EcosistemaSimulacion.suave(c / cima))
            return Geometria.reunionY + (rebasado - Geometria.reunionY) * v
        }
        let v = CGFloat(EcosistemaSimulacion.suave((c - cima) / (1 - cima)))
        return rebasado + (Geometria.cenit.y - rebasado) * v
    }

    /// Rampa suave entre dos hitos del guion (smoothstep clampeado).
    static func rampa(_ t: Double, de ini: Double, a fin: Double) -> Double {
        guard fin > ini else { return t >= fin ? 1 : 0 }
        return EcosistemaSimulacion.suave((t - ini) / (fin - ini))
    }

    /// Rampa LINEAL clampeada (sin suavizar) — para el progreso global de la reunión, que se
    /// suaviza DESPUÉS por-partícula en `reunionParticula`.
    static func lineal(_ t: Double, de ini: Double, a fin: Double) -> Double {
        guard fin > ini else { return t >= fin ? 1 : 0 }
        return min(1, max(0, (t - ini) / (fin - ini)))
    }

    // MARK: Dispersión determinista (el «flotar»)

    /// Un hash entero → `[0,1)`, determinista y bien mezclado, para esparcir la partícula `i`
    /// sin `Math.random` (que rompería «función pura del tiempo»). Dos constantes distintas
    /// para x e y para que no caigan sobre una diagonal.
    private static func hash01(_ i: Int, _ salt: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(i)) &* 0x9E3779B97F4A7C15 &+ salt
        x ^= x >> 30; x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 27; x &*= 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x % 100_000) / 100_000
    }

    /// La posición dispersa (flotante) de la partícula `i`, en coords del lienzo. Determinista:
    /// la misma partícula nace siempre en el mismo punto, así que el campo es estable entre
    /// cuadros y sólo la deriva lo mueve.
    static func dispersa(_ i: Int) -> CGPoint {
        let fx = Geometria.dispersionX.lowerBound
            + (Geometria.dispersionX.upperBound - Geometria.dispersionX.lowerBound) * CGFloat(hash01(i, 0x1111))
        let fy = Geometria.dispersionY.lowerBound
            + (Geometria.dispersionY.upperBound - Geometria.dispersionY.lowerBound) * CGFloat(hash01(i, 0x2222))
        return CGPoint(x: Geometria.lienzo.width * fx, y: Geometria.lienzo.height * fy)
    }

    /// La deriva de flotación de la partícula `i` en el instante `t` (pt del lienzo): un vaivén
    /// lento con fase propia, para que el campo respire sin sincronizarse.
    static func deriva(_ i: Int, t: TimeInterval) -> CGSize {
        let ph = hash01(i, 0x3333) * 6.2831853
        let sp = 0.5 + hash01(i, 0x4444) * 0.7
        return CGSize(width: CGFloat(cos(ph + t * sp)) * Geometria.flotaAmplitud,
                      height: CGFloat(sin(ph * 1.3 + t * sp * 0.9)) * Geometria.flotaAmplitud)
    }

    /// El progreso de reunión de la partícula `i` (0 = dispersa, 1 = en el orbe), dado el
    /// progreso GLOBAL `g` (0..1 sobre el tramo de reunión). Escalonado por un retardo propio
    /// y suavizado (easeOut) para que cada una entre rápido y se pose.
    static func reunionParticula(_ i: Int, global g: Double) -> Double {
        let retardo = Guion.reunirStagger * hash01(i, 0x5555)
        return desacelera((g - retardo) / (1 - retardo))
    }

    // MARK: El cuadro

    struct Cuadro: Equatable, Sendable {
        /// Centro del orbe (baja en reunión/respiro, sube en el ascenso), coords del lienzo.
        var centro: CGPoint
        /// Giro de la esfera (rad).
        var rotacion: Double
        /// 0 = dispersas · 1 = reunidas. Progreso GLOBAL del gather (la vista lo escalona
        /// por-partícula con `reunionParticula`).
        var reunion: Double
        /// 0 = en la reunión (abajo) · 1 = asentado (arriba). Progreso del ascenso — la vista
        /// lo usa para aterrizar sin costura sobre el frame del héroe.
        var ascenso: Double
        /// 0 = tinta neutra · 1 = el clima del veredicto.
        var tinte: Double
        /// Alfa del especular.
        var especular: Double
        /// Alfa global de la entrada — el fundido con el que se retira.
        var alfa: Double
    }

    /// El cuadro de la entrada en el instante `t` (segundos desde que arrancó).
    ///
    /// `reduce` = «Reducir movimiento»: NO hay flotar, reunir ni ascenso. El orbe aparece ya
    /// asentado en el cénit y ya teñido, y solo se sostiene `duracionReduce` antes del fundido.
    static func cuadro(t crudo: TimeInterval, reduce: Bool = false) -> Cuadro {
        // Un `t` no finito contamina todo (NaN pasa los min/max): se ataja en la puerta.
        let t = crudo.isFinite ? crudo : 0
        let total = LiquidEntradaMotion.duracionTotal

        guard !reduce else {
            return Cuadro(centro: Geometria.cenit, rotacion: 0,
                          reunion: 1, ascenso: 1, tinte: 1, especular: 1,
                          alfa: 1 - rampa(t, de: LiquidEntradaMotion.duracionReduce,
                                          a: LiquidEntradaMotion.duracionReduce + LiquidEntradaMotion.salida))
        }

        // El reloj normalizado: 0 al abrir, 1 al cerrar la coreografía.
        let u = total > 0 ? t / total : 1

        // Reunión: lineal sobre su tramo (el suavizado y el escalón viven por-partícula).
        let reunion = lineal(u, de: Guion.flotarFin, a: Guion.reunirFin)
        // Ascenso: del respiro al final, con el rebase; la altura clampa fuera de ventana.
        let ascProg = (u - Guion.respiroFin) / (Guion.ascensoFin - Guion.respiroFin)
        let ascenso = EcosistemaSimulacion.suave(min(1, max(0, ascProg)))
        let y = alturaAscenso(ascProg)

        return Cuadro(
            centro: CGPoint(x: Geometria.cenit.x, y: y),
            rotacion: EcosistemaSimulacion.fase(t * Geometria.giro),
            reunion: reunion,
            ascenso: ascenso,
            tinte: rampa(u, de: Guion.tinteIni, a: Guion.tinteFin),
            especular: rampa(u, de: Guion.especularIni, a: Guion.especularFin),
            alfa: 1 - rampa(t, de: total, a: total + LiquidEntradaMotion.salida))
    }

    /// Cuánto vive la entrada de punta a punta (coreografía + fundido de salida).
    static func duracion(reduce: Bool = false) -> TimeInterval {
        (reduce ? LiquidEntradaMotion.duracionReduce : LiquidEntradaMotion.duracionTotal)
            + LiquidEntradaMotion.salida
    }

    /// El instante en que el color empieza a existir. La vista lee el veredicto AQUÍ y no al
    /// montarse (a los 0 ms casi nunca está calculado). Con «Reducir movimiento» es inmediato.
    static func instanteDelTeñido(reduce: Bool = false) -> TimeInterval {
        reduce ? 0 : LiquidEntradaMotion.duracionTotal * Guion.tinteIni
    }
}
