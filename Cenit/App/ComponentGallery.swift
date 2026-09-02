#if os(iOS) && DEBUG
import SwiftUI
import CenitDesign

/// **Galería de componentes** — catálogo vivo de las piezas de `CenitDesign` (FER-315), hermano del
/// `AppMap` de pantallas. Cada entrada renderiza UNA pieza del sistema **Liquid Glass · El Eje** sobre
/// el lienzo casi-blanco canónico (`LiquidColor.fondoGradient`), con un uso representativo tomado de su
/// propio `#Preview` — el código gana, esto solo lo expone.
///
/// Se alcanza por launch-arg `-noop.component <Nombre>` (igual disciplina que los fixtures de pantalla):
/// `ContentView` monta `ComponentGalleryHost(name:)` a pantalla completa cuando el arg está presente, y
/// `CenitScreenshotTests.test_components()` recorre `ComponentGallery.names` para capturar un PNG por
/// pieza hacia el muro `docs/appmap/` (grupo «Componentes» de `Tools/build-appmap.py`).
///
/// Mantener: al añadir/renombrar una pieza del núcleo, edita `entries`. La lista de nombres vive en el
/// código (no en el test) para que una pieza nueva entre a la captura sin tocar el harness.
enum ComponentGallery {

    /// Una pieza del catálogo: nombre canónico (== símbolo de CenitDesign), familia para agrupar en el
    /// muro, y el `View` de muestra (uso representativo, sin fondo — el host pinta el lienzo).
    struct Entry: Identifiable {
        let name: String
        let family: String
        let make: () -> AnyView
        var id: String { name }
    }

