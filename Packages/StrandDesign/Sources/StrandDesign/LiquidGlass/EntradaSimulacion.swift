import Foundation
import CoreGraphics

// MARK: - «El orbe en tres actos» · Acto I — la ENTRADA (FER-41)
//
// La física PURA de la animación de arranque: seis corrientes de partículas entran desde
// FUERA del lienzo, se funden en el orbe al centro-bajo, respiran un momento, suben al
// cénit y se tiñen del clima del veredicto.
//
// CERO SwiftUI a propósito — la misma frontera que `EcosistemaSimulacion`: aquí se calculan
// números y `LiquidOrbeEntrada` los dibuja. Todo tiempo llega de afuera (TimelineView /
// tests); no existe `Date()` ni azar, así que el mismo `t` siempre da el mismo cuadro y la
// coreografía completa se puede afirmar en `swift test` sin pantalla.
//
// Dos decisiones que el código no puede explicar solo:
//
//   · La esfera es la MISMA del héroe (`EcosistemaSimulacion.direccion` sobre `nEsfera`)
//     pero PLENA — sin el gauge de nivel. El nivel del héroe codifica un dato; la entrada
//     corre ANTES de que ese dato exista, así que fabricarle un nivel sería mentir. El orbe
//     entra como OBJETO (el mismo del ícono) y la superficie de Hoy es la que después lo
//     muestra como LECTURA.
//
//   · El orbe entra NEUTRO y se tiñe al asentarse. Al arrancar la app el veredicto todavía
//     se está calculando, así que cualquier color de entrada sería una apuesta: si acertara
//     sería suerte y si fallara habría que corregirlo a la vista del usuario. El gris es lo
//     único honesto que se puede decir a los 0 ms, y el color llega como REVELACIÓN.
public enum EntradaSimulacion {

    // MARK: Geometría (lienzo de referencia 364×720 — la vista lo escala al alto disponible)

    public enum Geometria {
        /// El ancho se DERIVA del lienzo del Ecosistema (no se copia): la esfera reusa su
        /// MISMA proyección, así que si el héroe reescala su lienzo la entrada lo hereda en
        /// vez de quedarse con un número que un día dejó de ser cierto. El alto es propio —
        /// da aire arriba y abajo para que las corrientes nazcan fuera de cuadro.
        public static let lienzo = CGSize(width: EcosistemaSimulacion.Geometria.lienzo.width,
                                          height: 720)
        /// La esfera plena del veredicto: las mismas direcciones.
        public static let n = EcosistemaSimulacion.Geometria.nEsfera
        /// El radio, un 29 % sobre el del héroe.
        ///
        /// En Hoy el orbe comparte pantalla con el tablero, así que su tamaño se mide contra
        /// lo que tiene al lado. En la entrada está SOLO sobre blanco, y ahí el mismo radio se
        /// ve perdido — un punto en medio de la nada en vez de la presencia que abre la app.
        /// El 29 % lo devuelve a peso de héroe sin sacarlo de su familia: la merma al pasar al
        /// orbe real queda por debajo de lo que el ojo registra durante un fundido de 0.35 s.
        public static let radio = EcosistemaSimulacion.Geometria.radioOrbe * 1.29
        /// Dónde ASIENTA el orbe (el cénit) y a qué altura se REÚNEN antes de subir. La
        /// reunión es solo una `y`: el viaje es vertical, así que compartir la `x` del cénit
        /// no es una coincidencia que haya que mantener a mano — es la definición.
        public static let cenit = CGPoint(x: 182, y: 250)
        public static let reunionY: CGFloat = 430
        /// Cuánto REBASA el orbe al cénit antes de asentar, en pt. Se aplica como un lóbulo
        /// normalizado (`loboTardio`), así que este número es literalmente el pico.
        public static let sobrepaso: CGFloat = 7
        /// En cuántas corrientes se parte la esfera para el viaje de llegada.
        public static let corrientes = 6
        /// Autorrotación del orbe (rad/s) — el mismo giro lento de la esfera del héroe.
        public static let giro = LiquidEcosistemaMotion.rotacionEsfera * 0.5
        /// De dónde entra cada corriente, como desvío en pt respecto de su posición final.
        /// TODOS caen fuera del lienzo (|dx| > 238 = 182+56, o |dy| > 290 = 720−430), así que
        /// ninguna corriente «aparece» dentro de cuadro: todas cruzan un borde. Y todas
        /// vienen de ABAJO o de los costados-abajo (dy > 0): el orbe se arma desde el pie de
        /// la pantalla y sube, que es el gesto que el dueño aprobó.
        public static let origenes: [CGSize] = [
            CGSize(width: -430, height: 250),
            CGSize(width:  -90, height: 470),
            CGSize(width:  430, height: 190),
            CGSize(width:  380, height: 430),
            CGSize(width:   70, height: 520),
            CGSize(width: -390, height: 400),
        ]
    }

    // MARK: Guion (los hitos, en FRACCIÓN de `LiquidEntradaMotion.duracionTotal`)

