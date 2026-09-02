import SwiftUI

// MARK: - EntrenarFilaHerramienta — fila «rótulo + valor + control» (FER-197 · Ola 1)
//
// La fila base que una hoja-herramienta usa para UN ajuste: un rótulo a la izquierda, el valor
// resuelto (opcional — algunos controles ya muestran su propio valor y repetirlo en texto es
// ruido) y el control interactivo a la derecha (`@ViewBuilder`, arbitrario: `EntrenarStepperSegundos`,
// un `Toggle`, cualquier cosa que la hoja necesite). No trae fondo propio a propósito — vive
// DENTRO de una hoja ya teñida por `.entrenarHojaFondo`, y su propia superficie tiene que ser
// PAPEL OPACO (`.pastillaSolida`/`.superficieSolida`), nunca vidrio-sobre-vidrio (ADN §11.1,
// regla «no-sheet-glass»): el caller decide si agrupa varias filas en una sola tarjeta
// (`.liquidGlass(.superficieSolida)`, con `divider` entre ellas) o si es la única fila de la
// hoja (`.liquidGlass(.pastillaSolida)`) — el mismo patrón que `LiquidListRow`/`LiquidListCard`
// ya usan para las filas de navegación, aquí para filas de AJUSTE.

struct EntrenarFilaHerramienta<Control: View>: View {
    private let rotulo: String
    private let valor: String?
    private let divider: Bool
    private let control: Control

    /// - Parameters:
    ///   - rotulo: ya localizado («Descanso», «Aplicar a todas las series»).
    ///   - valor: ya formateado («1:30»); `nil` = el control ya lo dice (un `Toggle` no necesita
    ///     que la fila repita «Activado»/«Desactivado» en texto).
    ///   - divider: filete inferior de 0.5 pt (tinta al 10 %) — `false` en la última fila de una
    ///     tarjeta agrupada, mismo contrato que `LiquidListRow.divider`.
    init(rotulo: String, valor: String? = nil, divider: Bool = true,
                @ViewBuilder control: () -> Control) {
        self.rotulo = rotulo
        self.valor = valor
        self.divider = divider
        self.control = control()
    }

    var body: some View {
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
            }
            Spacer(minLength: LiquidSpace.s200)
            control
        }
        .padding(.horizontal, LiquidSpace.s400)
        .frame(minHeight: EntrenarMetrics.row)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
            }
        }
    }
}

#if DEBUG
#Preview("EntrenarFilaHerramienta · sola, pastillaSolida") {
    EntrenarFilaHerramienta(rotulo: "Descanso", valor: "1:30", divider: false) {
        EntrenarStepperSegundos(valor: "1:30", tono: .rosa, onBajar: {}, onSubir: {})
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
            Toggle("", isOn: .constant(true)).labelsHidden()
        }
        EntrenarFilaHerramienta(rotulo: "Objetivo de reps", valor: "8–10", divider: false) {
            Image(systemName: "chevron.right").foregroundStyle(LiquidColor.tinta500)
        }
    }
    .liquidGlass(.superficieSolida)
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .indigo)
}
#endif
