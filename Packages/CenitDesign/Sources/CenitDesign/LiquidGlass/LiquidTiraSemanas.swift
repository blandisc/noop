import SwiftUI

// MARK: - Liquid Glass · TiraSemanas (ola 1 · E11, FER-334)
//
// La tira de un programa de varias semanas: una celda por semana, hecha / hoy / futura / ligera —
// «la ves marcada desde el día uno» (artefacto aprobado §5). Distinta de `EntrenarHubSemana` (esa es
// la semana de 7 DÍAS del hub); esta cuenta SEMANAS de un programa completo, casi siempre 4…8 celdas.
//
// Celdas de numeral fijo: cada una es el mismo ancho cuadrado con `.monospacedDigit()`, así que la
// tira no baila cuando el numeral cambia de 1 a 2 dígitos (ciclo 2, semana 10 de un import de 8
// semanas). Accesibilidad: la tira es UN solo elemento («Programa, semana 3 de 5, semana ligera en 2
// semanas») — el caller pasa esa frase ya armada; las celdas no anuncian nada por su cuenta.

/// El estado de una celda de `LiquidTiraSemanas`.
public enum LiquidSemanaEstado: Sendable, Equatable {
    /// Ya se entrenó (D-Q2: al menos una sesión esa semana).
    case hecha
    /// La semana en curso.
    case hoy
    /// Todavía no llega.
    case futura
    /// La semana ligera del ciclo — lleva la marca «LIGERA» debajo.
    case ligera
}

public struct LiquidTiraSemanas: View {
    private let semanas: [LiquidSemanaEstado]
    private let etiquetaAccesibilidad: Text

    /// - Parameters:
    ///   - semanas: una entrada por semana del ciclo, en orden (1…N).
    ///   - etiquetaAccesibilidad: la frase completa que VoiceOver lee por la tira ENTERA — nunca
    ///     celda por celda («Programa, semana 3 de 5, semana ligera en 2 semanas»).
    public init(_ semanas: [LiquidSemanaEstado], etiquetaAccesibilidad: Text) {
        self.semanas = semanas
        self.etiquetaAccesibilidad = etiquetaAccesibilidad
    }

    private static let celda: CGFloat = 26

    public var body: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s100) {
            ForEach(Array(semanas.enumerated()), id: \.offset) { index, estado in
                celdaSemana(numero: index + 1, estado: estado)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(etiquetaAccesibilidad)
    }

    private func celdaSemana(numero: Int, estado: LiquidSemanaEstado) -> some View {
        VStack(spacing: LiquidSpace.s050) {
            ZStack {
                fondo(estado)
                Text(verbatim: "\(numero)")
                    .font(LiquidType.captionLectura.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(color(estado))
            }
            .frame(width: Self.celda, height: Self.celda)
            // AX1+ (issue P10/accesibilidad): la marca «LIGERA» baja debajo de la línea de celdas en
            // vez de encogerse dentro de ellas — nunca trunca.
            if estado == .ligera {
                Text("Light").font(LiquidType.micro).textCase(.uppercase).foregroundStyle(LiquidColor.ambar)
            }
        }
    }

    @ViewBuilder
    private func fondo(_ estado: LiquidSemanaEstado) -> some View {
        let shape = RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous)
        switch estado {
        case .hecha:
            shape.fill(LiquidColor.verdeCarga)
        case .hoy:
            shape.strokeBorder(LiquidColor.tinta900, lineWidth: 1.5)
        case .futura:
            shape.strokeBorder(LiquidColor.tinta900.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        case .ligera:
            shape.strokeBorder(LiquidColor.ambar, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
        }
    }

    private func color(_ estado: LiquidSemanaEstado) -> Color {
        switch estado {
        case .hecha: return .white
        case .hoy: return LiquidColor.tinta900
        case .futura: return LiquidColor.tinta500
        case .ligera: return LiquidColor.ambar
        }
    }
}

#if DEBUG
#Preview("LiquidTiraSemanas") {
    LiquidTiraSemanas([.hecha, .hecha, .hoy, .futura, .ligera],
                      etiquetaAccesibilidad: Text(verbatim: "Program, week 3 of 5, light week in 2 weeks"))
        .padding(LiquidSpace.s600)
        .background(LiquidColor.fondoGradient)
        .preferredColorScheme(.light)
}
#endif
