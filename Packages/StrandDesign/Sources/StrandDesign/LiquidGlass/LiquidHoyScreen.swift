import SwiftUI

// MARK: - Liquid Glass · Pantalla Hoy (handoff §7.1 · FER-1045)
//
// Dos capas:
//   • `LiquidHoyContent` — la columna de Hoy COMPONIBLE: sin ScrollView, sin TabBar, sin
//     fondo y sin safe-areas propios. El app es dueño del scroll (pull-to-sync), del dock
//     y monta `LiquidAmbientBackground` detrás. Las acciones llegan por closures con IDs
//     estables del modelo.
//   • `LiquidHoyScreen` — la pantalla de REFERENCIA standalone (previews/render tests):
//     envuelve el content con fondo, velo, scroll y TabBar, con el mock del ensamble.
//
// El modelo (`LiquidHoyModel`) es el estado del §9 del handoff extendido para datos
// reales: héroe por estado (veredicto/demotado), señal sin datos (`progress == nil`),
// carga calibrando, dial con noche opcional y origen por métrica. Todos los strings
// llegan YA localizados — el DS no conoce locales.

public struct LiquidHoyModel: Sendable {
    public struct Senal: Sendable, Identifiable {
        public let id: String
        public let label: String
        public let caption: String
        /// `nil` = SIN DATOS (el eje no vota): solo track, sin arco ni punto.
        public let progress: Double?
        public let icon: LiquidIcon.Glyph
        public let state: LiquidSignalState
        /// El micro-valor del eje YA formateado («56 ms» · «7:20» · «+0.1°») — camino
        /// 1+3 de la elevación /inject: el orbe muestra su DATO; el icono queda como
        /// identidad cuando no hay lectura.
        public let valor: String?

        public init(id: String, label: String, caption: String, progress: Double?,
                    icon: LiquidIcon.Glyph, state: LiquidSignalState, valor: String? = nil) {
            self.id = id
            self.label = label
            self.caption = caption
            self.progress = progress
            self.icon = icon
            self.state = state
            self.valor = valor
        }
    }

    /// El héroe por estado (tabla canónica FER-1045): veredicto con palabra destacada, o
    /// la variante demotada (lectura de día / fallback de sueño) sin palabra grande.
    public enum Hero: Sendable {
        case veredicto(title: String, highlight: String, highlightTone: Color,
                       subtitle: String, confianza: String?)
        case demotado(kicker: String?, title: String, subtitle: String)
    }

    /// El dial-sello 24 h: noche real de anoche (horas 0–24, medianoche arriba) o `nil`
    /// si no hubo sesión; `sol` = amanecer/atardecer reales para el arco del día en oro;
    /// `marker` = la hora actual.
    public struct Dial: Sendable {
        public let night: (start: Double, end: Double)?
        public let sol: (start: Double, end: Double)?
        public let marker: Double

        public init(night: (start: Double, end: Double)?,
                    sol: (start: Double, end: Double)? = nil, marker: Double) {
            self.night = night
            self.sol = sol
            self.marker = marker
        }
    }

    public enum Carga: Sendable {
        /// `ratio` es el DATO (p. ej. «1.03») separado del rótulo de estado (pasada UI:
        /// jerarquía de dato — el número pesa más que el rótulo).
        case medida(pos: Double, zone: Int, status: String, ratio: String?,
                    state: LiquidSignalState)
        case calibrando(status: String)
    }

    public struct Metrica: Sendable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        public let unit: String
        public let delta: String
        public let deltaTone: LiquidDeltaTone
        public let tone: Color
        public let icon: LiquidIcon.Glyph
        public let origen: LiquidOrigen
        /// Valencia YA localizada para VoiceOver («mejor que tu base») — el color solo no
        /// habla (pasada UX). `nil` = sin valencia.
        public let a11yValencia: String?
        /// Origen YA localizado para VoiceOver («Apple Salud» / «calculado en tu teléfono»).
        public let a11yOrigen: String?

