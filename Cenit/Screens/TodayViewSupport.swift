import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import WhoopStore
import Foundation

/// Publica el offset vertical del tope del contenido de Hoy para el pull-to-refresh propio (FER-222).
/// En el tope vale 0; al jalar hacia abajo (overscroll) crece > 0; con scroll normal es < 0. Solo se
/// conserva el último valor (un único productor), así que `reduce` toma el más reciente.
struct TodayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// El alto NATURAL de cada página del pager de «Hoy», por índice (FER-725). Deja que el pager mida su
/// alto según la página ACTIVA en vez de la más alta: así Señales (más corta) no arrastra el alto de
/// Brief y el scroll vertical solo aparece en Brief. `reduce` coalesce con el máximo por si un mismo
/// índice reporta dos veces en un frame de transición.
struct TodayPageHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { Swift.max($0, $1) })
    }
}

/// FER-878: la tarjeta «Qué medimos» que abre la ⓘ junto a «POR QUÉ N». Saca de la pantalla el caption
/// explicativo (ya no flota bajo las cinco reglas) y lo deja aquí, en la misma superficie radio-12 que las
/// tarjetas de Tendencias: la suma encendida ES el numeral, el largo de cada marca es su peso, y por qué
/// la VFC pesa más. El tema se pasa explícito (no se propaga por `.sheet`).
struct WhatWeMeasureSheet: View {
    let score: Int
    var theme: InstrumentoTheme = .base
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("What we measure")
                    .font(StrandFont.title2)
                    .foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    Text("The five marks below add up to your recovery of \(score).")
                    Text("The longer a mark, the more that signal weighed today.")
                    Text("HRV (how your heart's timing varied overnight) carries the most weight, because it's the earliest sign of how recovered you are.")
                }
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(CenitMetrics.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .instrumentoCard(.control, theme: theme)   // superficie + hairline, radio 12 (como Tendencias)
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: SheetContentHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium])
        .presentationDragIndicator(.visible)
    }
}


extension TodayView {

    /// La hora reloj actual (0…24) para el punto «ahora» del sello.
    var clockHourNow: Double {
        #if DEBUG
        // FER-924: en modo fixture el «ahora» del sello se congela a las 9:41 — su POSICIÓN depende del
        // reloj real (no es animación, así que Reduce Motion no lo cubre); congelarlo hace que dos
        // capturas del mismo estado salgan idénticas (gate de diff / regresión visual del canvas).
        if ScreenshotFixtures.activeState() != nil { return 9.0 + 41.0 / 60.0 }
        #endif
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    /// Tiempo relativo en unidades de UNA letra: «hace 30 s / 5 m / 2 h / 3 d».
    static func compactAgo(_ secondsAgo: Double) -> String {
        let s = Int(secondsAgo.rounded())
        let core: String
        if s < 60 { core = "\(s) s" }
        else if s < 3600 { core = "\(s / 60) m" }
        else if s < 86_400 { core = "\(s / 3600) h" }
        else { core = "\(s / 86_400) d" }
        return String(localized: "\(core) ago")
    }

    /// SF Symbol del nivel de batería. Al CARGAR devuelve `battery.100.bolt` — el ÚNICO glifo
    /// batería-con-rayo que SF Symbols realmente trae. Las variantes parciales (`battery.75/.50/.25.bolt`)
    /// NO existen, y `Image(systemName:)` no dibuja NADA con un nombre desconocido → por eso el ícono
    /// desaparecía al cargar por debajo de 75%. El rayo comunica «cargando»; el nivel exacto lo lleva el
    /// «%» de al lado.
    func batteryIcon(pct: Double, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch pct {
        case 75...:   return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default:      return "battery.25"
        }
    }

    /// Umbral de batería crítica del strap (%): la MISMA zona roja que `theme.batteryColor(forLevel:)`
    /// (`≤10 %` → `critical`), para que el banner y el color del icono no discrepen. En esta zona la
    /// noche corre peligro de perderse.
    static let criticalBatteryPct: Double = 10

    /// ¿Horario diurno (8–22)? Puro reloj: no gritamos «banda desconectada» mientras duermes.
    var isDaytime: Bool { clockHourNow >= 8 && clockHourNow < 22 }

    /// El glifo del ajuste de ritmo (flecha diagonal arriba/abajo; horizontal en «mantén»).
    func paceGlyph(_ pace: DailyBrief.TrainingBlock.Pace?) -> String {
        switch pace {
        case .up:   return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .hold, .none: return "arrow.right"
        }
    }

    /// SF Symbol por tema de viñeta (la presentación vive en la app, no en el motor puro).
    func briefGlyph(_ kind: DailyBrief.BulletKind) -> String {
        switch kind {
        case .sleep:    return "moon.fill"
        case .recovery: return "arrow.up"
        case .hrv:      return "waveform.path.ecg"
        case .rhr:      return "bed.double.fill"
        case .respRate: return "lungs.fill"
        case .skinTemp: return "thermometer.medium"
        case .acwr:     return "bolt.fill"
        }
    }

    /// El canalón entre Señales y Brief (FER-725): el hueco de papel que se ve al deslizar, para que las
    /// hojas no se lean pegadas. Solo visible en la transición (en reposo la hoja activa llena la pantalla).
    var pagerGutter: CGFloat { CenitMetrics.screenPadding + CenitMetrics.space2 }   // 32

    /// El label es-MX por nivel, derivado del `level` (no del `headline` de la página 1, que F3 va a
    /// cambiar). Reusa las MISMAS claves del catálogo que `ReadinessEngine` (`Primed`/`Balanced`/…), así
    /// que «A punto / Equilibrado / Exigido / Desgastado» ya están traducidas. `insufficient` no tiene
    /// palabra (el encabezado se queda solo con el overline).
    func stateLabel(_ level: ReadinessEngine.Level) -> LocalizedStringKey {
        switch level {
        case .primed:       return "Primed"
        case .balanced:     return "Balanced"
        case .strained:     return "Strained"
        case .rundown:      return "Run down"
        case .insufficient: return "Readiness"
        }
    }

    /// Sueño en formato reloj del handoff: «7:12» (horas:minutos dormidos).
    func sleepClockText(_ mins: Double) -> String {
        String(format: "%d:%02d", Int(mins) / 60, Int(mins) % 60)
    }

    /// Los ≤7 valores válidos más recientes de una métrica sobre los días de base: su ventana de media.
    func history(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [Double] {
        Array(days.compactMap(pick).suffix(7))
    }

    /// Δ de sueño en unidades de una letra: «18m» bajo una hora, «1h 5m» a partir de una (FER-575 follow-up:
    /// «18 min» era más ancho que «+27» y el `minimumScaleFactor` encogía solo el delta de sueño).
    func sleepDeltaText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// Thousands-grouped integer string (steps / calories).
    func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }
}