    /// El núcleo (30 piezas del sistema NUEVO, Liquid Glass · El Eje + los últimos botones/filas
    /// «Instrumento» que todavía no tienen sucesor Liquid). Corte transversal por familia.
    static let entries: [Entry] = [

        // MARK: Botones
        Entry(name: "LiquidGlassButton", family: "Botones") {
            AnyView(VStack(spacing: LiquidSpace.s300) {
                LiquidGlassButton("Empezar", variant: .primary, minWidth: 168) {}
                LiquidGlassButton("Ver detalle", variant: .glass) {}
                LiquidGlassButton("Crear ejercicio", variant: .solida) {}
                LiquidGlassButton("Editar semana", variant: .quiet) {}
                LiquidGlassButton("Turn off automatic backup", variant: .destructive, expands: true) {}
            })
        },
        Entry(name: "OutlineCapsule", family: "Botones") {
            let t = InstrumentoTheme.base
            return AnyView(VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    OutlineCapsule("Start", theme: t, size: .sm, weight: .bold, action: {})
                    OutlineCapsule("Stop", theme: t, size: .sm, weight: .bold, action: {})
                }
                HStack(spacing: 10) {
                    OutlineCapsule("Equipment", theme: t, size: .md, action: {})
                    OutlineCapsule("Barbell", theme: t, size: .md, filled: true, action: {})
                }
            }.instrumentoTheme(t))
        },
        Entry(name: "HeaderActionButton", family: "Botones") {
            let t = InstrumentoTheme.base
            return AnyView(HStack(spacing: 12) {
                HeaderActionButton(Text(verbatim: "Guardar"), theme: t, action: {})
                HeaderActionButton(Text(verbatim: "Guardar"), enabled: false, theme: t, action: {})
            }.instrumentoTheme(t))
        },
        Entry(name: "BackButton", family: "Botones") {
            let t = InstrumentoTheme.base
            return AnyView(HStack(spacing: 20) {
                BackButton(role: .back, theme: t, action: {})
                BackButton(role: .close, theme: t, action: {})
            }.instrumentoTheme(t))
        },

        // MARK: Tiles / datos
        Entry(name: "LiquidMetricTile", family: "Tiles") {
            AnyView(LazyVGrid(columns: [GridItem(.flexible(), spacing: LiquidSpace.s200), GridItem(.flexible())],
                              spacing: LiquidSpace.s200) {
                LiquidMetricTile(label: "SUEÑO", value: "7:20", delta: "En tu base",
                                 tone: LiquidColor.indigo, icon: .luna)
                LiquidMetricTile(label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                                 deltaTone: .up, tone: LiquidColor.cian, icon: .onda)
                LiquidMetricTile(label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                                 tone: LiquidColor.rosa, icon: .corazon)
                LiquidMetricTile(label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                                 deltaTone: .down, tone: LiquidColor.ambar, icon: .llama, action: {})
            })
        },
        Entry(name: "LiquidCajita", family: "Tiles") {
            AnyView(LiquidCajitaGrid {
                LiquidCajita(rotulo: "Rendimiento", valor: "88", unidad: "%",
                             pie: "vs tu necesidad", action: {})
                LiquidCajita(rotulo: "Eficiencia", valor: "92", unidad: "%",
                             pie: "vs tiempo en cama", action: {})
                LiquidCajita(rotulo: "Latencia", valor: LiquidCajita.sinDato,
                             pie: "sin dato en Apple Salud")
                LiquidCajita(rotulo: "Respiración", valor: "14.2", pie: "rpm",
                             tono: LiquidColor.azul, action: {})
            })
        },
        Entry(name: "EntrenarTile", family: "Tiles") {
            AnyView(HStack(spacing: 12) {
                EntrenarTile(tono: .ambar) {
                    Text(verbatim: "TILE").font(LiquidType.micro)
                        .foregroundStyle(LiquidTono.ambar.rotulo)
                }
                EntrenarTile(tono: .cian) {
                    Circle().fill(LiquidTono.cian.tesela).frame(width: 20, height: 20)
                }
            })
        },
        Entry(name: "EntrenarModulo", family: "Tiles") {
            AnyView(VStack(alignment: .leading, spacing: 8) {
                EntrenarModulo(tono: .indigo) {
                    Text(verbatim: "MÓDULO · indigo")
                        .font(LiquidType.micro)
                        .foregroundStyle(LiquidTono.indigo.rotulo)
                }
                EntrenarModulo(tono: .neutro) {
                    Text(verbatim: "MÓDULO · neutro")
                        .font(LiquidType.micro)
                        .foregroundStyle(LiquidTono.neutro.rotulo)
                }
            })
        },

        // MARK: Chips
        Entry(name: "LiquidChipSeleccion", family: "Chips") {
            AnyView(LiquidFlujoLeyenda(espacioH: LiquidSpace.s150, espacioV: LiquidSpace.s150) {
                LiquidChipSeleccion(nombre: "VFC", tono: LiquidColor.cian, a11yQuitar: "Quitar VFC") {}
                LiquidChipSeleccion(nombre: "Esfuerzo", tono: LiquidColor.ambar, a11yQuitar: "Quitar Esfuerzo") {}
                LiquidChipSeleccion(nombre: "Sueño", tono: LiquidColor.indigo, a11yQuitar: "Quitar Sueño") {}
                LiquidChipSeleccion(nombre: "FC en reposo", tono: LiquidColor.rosa, a11yQuitar: "Quitar FC en reposo") {}
            })
        },
        Entry(name: "LiquidOrigenChip", family: "Chips") {
            AnyView(VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                                 etiqueta: "Apple Salud", sufijo: "en tu dispositivo")
                LiquidOrigenChip(glyph: .rayo, badgeTono: LiquidColor.tinta500,
                                 etiqueta: "Calculado en el teléfono")
                LiquidOrigenChip(glyph: nil, badgeTono: LiquidColor.verdePrimario,
                                 etiqueta: "En tu dispositivo")
            })
        },
        Entry(name: "LiquidOrigenBadge", family: "Chips") {
            AnyView(HStack(spacing: LiquidSpace.s200) {
                LiquidOrigenBadge("Apple", tono: LiquidColor.azul)
                LiquidOrigenBadge("Manual", tono: nil)
                LiquidOrigenBadge("Medido en el dispositivo", tono: LiquidColor.verdePrimario)
            })
        },
        Entry(name: "EntrenarChipHerramienta", family: "Chips") {
            AnyView(HStack(spacing: LiquidSpace.s200) {
                EntrenarChipHerramienta(systemImage: "rectangle.stack.badge.plus",
                                        label: Text(verbatim: "Crear plan")) {}
                EntrenarChipHerramienta(systemImage: "folder.badge.plus",
                                        label: Text(verbatim: "Nueva sección")) {}
            })
        },
        Entry(name: "LiquidStatePill", family: "Chips") {
            let t = InstrumentoTheme.base
            return AnyView(VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                HStack(spacing: LiquidSpace.s200) {
                    LiquidStatePill("Session live", dot: LiquidStatePillMetrics.dotVivoDefault)
                    LiquidStatePill("Ready")
                }
                HStack(spacing: LiquidSpace.s200) {
                    LiquidStatePill(valencia: "↗ +12% vs. last month", tono: t.positiveText)
                    LiquidStatePill(valencia: "↘ −8% vs. last month", tono: t.warning)
                }
            })
        },

        // MARK: Filas
        Entry(name: "LiquidListRow", family: "Filas") {
            AnyView(LiquidListCard {
                LiquidListRow(title: "Empuje", subtitle: "L · Pecho · Hombros · Tríceps",
                              tone: LiquidColor.ambar, action: {})
                LiquidListRow(title: "Jalón", subtitle: "M · Dorsales · Espalda baja · Espalda media",
                              tone: LiquidColor.cian, action: {})
                LiquidListRow(title: "Pierna", subtitle: "X · Cuádriceps · Glúteo · Isquios",
                              tone: LiquidColor.indigo, divider: false, action: {})
            })
        },
        Entry(name: "LiquidChecklistRow", family: "Filas") {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                LiquidChecklistRow(etiqueta: "Frecuencia cardiaca en reposo", presente: true)
                LiquidChecklistRow(etiqueta: "VO₂ máx estimado", presente: true)
                LiquidChecklistRow(etiqueta: "Sueño", presente: false,
                                   motivo: "Sin noches suficientes para tu base todavía.")
            })
        },
        Entry(name: "EntrenarFilaEjercicio", family: "Filas") {
            AnyView(EntrenarFilaEjercicio(
                family: .push,
                nombre: "Press banca",
                meta: "Pecho · Barra",
                dato: (valor: "82,5 kg", rotulo: "tu récord"),
                afordancia: .chevron,
                action: {}
            ) {
                RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 52), style: .continuous)
                    .fill(LiquidColor.tinta10)
                    .frame(width: 52, height: 52)
            }.instrumentoTheme(.base))
        },

        // MARK: Controles
        Entry(name: "LiquidRangeSelector", family: "Controles") {
            AnyView(ComponentGalleryRangeDemo())
        },
        Entry(name: "EntrenarStepper", family: "Controles") {
            AnyView(VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                EntrenarStepper(valor: "+2,5 kg", tono: .verde, talla: .fila, onBajar: {}, onSubir: {})
                EntrenarStepper(valor: "1:30", tono: .neutro, talla: .hoja, onBajar: {}, onSubir: {})
            })
        },
        Entry(name: "LiquidCampoBusqueda", family: "Controles") {
            AnyView(LiquidCampoBusqueda(placeholder: "Buscar ejercicio", text: .constant("press banca"),
                                        a11yLimpiar: "Limpiar búsqueda"))
        },

        // MARK: Estructura
        Entry(name: "LiquidTabBar", family: "Estructura") {
            AnyView(ComponentGalleryTabBarDemo())
        },
        Entry(name: "LiquidMenu", family: "Estructura") {
            AnyView(
                Text(verbatim: "···")
                    .font(LiquidType.titulo)
                    .padding(LiquidSpace.s400)
                    .liquidMenu(isPresented: .constant(true), items: [
                        LiquidMenuItem("Agregar calentamiento", systemImage: "flame"),
                        LiquidMenuItem("Sustituir ejercicio", systemImage: "arrow.left.arrow.right"),
                        LiquidMenuItem("Quitar de la rutina", systemImage: "trash", isDestructive: true),
                    ])
            )
        },
        Entry(name: "LiquidSheetHeader", family: "Estructura") {
            AnyView(LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                                      numeral: "56", unidad: "ms",
                                      origenEtiqueta: "Apple Salud · anoche",
                                      explicacion: "La variación entre latidos mientras duermes.",
                                      infoMostrar: "Mostrar explicación",
                                      infoOcultar: "Ocultar explicación"))
        },
        Entry(name: "LiquidSectionHeader", family: "Estructura") {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                LiquidSectionHeader("La sesión de hoy")
                Text("El contenido de la sección vive aquí, sin banda de papel.")
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
                LiquidSectionHeader("Tu plan") {
                    Text("Editar semana").font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta700)
                }
            })
        },

        // MARK: Avisos
        Entry(name: "LiquidAviso", family: "Avisos") {
            AnyView(LiquidAviso(
                titulo: "Heads up",
                cuerpo: "Your resting heart rate has been higher than usual. Consider easing up today.",
                tono: LiquidColor.atencion))
        },
        Entry(name: "UndoToast", family: "Avisos") {
            let t = InstrumentoTheme.base
            return AnyView(UndoToast(message: "Routine deleted", theme: t, action: {})
                .instrumentoTheme(t))
        },
        Entry(name: "ConfirmCard", family: "Avisos") {
            AnyView(ConfirmCard(
                title: "¿Terminar la sesión?",
                context: "SESIÓN · 23:41 EN CURSO",
                message: "Se guardan las 8 series registradas. Las 9 que faltan no cuentan.",
                actions: [
                    InstrumentoConfirmAction("Guardar y terminar", role: .primary),
                    InstrumentoConfirmAction("Seguir entrenando", role: .secondary),
                    InstrumentoConfirmAction("Descartar la sesión", role: .destructive),
                ],
                isPresented: .constant(true)))
        },
        Entry(name: "LiquidInputCard", family: "Avisos") {
            AnyView(LiquidInputCard(
                text: .constant("Empuje y jalón"),
                title: "Renombrar carpeta",
                context: "TU PLAN",
                placeholder: "",
                cta: "Renombrar",
                dismissLabel: "Ahora no",
                isPresented: .constant(true),
                onCommit: { _ in }))
        },
        Entry(name: "LiquidPatternBlock", family: "Avisos") {
            AnyView(LiquidPatternBlock(
                overline: "Tu patrón",
                lineas: [
                    "Tus noches con alcohol bajan tu VFC al día siguiente.",
                    "Dormir 7 h o más sube tu base a la mañana.",
                ],
                tono: LiquidColor.cian))
        },

        // MARK: Gráficas
        Entry(name: "LiquidTrendChart", family: "Graficas") {
            let ejeFmt: (Date) -> String = {
                let f = DateFormatter()
                f.setLocalizedDateFormatFromTemplate("dMMM")
                return { d in f.string(from: d) }
            }()
            var chart = LiquidTrendChart(
                titulo: "Últimos 14 días",
                readout: (etiqueta: "Adecuado", tono: LiquidColor.indigo,
                          frase: "9 de las últimas 14 noches en este rango"),
                puntos: Self.trendDemoPoints(),
                bandas: [
                    LiquidChartBanda(lo: 7, hi: 9, color: LiquidColor.indigo, activa: true),
                    LiquidChartBanda(lo: 6, hi: 7, color: LiquidColor.teal, activa: false),
                    LiquidChartBanda(lo: nil, hi: 6, color: LiquidColor.atencion, activa: false),
                ],
                dominio: 5...10,
                ticksY: [(9, "9"), (7, "7"), (6, "6")],
                tono: LiquidColor.indigo,
                formatoValorScrub: { v in String(format: "%.1f h", v) },
                formatoFechaEje: ejeFmt,
                estado: .datos,
                a11yLabel: "Sueño, últimos 14 días")
            chart.scrubFijo = 5
            return AnyView(chart.environment(\.liquidMotionDisabled, true))
        },
        Entry(name: "Sparkline", family: "Graficas") {
            AnyView(Sparkline(values: Self.sparklineDemoValues())
                .frame(height: 60))
        },
    ]

    /// Serie de 14 días de muestra — misma fórmula que el `#Preview` de `LiquidTrendChart`.
    private static func trendDemoPoints() -> [(fecha: Date, valor: Double)] {
        let cal = Calendar.current
        return (0..<14).map { i in
            let fecha = cal.date(byAdding: .day, value: i - 13, to: Date())!
            let seno = 0.9 * sin(Double(i) / 1.8)
            let ruido = Double((i * 5) % 3) * 0.2
            return (fecha: fecha, valor: 7.1 + seno + ruido)
        }
    }

    /// Serie de muestra — misma fórmula que el `#Preview` de `Sparkline`.
    private static func sparklineDemoValues() -> [Double] {
        (0..<48).map { i in
            let wave = 10 * sin(Double(i) / 4.0)
            let jitter = Double((i * 13) % 7)
            return 58 + wave + jitter
        }
    }

    /// Nombres en orden de catálogo — lo que recorre el harness de captura.
    static var names: [String] { entries.map(\.name) }

    static func entry(named name: String) -> Entry? { entries.first { $0.name == name } }
}