        public init(id: String, label: String, value: String, unit: String = "",
                    delta: String, deltaTone: LiquidDeltaTone = .neutral, tone: Color,
                    icon: LiquidIcon.Glyph, origen: LiquidOrigen = .medido,
                    a11yValencia: String? = nil, a11yOrigen: String? = nil) {
            self.id = id
            self.label = label
            self.value = value
            self.unit = unit
            self.delta = delta
            self.deltaTone = deltaTone
            self.tone = tone
            self.icon = icon
            self.origen = origen
            self.a11yValencia = a11yValencia
            self.a11yOrigen = a11yOrigen
        }
    }

    public let kicker: String
    public let dial: Dial
    public let senales: [Senal]
    public let hero: Hero
    /// `nil` = la barra de carga no se muestra (el modelo de carga aún no siembra).
    public let carga: Carga?
    public let metricas: [Metrica]
    /// Hint de VoiceOver del héroe («Abre el detalle»), YA localizado. `nil` = sin hint.
    public let heroHint: String?
    /// El ambiente semántico del día (tiñe fondo y pulsos): verde/ámbar/rojo/neutro.
    public let ambiente: LiquidAmbiente

    public init(kicker: String, dial: Dial, senales: [Senal], hero: Hero, carga: Carga?,
                metricas: [Metrica], heroHint: String? = nil,
                ambiente: LiquidAmbiente = .bien) {
        self.kicker = kicker
        self.dial = dial
        self.senales = senales
        self.hero = hero
        self.carga = carga
        self.metricas = metricas
        self.heroHint = heroHint
        self.ambiente = ambiente
    }

    /// El contenido de muestra del ensamble §7.1 («Dale con todo»).
    public static let ejemplo = LiquidHoyModel(
        kicker: "MIÉ 22 DE JUL",
        dial: Dial(night: (start: 20, end: 4), sol: (start: 6.8, end: 20.3), marker: 8),
        senales: [
            .init(id: "autonomico", label: "AUTONÓMICO", caption: "EN TU RANGO",
                  progress: 0.35, icon: .ondaSenal, state: .ok, valor: "56 ms"),
            .init(id: "sueno", label: "SUEÑO", caption: "EN TU RANGO",
                  progress: 0.43, icon: .lunaSenal, state: .ok, valor: "7:20"),
            .init(id: "termico", label: "TÉRMICO", caption: "EN TU RANGO",
                  progress: 0.5, icon: .termoSenal, state: .ok, valor: "+0.1°"),
        ],
        hero: .veredicto(title: "Dale\ncon todo", highlight: "todo",
                         highlightTone: LiquidColor.verdePrimario,
                         subtitle: "Tus 3 señales amanecieron dentro de tu rango.",
                         confianza: nil),
        carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", state: .ok),
        metricas: [
            .init(id: "sleep", label: "SUEÑO", value: "7:20", delta: "En tu base",
                  tone: LiquidColor.indigo, icon: .luna),
            .init(id: "hrv", label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                  deltaTone: .up, tone: LiquidColor.cian, icon: .onda),
            .init(id: "rhr", label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                  tone: LiquidColor.rosa, icon: .corazon),
            .init(id: "strain", label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                  deltaTone: .down, tone: LiquidColor.ambar, icon: .llama),
            .init(id: "steps", label: "PASOS", value: "8,432", delta: "+612 vs tu base",
                  deltaTone: .up, tone: LiquidColor.teal, icon: .pasos),
            .init(id: "skintemp", label: "TEMP. DE PIEL", value: "+0.1", unit: "°C",
                  delta: "En tu base", tone: LiquidColor.ambar, icon: .termo),
            .init(id: "resp", label: "RESPIRACIÓN", value: "14.5", unit: "rpm",
                  delta: "En tu base", tone: LiquidColor.azul, icon: .resp),
            .init(id: "stress", label: "ESTRÉS", value: "1.2", unit: "/3",
                  delta: "−0.5 vs tu base", deltaTone: .up,
                  tone: LiquidColor.verdePrimario, icon: .estres),
        ])
}

// MARK: - Contenido componible

public struct LiquidHoyContent: View {
    private let model: LiquidHoyModel
    private let onTapMetric: ((String) -> Void)?
    private let onTapSenal: ((String) -> Void)?
    private let onTapCarga: (() -> Void)?
    private let onTapHero: (() -> Void)?

    public init(model: LiquidHoyModel,
                onTapMetric: ((String) -> Void)? = nil,
                onTapSenal: ((String) -> Void)? = nil,
                onTapCarga: (() -> Void)? = nil,
                onTapHero: (() -> Void)? = nil) {
        self.model = model
        self.onTapMetric = onTapMetric
        self.onTapSenal = onTapSenal
        self.onTapCarga = onTapCarga
        self.onTapHero = onTapHero
    }

