import SwiftUI

// MARK: - EntrenarHistorialLista — contenedor de la línea de tiempo mixta (FER-202)
//
// Chrome de lista: `EntrenarModulo(tono: .neutro)` + separadores `LiquidColor.tinta7` sangrados
// entre filas YA construidas (fuerza y/o cardio). NO conoce la proyección ni el filtro — el
// caller arma las filas heterogéneas y decide el vacío. Una lista con separadores, no tarjetas
// por fila (el esqueleto de `EntrenarFilaFuerza`/`EntrenarFilaCardio` queda intacto).

public struct EntrenarHistorialLista: View {
    private let vacio: String?
    private let filas: [AnyView]

    /// - Parameters:
    ///   - vacio: texto de estado vacío YA localizado; `nil` = hay filas (se pintan `filas`).
    ///   - filas: filas ya construidas (`EntrenarFilaFuerza` / `EntrenarFilaCardio` / …).
    public init(vacio: String? = nil, filas: [AnyView]) {
        self.vacio = vacio
        self.filas = filas
    }

    /// Convenience tipada — evita `AnyView(...)` en el call site.
    public init(vacio: String? = nil, filas: [any View]) {
        self.vacio = vacio
        self.filas = filas.map { AnyView($0) }
    }

    public var body: some View {
        EntrenarModulo(tono: .neutro) {
            if let vacio {
                Text(verbatim: vacio)
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta500)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LiquidSpace.s400)
                    .accessibilityLabel(Text(verbatim: vacio))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filas.enumerated()), id: \.offset) { index, fila in
                        fila
                        if index < filas.count - 1 {
                            Rectangle()
                                .fill(LiquidColor.tinta7)
                                .frame(height: Metrics.separador)
                                .padding(.leading, Metrics.sangrado)
                        }
                    }
                }
            }
        }
    }
}

private enum Metrics {
    /// Hairline de lista — mismo peso visual que el mock (1 px tinta7).
    static let separador: CGFloat = 1
    /// Sangrado bajo el glifo 38 + gap 12, para que el filo arranque con el texto, no con el chip.
    static let sangrado: CGFloat = 38 + LiquidSpace.s300
}

#if DEBUG
#Preview("EntrenarHistorialLista · mixta") {
    EntrenarHistorialLista(filas: [
        EntrenarFilaFuerza(family: .push, nombre: "Empuje A",
                           meta: "vie 10 jul · 48 min · 4.320 kg",
                           marcas: 2, esfuerzo: "14", onTap: {}),
        EntrenarFilaCardio(
            sfSymbol: "figure.run", deporte: "Correr", origen: .apple,
            meta: "mié 8 jul · 30 min · 5,2 km",
            dato: .init(valor: "148", unidad: "bpm",
                        tono: LiquidTono.rosa.rotulo),
            onTap: {}),
        EntrenarFilaFuerza(family: .pull, nombre: "Jalón B",
                           meta: "mar 7 jul · 41 min · 3.640 kg",
                           marcas: 0, esfuerzo: "11", onTap: {}),
        EntrenarFilaCardio(
            sfSymbol: "figure.outdoor.cycle", deporte: "Ciclismo", origen: .manual,
            meta: "lun 6 jul · 45 min",
            dato: .init(valor: "45", unidad: "min",
                        tono: LiquidColor.tinta700),
            onTap: {}),
    ])
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
    .instrumentoTheme(.base)
}

#Preview("EntrenarHistorialLista · vacío") {
    EntrenarHistorialLista(vacio: "Todavía no hay sesiones en este periodo.", filas: [])
        .padding(LiquidSpace.s550)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}
#endif
