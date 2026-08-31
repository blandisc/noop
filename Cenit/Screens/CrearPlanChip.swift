#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - «Crear plan» (FER-88) — la puerta única que reemplaza el par duplicado
//
// `EntrenarView.nuevaRutinaRow` y `WeeklyPlanEditorView.toolsChipsRow` dibujaban, byte a byte, el
// MISMO par de chips: `InstrumentoToolChip(systemImage: "square.stack.3d.up", label: "Templates")`
// seguido de `InstrumentoToolChip(systemImage: "square.and.arrow.down", label: "Import")` — solo el
// nombre de la bandera que abre el importador difería entre pantallas. Un chip, una puerta: toca
// «Crear plan» y elige entre las mismas dos acciones en el `paperMenu` que ya usan los «···» de la
// sección, en vez de inventar una hoja nueva para dos opciones.

struct CrearPlanChip: View {
    var onTemplates: () -> Void
    var onImport: () -> Void

    @State private var showMenu = false

    var body: some View {
        InstrumentoToolChip(systemImage: "rectangle.stack.badge.plus", label: Text("Create plan")) {
            showMenu = true
        }
        .paperMenu(isPresented: $showMenu, items: [
            .init(String(localized: "Template"), systemImage: "square.stack.3d.up", action: onTemplates),
            .init(String(localized: "Import"), systemImage: "square.and.arrow.down", action: onImport)
        ])
    }
}

#if DEBUG
#Preview("CrearPlanChip") {
    HStack(spacing: 8) {
        CrearPlanChip(onTemplates: {}, onImport: {})
    }
    .padding(24)
    .background(CenitColor.pantalla)
    .environment(\.instrumentoTheme, .base)
    .preferredColorScheme(.light)
}
#endif
#endif
