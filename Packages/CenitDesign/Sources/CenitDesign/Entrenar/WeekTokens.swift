import SwiftUI

// MARK: - WeekTokens + SessionStatsBar (FER-83 · E2)
//
// La semana de un vistazo, y la barra de estado de la sesión en vivo.

/// El estado de un día de la semana en la tira de tokens.
public enum EntrenarDayToken: Sendable, Hashable {
    /// Sesión hecha, en el tinte de la familia que se entrenó.
    case done(EntrenarFamily)
    /// Hoy. El aro es SIEMPRE de tinta, nunca del color del veredicto: el día no se tiñe de cómo
    /// amaneciste, y si hoy toca descanso el aro va punteado.
    case today(isRest: Bool)
    /// Planeado por la semana, todavía no entrenado.
    case planned(EntrenarFamily)
    /// Descanso planeado.
    case rest
}

public struct WeekTokens: View {
    private let days: [EntrenarDayToken]
    private let labels: [String]
    private let action: (() -> Void)?

    /// - Parameters:
    ///   - days: los 7 estados, en el orden en que se muestran (L→D en es-MX).
    ///   - labels: la inicial de cada día, ya localizada por la app.
    public init(days: [EntrenarDayToken], labels: [String], action: (() -> Void)? = nil) {
        self.days = days; self.labels = labels; self.action = action
    }

    public var body: some View {
        let cells = HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: LiquidSpace.s100 + 2) {
                    token(day)
                    Text(verbatim: i < labels.count ? labels[i] : "")
                        .entrenarWeekDayLabel().foregroundStyle(LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())

        if let action {
            // Un `Button` es SIEMPRE una hoja de accesibilidad: VoiceOver no baja a sus hijos. Sin un
            // label propio en el Button, las 7 etiquetas por día (puestas abajo en la rama sin acción)
            // quedan selladas dentro de un subárbol que el botón no hereda de forma confiable. Aquí se
            // fija el label compuesto explícito — «L, entrenado, empuje. M, descanso. …» — para que la
            // tira tocable diga lo mismo que la tira estática.
            Button(action: action) { cells }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(weekLabel)
                .accessibilityAddTraits(.isButton)
        } else {
            // Sin esto la tira se leía «L M X J V S D» y el estado de cada día —el dato entero de la
            // fila— no llegaba a quien no la ve.
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: LiquidSpace.s100 + 2) {
                        token(day)
                        Text(verbatim: i < labels.count ? labels[i] : "")
                            .entrenarWeekDayLabel().foregroundStyle(LiquidColor.tinta500)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(for: day, dayName: i < labels.count ? labels[i] : ""))
                }
            }
            .frame(minHeight: EntrenarMetrics.row)
            .contentShape(Rectangle())
        }
    }

    /// La semana entera en un solo label, para el Button (VoiceOver nunca entra a sus hijos): junta
    /// las 7 etiquetas por día con un punto y espacio.
    private var weekLabel: Text {
        Array(days.enumerated()).reduce(Text(verbatim: "")) { acc, pair in
            let (i, day) = pair
            let sep = i == 0 ? Text(verbatim: "") : Text(verbatim: ". ")
            return acc + sep + label(for: day, dayName: i < labels.count ? labels[i] : "")
        }
    }

    private func label(for day: EntrenarDayToken, dayName: String) -> Text {
        let name = Text(verbatim: dayName) + Text(verbatim: ", ")
        switch day {
        case .done(let f):        return name + Text("trained") + Text(verbatim: ", ") + Text(f.label)
        case .today(let isRest):  return name + Text("today") + Text(verbatim: ", ")
                                       + (isRest ? Text("rest day") : Text("training day"))
        case .planned(let f):     return name + Text("planned") + Text(verbatim: ", ") + Text(f.label)
        case .rest:               return name + Text("rest day")
        }
    }

    @ViewBuilder private func token(_ day: EntrenarDayToken) -> some View {
        let side = EntrenarMetrics.weekToken
        switch day {
        case .done(let f):
            Circle().fill(f.tint()).frame(width: side, height: side)
        case .today(let isRest):
            Circle()
                .strokeBorder(LiquidColor.tinta900,
                              style: StrokeStyle(lineWidth: 2, dash: isRest ? [2, 2] : []))
                .frame(width: side, height: side)
        case .planned(let f):
            Circle().strokeBorder(f.tint(), lineWidth: 1.5).frame(width: side, height: side)
        case .rest:
            Circle()
                .strokeBorder(LiquidColor.tinta500, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: side, height: side)
        }
    }
}

