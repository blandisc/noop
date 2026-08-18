import SwiftUI

// MARK: - Liquid Glass · Franja de sección (FER-102, pantallas de detalle)
//
// La costura que parte una pantalla de detalle en secciones: una banda A SANGRE con el rótulo
// en caja alta a la izquierda y una pista opcional a la derecha («23:38 → 7:04»).
//
// POR QUÉ NO ES UN ENCABEZADO DE TARJETA: en papel esta franja era gris macizo de formulario, y
// era lo más «papel» que quedaba en la pantalla. Aquí es un velo del TONO DE LA MÉTRICA al 4 %
// (`LiquidColor.franjaVelo`), plano — un gradiente la convierte en una barra de cabecera teñida,
// y esto es una costura, no un encabezado. Sigue llegando a los dos cantos: el dueño pidió
// explícitamente que las secciones llenen el ancho y no floten (2026-08-17).
//
// La sección que va DEBAJO se compone con `.liquidSeccion()`, que aplica el margen del sistema.

/// La banda de sección a sangre de una pantalla de detalle: rótulo + pista opcional sobre un
/// velo del tono al 4 %.
public struct LiquidFranjaSeccion: View {
    private let titulo: String
    private let pista: String?
    private let tono: Color

    public init(_ titulo: String, pista: String? = nil, tono: Color) {
        self.titulo = titulo
        self.pista = pista
        self.tono = tono
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s250) {
            Text(titulo)
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta700)
            if let pista {
                Spacer(minLength: 0)
                // La pista es LECTURA, no rótulo: sin tracking ni caja alta, o compite con
                // el título de la franja y la banda se vuelve dos encabezados.
                Text(pista)
                    .font(LiquidType.filaConteo)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .padding(.horizontal, LiquidSpace.s550)
        .padding(.vertical, LiquidSpace.s225)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiquidColor.franjaVelo(tono))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension View {
    /// El margen del contenido de una sección de detalle, bajo su `LiquidFranjaSeccion`.
    func liquidSeccion(top: CGFloat = LiquidSpace.s400,
                       bottom: CGFloat = LiquidSpace.s550) -> some View {
        padding(.horizontal, LiquidSpace.s550)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Liquid · Franja de sección") {
    ScrollView {
        VStack(spacing: 0) {
            LiquidFranjaSeccion("Anoche", pista: "23:38 → 7:04", tono: LiquidColor.indigo)
            Text("El contenido de la sección vive aquí, con el margen del sistema.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
                .liquidSeccion()
            LiquidFranjaSeccion("Historial", pista: "24 de 30 noches suficientes",
                                tono: LiquidColor.indigo)
            Text("Otra sección.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
                .liquidSeccion()
        }
    }
    .background(LiquidColor.fondoGradient)
}
#endif
