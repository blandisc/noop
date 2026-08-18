import Foundation
import CoreGraphics

// MARK: - «Hoy en atmósfera» (FER-118) · El polvo
//
// El fondo de Hoy es blanco puro y lo único vivo detrás del vidrio son estas partículas: un
// campo de motas que deriva lentamente hacia arriba, respira en alfa, toma el color del
// veredicto (con un 20 % de las cuatro identidades del héroe) y se desplaza un 22 % con el
// scroll. Nada más: sin halo, sin aurora, sin plasta (decisión del dueño, 2026-08-17).
//
// Esta enum ES LA SPEC. La partícula `i` en el instante `t` se deriva de su índice con un hash
// entero — ni la CPU ni la GPU reciben una lista de partículas — y el shader `vsPolvo` de
// `EcosistemaShaders.msl` es su espejo campo a campo (misma aritmética `uint32`, mismas
// fórmulas, mismos tokens de `Fisica` viajando en el uniform). El `Canvas` de respaldo y los
// tests recorren esta función; el contrato compartido es la función, no el rasterizado (la
// misma regla de FER-13 para el héroe).
public enum PolvoSimulacion {

    /// Los tokens del polvo. Cada uno viaja al shader en `EcosistemaPolvoU`: el shader no
    /// tiene constantes propias.
    public enum Fisica {
        /// Área por partícula (pt²): 402×874 / 1 500 del prototipo aprobado.
        public static let ptPorParticula: CGFloat = 234
        public static let nMin = 600
        public static let nMax = 2000
        public static let radioMin: CGFloat = 0.6
        public static let radioMax: CGFloat = 2.3
        /// alfa = (alfaBase + alfaRango·densidad)·(0.5 + 0.5·h)·respiración
        public static let alfaBase: Double = 0.07
        public static let alfaRango: Double = 0.24
        /// La densidad sube con la altura: detrás del héroe (arriba) hay menos polvo que detrás
        /// de la cuadrícula. `densidadPiso` arriba, 1 abajo, rampa entre `desde` y `hasta` (en
        /// fracciones del alto del lienzo).
        public static let densidadPiso: Double = 0.35
        public static let densidadDesde: Double = 0.23
        public static let densidadHasta: Double = 0.80
        /// respiración = (1 − amp) + amp·sin(w·t + φ) — o sea el alfa oscila entre 1 − 2·amp (0.44) y 1,
        /// como en el prototipo aprobado; w ∈ [wMin, wMin + wRango] rad/s.
        public static let respiracionAmp: Double = 0.28
        public static let respiracionWMin: Double = 0.5
        public static let respiracionWRango: Double = 0.9
        /// Deriva en pt/s: horizontal simétrica en ±derivaXMax; vertical SIEMPRE hacia arriba
        /// entre derivaYMin y derivaYMin + derivaYRango.
        public static let derivaXMax: Double = 2.1
        public static let derivaYMin: Double = 0.9
        public static let derivaYRango: Double = 3.0
        /// Cuánto se mueve el campo con el scroll (fracción del desplazamiento).
        public static let parallax: CGFloat = 0.22
        /// Sin veredicto (calibración, T3, T4, T5, base rancia): tinta neutra y alfa × 0.55.
        public static let alfaNeutra: Double = 0.55
        /// 80 % del polvo lleva el clima; el resto se reparte en cuartos iguales entre las cuatro
        /// identidades del héroe (reposo · sueño · vigía temp · vigía resp).
        public static let umbralClima: Double = 0.80
    }

    /// De qué color es una mota. Los colores concretos los pone `EcosistemaPaleta` (la misma del
    /// héroe): así héroe y polvo comparten un solo diccionario.
    public enum Tono: Equatable, Sendable {
        case clima, reposo, sueno, vigiaTemp, vigiaResp, neutra
    }

    public struct Particula: Equatable, Sendable {
        public let centro: CGPoint
        public let radio: CGFloat
        public let alfa: Double
        public let tono: Tono
    }

    // MARK: Hash

    /// Hash entero de Wang. `&*`/`&+` a propósito: la aritmética `uint32` con wrap es la que el
    /// shader reproduce bit a bit.
    static func wang(_ v: UInt32) -> UInt32 {
        var x = v
        x = (x ^ 61) ^ (x >> 16)
        x = x &* 9
        x = x ^ (x >> 4)
        x = x &* 0x27d4_eb2d
        x = x ^ (x >> 15)
        return x
    }

