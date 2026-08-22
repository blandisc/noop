import SwiftUI

// MARK: - Liquid Glass · Frase del nivel destacado (recuperación /inject, L2)
//
// La frase DISPLAY del explorador de niveles: el nombre del nivel destacado leído en
// grande y en el tono del dato, con el conteo que lo sostiene debajo en voz de lectura
// («12 de tus últimos 14 días»). Recupera la jerarquía de dos escalones de la vieja
// `MetricLevelsExplorer.phrase` (grotesk 28 en el tono + subhead secundaria), que el
// primer pase Liquid había aplanado a una sola línea de `LiquidReadingLine`.
//
// TIPOGRAFÍA — el nivel usa `LiquidType.nivelTitulo` (18/700, relativo a `.title3`; su
// justificación vive junto al token en `LiquidType.swift`): en esta hoja el nivel se lee como
// DATO —es el veredicto de la ventana— con una voz propia, más chica que el numeral `valorL`
// que usaba el primer pase (revote /inject) para que no compita con el héroe.
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
    private let sello: String?

    /// - Parameters:
    ///   - nivel: el nombre YA localizado del nivel destacado («En tu base»); `nil` cuando
    ///     no hay lectura que destacar.
    ///   - conteo: la frase de soporte YA localizada («12 de tus últimos 14 días»).
    ///   - tono: el tono del dato — tiñe SOLO el nivel, nunca el conteo.
    ///   - sinLectura: el texto que sustituye al nivel cuando `nivel` es `nil` («Hoy sin
    ///     lectura»), en tinta/500. Obligatorio en la práctica para todo caller que pueda
    ///     pasar `nivel: nil`.
    ///   - sello: etiqueta corta de la ventana del dato («HOY · 3 AGO»), YA compuesta por
    ///     el caller (contrato D3). Opcional: `nil` no pinta nada.
    public init(nivel: String?, conteo: String, tono: Color,
                sinLectura: String? = nil, sello: String? = nil) {
        self.nivel = nivel
        self.conteo = conteo
        self.tono = tono
        self.sinLectura = sinLectura
        self.sello = sello
    }

    /// El tracking hermano del nivel: `valorL` no trae uno propio en `LiquidType` porque
    /// nace como token de numeral; a 22 pt en Grotesk la palabra pide este apriete leve
    /// para leerse como un solo bloque (mismo signo que el resto de la escala display).
    private static let nivelTracking: CGFloat = -0.3

    /// XC7-06 / Q8-12 (FER-128) · la misma regla que `LiquidSheetHeader`: a tamaños de
    /// accesibilidad el sello baja a su propia línea en vez de estrangular el nivel.
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public var body: some View {
        let apilado = tamanoTexto >= .accessibility1
        let fila = apilado
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiquidSpace.s100))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: LiquidSpace.s200))
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            if let titulo = nivel ?? sinLectura {
                fila {
                    Text(verbatim: titulo)
                        .font(LiquidType.nivelTitulo)
                        .tracking(Self.nivelTracking)
                        .foregroundStyle(nivel != nil ? tono : LiquidColor.tinta500)
                        // Escala con Dynamic Type y ENVUELVE: el nivel nunca se trunca.
                        .fixedSize(horizontal: false, vertical: true)
                    if let sello {
                        if !apilado { Spacer(minLength: LiquidSpace.s200) }
                        // El MISMO sello que las 9 hojas de métrica (`LiquidSheetHeader`): `filaRango`
                        // y el tono de TEXTO (ámbar demotado a `atencionTexto`, AA — el crudo mide
                        // 3.8:1 a 13 pt) (FER-128 r7/r8 — cambiaba de familia, tamaño y tono solo aquí).
                        Text(verbatim: sello)
                            .font(LiquidType.filaRango)
                            .foregroundStyle(nivel != nil ? LiquidSheetHeader.tonoTexto(tono) : LiquidColor.tinta500)
                            .lineLimit(apilado ? nil : 1)
                            .layoutPriority(1)
                    }
                }
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
        // Con sello (F0.2): ventana del dato a la derecha del nivel.
        LiquidFraseNivel(nivel: "En tu base",
                         conteo: "12 de tus últimos 14 días",
                         tono: LiquidColor.cian,
                         sello: "MEDIA · 30 DÍAS")
        // Sin lectura hoy: el texto del caller, en tinta/500 (jamás en el tono).
        LiquidFraseNivel(nivel: nil,
                         conteo: "14 noches con datos en este rango",
                         tono: LiquidColor.indigo,
                         sinLectura: "Hoy sin lectura")
        // Texto largo (es-MX + Dynamic Type): envuelve, nunca trunca.
        LiquidFraseNivel(nivel: "Bastante sobre tu base",
                         conteo: "3 de tus últimas 90 noches con datos en este rango",
                         tono: LiquidColor.ambar)
        // AX (preparación, la app capa en xxxLarge): nivel y sello apilados, el sello entero.
        LiquidFraseNivel(nivel: "Dentro de tu patrón",
                         conteo: "Tus dos señales amanecieron donde siempre.",
                         tono: LiquidColor.verdeProfundo,
                         sello: "ANOCHE · 3 AGO")
            .environment(\.dynamicTypeSize, .accessibility3)
    }
    .padding(LiquidSpace.s550)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
