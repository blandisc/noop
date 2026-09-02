#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Crear plan» (FER-88) — la puerta única que reemplaza el par duplicado
//
// `EntrenarView.nuevaRutinaRow` y `WeeklyPlanEditorView.toolsChipsRow` dibujaban, byte a byte, el
// MISMO par de chips: plantillas + importar — solo el nombre de la bandera que abre el importador
// difería entre pantallas. Un chip, una puerta: toca «Crear plan» y elige entre las mismas dos
// acciones en el `liquidMenu` que ya usan los «···» de la sección. Piel El Eje vía
// `EntrenarChipHerramienta` (FER-292).

struct CrearPlanChip: View {
    var onTemplates: () -> Void
    var onImport: () -> Void

    @State private var showMenu = false

    var body: some View {
        EntrenarChipHerramienta(systemImage: "rectangle.stack.badge.plus", label: Text("Create plan")) {
            showMenu = true
        }
        .liquidMenu(isPresented: $showMenu, items: [
            .init(String(localized: "Template"), systemImage: "square.stack.3d.up", action: onTemplates),
            .init(String(localized: "Import"), systemImage: "square.and.arrow.down", action: onImport)
        ])
    }
}

#if DEBUG
#Preview("CrearPlanChip") {
    HStack(spacing: LiquidSpace.s200) {
        CrearPlanChip(onTemplates: {}, onImport: {})
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoGradient)
    .preferredColorScheme(.light)
}
#endif
#endif
