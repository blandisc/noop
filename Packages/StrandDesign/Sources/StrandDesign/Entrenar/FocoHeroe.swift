import SwiftUI

// MARK: - FocoHeroe — numeral + steppers del modo enfoque (FER-170 · F5)
//
// Mock `hoja-pantallas.html` P6 `.step` + `.heroN` (+ `small`): fila centrada − valor+unidad ＋.

/// Constantes locales del héroe de foco (mock `.step` / `.heroN`). No viven en `HojaMetrics`.
private enum FocoHeroeMetrics {
    /// `.heroN` `font-size: 46px`.
    static var valorSize: CGFloat { 46 }
    /// `.heroN` `letter-spacing: -2px`.
    static var valorTracking: CGFloat { -2 }
    /// `.heroN small` `font-size: 14px`.
    static var unidadSize: CGFloat { 14 }
    /// `.step` `width/height: 38px`.
    static var stepDiametro: CGFloat { 38 }
    /// `.step` glifo `font-size: 16px`.
    static var stepGlifoSize: CGFloat { 16 }
    /// `.step` canto `0 0 0 .5px var(--canto)` (= tinta 8 %).
    static var stepCantoAlfa: Double { 0.08 }
    /// Gap de la fila (spec F5; mock inline sin gap nombrado).
    static var filaGap: CGFloat { 18 }
    /// Blanco táctil mínimo (HIG).
    static var hitMin: CGFloat { 44 }
    /// Glifo − (U+2212) del mock `.step`.
    static var glifoMenos: String { "−" }
    /// Glifo ＋ (U+FF0B) del mock `.step`.
    static var glifoMas: String { "＋" }
}

/// Héroe de captura en modo enfoque: steppers circulares flanqueando el numeral + unidad.
public struct FocoHeroe: View {
    private let valor: String
    private let unidad: String
    private let onMenos: () -> Void
    private let onMas: () -> Void
    private let menosHabilitado: Bool
    private let masHabilitado: Bool
    private let etiquetaAccesible: String
    private let etiquetaMenos: String?
    private let etiquetaMas: String?

    /// - Parameters:
    ///   - valor: ya formateado (p. ej. `"82.5"`).
    ///   - unidad: ya localizada, con el espacio que pida el mock (p. ej. `" kg"`).
    ///   - etiquetaAccesible: rótulo VO del valor (p. ej. «Peso, 82.5 kilogramos»).
    ///   - etiquetaMenos / etiquetaMas: rótulos VO de los steppers; `nil` → glifos «−» / «+».
    public init(
        valor: String,
        unidad: String,
        onMenos: @escaping () -> Void,
        onMas: @escaping () -> Void,
        menosHabilitado: Bool = true,
        masHabilitado: Bool = true,
        etiquetaAccesible: String,
        etiquetaMenos: String? = nil,
        etiquetaMas: String? = nil
    ) {
        self.valor = valor
        self.unidad = unidad
        self.onMenos = onMenos
        self.onMas = onMas
        self.menosHabilitado = menosHabilitado
        self.masHabilitado = masHabilitado
        self.etiquetaAccesible = etiquetaAccesible
        self.etiquetaMenos = etiquetaMenos
        self.etiquetaMas = etiquetaMas
    }

    public var body: some View {
        HStack(alignment: .center, spacing: FocoHeroeMetrics.filaGap) {
            stepper(
                glifo: FocoHeroeMetrics.glifoMenos,
                habilitado: menosHabilitado,
                etiqueta: etiquetaMenos ?? FocoHeroeMetrics.glifoMenos,
                action: onMenos)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: valor)
                    .font(InstrumentoType.groteskNumber(
                        FocoHeroeMetrics.valorSize,
                        weight: .bold,
                        relativeTo: .largeTitle))
                    .tracking(FocoHeroeMetrics.valorTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(verbatim: unidad)
                    .font(InstrumentoType.grotesk(
                        FocoHeroeMetrics.unidadSize,
                        weight: .semibold,
                        relativeTo: .footnote))
                    .foregroundStyle(LiquidColor.tinta500)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: etiquetaAccesible))

            stepper(
                glifo: FocoHeroeMetrics.glifoMas,
                habilitado: masHabilitado,
                etiqueta: etiquetaMas ?? "+",
                action: onMas)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepper(
        glifo: String,
        habilitado: Bool,
        etiqueta: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: glifo)
                .font(InstrumentoType.grotesk(
                    FocoHeroeMetrics.stepGlifoSize,
                    weight: .bold,
                    relativeTo: .callout))
                .foregroundStyle(LiquidColor.tinta700)
                .frame(
                    width: FocoHeroeMetrics.stepDiametro,
                    height: FocoHeroeMetrics.stepDiametro)
                .background {
                    // R5 (ronda 2 del gate, Grok G8): `LiquidColor.vidrioStep` — antes `Color.white
                    // .opacity(...)` crudo.
                    Circle()
                        .fill(LiquidColor.vidrioStep)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LiquidColor.tinta900.opacity(FocoHeroeMetrics.stepCantoAlfa),
                            lineWidth: 0.5)
                }
        }
        .buttonStyle(.liquidPress)
        .disabled(!habilitado)
        .frame(minWidth: FocoHeroeMetrics.hitMin, minHeight: FocoHeroeMetrics.hitMin)
        .contentShape(Circle())
        .accessibilityLabel(Text(verbatim: etiqueta))
    }
}

#if DEBUG
#Preview("FocoHeroe · kg") {
    FocoHeroe(
        valor: "82.5",
        unidad: " kg",
        onMenos: {},
        onMas: {},
        etiquetaAccesible: "Peso, 82.5 kilogramos",
        etiquetaMenos: "menos",
        etiquetaMas: "más")
    .padding(24)
    .background(LiquidColor.fondoGradient)
}

#Preview("FocoHeroe · reps") {
    FocoHeroe(
        valor: "8",
        unidad: " reps",
        onMenos: {},
        onMas: {},
        menosHabilitado: false,
        etiquetaAccesible: "Repeticiones, 8",
        etiquetaMenos: "menos",
        etiquetaMas: "más")
    .padding(24)
    .background(LiquidColor.fondoGradient)
}
#endif