/// La barra de estado de la sesión en vivo: volumen · series · pulso · Foco.
/// El único hue es el del pulso, y solo en su numeral.
///
/// La pausa VIVÍA aquí; con FER-133 (handoff «Sesión en vivo» v4) vuelve a la cabecera —el disco
/// ❚❚/▶ junto al reloj— y el teclado conserva su propio accesorio de pausa (misma acción,
/// `AppModel.pauseStrengthSession`/`resumeStrengthSessionFromPause`, dos caras). Esta barra ya no
/// controla nada de eso; `isPaused` se queda solo para atenuar sus propias cifras.
public struct SessionStatsBar: View {
    private let volume: String
    private let sets: String
    private let pulse: String?
    private let isPaused: Bool
    private let onFocus: (() -> Void)?

    public init(volume: String, sets: String, pulse: String? = nil, isPaused: Bool = false,
                onFocus: (() -> Void)? = nil) {
        self.volume = volume; self.sets = sets; self.pulse = pulse
        self.isPaused = isPaused; self.onFocus = onFocus
    }

    public var body: some View {
        // Con Dynamic Type grande tres numerales y dos controles de 44 no caben en una línea. En vez
        // de aplastar el dato (que es lo que el usuario subió de tamaño), la barra se parte: los
        // números arriba, los controles abajo. `ViewThatFits` elige sin medir a mano.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LiquidSpace.s300) { stats; Spacer(minLength: LiquidSpace.s200); controls }
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                HStack(spacing: LiquidSpace.s300) { stats }
                HStack(spacing: LiquidSpace.s300) { controls }
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
    }

    @ViewBuilder private var stats: some View {
        stat(volume, unit: "kg", tone: isPaused ? LiquidColor.tinta700 : LiquidColor.tinta900)
        dot
        stat(sets, unit: "sets", tone: isPaused ? LiquidColor.tinta700 : LiquidColor.tinta900)
        if let pulse {
            dot
            // El numeral son 17 pt, no 24: por debajo del piso, el hue saturado NO se puede usar
            // en texto. `rosa` da 4.24:1 sobre el papel. Va su tono de LECTURA — el mismo par
            // «hue de dato / tono de lectura» que `EntrenarFamily.reading` ya obliga en la sección.
            stat(pulse, unit: "bpm",
                 tone: isPaused ? LiquidColor.tinta700
                                : LiquidColor.contrastTuned(LiquidColor.rosa, against: EntrenarMetrics.lienzoContraste))
        }
    }

    @ViewBuilder private var controls: some View {
        if let onFocus {
            control("scope", label: Text("Focus mode"), action: onFocus)
                .accessibilityHint(Text("Opens a full-screen set logger"))
        }
    }

    private func stat(_ value: String, unit: LocalizedStringKey, tone: Color) -> some View {
        (Text(verbatim: value)
            .font(InstrumentoType.groteskNumber(17, weight: .bold, relativeTo: .body))
            .foregroundStyle(tone)
         + Text(verbatim: " ")
         + Text(unit).font(StrandFont.caption).foregroundStyle(LiquidColor.tinta500))
            .accessibilityElement(children: .combine)
    }

    private var dot: some View {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(LiquidColor.tinta500)
            .accessibilityHidden(true)
    }

    private func control(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(LiquidColor.tinta700)
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                .background(LiquidColor.papelTarjeta, in: Circle())
                .overlay(Circle().strokeBorder(LiquidColor.tinta10, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityLabel(label)
    }
}

#if DEBUG
#Preview("WeekTokens · estados") {
    VStack(spacing: 24) {
        WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest, .today(isRest: false), .planned(.legs)],
                   labels: ["L", "M", "X", "J", "V", "S", "D"], action: {})
        WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest, .today(isRest: true), .planned(.legs)],
                   labels: ["L", "M", "X", "J", "V", "S", "D"])
        WeekTokens(days: Array(repeating: .rest, count: 7),
                   labels: ["L", "M", "X", "J", "V", "S", "D"])
        WeekTokens(days: [.done(.push), .done(.pull), .done(.legs), .done(.fullBody), .done(.push), .done(.pull), .done(.legs)],
                   labels: ["L", "M", "X", "J", "V", "S", "D"])
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("SessionStatsBar · estados") {
    VStack(spacing: 20) {
        SessionStatsBar(volume: "4,880", sets: "12", pulse: "128", onFocus: {})
        SessionStatsBar(volume: "4,880", sets: "12", onFocus: {})
        SessionStatsBar(volume: "12,480", sets: "24", pulse: "96", isPaused: true, onFocus: {})
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
}

#Preview("Semana y barra · xxxLarge") {
    VStack(spacing: 20) {
        WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest, .today(isRest: false), .planned(.legs)],
                   labels: ["L", "M", "X", "J", "V", "S", "D"], action: {})
        SessionStatsBar(volume: "4,880", sets: "12", pulse: "128", onFocus: {})
    }
    .padding(24)
    .background(LiquidColor.fondoAlto)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
