#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import CenitDesign   // LiquidColor, LiquidMotion, LiquidRadius

// MARK: - Arrastrar una rutina a otra sección
//
// El planificador ya sabía mover una rutina de carpeta, pero solo por el menú «···» → «Mover a…».
// Arrastrarla —el gesto que cualquiera intenta primero al ver una lista con secciones— no hacía nada
// (petición Fer 2026-07-18). Estos dos modificadores viven fuera de `WeeklyPlanEditorView` a propósito:
// esa pantalla ya reventó el layout de tipos del canvas una vez (crash de previews del 2026-07-16, ver
// la nota de `foldersListErased`), así que todo lo que se le pueda quitar al cuerpo, se le quita.

/// Identificador de arrastre propio. NO se usa `String` a secas: con el tipo genérico de texto, la lista
/// aceptaría cualquier cosa arrastrada desde otra app —una palabra de Safari, por ejemplo— e intentaría
/// resolverla como rutina. Con un tipo propio, el sistema solo ofrece el soltar donde tiene sentido.
extension UTType {
    static let cenitRoutineID = UTType(exportedAs: "com.feriracheta.cenit.routine-id")
}

private struct RoutineID: Transferable, Codable {
    let id: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .cenitRoutineID)
    }
}

extension View {
    /// Hace la fila arrastrable, con la propia fila como vista de arrastre.
    func routineDraggable(_ id: String) -> some View {
        draggable(RoutineID(id: id)) {
            // La miniatura de arrastre: la misma fila a media opacidad. Sin esto UIKit inventa un
            // rectángulo del tamaño del contenedor y la rutina «desaparece» al levantarla.
            self.opacity(0.9)
        }
    }

    /// Convierte la banda de una sección en destino de soltado.
    /// - Parameters:
    ///   - active: si hay una rutina flotando encima ahora mismo (pinta el resalte).
    ///   - onDrop: recibe el id soltado; devuelve `true` si de verdad movió algo.
    ///   - targeted: avisa cuándo entra y sale el arrastre, para que la pantalla pinte el resalte.
    /// Resalte El Eje (FER-292): canto `tinta900` a 1 pt — sin theme, sin color de relleno.
    func routineDropTarget(active: Bool,
                           onDrop: @escaping (String) -> Bool,
                           targeted: @escaping (Bool) -> Void) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
                    .strokeBorder(active ? LiquidColor.tinta900 : .clear, lineWidth: 1)
            )
            .animation(LiquidMotion.fundido, value: active)
            .dropDestination(for: RoutineID.self) { items, _ in
                guard let first = items.first else { return false }
                return onDrop(first.id)
            } isTargeted: { targeted($0) }
    }
}
#endif
