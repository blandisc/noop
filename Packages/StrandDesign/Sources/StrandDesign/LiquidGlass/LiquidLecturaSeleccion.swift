import SwiftUI

// MARK: - Liquid Glass · Lectura de selección (FER-102, pantallas de detalle)
//
// La línea que dice QUÉ SE TOCÓ: bajo un calendario, un hipnograma o cualquier retícula donde
// el dedo elige un elemento. Reserva su alto SIEMPRE (con la invitación cuando no hay selección)
// para que elegir una celda no empuje la página hacia abajo — el salto de layout bajo el dedo es
// lo que hace que una retícula tocable se sienta rota.
//
// Es el gemelo quieto de `LiquidScrubPopup`: aquel sigue al dedo sobre una gráfica; este se
// queda debajo de una retícula. Los dos dicen lo mismo — foco, palabra, valor.

/// La línea de lectura bajo una retícula tocable: rótulo del elegido, palabra opcional y valor.
public struct LiquidLecturaSeleccion: View {
    /// Lo que hay que decir del elemento tocado.
    public struct Lectura: Equatable, Sendable {
        /// El foco: la fecha, la etapa, el eje («MIÉ 12 AGO», «PROFUNDO»).
        public let foco: String
        /// La palabra de nivel, si la hay («Suficiente», «sin dato»).
        public let palabra: String?
        /// El valor ya formateado («7:12», «0:42 → 2:12»).
        public let valor: String?
        /// Tiñe el valor con el nivel. `nil` lo deja en tinta.
        public let tono: Color?
        /// Cómo lo dicta VoiceOver, si «7:12» no debe leerse como hora del reloj.
        public let a11y: String?

        public init(foco: String, palabra: String? = nil, valor: String? = nil,
                    tono: Color? = nil, a11y: String? = nil) {
            self.foco = foco
            self.palabra = palabra
            self.valor = valor
            self.tono = tono
            self.a11y = a11y
        }
    }

    private let lectura: Lectura?
    private let invitacion: String
    private let ayuda: String?

    /// - Parameters:
    ///   - invitacion: qué decir sin selección («Toca una noche»).
    ///   - ayuda: el complemento de la invitación («para ver cuánto dormiste»).
    public init(_ lectura: Lectura?, invitacion: String, ayuda: String? = nil) {
        self.lectura = lectura
        self.invitacion = invitacion
        self.ayuda = ayuda
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            if let lectura {
                Text(lectura.foco)
                    .font(LiquidType.label)
                    .tracking(LiquidType.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                if let palabra = lectura.palabra {
                    Text(palabra)
                        .font(LiquidType.filaConteo)
                        .foregroundStyle(LiquidColor.tinta700)
                }
                if let valor = lectura.valor {
                    Spacer(minLength: LiquidSpace.s200)
                    Text(valor)
                        .font(LiquidType.valorL)
                        .foregroundStyle(lectura.tono ?? LiquidColor.tinta900)
                }
            } else {
                Text(invitacion)
                    .font(LiquidType.label)
                    .tracking(LiquidType.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                if let ayuda {
                    Text(ayuda)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                Spacer(minLength: 0)
            }
        }
        // Alto reservado: sin esto, tocar una celda empuja todo lo de abajo.
        .frame(minHeight: LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        // El mismo resorte que mueve el tick del selector al elegir: elegir es elegir.
        .animation(LiquidMotion.selector, value: lectura)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lectura?.foco ?? invitacion))
        .accessibilityValue(Text(a11y))
    }

    private var a11y: String {
        guard let lectura else { return ayuda ?? "" }
        let valor = lectura.a11y ?? lectura.valor ?? ""
        return [lectura.palabra, valor].compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Liquid · Lectura de selección") {
    VStack(alignment: .leading, spacing: LiquidSpace.s600) {
        LiquidLecturaSeleccion(nil, invitacion: "Toca una noche",
                               ayuda: "para ver cuánto dormiste")
        LiquidLecturaSeleccion(
            .init(foco: "Mié 12 ago", palabra: "Suficiente", valor: "7:12",
                  tono: LiquidColor.indigo, a11y: "7 horas 12 minutos"),
            invitacion: "Toca una noche")
        LiquidLecturaSeleccion(
            .init(foco: "Profundo", valor: "0:42 → 2:12"),
            invitacion: "Toca un tramo")
        LiquidLecturaSeleccion(
            .init(foco: "Lun 3 ago", palabra: "sin dato"),
            invitacion: "Toca una noche")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
}
#endif
