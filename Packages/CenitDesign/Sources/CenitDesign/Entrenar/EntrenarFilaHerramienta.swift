import SwiftUI

// MARK: - EntrenarFilaHerramienta — fila «rótulo + valor/nota + control» (FER-197 · FER-293)
//
// La fila base que una hoja-herramienta usa para UN ajuste: un rótulo a la izquierda, el valor
// resuelto o una nota de prosa (opcionales — algunos controles ya muestran su propio valor y
// repetirlo en texto es ruido) y el control interactivo a la derecha (`@ViewBuilder`). No trae
// fondo propio a propósito — vive DENTRO de una hoja ya teñida por `.entrenarHojaFondo`, y su
// propia superficie tiene que ser PAPEL OPACO (`.pastillaSolida`/`.superficieSolida`), nunca
// vidrio-sobre-vidrio (ADN §11.1, regla «no-sheet-glass»): el caller decide si agrupa varias
// filas en una sola tarjeta (`.liquidGlass(.superficieSolida)`, con `divider` entre ellas) o
// si es la única fila de la hoja (`.liquidGlass(.pastillaSolida)`).

public struct EntrenarFilaHerramienta<Control: View>: View {
    private let rotulo: String
    private let valor: String?
    private let nota: String?
    private let divider: Bool
    private let control: Control

    /// - Parameters:
    ///   - rotulo: ya localizado («Descanso», «Aplicar a todas las series»).
    ///   - valor: ya formateado («1:30»); una línea, `unidadCompacta`. `nil` = el control ya lo dice.
    ///   - nota: prosa de segunda línea que envuelve (`LiquidType.cuerpo` · `tinta500`). Distinta
    ///     de `valor` (compacto, una línea). FER-293.
    ///   - divider: filete inferior de 0.5 pt (tinta al 10 %) — `false` en la última fila de una
    ///     tarjeta agrupada, mismo contrato que `LiquidListRow.divider`.
    public init(rotulo: String,
                valor: String? = nil,
                nota: String? = nil,
                divider: Bool = true,
                @ViewBuilder control: () -> Control) {
        self.rotulo = rotulo
        self.valor = valor
        self.nota = nota
        self.divider = divider
        self.control = control()
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s300) {
            VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                Text(rotulo)
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                if let valor {
                    Text(valor)
                        .font(LiquidType.unidadCompacta)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                if let nota {
                    Text(nota)
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
                .frame(maxWidth: EntrenarFilaHerramientaMetrics.controlMaxWidth, alignment: .trailing)
        }
        .padding(.horizontal, LiquidSpace.s400)
        // Con nota (dos líneas de prosa) el piso sube a 52 — el de las filas de Progresión
        // (FER-89); sin ella se queda en el row HIG de 44.
        .frame(minHeight: nota == nil ? EntrenarMetrics.row : EntrenarFilaHerramientaMetrics.minConNota)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
            }
        }
    }
}

private enum EntrenarFilaHerramientaMetrics {
    static let controlMaxWidth: CGFloat = 184
    static let minConNota: CGFloat = 52
}

#if DEBUG
#Preview("EntrenarFilaHerramienta · sola, pastillaSolida") {
    EntrenarFilaHerramienta(rotulo: "Descanso", valor: "1:30", divider: false) {
        EntrenarStepper(valor: "1:30", tono: .rosa, onBajar: {}, onSubir: {})
    }
    .padding(.vertical, LiquidSpace.s100)
    .liquidGlass(.pastillaSolida)
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .rosa)
}

/// Varias filas agrupadas en UNA tarjeta opaca — el patrón que usa `ProgressionSetupScreen`
/// (varios ajustes, una sola superficie).
#Preview("EntrenarFilaHerramienta · agrupadas, superficieSolida") {
    VStack(spacing: 0) {
        EntrenarFilaHerramienta(rotulo: "Aplicar a todas las series") {
            Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.liquid)
        }
        EntrenarFilaHerramienta(rotulo: "Objetivo de reps",
                                nota: "se aplica a las 4 series de trabajo",
                                divider: false) {
            Image(systemName: "chevron.right").foregroundStyle(LiquidColor.tinta500)
        }
    }
    .liquidGlass(.superficieSolida)
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .indigo)
}
#endif
