import SwiftUI

// MARK: - EntrenarHojaFondo — el fondo de cristal El Eje para hojas-herramienta
// (FER-197 · Ola 1 del épico FER-195 «Entrenar en vidrio»)
//
// El vestido de una hoja-herramienta (RPE, Nota, Descanso, Discos, Progresión, Cambiar
// ejercicio, Detalle/Biblioteca de ejercicio…) es un MODIFICADOR sobre la estructura propia de
// la hoja, no un envoltorio: `.entrenarHojaFondo(tono:)` solo pinta lo que hay DETRÁS del
// contenido — nunca sustituye el `NavigationStack`, el `ScrollView` o el `TextEditor` de la
// hoja, ni le impone detents o toolbar. Esa es la diferencia deliberada con `LiquidMetricSheet`
// (que SÍ es un cascarón completo: `ScrollView` + `presentationDetents` + `presentationBackground`
// propios, pensado para una hoja que el DS controla de punta a punta) — envolver una hoja que ya
// trae su propio `NavigationStack`/`TextEditor` en ese cascarón le duplica el scroll y le roba su
// toolbar nativo. REGLA DURA del épico: nunca envolver; aquí cada hoja sigue siendo dueña de su
// estructura, este modificador solo la tiñe por debajo.
//
// Receta: el mismo split nativo-vs-imitación que `ConfirmCard.cardGlassFill` /
// `LiquidModulo.glass` / `LiquidTabBar` (`#available(iOS 26…, *) + !liquidMotionDisabled`),
// aplicado EDGE-TO-EDGE (sin forma acotada — es el fondo de TODA la hoja, no una tarjeta
// flotando encima de otra cosa) sobre el papel de «El Tablero» (`LiquidColor.fondoGradient`),
// teñido por `EntrenarTono` a la MISMA intensidad que `EntrenarVidrio` usa para sus módulos
// (`EntrenarVidrioMetrics.intensidadDefault`) — hub y hojas-herramienta leen como el mismo
// material.
//
// ## Menú de presentación — las 11 superficies de la Ola 2 (FER-195), verificado en código
//
// | Superficie | Fondo | Cabecera | Presentación |
// |---|---|---|---|
// | `ProgressionSetupScreen` | `.entrenarHojaFondo(tono:)` en su raíz | reemplaza su header a mano por `EntrenarHojaCabecera` (no trae `NavigationStack` propio en ningún camino) | fría: push (`.navigationDestination`, `RoutineSheet.swift`) · viva: sheet sin detent explícito (`RoutineSheetLive.swift`/`LiveStrengthSheet.swift`) |
// | `RestEditorScreen` | `.entrenarHojaFondo(tono:)` | reemplaza su header a mano (hoy `BackButton`) por `EntrenarHojaCabecera(.cerrar)` | fría: push · viva: sheet `.large` |
// | `RPESheet` | `.entrenarHojaFondo(tono: .ambar)` | reemplaza título+`BackButton` a mano por `EntrenarHojaCabecera(.cerrar)` | sheet `.height(560)`, fila de 6 (`EntrenarFilaEsfuerzo`) |
// | `NoteSheet` | `.entrenarHojaFondo(tono: .ambar)` — el `TextEditor` (`EntrenarNotaCampo`) queda INTACTO, sin envolver | reemplaza título+«Save» a mano por `EntrenarHojaCabecera(.guardar(_:))` | sheet `.medium`/`.large` |
// | `PlatesScreen` | `.entrenarHojaFondo(tono: .ambar)` | reemplaza overline+`BackButton` por `EntrenarHojaCabecera(.cerrar)` | sheet `.large`, `ScrollView` |
// | `ChangeExerciseSheet` | `.entrenarHojaFondo(tono:)` en la raíz DEL `NavigationStack` propio (no lo reemplaza) | CONSERVA su `NavigationStack`/toolbar — el buscador vive en el toolbar nativo | sheet, `NavigationStack` |
// | `ExerciseDetailScreen` | `.entrenarHojaFondo(tono:)` en la raíz del `NavigationStack` que pone el caller | CONSERVA su `NavigationStack`/toolbar (item «Done») | sheet, `NavigationStack` |
// | `ExerciseLibraryScreen` | `.entrenarHojaFondo(tono: .neutro)` en su raíz | SIN `NavigationStack` propio en NINGUNO de sus 5 call sites (verificado en código): su `body` es un `ScrollView` con un kicker dibujado a mano, no un toolbar nativo — la Ola 2 decide si lo sustituye por `EntrenarHojaCabecera` | push/`.navigationDestination` según lo decida el caller (el `NavigationStack` es AMBIENTE, no propio) |
// | `CreateExerciseSheet` | `.entrenarHojaFondo(tono: .neutro)` | reemplaza el título Grotesk dibujado a mano por `EntrenarHojaCabecera(.cancelar(_:))` — el CTA de guardar sigue siendo el botón grande de abajo, sin cambio | sheet dentro de Library, SIN `NavigationStack` propio |
// | `LiveStrengthSheet.summaryPhase` | `.entrenarHojaFondo(tono:)` en la raíz del `fullScreenCover` | NO aplica — es una SECCIÓN dentro de una hoja ya cubierta, sin cabecera de salida propia | `fullScreenCover` |
// | `emptyAdHocSession` | `.entrenarHojaFondo(tono:)` | NO aplica, misma razón | `fullScreenCover` (misma clase que `summaryPhase`) |
//
// Regla de lectura: las tres primeras filas, `ExerciseLibraryScreen` y `CreateExerciseSheet` —
// las CINCO que NO traen `NavigationStack` propio — REEMPLAZAN su cabecera dibujada a mano por
// `EntrenarHojaCabecera` (aunque `ExerciseLibraryScreen` es la única de las cinco que la Ola 2
// puede dejar como está: hoy es solo un kicker mudo, sin acción de salida que resolver). Las DOS
// de `NavigationStack` propio (`ChangeExerciseSheet`, `ExerciseDetailScreen`) CONSERVAN su
// toolbar nativo tal cual (el fondo se aplica en la raíz del stack, no en su toolbar); las dos
// de `fullScreenCover` son secciones internas de una hoja que la Ola 2 no reestructura, así que
// solo heredan el fondo.