    /// Cada hito se DERIVA del anterior más su duración: mover un tiempo no desfasa los
    /// demás, y la suma no puede pasarse de 1 sin que un test lo grite.
    public enum Guion {
        /// Cuánto dura el viaje de UNA corriente.
        public static let viaje = 0.38
        /// En qué fracción de su viaje una corriente llega a opacidad plena.
        ///
        /// Corto a propósito. Con una ventana larga la corriente alcanzaba su opacidad plena
        /// cuando ya llevaba el 70 % del camino andado — o sea, YA DENTRO del lienzo: el
        /// usuario nunca la veía entrar, solo aparecer adentro (lo cazó la revisión
        /// adversarial de FER-41). Con 0.12 la corriente termina de encenderse todavía fuera
        /// de cuadro y cruza el borde ya opaca, que es el gesto que se aprobó.
        public static let alfaVentana = 0.12
        /// Retardo de arranque de cada corriente (la última define `escalonMax`).
        public static let retardos: [Double] = [0.02, 0.07, 0.04, 0.09, 0.00, 0.11]
        public static var escalonMax: Double { retardos.max() ?? 0 }
        /// La última corriente termina de llegar.
        public static var llegadaFin: Double { escalonMax + viaje }
        /// El respiro: el orbe ya armado se sostiene abajo, quieto.
        public static let respiro = 0.21
        public static var respiroFin: Double { llegadaFin + respiro }
        /// El ascenso al cénit.
        public static let ascenso = 0.24
        public static var ascensoFin: Double { respiroFin + ascenso }
        /// En qué punto del ascenso queda el REBASE (y de ahí el orbe se posa). Después de
        /// esta cima queda poco viaje a propósito: el asentamiento es un detalle, no un tramo.
        public static let cimaAscenso = 0.78
        /// El teñido ARRANCA antes de que termine el ascenso (se solapa con su cola: el
        /// color llega mientras el orbe todavía se está posando, no después de un silencio).
        public static let tinteIni = 0.82
        public static let tinteFin = 0.98
        /// El especular se enciende DESPUÉS del teñido (CA-2.5).
        public static let especularIni = 0.90
        public static let especularFin = 1.0
    }

    // MARK: Curvas

    /// Desaceleración pura (easeOutCubic): la corriente entra rápido y se posa. La curva del
    /// viaje de llegada.
    public static func desacelera(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        let v = 1 - c
        return 1 - v * v * v
    }