/// Demo con `@State` para `LiquidRangeSelector` — la pieza necesita un `Binding` vivo
/// (mismo patrón que su propio `#Preview`).
private struct ComponentGalleryRangeDemo: View {
    @State private var seleccion = 0

    var body: some View {
        LiquidRangeSelector(opciones: ["S", "M", "3M", "6M", "1A", "TODO"],
                            seleccion: $seleccion, tono: LiquidColor.rosa)
    }
}

/// Demo con `@State` para `LiquidTabBar` — la pestaña activa necesita un `Binding` vivo
/// (mismo patrón que su propio `#Preview`).
private struct ComponentGalleryTabBarDemo: View {
    @State private var active: LiquidTab = .hoy

    var body: some View {
        LiquidTabBar(active: active, rotulos: .demo) { active = $0 }
    }
}

/// Monta UNA pieza del catálogo a pantalla completa sobre el lienzo Liquid, centrada, con aire.
/// `ContentView` la usa cuando el launch-arg `-noop.component` está presente.
struct ComponentGalleryHost: View {
    let name: String

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            if let entry = ComponentGallery.entry(named: name) {
                entry.make()
                    .padding(LiquidSpace.s550)
                    .frame(maxWidth: 402)
            } else {
                // Pieza no registrada: lo decimos fuerte (un PNG en blanco sería un falso verde).
                Text(verbatim: "¿componente no registrado?: \(name)")
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.rosa)
                    .padding(LiquidSpace.s550)
            }
        }
        .accessibilityIdentifier("component-gallery-\(name)")
    }
}

/// Lee el launch-arg `-noop.component <Nombre>` (poblado en `UserDefaults` por el harness).
/// `nil` en un arranque normal → la galería no aparece nunca fuera de la captura DEBUG.
enum ComponentGalleryLaunch {
    static var requestedName: String? {
        guard let n = UserDefaults.standard.string(forKey: "noop.component"), !n.isEmpty else { return nil }
        return n
    }
}
#endif
