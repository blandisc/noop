import SwiftUI

// MARK: - Liquid Glass · Cajita de lectura (FER-102, pantallas de detalle)
//
// El mosaico de una pantalla de detalle: [rótulo · valor + unidad · pie]. Papel OPACO con el
// chrome del sistema (`.superficieSolida`, r/tarjeta), en rejilla de 2 o 3.
//
// POR QUÉ NO ES `LiquidMetricTile`: aquel es el tile del grid de Hoy y lleva gota de ícono +
// delta con valencia. Esta es una lectura desnuda de una sub-métrica dentro de una sección que
// ya tiene su franja diciendo de qué habla — un ícono por cajita sería ruido, y el delta ya
// vive en la gráfica de arriba. Comparten receta y radio; no comparten anatomía.
//
// POR QUÉ EL VALOR VA EN TINTA Y NO EN EL TONO (pasada /ui): seis cajitas del mismo tono debajo
// de un campo ya teñido es demasiado color — la página sigue siendo tinta sobre papel
// (DESIGN.md §8.4-2). El tono se reserva para las marcas y para la cajita que de verdad es la
// protagonista de su sección, vía `tono:`.
//
// SIN CHEVRON: el tile tocable del sistema no lo lleva — el press y la háptica dicen que es
// tocable, y seis chevrons en una rejilla leen como una lista de ajustes.

/// Una lectura en cajita dentro de una sección de detalle: rótulo, valor con unidad y un pie.
public struct LiquidCajita: View {
    private let rotulo: String
    private let valor: String
    private let unidad: String
    private let pie: String?
    private let tono: Color?
    private let compacto: Bool
    private let a11yValor: String?
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - tono: tiñe el valor. `nil` (lo normal) lo deja en tinta/900.
    ///   - compacto: usa `valorM` (17) en vez de `valorL` (22) — para rejillas de 3, donde
    ///     un rango como «5:48 – 8:31» a 22 se parte en dos líneas.
    ///   - a11yValor: cómo lo dicta VoiceOver («7 horas 12 minutos» y no «siete doce»).
    public init(rotulo: String,
                valor: String,
                unidad: String = "",
                pie: String? = nil,
                tono: Color? = nil,
                compacto: Bool = false,
                a11yValor: String? = nil,
                action: (() -> Void)? = nil) {
        self.rotulo = rotulo
        self.valor = valor
        self.unidad = unidad
        self.pie = pie
        self.tono = tono
        self.compacto = compacto
        self.a11yValor = a11yValor
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { contenido }
                .buttonStyle(.liquidPress)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(rotulo))
                .accessibilityValue(Text(a11yLabel))
                .accessibilityAddTraits(.isButton)
        } else {
            contenido
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(rotulo))
                .accessibilityValue(Text(a11yLabel))
        }
    }

    /// «— » se dicta «guion»: cuando no hay dato, VoiceOver debe decir «sin dato».
    private var a11yLabel: String {
        if valor == LiquidCajita.sinDato { return String(localized: "no data") }
        let base = unidad.isEmpty ? valor : "\(valor) \(unidad)"
        let dicho = a11yValor ?? base
        guard let pie else { return dicho }
        return "\(dicho), \(pie)"
    }

    /// El texto del valor ausente. Una pantalla honesta prefiere el guion a un cero inventado.
    public static let sinDato = "—"

    private var contenido: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(rotulo)
                .font(LiquidType.label)
                .tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
                Text(valor)
                    .font(compacto ? LiquidType.valorM : LiquidType.valorL)
                    .foregroundStyle(valor == Self.sinDato
                                     ? LiquidColor.tinta500
                                     : (tono ?? LiquidColor.tinta900))
                if !unidad.isEmpty {
                    Text(unidad)
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if let pie {
                Text(pie)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }
}

/// La rejilla de cajitas de una sección. Se apila en una columna en tamaños de accesibilidad:
/// a AX3 dos cajitas lado a lado truncan su valor (DESIGN.md §8.8).
public struct LiquidCajitaGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var tipo
    private let columnas: Int
    private let content: Content

    public init(columnas: Int = 2, @ViewBuilder content: () -> Content) {
        self.columnas = columnas
        self.content = content()
    }

    public var body: some View {
        let n = tipo.isAccessibilitySize ? 1 : columnas
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpace.s250),
                                 count: n),
                  spacing: LiquidSpace.s250) {
            content
        }
    }
}

#if DEBUG
#Preview("Liquid · Cajitas") {
    ScrollView {
        VStack(spacing: LiquidSpace.s550) {
            LiquidCajitaGrid {
                LiquidCajita(rotulo: "Rendimiento", valor: "88", unidad: "%",
                             pie: "vs tu necesidad", action: {})
                LiquidCajita(rotulo: "Eficiencia", valor: "92", unidad: "%",
                             pie: "vs tiempo en cama", action: {})
                LiquidCajita(rotulo: "Latencia", valor: LiquidCajita.sinDato,
                             pie: "sin dato en Apple Salud")
                LiquidCajita(rotulo: "Respiración", valor: "14.2", pie: "rpm",
                             tono: LiquidColor.azul, action: {})
            }
            LiquidCajitaGrid(columnas: 3) {
                LiquidCajita(rotulo: "Promedio", valor: "7:04", pie: "30 noches",
                             compacto: true, a11yValor: "7 horas 4 minutos")
                LiquidCajita(rotulo: "Rango", valor: "5:48 – 8:31", pie: "mín · máx",
                             compacto: true)
                LiquidCajita(rotulo: "Anoche", valor: "7:12", pie: "suficiente",
                             tono: LiquidColor.indigo, compacto: true,
                             a11yValor: "7 horas 12 minutos")
            }
        }
        .padding(LiquidSpace.s550)
    }
    .background(LiquidColor.fondoGradient)
}
#endif
