import SwiftUI

// MARK: - Liquid Glass · Tarjeta de tendencia (FER-101 · pasada F4/F5, UX-09)
//
// La tarjeta «Qué mueve…» de las pantallas de detalle: overline en caja alta + el chip
// punteado «tendencia, no causa» + una o varias frases honestas de lectura, sobre la
// superficie sólida de sección (`liquidTarjetaSeccion`). Antes el chip punteado vivía
// copiado a mano en tres pantallas (Esfuerzo, Estrés, Temp de piel) con los mismos
// tokens; aquí se acuña UNA vez.
//
// POR QUÉ NO ES `LiquidPatternBlock`: aquel es la anotación quieta con barra lateral y
// SIN vidrio («Tu patrón» de la hoja de métrica). Esta es la tarjeta de sección con el
// chip-disclaimer — anatomía distinta, mismo espíritu.
//
// Contrato D3: strings YA localizados (el DS no conoce locales ni acuña copy — el chip
// llega como texto del caller). El caller oculta la tarjeta cuando no hay líneas.

public struct LiquidTendenciaCard: View {
    private let overline: String?
    private let chip: String
    private let lineas: [String]

    /// - Parameters:
    ///   - overline: el rótulo en caja alta («LO QUE VEMOS EN TU HISTORIAL»). `nil` cuando
    ///     la franja de la sección ya titula el bloque.
    ///   - chip: el disclaimer del chip punteado, YA localizado («tendencia, no causa»).
    ///   - lineas: las frases de lectura, YA localizadas. Vacío ⇒ no se dibuja nada.
    public init(overline: String? = nil, chip: String, lineas: [String]) {
        self.overline = overline
        self.chip = chip
        self.lineas = lineas
    }

    public var body: some View {
        // Sin líneas no hay tarjeta: un chip-disclaimer sin contenido es ruido (mismo
        // guard que `LiquidPatternBlock`).
        if lineas.isEmpty { EmptyView() } else { contenido }
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            HStack(alignment: .center, spacing: LiquidSpace.s200) {
                if let overline {
                    Text(overline)
                        .liquidLabel()
                        .foregroundStyle(LiquidColor.tinta500)
                }
                chipVista
            }
            ForEach(lineas.indices, id: \.self) { i in
                Text(verbatim: lineas[i])
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .liquidTarjetaSeccion()
        .accessibilityElement(children: .combine)
    }

    /// El chip punteado: cápsula con trazo discontinuo, tinta neutra — un disclaimer,
    /// nunca un dato (mismos tokens que llevaba la copia a mano de las tres pantallas).
    private var chipVista: some View {
        Text(chip)
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta700)
            .padding(.horizontal, LiquidSpace.s225)
            .padding(.vertical, LiquidSpace.s075)
            .overlay(
                Capsule().stroke(LiquidColor.tinta10,
                                 style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            )
    }
}

#if DEBUG
#Preview("Liquid · TendenciaCard") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // Con overline (Estrés: «lo que vemos en tu historial»).
        LiquidTendenciaCard(
            overline: "Lo que vemos en tu historial",
            chip: "tendencia, no causa",
            lineas: [
                "Tu estrés tiende a subir en las mañanas.",
                "«Weekly sync» tiende a coincidir con estrés más alto.",
            ])

        // Sin overline (la franja de la sección ya titula el bloque).
        LiquidTendenciaCard(
            chip: "tendencia, no causa",
            lineas: ["Tiende a correr más alto los días que amaneces más recuperado."])
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.ambar))
}
#endif
