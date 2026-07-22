import SwiftUI

// MARK: - Liquid Glass · Pantalla Hoy (handoff §7.1)
//
// La pantalla de referencia del sistema, armada 100 % por composición (regla del 90 %):
// fondo ambiental → velo + cabecera (kicker + dial-sello) → zona de señales (cables vivos
// + 3 × SignalOrb) → hero de veredicto → CargaBar → grid 2 col de 8 × MetricTile → TabBar
// flotante. Aquí solo hay layout + datos: cero estilos sueltos, cero hex, cero duraciones.
//
// Los datos entran por `LiquidHoyModel` (el estado del §9 del handoff); `.ejemplo` es el
// contenido de muestra del ensamble. La entrada de bloques usa la receta `entrada` con
// stagger 60 ms; bajo Reduce Motion todo aparece con un crossfade simple.

public struct LiquidHoyModel: Sendable {
    public struct Senal: Sendable, Identifiable {
        public var id: String { label }
        public let label: String
        public let caption: String
        public let progress: Double
        public let icon: LiquidIcon.Glyph
        public let state: LiquidSignalState

        public init(label: String, caption: String, progress: Double,
                    icon: LiquidIcon.Glyph, state: LiquidSignalState) {
            self.label = label
            self.caption = caption
            self.progress = progress
            self.icon = icon
            self.state = state
        }
    }

    public struct Veredicto: Sendable {
        public let title: String
        public let highlight: String
        public let subtitle: String

        public init(title: String, highlight: String, subtitle: String) {
            self.title = title
            self.highlight = highlight
            self.subtitle = subtitle
        }
    }

    public struct Carga: Sendable {
        public let pos: Double
        public let zone: Int
        public let status: String
        public let state: LiquidSignalState

        public init(pos: Double, zone: Int, status: String, state: LiquidSignalState) {
            self.pos = pos
            self.zone = zone
            self.status = status
            self.state = state
        }
    }

    public struct Metrica: Sendable, Identifiable {
        public var id: String { label }
        public let label: String
        public let value: String
        public let unit: String
        public let delta: String
        public let deltaTone: LiquidDeltaTone
        public let tone: Color
        public let icon: LiquidIcon.Glyph

        public init(label: String, value: String, unit: String = "", delta: String,
                    deltaTone: LiquidDeltaTone = .neutral, tone: Color, icon: LiquidIcon.Glyph) {
            self.label = label
            self.value = value
            self.unit = unit
            self.delta = delta
            self.deltaTone = deltaTone
            self.tone = tone
            self.icon = icon
        }
    }

    public let kicker: String
    public let senales: [Senal]
    public let veredicto: Veredicto
    public let carga: Carga
    public let metricas: [Metrica]

    public init(kicker: String, senales: [Senal], veredicto: Veredicto, carga: Carga,
                metricas: [Metrica]) {
        self.kicker = kicker
        self.senales = senales
        self.veredicto = veredicto
        self.carga = carga
        self.metricas = metricas
    }

    /// El contenido de muestra del ensamble §7.1 («Dale con todo»).
    public static let ejemplo = LiquidHoyModel(
        kicker: "MIÉ 22 DE JUL",
        senales: [
            .init(label: "AUTONÓMICO", caption: "EN TU RANGO", progress: 0.35,
                  icon: .ondaSenal, state: .ok),
            .init(label: "SUEÑO", caption: "EN TU RANGO", progress: 0.43,
                  icon: .lunaSenal, state: .ok),
            .init(label: "TÉRMICO", caption: "EN TU RANGO", progress: 0.5,
                  icon: .termoSenal, state: .ok),
        ],
        veredicto: .init(title: "Dale\ncon todo", highlight: "todo",
                         subtitle: "Tus 3 señales amanecieron dentro de tu rango."),
        carga: .init(pos: 51.5, zone: 1, status: "EN EQUILIBRIO · 1.03", state: .ok),
        metricas: [
            .init(label: "SUEÑO", value: "7:20", delta: "En tu base",
                  tone: LiquidColor.indigo, icon: .luna),
            .init(label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                  deltaTone: .up, tone: LiquidColor.cian, icon: .onda),
            .init(label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                  tone: LiquidColor.rosa, icon: .corazon),
            .init(label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                  deltaTone: .down, tone: LiquidColor.ambar, icon: .llama),
            .init(label: "PASOS", value: "8,432", delta: "+612 vs tu base",
                  deltaTone: .up, tone: LiquidColor.teal, icon: .pasos),
            .init(label: "TEMP. DE PIEL", value: "+0.1", unit: "°C", delta: "En tu base",
                  tone: LiquidColor.ambar, icon: .termo),
            .init(label: "RESPIRACIÓN", value: "14.5", unit: "rpm", delta: "En tu base",
                  tone: LiquidColor.azul, icon: .resp),
            .init(label: "ESTRÉS", value: "1.2", unit: "/3", delta: "−0.5 vs tu base",
                  deltaTone: .up, tone: LiquidColor.verdePrimario, icon: .estres),
        ])
}

