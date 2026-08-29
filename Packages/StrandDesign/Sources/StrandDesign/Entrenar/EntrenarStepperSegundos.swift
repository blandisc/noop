import SwiftUI

// MARK: - EntrenarStepperSegundos — stepper de descanso (FER-197 · Ola 1)
//
// El control «−  1:30  +» de un ajuste en segundos (descanso entre series). El valor llega YA
// FORMATEADO (mm:ss) del caller — el componente no sabe de segundos ni de formato, solo de
// layout y de estado (deshabilitado en los extremos: 0 s no baja más, el tope de la hoja no
// sube más). Pensado como el `control` de una `EntrenarFilaHerramienta`.

public struct EntrenarStepperSegundos: View {
    private let valor: String
    private let tono: LiquidTono
    private let puedeBajar: Bool
    private let puedeSubir: Bool
    private let onBajar: () -> Void
    private let onSubir: () -> Void

    public init(valor: String, tono: LiquidTono = .neutro,
                puedeBajar: Bool = true, puedeSubir: Bool = true,
                onBajar: @escaping () -> Void, onSubir: @escaping () -> Void) {
        self.valor = valor
        self.tono = tono
        self.puedeBajar = puedeBajar
        self.puedeSubir = puedeSubir
        self.onBajar = onBajar
        self.onSubir = onSubir
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s300) {
            boton("minus", habilitado: puedeBajar, action: onBajar,
                  etiqueta: String(localized: "Decrease", bundle: .main))
            Text(valor)
                .font(InstrumentoType.groteskNumber(17, weight: .bold))
                .foregroundStyle(tono == .neutro ? LiquidColor.tinta900 : tono.rotulo)
                .numeroVivo(value: valor)
                .frame(minWidth: EntrenarStepperSegundosMetrics.valorAncho)
                .accessibilityHidden(true)
            boton("plus", habilitado: puedeSubir, action: onSubir,
                  etiqueta: String(localized: "Increase", bundle: .main))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: valor))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if puedeSubir { onSubir() }
            case .decrement: if puedeBajar { onBajar() }
            @unknown default: break
            }
        }
    }

    private func boton(_ system: String, habilitado: Bool, action: @escaping () -> Void,
                       etiqueta: String) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))   // token-exempt: glifo de control
                .foregroundStyle(habilitado ? LiquidColor.tinta900 : LiquidColor.tinta500)
                .frame(width: EntrenarStepperSegundosMetrics.boton,
                       height: EntrenarStepperSegundosMetrics.boton)
                .liquidGlass(.pastillaSolida)
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(!habilitado)
        .accessibilityLabel(Text(verbatim: etiqueta))
    }
}

private enum EntrenarStepperSegundosMetrics {
    static let boton: CGFloat = 36
    static let valorAncho: CGFloat = 52
}

#if DEBUG
#Preview("EntrenarStepperSegundos · reposo, en el tope, en el piso") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        EntrenarStepperSegundos(valor: "1:30", tono: .rosa, onBajar: {}, onSubir: {})
        EntrenarStepperSegundos(valor: "5:00", tono: .rosa, puedeSubir: false, onBajar: {}, onSubir: {})
        EntrenarStepperSegundos(valor: "0:00", tono: .rosa, puedeBajar: false, onBajar: {}, onSubir: {})
        EntrenarStepperSegundos(valor: "1:30", onBajar: {}, onSubir: {})   // neutro, sin tono
    }
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .rosa)
}
#endif
