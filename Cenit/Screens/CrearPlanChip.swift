#if os(iOS)
import SwiftUI
import CenitDesign

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
    /// «Programa · 4 a 6 semanas» (ola 1 · E11). `nil` la esconde — D-Q8: fuera del primer uso, antes
    /// de que exista una semana que convertir. El caller decide cuándo pasar un closure real.
    var onProgram: (() -> Void)? = nil

    @State private var showMenu = false

    var body: some View {
        EntrenarChipHerramienta(systemImage: "rectangle.stack.badge.plus", label: Text("Create plan")) {
            showMenu = true
        }
        .liquidMenu(isPresented: $showMenu, items: menuItems)
    }

    private var menuItems: [LiquidMenuItem] {
        var items = [
            LiquidMenuItem(String(localized: "Template"), systemImage: "square.stack.3d.up", action: onTemplates),
            LiquidMenuItem(String(localized: "Import"), systemImage: "square.and.arrow.down", action: onImport)
        ]
        if let onProgram {
            items.append(LiquidMenuItem(String(localized: "Program"),
                                        subtitle: String(localized: "4 to 6 weeks"),
                                        systemImage: "calendar.badge.clock", action: onProgram))
        }
        return items
    }
}

#if DEBUG
#Preview("CrearPlanChip") {
    HStack(spacing: LiquidSpace.s200) {
        CrearPlanChip(onTemplates: {}, onImport: {})
    }
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoGradient)
}
#endif
#endif
