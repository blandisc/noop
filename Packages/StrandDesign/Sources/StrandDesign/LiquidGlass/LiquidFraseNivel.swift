import SwiftUI

// MARK: - Liquid Glass · Frase del nivel destacado (recuperación /inject, L2)
//
// La frase DISPLAY del explorador de niveles: el nombre del nivel destacado leído en
// grande y en el tono del dato, con el conteo que lo sostiene debajo en voz de lectura
// («12 de tus últimos 14 días»). Recupera la jerarquía de dos escalones de la vieja
// `MetricLevelsExplorer.phrase` (grotesk 28 en el tono + subhead secundaria), que el
// primer pase Liquid había aplanado a una sola línea de `LiquidReadingLine`.
//
// TIPOGRAFÍA — decisión consciente (revote /inject, corrección de Grok): el nivel usa
// `LiquidType.valorL`, que es el token de NUMERAL (22/700 con dígitos tabulares), aunque
// aquí pinte una PALABRA. Es deliberado: en esta hoja el nivel se lee como DATO —es el
// veredicto de la ventana— y por eso hereda la voz del numeral. No se acuña un token
// nuevo para una sola pieza; los dígitos tabulares son inertes sobre texto sin cifras.
//
// Contrato D3: los tres strings llegan YA localizados y formateados del caller (el DS no
// conoce `MetricLevels` ni locales). `sinLectura` es el texto honesto de «hoy sin
// lectura» — el DS tampoco puede acuñarlo, así que si el caller no lo pasa, la frase
// simplemente se queda con su conteo en vez de inventar copy.

public struct LiquidFraseNivel: View {
    private let nivel: String?
    private let conteo: String
    private let tono: Color
    private let sinLectura: String?

    /// - Parameters:
    ///   - nivel: el nombre YA localizado del nivel destacado («En tu base»); `nil` cuando
    ///     no hay lectura que destacar.
    ///   - conteo: la frase de soporte YA localizada («12 de tus últimos 14 días»).
    ///   - tono: el tono del dato — tiñe SOLO el nivel, nunca el conteo.
    ///   - sinLectura: el texto que sustituye al nivel cuando `nivel` es `nil` («Hoy sin
    ///     lectura»), en tinta/500. Obligatorio en la práctica para todo caller que pueda
    ///     pasar `nivel: nil`.
    public init(nivel: String?, conteo: String, tono: Color, sinLectura: String? = nil) {
        self.nivel = nivel
        self.conteo = conteo
        self.tono = tono
        self.sinLectura = sinLectura
    }

    /// El tracking hermano del nivel: `valorL` no trae uno propio en `LiquidType` porque
    /// nace como token de numeral; a 22 pt en Grotesk la palabra pide este apriete leve
    /// para leerse como un solo bloque (mismo signo que el resto de la escala display).
    private static let nivelTracking: CGFloat = -0.3

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            if let titulo = nivel ?? sinLectura {
                Text(verbatim: titulo)
                    .font(LiquidType.valorL)
                    .tracking(Self.nivelTracking)
                    .foregroundStyle(nivel != nil ? tono : LiquidColor.tinta500)
                    // Escala con Dynamic Type y ENVUELVE: el nivel nunca se trunca.
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: conteo)
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Un solo elemento: «nivel, conteo». `.combine` los une sin que el DS invente
        // separador ni orden (los dos textos ya vienen del caller).
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Liquid · FraseNivel") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // Con lectura: el nivel manda, en el tono del dato.
        LiquidFraseNivel(nivel: "En tu base",
                         conteo: "12 de tus últimos 14 días",
                         tono: LiquidColor.cian)
        // Sin lectura hoy: el texto del caller, en tinta/500 (jamás en el tono).
        LiquidFraseNivel(nivel: nil,
                         conteo: "14 noches con datos en este rango",
                         tono: LiquidColor.indigo,
                         sinLectura: "Hoy sin lectura")
        // Texto largo (es-MX + Dynamic Type): envuelve, nunca trunca.
        LiquidFraseNivel(nivel: "Bastante sobre tu base",
                         conteo: "3 de tus últimas 90 noches con datos en este rango",
                         tono: LiquidColor.ambar)
    }
    .padding(LiquidSpace.s550)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