    /// El `k`-ésimo número «aleatorio» de la partícula `i`, en [0, 1). Determinista: la misma
    /// (i, k) da siempre lo mismo, en la CPU y en la GPU.
    public static func hash(_ i: UInt32, _ k: UInt32) -> Double {
        Double(wang(i &* 0x9E37_79B1 &+ k &* 0x85EB_CA77)) / 4_294_967_296.0
    }

    // MARK: Cuenta y posición

    /// Cuántas partículas caben en un lienzo: área / `ptPorParticula`, acotado.
    public static func cuenta(lienzo: CGSize) -> Int {
        let area = max(0, lienzo.width) * max(0, lienzo.height)
        let n = Int(area / Fisica.ptPorParticula)
        return min(Fisica.nMax, max(Fisica.nMin, n))
    }

    /// Módulo positivo: `wrap(-3, 10) == 7`. Es lo que vuelve infinito al campo (una mota que
    /// sale por arriba entra por abajo).
    static func wrap(_ v: Double, _ m: Double) -> Double {
        guard m > 0 else { return 0 }
        let r = v.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }

    /// La partícula `i` en el instante `t` (segundos desde que el fondo apareció — NUNCA el
    /// reloj absoluto de la app: ver `EcosistemaFisicaU` sobre la precisión de un `Float`),
    /// en un lienzo de `lienzo` puntos, con el `desplazamiento` del scroll (≥ 0), en tinta
    /// `neutra` o no, y `still` (Reduce Motion / renders): sin tiempo y sin parallax.
    public static func particula(indice: Int, t: TimeInterval, lienzo: CGSize,
                                 desplazamiento: CGFloat, neutra: Bool,
                                 still: Bool) -> Particula {
        let i = UInt32(truncatingIfNeeded: max(0, indice))
        func h(_ k: UInt32) -> Double { hash(i, k) }
        let W = Double(lienzo.width), H = Double(lienzo.height)
        let tt = still ? 0 : t
        let desp = still ? 0 : Double(max(0, desplazamiento))

        let x0 = h(0) * W, y0 = h(1) * H
        let radio = Fisica.radioMin + CGFloat(h(2)) * (Fisica.radioMax - Fisica.radioMin)
        let vx = (h(6) - 0.5) * 2 * Fisica.derivaXMax
        let vy = -(Fisica.derivaYMin + h(7) * Fisica.derivaYRango)
        let x = wrap(x0 + vx * tt, W)
        let y = wrap(y0 + vy * tt - Double(Fisica.parallax) * desp, H)

        // Densidad por altura, con la `y` YA envuelta: detrás de la cuadrícula siempre hay más.
        let rampa = H > 0 ? (y / H - Fisica.densidadDesde) / (Fisica.densidadHasta - Fisica.densidadDesde) : 0
        let f = Fisica.densidadPiso + (1 - Fisica.densidadPiso) * min(1, max(0, rampa))
        let w = Fisica.respiracionWMin + h(4) * Fisica.respiracionWRango
        let fase = 2 * Double.pi * h(5)
        let resp = still ? 1 : (1 - Fisica.respiracionAmp) + Fisica.respiracionAmp * sin(w * tt + fase)
        let alfa = (Fisica.alfaBase + Fisica.alfaRango * f) * (0.5 + 0.5 * h(3)) * resp
            * (neutra ? Fisica.alfaNeutra : 1)

        let tono: Tono
        if neutra {
            tono = .neutra
        } else {
            let k = h(8)
            if k < Fisica.umbralClima {
                tono = .clima
            } else {
                let satelites: [Tono] = [.reposo, .sueno, .vigiaTemp, .vigiaResp]
                let cuarto = (1 - Fisica.umbralClima) / Double(satelites.count)
                let idx = min(satelites.count - 1, Int((k - Fisica.umbralClima) / cuarto))
                tono = satelites[idx]
            }
        }
        return Particula(centro: CGPoint(x: x, y: y), radio: radio, alfa: alfa, tono: tono)
    }
}
