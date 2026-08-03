import SwiftUI

// MARK: - Liquid Glass · Franja del guardián (FER-1047)
//
// El centinela de enfermedad (temperatura + respiración) SIEMPRE visible, debajo de la franja de
// carga y con su MISMO vidrio, alto, radio y material: las dos forman un par simétrico que el ojo
// lee como «lo que acompaña», separado de los orbes que son «lo que decide». Hereda la jerarquía
// que la fila de carga ya establecía — no inventa una nueva.
//
// Principio rector: MOSTRAR NO ES VOTAR. El dueño quiere ver su temperatura y su respiración todos
// los días, aunque no haya alerta — pero ninguna de las dos decide el día por su cuenta (el motor
// mata así el falso positivo del cuarto caliente). El diseño enseña esa regla sin explicarla:
//   · tranquilo   → «VIGILANDO», números en tinta, CERO color (DNA «Instrumento diurno»).
//   · una fuera   → solo ESE dato se tiñe de ámbar; el veredicto NO cambia.
//   · las dos     → rótulo «JUNTAS», la franja se tiñe: aquí el centinela sí empuja el veredicto.
//
// La franja pesa MENOS que los orbes por jerarquía de espacio y tipografía (una tira delgada de
// vidrio pastilla, no un orbe de 72 pt), NUNCA por color. Nunca dice «enfermedad» ni diagnostica.
public struct LiquidGuardianFranja: View {

    private let model: LiquidHoyModel.Guardian

    public init(_ model: LiquidHoyModel.Guardian) {
        self.model = model
    }

    private var tempTinted: Bool { model.estado == .tempFuera || model.estado == .juntas }
    private var respTinted: Bool { model.estado == .respFuera || model.estado == .juntas }
    /// Solo cuando ambas se salen JUNTAS la franja entera se tiñe — la excepción consciente al
    /// «color solo en el dato», porque es justo lo que explica por qué esta vez sí cuenta.
    private var stripTinted: Bool { model.estado == .juntas }

    public var body: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(model.label)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(stripTinted ? LiquidColor.atencionTexto : LiquidColor.tinta500)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                Text(model.temp)
                    .font(LiquidType.cargaRatio)
                    .foregroundStyle(tempTinted ? LiquidColor.atencionTexto : LiquidColor.tinta700)
                Text(verbatim: "·")
                    .font(LiquidType.cargaRatio)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(model.resp)
                    .font(LiquidType.cargaRatio)
                    .foregroundStyle(respTinted ? LiquidColor.atencionTexto : LiquidColor.tinta700)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        // Mismo alto/vidrio/radio que `LiquidCargaEscala.fila` (par simétrico), + el área tocable
        // de ≥44 pt sin engordar el vidrio.
        .padding(.vertical, LiquidSpace.s225)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
        .overlay {
            if stripTinted { Capsule().fill(LiquidColor.atencion.opacity(0.10)) }
        }
        .padding(.vertical, LiquidSpace.s075)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: resolvedA11y))
    }

    private var resolvedA11y: String {
        model.a11y ?? "\(model.label): \(model.temp), \(model.resp)"
    }
}

#if DEBUG
private struct LiquidGuardianFranjaDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            LiquidCargaEscala(razon: 1.03, estado: .ok, rotulo: "EN EQUILIBRIO", densidad: .fila)
            LiquidGuardianFranja(.init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo))
            LiquidGuardianFranja(.init(label: "VIGILANDO", temp: "+0.9°", resp: "14 rpm", estado: .tempFuera))
            LiquidGuardianFranja(.init(label: "VIGILANDO", temp: "+0.1°", resp: "19 rpm", estado: .respFuera))
            LiquidGuardianFranja(.init(label: "JUNTAS", temp: "+0.9°", resp: "19 rpm", estado: .juntas))
            LiquidGuardianFranja(.init(label: "VIGILANDO", temp: "—", resp: "—", estado: .tranquilo))
        }
        .padding(LiquidSpace.s550)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColor.papelGradient)
    }
}

#Preview("Liquid · Guardián (par con carga)") {
    LiquidGuardianFranjaDemo()
}
#endif
