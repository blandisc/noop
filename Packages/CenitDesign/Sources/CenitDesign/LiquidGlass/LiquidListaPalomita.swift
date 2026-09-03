import SwiftUI

// MARK: - Liquid Glass · ListaPalomita (ola 1 · E11, FER-334)
//
// La lista de opciones EXCLUYENTES con explicación: título + subtítulo opcional, palomita a la
// derecha en la seleccionada. Regla de selectores del dueño (`ola1-pantallas.html` §5): un segmentado
// (`SegmentedPillControl`) es SOLO para etiquetas de una palabra o número («Semanas» 4 · 5 · 6); en
// cuanto una opción necesita una frase que la explique («Menos series · la mitad, mismo peso»), pasa
// a esta lista. Nunca las dos formas para la misma decisión.
//
// Distinta de `LiquidChecklistRow` (esa es un FACTOR presente/ausente de un desglose, con un motivo
// cuando falta) y de `LiquidMenuItem` (esa vive dentro de un `liquidMenu` flotante, no en el cuerpo
// de una pantalla). Esta es la fila EN LÍNEA de un grupo de opciones que el usuario elige de una vez
// y puede volver a cambiar — «Semana ligera», «Al terminar el ciclo».

/// Una opción de `LiquidListaPalomita`.
public struct LiquidOpcionPalomita<T: Hashable>: Identifiable {
    public let id: T
    public let titulo: String
    public let subtitulo: String?

    public init(id: T, titulo: String, subtitulo: String? = nil) {
        self.id = id
        self.titulo = titulo
        self.subtitulo = subtitulo
    }
}

/// Grupo de `LiquidOpcionPalomita` con selección única — un tap cambia `seleccion` de inmediato
/// (sin botón de confirmar aparte: cada fila ES la acción).
public struct LiquidListaPalomita<T: Hashable>: View {
    private let opciones: [LiquidOpcionPalomita<T>]
    @Binding private var seleccion: T

    public init(_ opciones: [LiquidOpcionPalomita<T>], seleccion: Binding<T>) {
        self.opciones = opciones
        self._seleccion = seleccion
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            ForEach(Array(opciones.enumerated()), id: \.element.id) { index, opcion in
                fila(opcion)
                if index < opciones.count - 1 {
                    Divider().overlay(LiquidColor.tinta10)
                }
            }
        }
    }

    private func fila(_ opcion: LiquidOpcionPalomita<T>) -> some View {
        let elegida = opcion.id == seleccion
        return Button {
            seleccion = opcion.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                    Text(verbatim: opcion.titulo)
                        .font(LiquidType.tituloFila)
                        .foregroundStyle(LiquidColor.tinta900)
                    if let subtitulo = opcion.subtitulo {
                        Text(verbatim: subtitulo)
                            .font(LiquidType.caption)
                            .foregroundStyle(LiquidColor.tinta500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: LiquidSpace.s200)
                if elegida {
                    CenitIcon.confirm.image
                        .font(LiquidType.iconSF(size: 15).weight(.semibold))
                        .foregroundStyle(LiquidColor.verdePrimario)
                }
            }
            .padding(.vertical, LiquidSpace.s200)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(elegida ? [.isSelected] : [])
    }
}

#if DEBUG
#Preview("LiquidListaPalomita") {
    struct Demo: View {
        @State private var seleccion = "menos_series"
        var body: some View {
            LiquidListaPalomita([
                LiquidOpcionPalomita(id: "menos_series", titulo: "Fewer sets", subtitulo: "half, same weight"),
                LiquidOpcionPalomita(id: "menos_series_y_peso", titulo: "Fewer sets and less weight", subtitulo: "half, and −7.5%"),
                LiquidOpcionPalomita(id: "ninguna", titulo: "No light week")
            ], seleccion: $seleccion)
        }
    }
    return Demo()
        .padding(LiquidSpace.s600)
        .background(LiquidColor.fondoGradient)
        .preferredColorScheme(.light)
}
#endif
