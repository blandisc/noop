import Foundation

/// FER-51 · Motor de medios tonos de la Matriz: tramado ordenado (Bayer 4×4) con
/// partícula irregular DETERMINISTA por semilla. La densidad codifica el dato; la
/// irregularidad hace que los puntos sean «partículas» (el mismo material de los orbes).
/// F2 replica `semilla(chartID:index:)` en el shader Metal para que la disolución del
/// cosmos aterrice EXACTAMENTE donde el Canvas pinta — este archivo es el contrato.
public enum MatrizDither {

    /// Matriz de Bayer 4×4 canónica, fila-mayor, valores 0…15.
    public static let bayer4x4: [UInt8] = [
        0,  8,  2, 10,
        12, 4, 14,  6,
        3, 11,  1,  9,
        15, 7, 13,  5,
    ]

    /// ¿Se pinta la celda (x, y) con densidad `densidad` ∈ [0,1]?
    /// Umbral ordenado y determinista: densidad 0 no pinta nada, 1 lo pinta todo,
    /// 0.5 pinta exactamente la mitad de las celdas de cada bloque 4×4.
    public static func encendido(x: Int, y: Int, densidad: Double) -> Bool {
        let umbral = Double(bayer4x4[((y & 3) << 2) | (x & 3)]) / 16.0
        return densidad > umbral
    }

    /// Semilla estable por gráfica+punto — contrato público para el shader de F2.
    /// FNV-1a 64 del `chartID`, mezclado con el índice vía la constante áurea y SplitMix64.
    public static func semilla(chartID: String, index: Int) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in chartID.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3 }
        let mezcla = h &+ (UInt64(bitPattern: Int64(index)) &* 0x9e37_79b9_7f4a_7c15)
        return splitmix64(mezcla)
    }

    /// Irregularidad de partícula derivada SOLO de la semilla (SplitMix64):
    /// dScale ∈ [0.8, 1.25], dAlpha ∈ [0.75, 1.0], dx/dy ∈ [−0.5, 0.5] pt.
    public static func particula(_ semilla: UInt64) -> (dScale: Double, dAlpha: Double, dx: Double, dy: Double) {
        var s = semilla
        func siguiente() -> Double {
            s = splitmix64(s)
            return Double(s >> 11) * (1.0 / 9_007_199_254_740_992.0)
        }
        let dScale = 0.8 + siguiente() * 0.45
        let dAlpha = 0.75 + siguiente() * 0.25
        let dx = siguiente() - 0.5
        let dy = siguiente() - 0.5
        return (dScale, dAlpha, dx, dy)
    }

    private static func splitmix64(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9e37_79b9_7f4a_7c15
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