public struct LiquidHoyScreen: View {
    private let model: LiquidHoyModel
    private let onSelectTab: ((LiquidTab) -> Void)?
    private let scrolls: Bool

    public init(model: LiquidHoyModel = .ejemplo, onSelectTab: ((LiquidTab) -> Void)? = nil) {
        self.init(model: model, onSelectTab: onSelectTab, scrolls: true)
    }

    /// `scrolls: false` presenta el contenido sin ScrollView — solo para renders/tests
    /// (ImageRenderer no dibuja el contenido de un ScrollView).
    init(model: LiquidHoyModel = .ejemplo, onSelectTab: ((LiquidTab) -> Void)? = nil,
         scrolls: Bool) {
        self.model = model
        self.onSelectTab = onSelectTab
        self.scrolls = scrolls
    }

    public var body: some View {
        ZStack {
            LiquidAmbientBackground.hoy
            if scrolls {
                ScrollView(.vertical, showsIndicators: false) { content }
            } else {
                VStack(spacing: 0) {
                    content
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .top) {
            LiquidVeil().frame(height: LiquidSpace.s1400)
        }
        .overlay(alignment: .bottom) {
            LiquidTabBar(active: .hoy, onSelect: onSelectTab)
                .padding(.horizontal, LiquidSpace.dockSide)
                .padding(.bottom, LiquidSpace.dockBottom)
        }
        .ignoresSafeArea(edges: .top)
    }

    /// La columna de Hoy (§7.1): cabecera → señales → hero → carga → grid de métricas.
    private var content: some View {
        VStack(spacing: 0) {
            LiquidScreenHeader(kicker: model.kicker) { LiquidDialSeal() }
                .liquidEntrada(index: 0)

            senales
                .padding(.top, LiquidSpace.s150)
                .liquidEntrada(index: 1)

            LiquidHeroVeredicto(title: model.veredicto.title,
                                highlight: model.veredicto.highlight,
                                subtitle: model.veredicto.subtitle)
                .padding(.top, LiquidSpace.s050)
                .liquidEntrada(index: 2)

            LiquidCargaBar(pos: model.carga.pos, zone: model.carga.zone,
                           status: model.carga.status, state: model.carga.state)
                .padding(.top, LiquidSpace.s300)
                .liquidEntrada(index: 3)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: LiquidSpace.s200),
                GridItem(.flexible()),
            ], spacing: LiquidSpace.s200) {
                ForEach(Array(model.metricas.enumerated()), id: \.element.id) { i, m in
                    LiquidMetricTile(label: m.label, value: m.value, unit: m.unit,
                                     delta: m.delta, deltaTone: m.deltaTone,
                                     tone: m.tone, icon: m.icon)
                        .liquidEntrada(index: 4 + i)
                }
            }
            .padding(.top, LiquidSpace.s200)
        }
        .padding(.horizontal, LiquidSpace.s550)
        .padding(.top, LiquidSpace.s1400)
        // Aire para que el último tile libre el dock flotante.
        .padding(.bottom, scrolls ? LiquidSpace.s1400 + LiquidSpace.s800 : 0)
    }

    /// Zona de señales (alto 178): cables vivos de fondo + 3 orbes centrados gap 53.
    private var senales: some View {
        ZStack(alignment: .top) {
            LiquidSignalCables()
            HStack(spacing: 53) {
                ForEach(model.senales) { senal in
                    LiquidSignalOrb(label: senal.label, caption: senal.caption,
                                    progress: senal.progress, icon: senal.icon,
                                    state: senal.state)
                }
            }
        }
        .frame(height: 178)
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Hoy · Liquid Glass") {
    LiquidHoyScreen()
        .frame(width: 402, height: 874)
}

#Preview("Hoy · sin motion (Reduce Motion)") {
    LiquidHoyScreen()
        .frame(width: 402, height: 874)
        .environment(\.liquidMotionDisabled, true)
}
#endif