public extension View {
    /// Viste el fondo de una hoja-herramienta con el cristal El Eje, teñido por `tono`. Aplícalo
    /// al contenido RAÍZ de la hoja (el `NavigationStack`, el `ScrollView`, o el `VStack` de
    /// siempre) EN VEZ de su `.background(theme.paper.ignoresSafeArea())` de hoy — nunca lo
    /// envuelvas en otro contenedor, es un `.background`, no un cascarón.
    func entrenarHojaFondo(tono: EntrenarTono) -> some View {
        modifier(EntrenarHojaFondoModifier(tono: tono))
    }
}

private struct EntrenarHojaFondoModifier: ViewModifier {
    let tono: EntrenarTono
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    func body(content: Content) -> some View {
        content.background { fondo.ignoresSafeArea() }
    }

    private var fondo: some View {
        ZStack {
            LiquidColor.fondoGradient
            glass
            streak
        }
    }

    /// El cristal: nativo en iOS 26 (refracción real de lo que sea que viva DETRÁS de la hoja
    /// presentada), material + relleno del sistema antes de eso — el MISMO patrón que
    /// `ConfirmCard.cardGlassFill`, sin forma acotada porque aquí no hay tarjeta que recortar:
    /// es el fondo de la hoja entera (el `Rectangle` llena el marco que le da el `.background`
    /// de arriba; el radio de esquina de la hoja lo pone `presentationCornerRadius`/el sistema,
    /// no este modificador — no le corresponde opinar de la presentación).
    @ViewBuilder
    private var glass: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear
                .background { tinte }
                .glassEffect(.regular, in: Rectangle())
        } else {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                tinte
            }
        }
    }

    /// El suspiro del tono — misma intensidad que un módulo teñido del hub
    /// (`EntrenarVidrioMetrics.intensidadDefault`), para que hub y hojas-herramienta lean como
    /// el mismo material. `neutro` no tiñe: la hoja se queda en el papel puro de «El Tablero».
    private var tinte: Color {
        tono == .neutro ? .clear : tono.base.opacity(EntrenarVidrioMetrics.intensidadDefault)
    }

    /// El filo de cristal en el canto superior — el gesto que delata al vidrio de verdad (misma
    /// gramática que `LiquidSheetFondo`/la receta `.lente`), para que la hoja no se lea como
    /// papel plano por más que su fondo sea, la mayoría del tiempo, casi blanco.
    private var streak: some View {
        VStack(spacing: 0) {
            LinearGradient(stops: [
                .init(color: LiquidColor.vidrioStreak, location: 0),
                .init(color: LiquidColor.vidrioStreak.opacity(0.25), location: 0.35),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
                .frame(height: LiquidSpace.s800)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("EntrenarHojaFondo · los 6 tonos") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(EntrenarTono.allCases, id: \.self) { tono in
                Text(verbatim: String(describing: tono))
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.tinta900)
                    .frame(maxWidth: .infinity, minHeight: 140, alignment: .top)
                    .padding(LiquidSpace.s400)
                    .entrenarHojaFondo(tono: tono)
                    .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.hoja, style: .continuous))
            }
        }
        .padding(20)
    }
    .background(LiquidColor.papelGradient)
}

/// Prueba estructural de la REGLA DURA: el fondo se aplica a la raíz de un `NavigationStack`
/// real, sin envolverlo — su propio toolbar sigue siendo el toolbar nativo de iOS.
#Preview("EntrenarHojaFondo · sobre NavigationStack (conserva su toolbar)") {
    NavigationStack {
        List {
            Text(verbatim: "Fila de biblioteca 1")
            Text(verbatim: "Fila de biblioteca 2")
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Biblioteca")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") {} }
        }
    }
    .entrenarHojaFondo(tono: .cian)
}

/// Prueba estructural de la REGLA DURA: el fondo detrás de un `TextEditor` real, sin envolverlo
/// (el `TextEditor` sigue siendo dueño de su propio scroll).
#Preview("EntrenarHojaFondo · sobre TextEditor (no lo envuelve)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s300) {
        Text(verbatim: "Nota").font(LiquidType.tituloHoja).foregroundStyle(LiquidColor.tinta900)
        TextEditor(text: .constant("Se sintió pesado en la última serie."))
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120)
    }
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .ambar)
}
#endif
