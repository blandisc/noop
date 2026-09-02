import SwiftUI

// MARK: - EntrenarStepper — stepper de ajuste (FER-293)
//
// El control «−  valor  +» de una hoja-herramienta. El valor llega YA FORMATEADO del caller
// («+2,5 kg», «1:30», «8») — el componente no sabe de unidades ni de formato, solo de layout
// y de estado (deshabilitado en los extremos). Pensado como el `control` de una
// `EntrenarFilaHerramienta` (talla `.fila`) o como el héroe de una hoja (talla `.hoja`).
// Sucesor público de `EntrenarStepperSegundos` (FER-197).

public struct EntrenarStepper: View {
    public enum Talla: Sendable {
        /// Botones 36 + valor `groteskNumber(17)` — fila de ajuste.
        case fila
        /// Botones 44 + valor `numeralHoja` (52) — héroe de hoja (reloj de descanso).
        case hoja
    }

    private let valor: String
    private let tono: LiquidTono
    private let talla: Talla
    private let puedeBajar: Bool
    private let puedeSubir: Bool
    private let onBajar: () -> Void
    private let onSubir: () -> Void

    public init(valor: String,
                tono: LiquidTono = .neutro,
                talla: Talla = .fila,
                puedeBajar: Bool = true,
                puedeSubir: Bool = true,
                onBajar: @escaping () -> Void,
                onSubir: @escaping () -> Void) {
        self.valor = valor
        self.tono = tono
        self.talla = talla
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
                .font(valorFuente)
                .foregroundStyle(valorColor)
                .numeroVivo(value: valor)
                .frame(minWidth: Metrics.valorAncho)
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

    private var valorFuente: Font {
        switch talla {
        case .fila: return InstrumentoType.groteskNumber(17, weight: .bold)
        case .hoja: return LiquidType.numeralHoja
        }
    }

    /// `.neutro` pinta tinta900 (el reloj de «Por tiempo»); el resto usa el rótulo del tono
    /// (el incremento de progresión en verde de carga).
    private var valorColor: Color {
        tono == .neutro ? LiquidColor.tinta900 : tono.rotulo
    }

    private var botonLado: CGFloat {
        switch talla {
        case .fila: return Metrics.botonFila
        case .hoja: return Metrics.botonHoja
        }
    }

    private func boton(_ system: String, habilitado: Bool, action: @escaping () -> Void,
                       etiqueta: String) -> some View {
        let lado = botonLado
        let pad = max(0, (LiquidControl.hitTarget - lado) / 2)
        return Button(action: action) {
            Image(systemName: system)
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(habilitado ? LiquidColor.tinta900 : LiquidColor.tinta500)
                .frame(width: lado, height: lado)
                .liquidGlass(.pastillaSolida)
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(!habilitado)
        .padding(pad)
        .contentShape(Rectangle())
        .padding(-pad)
        .accessibilityLabel(Text(verbatim: etiqueta))
    }

    private enum Metrics {
        static let botonFila: CGFloat = 36
        static let botonHoja: CGFloat = 44
        static let valorAncho: CGFloat = 52
    }
}

#if DEBUG
#Preview("EntrenarStepper · fila / hoja") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        EntrenarStepper(valor: "+2,5 kg", tono: .verde, talla: .fila, onBajar: {}, onSubir: {})
        EntrenarStepper(valor: "1:30", tono: .neutro, talla: .hoja, onBajar: {}, onSubir: {})
        EntrenarStepper(valor: "0:00", tono: .rosa, talla: .fila,
                        puedeBajar: false, onBajar: {}, onSubir: {})
    }
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .verde)
}
#endif
