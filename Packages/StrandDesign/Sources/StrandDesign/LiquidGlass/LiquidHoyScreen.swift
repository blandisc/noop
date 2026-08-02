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
        /// El valor GRANDE del estado separado del Ecosistema (FER-10): «52» + su contexto
        /// («lpm · en tu rango») — no es el `valor` compacto del orbe retirado.
        public struct Badge: Sendable {
            public let valor: String
            public let contexto: String
            public init(valor: String, contexto: String) {
                self.valor = valor
                self.contexto = contexto
            }
        }

        public let id: String
        public let label: String
        public let caption: String
        /// `nil` = SIN DATOS (el eje no vota): la esfera separada no dibuja nivel.
        public let progress: Double?
        public let icon: LiquidIcon.Glyph
        public let state: LiquidSignalState
        /// El micro-valor del eje YA formateado («56 ms» · «7:20» · «+0.1°»).
        public let valor: String?
        /// El valor del estado separado (FER-10). `nil` = cae a `valor`/«—».
        public let badge: Badge?

        public init(id: String, label: String, caption: String, progress: Double?,
                    icon: LiquidIcon.Glyph, state: LiquidSignalState, valor: String? = nil,
                    badge: Badge? = nil) {
            self.id = id
            self.label = label
            self.caption = caption
            self.progress = progress
            self.icon = icon
            self.state = state
            self.valor = valor
            self.badge = badge
        }
    }

    /// El avance honesto de la calibración (FER-10): noche `noche` de `total`, donde
    /// `total` viene del MOTOR (`Baselines.minNightsSeed`), no de la UI. `nil` = no
    /// estamos calibrando.
    public struct Calibracion: Sendable, Equatable {
        public let noche: Int
        public let total: Int
        public init(noche: Int, total: Int) {
            self.noche = noche
            self.total = total
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
        /// `ratio` es el DATO como texto (p. ej. «1.03»); `razon` es el MISMO dato numérico
        /// (ACWR) que alimenta el bullet-graph `LiquidCargaEscala` (barra 0→2, muesca en 1.0,
        /// corredor sano). `pos`/`zone`/`ratio` se conservan por compatibilidad de firma.
        case medida(pos: Double, zone: Int, status: String, ratio: String?,
                    razon: Double?, state: LiquidSignalState)
        case calibrando(status: String)
    }

    /// La franja del guardián (FER-1047): temperatura + respiración SIEMPRE visibles, debajo de
    /// la franja de carga y con su mismo vidrio/alto (par simétrico «lo que acompaña»). Vigila,
    /// no vota — «mostrar no es votar». Tres estados: tranquilo (cero color), UNA fuera (solo ese
    /// dato en ámbar, el veredicto NO cambia — mata el falso positivo del cuarto caliente), y las
    /// dos JUNTAS (la franja se tiñe y el centinela sí empuja el veredicto).
    public struct Guardian: Sendable {
        public enum Estado: Sendable, Equatable { case tranquilo, tempFuera, respFuera, juntas }
        /// Rótulo YA localizado: «VIGILANDO» en tranquilo/una, «JUNTAS» cuando ambas se salen.
        public let label: String
        /// Temp y resp YA formateadas («+0.1°» · «14 rpm»); «—» cuando no hay lectura hoy.
        public let temp: String
        public let resp: String
        public let estado: Estado
        /// Etiqueta de VoiceOver YA compuesta y localizada. `nil` = se deriva de label + valores.
        public let a11y: String?
        public init(label: String, temp: String, resp: String, estado: Estado, a11y: String? = nil) {
            self.label = label
            self.temp = temp
            self.resp = resp
            self.estado = estado
            self.a11y = a11y
        }
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
    /// La franja del guardián (temp + resp). `nil` = sin lectura de ninguna de las dos (no se
    /// muestra); con al menos una lectura va SIEMPRE visible, debajo de la carga.
    public let guardian: Guardian?
    public let metricas: [Metrica]
    /// Hint de VoiceOver del héroe («Abre el detalle»), YA localizado. `nil` = sin hint.
    /// Orbes y barra de carga lo reutilizan (revote /inject: navegan igual que el héroe).
    public let heroHint: String?
    /// La AFORDANCIA de descubrimiento del héroe («Cómo llegué a esto»), YA localizada: la
    /// pastilla de vidrio con chevron bajo el veredicto. Vive en el MODELO y no dentro de
    /// `Hero` porque es la misma promesa en los dos estados del héroe (veredicto y
    /// demotado) y el destino es uno solo — igual que `heroHint`. `nil` = sin pastilla.
    public let heroPuerta: String?
    /// Rótulo YA localizado de la barra de carga («CARGA»/«LOAD») — el DS no conoce locales.
    public let cargaLabel: String
    /// La fecha completa para VoiceOver («miércoles, 22 de julio de 2026»).
    public let kickerA11y: String?
    /// El ambiente semántico del día (tiñe fondo y pulsos): verde/ámbar/rojo/neutro.
    public let ambiente: LiquidAmbiente
    /// Calibrando (FER-10): la acreción del Ecosistema + «Noche n de m». `nil` = no aplica.
    public let calibracion: Calibracion?
    /// Los rótulos del Ecosistema YA localizados (la app los pasa del catálogo).
    public let rotulos: EcosistemaRotulos

    public init(kicker: String, dial: Dial, senales: [Senal], hero: Hero, carga: Carga?,
                metricas: [Metrica], guardian: Guardian? = nil, heroHint: String? = nil,
                ambiente: LiquidAmbiente = .bien, cargaLabel: String = "CARGA",
                kickerA11y: String? = nil, heroPuerta: String? = nil,
                calibracion: Calibracion? = nil, rotulos: EcosistemaRotulos = .base) {
        self.cargaLabel = cargaLabel
        self.kickerA11y = kickerA11y
        self.kicker = kicker
        self.dial = dial
        self.senales = senales
        self.hero = hero
        self.carga = carga
        self.guardian = guardian
        self.metricas = metricas
        self.heroHint = heroHint
        self.ambiente = ambiente
        self.heroPuerta = heroPuerta
        self.calibracion = calibracion
        self.rotulos = rotulos
    }

    /// El contenido de muestra del ensamble («En rango» — palabras FER-10).
    public static let ejemplo = LiquidHoyModel(
        kicker: "MIÉ 22 DE JUL",
        dial: Dial(night: (start: 20, end: 4), sol: (start: 6.8, end: 20.3), marker: 8),
        senales: [
            .init(id: "autonomico", label: "EN REPOSO", caption: "EN TU RANGO",
                  progress: 0.35, icon: .ondaSenal, state: .ok, valor: "52 lpm",
                  badge: .init(valor: "52", contexto: "lpm · en tu rango")),
            .init(id: "sueno", label: "SUEÑO", caption: "EN TU RANGO",
                  progress: 0.43, icon: .lunaSenal, state: .ok, valor: "7:20",
                  badge: .init(valor: "7:20", contexto: "h · en tu rango")),
        ],
        hero: .veredicto(title: "En rango", highlight: "rango",
                         highlightTone: LiquidColor.verdePrimario,
                         subtitle: "Tus dos señales amanecieron dentro de tu rango.",
                         confianza: nil),
        carga: .medida(pos: 51.5, zone: 1, status: "EN EQUILIBRIO", ratio: "1.03", razon: 1.03, state: .ok),
        metricas: [
            .init(id: "sleep", label: "SUEÑO", value: "7:20", delta: "En tu base",
                  tone: LiquidColor.indigo, icon: .luna),
            .init(id: "hrv", label: "VFC", value: "56", unit: "ms", delta: "+2 ms vs tu base",
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
        ],
        guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
        heroPuerta: "Cómo llegué a esto")
}

// MARK: - Contenido componible

public struct LiquidHoyContent: View {
    private let model: LiquidHoyModel
    private let onTapMetric: ((String) -> Void)?
    private let onTapSenal: ((String) -> Void)?
    private let onTapCarga: (() -> Void)?
    private let onTapHero: (() -> Void)?
    private let onTapGuardian: (() -> Void)?
    private let mostrarHintSeparar: Bool
    private let fusionInicial: Bool
    private let onFusionArrancada: (() -> Void)?
    private let onSeparacion: (() -> Void)?
    /// SOLO tests/renders: fija la fase del Ecosistema (p. ej. `.separada`).
    let ecosistemaFase: EcosistemaSimulacion.Fase?

    public init(model: LiquidHoyModel,
                onTapMetric: ((String) -> Void)? = nil,
                onTapSenal: ((String) -> Void)? = nil,
                onTapCarga: (() -> Void)? = nil,
                onTapHero: (() -> Void)? = nil,
                onTapGuardian: (() -> Void)? = nil,
                mostrarHintSeparar: Bool = true,
                fusionInicial: Bool = false,
                onFusionArrancada: (() -> Void)? = nil,
                onSeparacion: (() -> Void)? = nil) {
        self.init(model: model, onTapMetric: onTapMetric, onTapSenal: onTapSenal,
                  onTapCarga: onTapCarga, onTapHero: onTapHero,
                  onTapGuardian: onTapGuardian,
                  mostrarHintSeparar: mostrarHintSeparar, fusionInicial: fusionInicial,
                  onFusionArrancada: onFusionArrancada, onSeparacion: onSeparacion,
                  ecosistemaFase: nil)
    }

    init(model: LiquidHoyModel,
         onTapMetric: ((String) -> Void)? = nil,
         onTapSenal: ((String) -> Void)? = nil,
         onTapCarga: (() -> Void)? = nil,
         onTapHero: (() -> Void)? = nil,
         onTapGuardian: (() -> Void)? = nil,
         mostrarHintSeparar: Bool = true,
         fusionInicial: Bool = false,
         onFusionArrancada: (() -> Void)? = nil,
         onSeparacion: (() -> Void)? = nil,
         ecosistemaFase: EcosistemaSimulacion.Fase?) {
        self.model = model
        self.onTapMetric = onTapMetric
        self.onTapSenal = onTapSenal
        self.onTapCarga = onTapCarga
        self.onTapHero = onTapHero
        self.onTapGuardian = onTapGuardian
        self.mostrarHintSeparar = mostrarHintSeparar
        self.fusionInicial = fusionInicial
        self.onFusionArrancada = onFusionArrancada
        self.onSeparacion = onSeparacion
        self.ecosistemaFase = ecosistemaFase
    }

    public var body: some View {
        VStack(spacing: 0) {
            LiquidScreenHeader(kicker: model.kicker, kickerA11y: model.kickerA11y) {
                LiquidDialSeal(night: model.dial.night, sol: model.dial.sol,
                               marker: model.dial.marker)
            }
            .liquidEntrada(index: 0)

            // «El Ecosistema» (FER-10): sustituye a la fila de orbes + el bloque del héroe.
            LiquidEcosistema(
                senales: model.senales, hero: model.hero, guardian: model.guardian,
                ambiente: model.ambiente, calibracion: model.calibracion,
                rotulos: model.rotulos, heroPuerta: model.heroPuerta,
                heroHint: model.heroHint, mostrarHintSeparar: mostrarHintSeparar,
                fusionInicial: fusionInicial, faseForzada: ecosistemaFase,
                onTapVeredicto: onTapHero, onTapSenal: onTapSenal,
                onTapGuardian: onTapGuardian,
                onFusionArrancada: onFusionArrancada, onSeparacion: onSeparacion)
                .padding(.top, LiquidSpace.s150)
                .liquidEntrada(index: 1)

            if model.carga != nil {
                carga
                    .padding(.top, LiquidSpace.s300)
                    .liquidEntrada(index: 2)
            }

            // La franja del guardián (FER-1047): par simétrico bajo la carga (mismo vidrio/alto).
            // Gap corto (s150) cuando acompaña a la carga para que el ojo las lea juntas; s300 si
            // la carga no está, para no pegarse al héroe/grid.
            if let guardian = model.guardian {
                LiquidGuardianFranja(guardian)
                    .padding(.top, model.carga != nil ? LiquidSpace.s150 : LiquidSpace.s300)
                    .liquidEntrada(index: 2)
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
                        .liquidEntrada(index: 3 + i)
                }
            }
            // s300 (revote /inject): la barra de carga NO es una fila del grid — el gap
            // hacia los tiles debe ser mayor que el gap interno del grid (s200).
            .padding(.top, LiquidSpace.s300)
        }
        .padding(.horizontal, LiquidSpace.s550)
    }

    @ViewBuilder
    private var carga: some View {
        switch model.carga {
        case .medida(_, _, let status, _, let razon, let state):
            cargaTocable(LiquidCargaEscala(razon: razon, estado: state, rotulo: status,
                                           densidad: .fila, eje: model.cargaLabel))
        case .calibrando(let status):
            cargaTocable(LiquidCargaEscala(razon: nil, rotulo: status, densidad: .fila,
                                           calibrando: true, eje: model.cargaLabel))
        case nil:
            EmptyView()
        }
    }

    /// La escala de carga navega igual que el héroe (revote /inject). El bullet-graph
    /// aporta su propio vidrio y área tocable; aquí solo lo hacemos botón cuando hay destino.
    @ViewBuilder
    private func cargaTocable(_ escala: LiquidCargaEscala) -> some View {
        if let onTapCarga {
            Button(action: onTapCarga) { escala }
                .buttonStyle(.liquidPress)
                .accessibilityHint(Text(verbatim: model.heroHint ?? ""))
        } else {
            escala
        }
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
            // Padding superior recortado (pedido del dueño /inject: la pantalla tenía un
            // scroll «ligero»): s800 en vez de s1400 — el velo del status bar ya cubre esa
            // franja, así que 56 pt eran aire de más. Recupera 24 pt y la columna entra sin
            // scroll. Mejor que bajar el dock, que es flotante con margen intencional.
            .padding(.top, LiquidSpace.s800)
            // Aire para que el último tile libre el dock flotante.
            .padding(.bottom, scrolls ? LiquidSpace.s1400 + LiquidSpace.s1400 : 0)
            // ↑ el dock FLOTA sobre el contenido (~64 pt de alto + margen): el aire debe
            // librarlo o los últimos dos tiles quedan tapados (pedido del dueño /inject).
            // El scroll se recortó arriba (top s1400→s800), no aquí.
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

#Preview("Hoy · calibrando (acreción)") {
    LiquidHoyScreen(model: LiquidHoyModel(
        kicker: "MIÉ 22 DE JUL",
        dial: .init(night: nil, marker: 10),
        senales: [
            .init(id: "autonomico", label: "EN REPOSO", caption: "SIN DATOS",
                  progress: nil, icon: .ondaSenal, state: .ok),
            .init(id: "sueno", label: "SUEÑO", caption: "SIN DATOS",
                  progress: nil, icon: .lunaSenal, state: .ok),
        ],
        hero: .demotado(kicker: "PREPARACIÓN",
                        title: "Conociéndote",
                        subtitle: "Noche 4 de 7 · tu rango se está formando"),
        carga: .calibrando(status: "CALIBRANDO"),
        metricas: LiquidHoyModel.ejemplo.metricas,
        guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .tranquilo),
        ambiente: .neutro,
        calibracion: .init(noche: 4, total: 7)))
        .frame(width: 402, height: 874)
        .environment(\.liquidMotionDisabled, true)
}
#endif
