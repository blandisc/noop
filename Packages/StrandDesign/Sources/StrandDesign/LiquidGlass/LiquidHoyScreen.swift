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
        /// Estados del guardián (FER-33 · F3).
        /// - `tranquilo` / `tempFuera` / `respFuera` / `juntas`: con lecturas y base.
        /// - `sinLectura`: anoche no hubo ninguna de las dos señales (la hoja NO afirma «en patrón»).
        /// - `conociendote`: hay lecturas pero aún no hay patrón propio que comparar.
        public enum Estado: Sendable, Equatable {
            case tranquilo, tempFuera, respFuera, juntas, sinLectura, conociendote, incompleto
        }
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

    // MARK: Los 4 módulos de «El Tablero» (FER-28)

    /// Una COLUMNA de dato dentro de un módulo: su rótulo, su tono 1:1, su contenido (simple,
    /// sueño con dos-puntos tenue, carga con bullet-graph, o par teñido tipo «VIGILANDO»), a
    /// dónde navega su tap y su etiqueta de VoiceOver YA compuesta.
    public struct Columna: Sendable, Identifiable {
        /// A qué hoja abre el tap — reusa las hojas de hoy (no se crean nuevas).
        public enum Destino: Sendable { case metrica(String), carga, guardian }
        /// Alineación de la columna en su celda (las columnas `.der` del mockup van a la derecha).
        public enum Alineacion: Sendable { case izq, der }
        /// La forma del valor de la columna.
        public enum Contenido: Sendable {
            /// Valor teñido 1:1 + unidad + una línea de detalle (verde si `mejora`).
            case simple(value: String, unit: String, detail: String, mejora: Bool)
            /// Sueño: los dígitos mandan, los dos-puntos van en regular tinta/700.
            case sueno(horas: String, minutos: String, unit: String, detail: String)
            /// Carga: bullet-graph `LiquidCargaEscala` en densidad de bloque.
            case carga(razon: Double?, status: String, state: LiquidSignalState, calibrando: Bool)
            /// Par teñido separado por un punto («+0.1°» ámbar · «14 rpm» azul).
            case par(v1: String, tone1: Color, v2: String, tone2: Color)
        }

        public let id: String
        public let label: String
        public let tone: Color
        public let alineacion: Alineacion
        public let contenido: Contenido
        public let destino: Destino
        /// VoiceOver YA compuesto: «{dato}, {valor}, {delta}[, {valencia}]».
        public let a11yLabel: String
        public let a11yHint: String

        public init(id: String, label: String, tone: Color, alineacion: Alineacion = .izq,
                    contenido: Contenido, destino: Destino, a11yLabel: String,
                    a11yHint: String = "Opens the detail") {
            self.id = id
            self.label = label
            self.tone = tone
            self.alineacion = alineacion
            self.contenido = contenido
            self.destino = destino
            self.a11yLabel = a11yLabel
            self.a11yHint = a11yHint
        }
    }

    /// Un MÓDULO de vidrio: su cabecera-kicker (solo el rótulo — «silencio por defecto»), la
    /// palabra única de ámbar cuando un dato sale de rango (`atencion`), los tonos+periodo de
    /// su aurora fina, y sus columnas.
    public struct Modulo: Sendable, Identifiable {
        public let id: String
        public let kicker: String
        /// UNA palabra en ámbar en la cabecera cuando un dato del módulo sale de rango
        /// («temp. alta»). `nil` = día bueno, la cabecera calla.
        public let atencion: String?
        public let auroraTones: [Color]
        public let auroraPeriod: Double
        public let auroraReverse: Bool
        public let columnas: [Columna]

        public init(id: String, kicker: String, atencion: String? = nil,
                    auroraTones: [Color], auroraPeriod: Double, auroraReverse: Bool = false,
                    columnas: [Columna]) {
            self.id = id
            self.kicker = kicker
            self.atencion = atencion
            self.auroraTones = auroraTones
            self.auroraPeriod = auroraPeriod
            self.auroraReverse = auroraReverse
            self.columnas = columnas
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
    /// Los 4 módulos de «El Tablero» (FER-28) — la mitad inferior de Hoy. Vacío = el content
    /// no dibuja tablero (compat con consumidores previos al rediseño).
    public let modulos: [Modulo]
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
                metricas: [Metrica], modulos: [Modulo] = [], guardian: Guardian? = nil,
                heroHint: String? = nil, ambiente: LiquidAmbiente = .bien,
                cargaLabel: String = "CARGA", kickerA11y: String? = nil,
                heroPuerta: String? = nil, calibracion: Calibracion? = nil,
                rotulos: EcosistemaRotulos = .base) {
        self.cargaLabel = cargaLabel
        self.kickerA11y = kickerA11y
        self.kicker = kicker
        self.dial = dial
        self.senales = senales
        self.hero = hero
        self.carga = carga
        self.guardian = guardian
        self.metricas = metricas
        self.modulos = modulos
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
                         // El copy EXACTO del builder (`Both of your signals woke up in your
                         // range.` → es). El ejemplo se presenta como paridad de producto y el
                         // arnés de estados lo renderiza como tal, así que una redacción propia
                         // aquí acaba enseñándole al dueño un texto que la app nunca dice.
                         subtitle: "Tus dos señales amanecieron en tu rango.",
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
        modulos: ejemploModulos,
        guardian: .init(label: "VIGILANDO", temp: "+0.1°", resp: "14 rpm", estado: .tranquilo),
        heroPuerta: "Cómo llegué a esto")

    /// Los 4 módulos de muestra (datos del mockup canónico «El Tablero»).
    public static let ejemploModulos: [Modulo] = [
        .init(id: "veredicto", kicker: "LO QUE INFORMA TU VEREDICTO",
              auroraTones: [LiquidColor.indigo, LiquidColor.rosa, LiquidColor.verdePrimario],
              auroraPeriod: 44, auroraReverse: false,
              columnas: [
                .init(id: "sleep", label: "SUEÑO", tone: LiquidColor.indigo, alineacion: .izq,
                      contenido: .sueno(horas: "7", minutos: "20", unit: "h",
                                        detail: "20:00 → 4:00"),
                      destino: .metrica("sleep"),
                      a11yLabel: "Sueño, 7 horas 20 minutos, de 20:00 a 4:00"),
                .init(id: "rhr", label: "FC REPOSO", tone: LiquidColor.rosa, alineacion: .der,
                      contenido: .simple(value: "52", unit: "lpm", detail: "en tu rango",
                                         mejora: false),
                      destino: .metrica("rhr"),
                      a11yLabel: "FC en reposo, 52 lpm, en tu rango"),
              ]),
        .init(id: "acompana", kicker: "LO QUE ACOMPAÑA",
              auroraTones: [LiquidColor.verdePrimario, LiquidColor.ambar, LiquidColor.azul],
              auroraPeriod: 52, auroraReverse: true,
              columnas: [
                .init(id: "carga", label: "CARGA", tone: LiquidColor.verdePrimario,
                      alineacion: .izq,
                      contenido: .carga(razon: 1.03, status: "EN EQUILIBRIO", state: .ok,
                                        calibrando: false),
                      destino: .carga, a11yLabel: "Carga, 1.03, en equilibrio"),
                .init(id: "vigilando", label: "VIGILANDO", tone: LiquidColor.tinta500,
                      alineacion: .der,
                      contenido: .par(v1: "+0.1°", tone1: LiquidColor.ambar,
                                      v2: "14 rpm", tone2: LiquidColor.azul),
                      destino: .guardian,
                      a11yLabel: "Vigilando, temperatura +0.1 grados, respiración 14 rpm"),
              ]),
        .init(id: "dia", kicker: "EL DÍA",
              auroraTones: [LiquidColor.ambar, LiquidColor.teal, LiquidColor.verdePrimario],
              auroraPeriod: 38, auroraReverse: false,
              columnas: [
                .init(id: "strain", label: "ESFUERZO", tone: LiquidColor.ambar, alineacion: .izq,
                      contenido: .simple(value: "10.0", unit: "", detail: "−0.7 vs base",
                                         mejora: false),
                      destino: .metrica("strain"),
                      a11yLabel: "Esfuerzo, 10.0, −0.7 contra tu base"),
                .init(id: "steps", label: "PASOS", tone: LiquidColor.teal, alineacion: .izq,
                      contenido: .simple(value: "8,432", unit: "", detail: "+612", mejora: true),
                      destino: .metrica("steps"),
                      a11yLabel: "Pasos, 8,432, +612 contra tu base"),
                .init(id: "stress", label: "ESTRÉS", tone: LiquidColor.verdePrimario,
                      alineacion: .der,
                      contenido: .simple(value: "1.2", unit: "/3", detail: "−0.5", mejora: true),
                      destino: .metrica("stress"),
                      a11yLabel: "Estrés, 1.2 de 3, −0.5 contra tu base"),
              ]),
        .init(id: "noche", kicker: "LA NOCHE",
              auroraTones: [LiquidColor.cian, LiquidColor.ambar, LiquidColor.azul],
              auroraPeriod: 58, auroraReverse: true,
              columnas: [
                .init(id: "hrv", label: "VFC", tone: LiquidColor.cian, alineacion: .izq,
                      contenido: .simple(value: "56", unit: "ms", detail: "+2 vs base",
                                         mejora: true),
                      destino: .metrica("hrv"),
                      a11yLabel: "VFC, 56 ms, +2 contra tu base"),
                .init(id: "skintemp", label: "TEMP. PIEL", tone: LiquidColor.ambar,
                      alineacion: .izq,
                      contenido: .simple(value: "+0.1", unit: "°C", detail: "en base",
                                         mejora: false),
                      destino: .metrica("skintemp"),
                      a11yLabel: "Temperatura de piel, +0.1 grados, en base"),
                .init(id: "resp", label: "RESP.", tone: LiquidColor.azul, alineacion: .der,
                      contenido: .simple(value: "14.5", unit: "rpm", detail: "en base",
                                         mejora: false),
                      destino: .metrica("resp"),
                      a11yLabel: "Respiración, 14.5 rpm, en base"),
              ]),
    ]

    /// Módulos en CALIBRANDO: los valores existen, pero sin base los deltas dicen «aún sin
    /// base» y la carga va apagada. La plasta acompaña NEUTRA (no finge veredicto verde).
    public static let calibrandoModulos: [Modulo] = [
        .init(id: "veredicto", kicker: "LO QUE INFORMA TU VEREDICTO",
              auroraTones: [LiquidColor.indigo, LiquidColor.rosa, LiquidColor.tinta500],
              auroraPeriod: 44,
              columnas: [
                .init(id: "sleep", label: "SUEÑO", tone: LiquidColor.indigo,
                      contenido: .sueno(horas: "7", minutos: "20", unit: "h",
                                        detail: "20:00 → 4:00"),
                      destino: .metrica("sleep"),
                      a11yLabel: "Sueño, 7 horas 20 minutos, de 20:00 a 4:00"),
                .init(id: "rhr", label: "FC REPOSO", tone: LiquidColor.rosa, alineacion: .der,
                      contenido: .simple(value: "52", unit: "lpm", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("rhr"), a11yLabel: "FC en reposo, 52 lpm, aún sin base"),
              ]),
        .init(id: "acompana", kicker: "LO QUE ACOMPAÑA",
              auroraTones: [LiquidColor.tinta500, LiquidColor.ambar, LiquidColor.azul],
              auroraPeriod: 52, auroraReverse: true,
              columnas: [
                .init(id: "carga", label: "CARGA", tone: LiquidColor.tinta500,
                      contenido: .carga(razon: nil, status: "CALIBRANDO", state: .ok,
                                        calibrando: true),
                      destino: .carga, a11yLabel: "Carga, calibrando"),
                .init(id: "vigilando", label: "VIGILANDO", tone: LiquidColor.tinta500,
                      alineacion: .der,
                      contenido: .par(v1: "—", tone1: LiquidColor.tinta500,
                                      v2: "—", tone2: LiquidColor.tinta500),
                      destino: .guardian, a11yLabel: "Vigilando, sin lectura"),
              ]),
        .init(id: "dia", kicker: "EL DÍA",
              auroraTones: [LiquidColor.ambar, LiquidColor.teal, LiquidColor.tinta500],
              auroraPeriod: 38,
              columnas: [
                .init(id: "strain", label: "ESFUERZO", tone: LiquidColor.ambar,
                      contenido: .simple(value: "10.0", unit: "", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("strain"), a11yLabel: "Esfuerzo, 10.0, aún sin base"),
                .init(id: "steps", label: "PASOS", tone: LiquidColor.teal,
                      contenido: .simple(value: "8,432", unit: "", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("steps"), a11yLabel: "Pasos, 8,432, aún sin base"),
                .init(id: "stress", label: "ESTRÉS", tone: LiquidColor.tinta500, alineacion: .der,
                      contenido: .simple(value: "1.2", unit: "/3", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("stress"), a11yLabel: "Estrés, 1.2 de 3, aún sin base"),
              ]),
        .init(id: "noche", kicker: "LA NOCHE",
              auroraTones: [LiquidColor.cian, LiquidColor.ambar, LiquidColor.azul],
              auroraPeriod: 58, auroraReverse: true,
              columnas: [
                .init(id: "hrv", label: "VFC", tone: LiquidColor.cian,
                      contenido: .simple(value: "56", unit: "ms", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("hrv"), a11yLabel: "VFC, 56 ms, aún sin base"),
                .init(id: "skintemp", label: "TEMP. PIEL", tone: LiquidColor.ambar,
                      contenido: .simple(value: "+0.1", unit: "°C", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("skintemp"),
                      a11yLabel: "Temperatura de piel, +0.1 grados, aún sin base"),
                .init(id: "resp", label: "RESP.", tone: LiquidColor.azul, alineacion: .der,
                      contenido: .simple(value: "14.5", unit: "rpm", detail: "aún sin base",
                                         mejora: false),
                      destino: .metrica("resp"), a11yLabel: "Respiración, 14.5 rpm, aún sin base"),
              ]),
    ]

    /// Módulos en ATENCIÓN: el módulo culpable (M1, sueño) recupera UNA palabra en ámbar en la
    /// cabecera — «nunca solo color» (fixture del estado ámbar).
    public static var atencionModulos: [Modulo] {
        var m = ejemploModulos
        let m1 = m[0]
        m[0] = Modulo(id: m1.id, kicker: m1.kicker, atencion: "sueño bajo",
                      auroraTones: m1.auroraTones, auroraPeriod: m1.auroraPeriod,
                      auroraReverse: m1.auroraReverse, columnas: m1.columnas)
        return m
    }
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                heroHint: model.heroHint,
                mostrarHintSeparar: mostrarHintSeparar && model.modulos.isEmpty,
                fusionInicial: fusionInicial, faseForzada: ecosistemaFase,
                compacto: !model.modulos.isEmpty,
                onTapVeredicto: onTapHero, onTapSenal: onTapSenal,
                onTapGuardian: onTapGuardian,
                onFusionArrancada: onFusionArrancada, onSeparacion: onSeparacion)
                .padding(.top, LiquidSpace.s150)
                .liquidEntrada(index: 1)

            // «El Tablero» (FER-28): los 4 módulos de vidrio sustituyen al grid de tiles +
            // las franjas de carga/guardián. La onda de apertura corre POR COLUMNA (orden de
            // lectura) con un índice global que cruza los módulos.
            ForEach(Array(indexadoModulos), id: \.modulo.id) { entry in
                moduloView(entry.modulo, index: entry.moduleIndex, colStart: entry.colStart)
                    .padding(.top, LiquidSpace.s200)
            }
        }
        .padding(.horizontal, LiquidSpace.s600)
    }

    /// Los módulos con su índice de módulo y el índice global de su primera columna (para la
    /// cascada de la onda de apertura, que es continua entre módulos).
    private var indexadoModulos: [(modulo: LiquidHoyModel.Modulo, moduleIndex: Int, colStart: Int)] {
        var out: [(LiquidHoyModel.Modulo, Int, Int)] = []
        var col = 0
        for (i, m) in model.modulos.enumerated() {
            out.append((m, i, col))
            col += m.columnas.count
        }
        return out
    }

    /// Un módulo de vidrio: cabecera-kicker (con la palabra de ámbar cuando algo sale de
    /// rango) + sus columnas separadas por capilares.
    private func moduloView(_ mod: LiquidHoyModel.Modulo, index: Int, colStart: Int) -> some View {
        LiquidModulo(index: index, auroraTones: mod.auroraTones,
                     auroraPeriod: mod.auroraPeriod, auroraReverse: mod.auroraReverse) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                cabecera(mod)
                if dynamicTypeSize >= .accessibility1 {
                    // Tallas AX: los capilares y las columnas lado a lado truncan; el módulo
                    // apila 1 dato por fila (excepción honesta, así lo hace Apple). Vuelve el
                    // scroll (lo aporta el contenedor de la app / la pantalla de referencia).
                    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                        ForEach(Array(mod.columnas.enumerated()), id: \.element.id) { j, col in
                            columnaView(col, align: .leading)
                                .liquidOnda(index: colStart + j)
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 0) {
                        ForEach(Array(mod.columnas.enumerated()), id: \.element.id) { j, col in
                            if j > 0 {
                                // Aire alrededor del capilar (mockup: margen 12 pt) para que el
                                // divisor quede centrado en el hueco y los datos no lo toquen.
                                LiquidCapilar()
                                    .padding(.horizontal, LiquidSpace.s300)
                                    .padding(.vertical, LiquidSpace.s050)
                            }
                            // Todas centradas (decisión del dueño): título centrado sobre su
                            // cifra, dato balanceado respecto a sus divisores.
                            columnaView(col, align: .center)
                                .liquidOnda(index: colStart + j)
                        }
                    }
                    // El capilar es greedy vertical (maxHeight: .infinity para igualar la
                    // columna más alta); sin esto, con columnas cortas (ACOMPAÑA) inflaba la
                    // fila. `fixedSize` la hace abrazar el alto real de las columnas.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// La cabecera del módulo: SOLO el rótulo en día bueno («silencio por defecto»); cuando un
    /// dato sale de rango, recupera UNA palabra en ámbar (nunca solo color).
    @ViewBuilder
    private func cabecera(_ mod: LiquidHoyModel.Modulo) -> some View {
        if let atencion = mod.atencion {
            HStack(spacing: LiquidSpace.s150) {
                Text(mod.kicker).liquidRegla().foregroundStyle(LiquidColor.tinta500)
                Text(atencion).liquidRegla().foregroundStyle(LiquidColor.atencionTexto)
            }
        } else {
            Text(mod.kicker).liquidRegla().foregroundStyle(LiquidColor.tinta500)
        }
    }

    /// Despacha el tap de una columna a la hoja existente de su destino (no crea hojas nuevas).
    private func tap(_ destino: LiquidHoyModel.Columna.Destino) {
        switch destino {
        case .metrica(let id): onTapMetric?(id)
        case .carga: onTapCarga?()
        case .guardian: onTapGuardian?()
        }
    }

    /// Una columna según su contenido: simple, sueño (dos-puntos tenue), carga (bullet) o par.
    @ViewBuilder
    private func columnaView(_ col: LiquidHoyModel.Columna, align: HorizontalAlignment) -> some View {
        switch col.contenido {
        case .simple(let value, let unit, let detail, let mejora):
            // El a11yLabel/a11yHint los compone el builder (con valencia + origen + hint
            // localizado); pasarlos evita perder la valencia audible en las columnas simples.
            LiquidColumna(label: col.label, value: value, unit: unit, detail: detail,
                          detailImproves: mejora, tone: col.tone, alignment: align,
                          a11yLabel: col.a11yLabel, a11yHint: col.a11yHint,
                          action: { tap(col.destino) })

        case .sueno(let horas, let minutos, let unit, let detail):
            LiquidColumnaShell(label: col.label, alignment: align, a11yLabel: col.a11yLabel,
                               a11yHint: col.a11yHint, action: { tap(col.destino) }) {
                VStack(alignment: align, spacing: LiquidSpace.s025) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(horas).font(LiquidType.valorL).foregroundStyle(col.tone)
                        Text(":").font(LiquidType.valorLSeparador)
                            .foregroundStyle(LiquidColor.tinta700)
                        Text(minutos).font(LiquidType.valorL).foregroundStyle(col.tone)
                        if !unit.isEmpty {
                            Text(" \(unit)").font(LiquidType.unidad)
                                .foregroundStyle(LiquidColor.tinta500)
                        }
                    }
                    .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
            }

        case .carga(let razon, let status, let state, let calibrando):
            LiquidColumnaShell(label: col.label, alignment: align, a11yLabel: col.a11yLabel,
                               a11yHint: col.a11yHint, action: { tap(col.destino) }) {
                LiquidCargaEscala(razon: razon, estado: state, rotulo: status,
                                  densidad: .modulo, calibrando: calibrando, eje: col.label)
                    .padding(.top, LiquidSpace.s025)
            }

        case .par(let v1, let tone1, let v2, let tone2):
            LiquidColumnaShell(label: col.label, alignment: align, a11yLabel: col.a11yLabel,
                               a11yHint: col.a11yHint, action: { tap(col.destino) }) {
                HStack(spacing: LiquidSpace.s100) {
                    Text(v1).font(LiquidType.datoMenor).foregroundStyle(tone1)
                    Text("·").font(LiquidType.datoMenor).foregroundStyle(LiquidColor.tinta500)
                    Text(v2).font(LiquidType.datoMenor).foregroundStyle(tone2)
                }
                .lineLimit(1)
            }
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
            LiquidAmbientBackground.tablero(model.ambiente)
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
                        // El motor siembra su base con 4 noches (`Baselines.minNightsSeed`); este
                        // preview prometía 7. Un preview que promete un número que la app no
                        // usa es lo que alguien acaba aprobando.
                        subtitle: "Noche 3 de 4 · tu rango se está formando"),
        carga: .calibrando(status: "CALIBRANDO"),
        metricas: LiquidHoyModel.ejemplo.metricas,
        modulos: LiquidHoyModel.calibrandoModulos,
        guardian: .init(label: "VIGILANDO", temp: "—", resp: "—", estado: .tranquilo),
        ambiente: .neutro,
        calibracion: .init(noche: 3, total: 4)))
        .frame(width: 402, height: 874)
        .environment(\.liquidMotionDisabled, true)
}
#endif