    public var body: some View {
        VStack(spacing: 0) {
            LiquidScreenHeader(kicker: model.kicker) {
                LiquidDialSeal(night: model.dial.night, sol: model.dial.sol,
                               marker: model.dial.marker)
            }
            .liquidEntrada(index: 0)

            senales
                .padding(.top, LiquidSpace.s150)
                .liquidEntrada(index: 1)

            hero
                .padding(.top, LiquidSpace.s050)
                .liquidEntrada(index: 2)

            if model.carga != nil {
                carga
                    .padding(.top, LiquidSpace.s300)
                    .liquidEntrada(index: 3)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: LiquidSpace.s200),
                GridItem(.flexible()),
            ], spacing: LiquidSpace.s200) {
                ForEach(Array(model.metricas.enumerated()), id: \.element.id) { i, m in
                    LiquidMetricTile(
                        label: m.label, value: m.value, unit: m.unit, delta: m.delta,
                        deltaTone: m.deltaTone, tone: m.tone, icon: m.icon, origen: m.origen,
                        a11yValencia: m.a11yValencia, a11yOrigen: m.a11yOrigen,
                        action: onTapMetric.map { tap in { tap(m.id) } })
                        .liquidEntrada(index: 4 + i)
                }
            }
            .padding(.top, LiquidSpace.s200)
        }
        .padding(.horizontal, LiquidSpace.s550)
    }

    @ViewBuilder
    private var hero: some View {
        let heroView = Group {
            switch model.hero {
            case .veredicto(let title, let highlight, let tone, let subtitle, let confianza):
                LiquidHeroVeredicto(title: title, highlight: highlight, highlightTone: tone,
                                    subtitle: subtitle, confianza: confianza)
            case .demotado(let kicker, let title, let subtitle):
                LiquidHeroDemotado(kicker: kicker, title: title, subtitle: subtitle)
            }
        }
        if let onTapHero {
            Button(action: onTapHero) { heroView }
                .buttonStyle(.liquidPress)
                .accessibilityHint(Text(verbatim: model.heroHint ?? ""))
        } else {
            heroView
        }
    }

    @ViewBuilder
    private var carga: some View {
        switch model.carga {
        case .medida(let pos, let zone, let status, let ratio, let state):
            LiquidCargaBar(modo: .medida(pos: pos, zone: zone), status: status,
                           ratio: ratio, state: state, action: onTapCarga)
        case .calibrando(let status):
            LiquidCargaBar(modo: .calibrando, status: status, action: onTapCarga)
        case nil:
            EmptyView()
        }
    }

    /// Zona de señales (alto 178): cables vivos de fondo + 3 orbes centrados gap 53.
    private var senales: some View {
        ZStack(alignment: .top) {
            // Detalle fino (pasada UI): los cables llegan al FINAL de la cascada de
            // entrada — primera impresión serena, el movimiento entra como respiración.
            LiquidSignalCables(tone: model.ambiente.acento)
                .liquidEntrada(index: 12)
            // 72 + 45 = 117: el paso de centros no cambia y los cables siguen exactos.
            HStack(spacing: 45) {
                ForEach(model.senales) { senal in
                    LiquidSignalOrb(label: senal.label, caption: senal.caption,
                                    progress: senal.progress, icon: senal.icon,
                                    state: senal.state, valor: senal.valor,
                                    action: onTapSenal.map { tap in { tap(senal.id) } })
                }
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Pantalla de referencia (standalone)

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
            LiquidAmbientBackground.hoy(model.ambiente)
            if scrolls {
                ScrollView(.vertical, showsIndicators: false) { column }
            } else {
                VStack(spacing: 0) {
                    column
                    Spacer(minLength: 0)
                }
            }
        }
        .overlay(alignment: .top) {
            LiquidVeil(tone: model.ambiente.acento).frame(height: LiquidSpace.s1400)
        }
        .overlay(alignment: .bottom) {
            LiquidTabBar(active: .hoy, onSelect: onSelectTab)
                .padding(.horizontal, LiquidSpace.dockSide)
                .padding(.bottom, LiquidSpace.dockBottom)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var column: some View {
        LiquidHoyContent(model: model)
            .padding(.top, LiquidSpace.s1400)
            // Aire para que el último tile libre el dock flotante.
            .padding(.bottom, scrolls ? LiquidSpace.s1400 + LiquidSpace.s800 : 0)
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

#Preview("Hoy · demotado + calibrando") {
    LiquidHoyScreen(model: LiquidHoyModel(
        kicker: "MIÉ 22 DE JUL",
        dial: .init(night: nil, marker: 10),
        senales: [
            .init(id: "autonomico", label: "AUTONÓMICO", caption: "EN TU RANGO",
                  progress: 0.4, icon: .ondaSenal, state: .ok),
            .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                  progress: nil, icon: .lunaSenal, state: .ok),
            .init(id: "termico", label: "TÉRMICO", caption: "SIN DATOS",
                  progress: nil, icon: .termoSenal, state: .ok),
        ],
        hero: .demotado(kicker: "LECTURA DE DÍA",
                        title: "Señales en tu rango",
                        subtitle: "Sin noche grabada: lectura menos precisa."),
        carga: .calibrando(status: "CALIBRANDO"),
        metricas: LiquidHoyModel.ejemplo.metricas))
        .frame(width: 402, height: 874)
        .environment(\.liquidMotionDisabled, true)
}
#endif