    /// La altura del orbe durante el ascenso, en y del lienzo: sube del punto de reunión
    /// hasta REBASAR el cénit por `sobrepaso` pt y de ahí se posa.
    ///
    /// Son dos smoothsteps encadenados, no una curva con un bulto restado: así el rebase
    /// vale EXACTAMENTE el token en vez de ser el residuo de restar dos curvas que no
    /// terminan juntas (el primer intento medía 1.5 pt de 7 declarados porque en el pico del
    /// bulto el avance suave todavía iba 5 pt corto). La velocidad se anula en el quiebre,
    /// que es justo lo que el ojo lee como asentarse.
    public static func alturaAscenso(_ u: Double) -> CGFloat {
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

    // MARK: Reparto de la esfera en corrientes

    /// A qué corriente pertenece la partícula `i`. El corte va por el ángulo en el plano de
    /// pantalla (x → derecha, y → abajo) con la esfera SIN GIRAR, así que cada corriente sale
    /// como un gajo contiguo del disco en vez de un revoltijo salpicado por toda la esfera
    /// (que leería como estática, no como materia que llega junta). Durante la llegada el orbe
    /// gira ~20°, así que los gajos se cizallan un poco respecto del corte original: a este
    /// giro no se nota, pero el reparto es exacto en t = 0, no a lo largo de todo el viaje.
    public static func corriente(_ i: Int, de n: Int) -> Int {
        let d = EcosistemaSimulacion.direccion(i, de: n)
        let ang = atan2(d.y, d.x) + .pi              // (0, 2π]
        let k = Int(ang / (2 * .pi) * Double(Geometria.corrientes))
        // El clamp no es decorativo: con `n` IMPAR la dirección del ecuador da `y = 0` exacto,
        // `atan2(0, x<0) + π` vale 2π clavado y `k` se sale por arriba. Con el `n` par de
        // producción no pasa, pero el reparto no debe depender de esa paridad.
        return min(max(0, k), Geometria.corrientes - 1)
    }

    /// Lee `tabla[i]` repitiendo el último elemento si la tabla es más corta, y cayendo a
    /// `porDefecto` si está VACÍA. Existe porque `min(i, count - 1)` con una tabla vacía da
    /// `-1`, e indexar con −1 en Swift no clampa: revienta. Un desalineo entre `corrientes` y
    /// sus tablas tiene que degradar a una animación fea, nunca a un crash en el primer frame
    /// del arranque de la app.
    static func enTabla<T>(_ tabla: [T], _ i: Int, porDefecto: T) -> T {
        tabla.isEmpty ? porDefecto : tabla[min(max(0, i), tabla.count - 1)]
    }

    // MARK: El cuadro

    public struct Cuadro: Equatable, Sendable {
        /// Desvío de cada corriente respecto de su posición final, en pt del lienzo.
        public var desvios: [CGSize]
        /// Alfa de cada corriente (0 antes de que arranque su viaje).
        public var alfas: [Double]
        /// Centro del orbe en este instante.
        public var centro: CGPoint
        /// Giro de la esfera (rad).
        public var rotacion: Double
        /// 0 = tinta neutra · 1 = el clima del veredicto.
        public var tinte: Double
        /// Alfa del especular.
        public var especular: Double
        /// Alfa global de la entrada — el fundido con el que se retira.
        public var alfa: Double
    }

    /// El cuadro de la entrada en el instante `t` (segundos desde que arrancó).
    ///
    /// `reduce` = «Reducir movimiento»: NO hay viaje ni ascenso. El orbe aparece ya asentado
    /// en el cénit y ya teñido, y solo se sostiene `duracionReduce` antes del fundido —
    /// congelar el viaje a medias sería enseñar una composición que nadie diseñó.
    public static func cuadro(t crudo: TimeInterval, reduce: Bool = false) -> Cuadro {
        // Un `t` no finito entra una sola vez y contamina todo lo que toca: las comparaciones
        // con NaN son siempre falsas, así que los `min`/`max` de las curvas lo dejan pasar y
        // el giro sale NaN. Se ataja aquí, en la puerta, para que «función pura del tiempo»
        // sea cierto para CUALQUIER entrada y no solo para las razonables.
        let t = crudo.isFinite ? crudo : 0
        let total = LiquidEntradaMotion.duracionTotal

        guard !reduce else {
            return Cuadro(desvios: [CGSize](repeating: .zero, count: Geometria.corrientes),
                          alfas: [Double](repeating: 1, count: Geometria.corrientes),
                          centro: Geometria.cenit,
                          rotacion: 0,
                          tinte: 1,
                          especular: 1,
                          alfa: 1 - rampa(t, de: LiquidEntradaMotion.duracionReduce,
                                          a: LiquidEntradaMotion.duracionReduce + LiquidEntradaMotion.salida))
        }

        // El reloj normalizado: 0 al abrir, 1 al cerrar la coreografía.
        let u = total > 0 ? t / total : 1

        // ── Llegada: cada corriente viaja de su origen a cero, con su propio retardo.
        var desvios = [CGSize](repeating: .zero, count: Geometria.corrientes)
        var alfas = [Double](repeating: 0, count: Geometria.corrientes)
        for c in 0..<Geometria.corrientes {
            let d = enTabla(Guion.retardos, c, porDefecto: 0)
            let v = desacelera((u - d) / Guion.viaje)
            let origen = enTabla(Geometria.origenes, c, porDefecto: .zero)
            desvios[c] = CGSize(width: origen.width * (1 - v), height: origen.height * (1 - v))
            // La corriente termina de encenderse mientras TODAVÍA viene de fuera de cuadro,
            // así que cruza el borde ya opaca: se la ve entrar, no aparecer adentro.
            alfas[c] = min(1, max(0, (u - d) / (Guion.viaje * Guion.alfaVentana)))
        }

        // ── Ascenso: del punto de reunión al cénit, rebasando `sobrepaso` pt en el camino.
        // Fuera de la ventana el avance queda negativo o >1 y `alturaAscenso` lo clampa, así
        // que durante el respiro el orbe está quieto en la reunión y al final, en el cénit.
        let y = alturaAscenso((u - Guion.respiroFin) / Guion.ascenso)

        return Cuadro(
            desvios: desvios,
            alfas: alfas,
            centro: CGPoint(x: Geometria.cenit.x, y: y),
            rotacion: EcosistemaSimulacion.fase(t * Geometria.giro),
            tinte: rampa(u, de: Guion.tinteIni, a: Guion.tinteFin),
            especular: rampa(u, de: Guion.especularIni, a: Guion.especularFin),
            alfa: 1 - rampa(t, de: total, a: total + LiquidEntradaMotion.salida))
    }

    /// Cuánto vive la entrada de punta a punta (coreografía + fundido de salida). El host la
    /// desmonta con esto, no con un número suelto que se desfase del guion.
    public static func duracion(reduce: Bool = false) -> TimeInterval {
        (reduce ? LiquidEntradaMotion.duracionReduce : LiquidEntradaMotion.duracionTotal)
            + LiquidEntradaMotion.salida
    }

    /// El instante en que el color empieza a existir. La vista lee el veredicto AQUÍ y no al
    /// montarse: a los 0 ms casi nunca está calculado, y leerlo por frame dejaría que uno que
    /// aterriza a media revelación saltara de color a la vista del usuario. Con «Reducir
    /// movimiento» no hay revelación que esperar, así que es inmediato.
    public static func instanteDelTeñido(reduce: Bool = false) -> TimeInterval {
        reduce ? 0 : LiquidEntradaMotion.duracionTotal * Guion.tinteIni
    }
}
