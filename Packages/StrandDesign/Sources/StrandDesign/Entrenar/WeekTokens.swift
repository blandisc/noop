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

    @Environment(\.instrumentoTheme) private var theme

    /// - Parameters:
    ///   - days: los 7 estados, en el orden en que se muestran (L→D en es-MX).
    ///   - labels: la inicial de cada día, ya localizada por la app.
    public init(days: [EntrenarDayToken], labels: [String], action: (() -> Void)? = nil) {
        self.days = days; self.labels = labels; self.action = action
    }

    public var body: some View {
        let strip = HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                VStack(spacing: CenitMetrics.space1 + 2) {
                    token(day)
                    Text(verbatim: i < labels.count ? labels[i] : "")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if let action {
            Button(action: action) { strip }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityAddTraits(.isButton)
        } else {
            strip
        }
    }

    @ViewBuilder private func token(_ day: EntrenarDayToken) -> some View {
        let side = EntrenarMetrics.weekToken
        switch day {
        case .done(let f):
            Circle().fill(f.tint(theme)).frame(width: side, height: side)
        case .today(let isRest):
            Circle()
                .strokeBorder(theme.ink,
                              style: StrokeStyle(lineWidth: 2, dash: isRest ? [2, 2] : []))
                .frame(width: side, height: side)
        case .planned(let f):
            Circle().strokeBorder(f.tint(theme), lineWidth: 1.5).frame(width: side, height: side)
        case .rest:
            Circle()
                .strokeBorder(theme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: side, height: side)
        }
    }
}

/// La barra de estado de la sesión en vivo: volumen · series · pulso · pausa · Foco.
/// El único hue es el del pulso, y solo en su numeral.
public struct SessionStatsBar: View {
    private let volume: String
    private let sets: String
    private let pulse: String?
    private let isPaused: Bool
    private let onPause: (() -> Void)?
    private let onFocus: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(volume: String, sets: String, pulse: String? = nil, isPaused: Bool = false,
                onPause: (() -> Void)? = nil, onFocus: (() -> Void)? = nil) {
        self.volume = volume; self.sets = sets; self.pulse = pulse
        self.isPaused = isPaused; self.onPause = onPause; self.onFocus = onFocus
    }

    public var body: some View {
        HStack(spacing: CenitMetrics.gap) {
            stat(volume, unit: "kg", tone: isPaused ? theme.inkSecondary : theme.ink)
            dot
            stat(sets, unit: "sets", tone: isPaused ? theme.inkSecondary : theme.ink)
            if let pulse {
                dot
                stat(pulse, unit: "bpm", tone: isPaused ? theme.inkSecondary : theme.dataHeart)
            }
            Spacer(minLength: CenitMetrics.space2)
            if let onPause {
                control(isPaused ? "play.fill" : "pause.fill",
                        label: isPaused ? Text("Resume session") : Text("Pause session"),
                        action: onPause)
            }
            if let onFocus {
                control("scope", label: Text("Focus mode"), action: onFocus)
            }
        }
        .frame(minHeight: EntrenarMetrics.row)
    }

    private func stat(_ value: String, unit: LocalizedStringKey, tone: Color) -> some View {
        (Text(verbatim: value)
            .font(InstrumentoType.groteskNumber(17, weight: .bold, relativeTo: .body))
            .foregroundStyle(tone)
         + Text(verbatim: " ")
         + Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary))
            .accessibilityElement(children: .combine)
    }

    private var dot: some View {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            .accessibilityHidden(true)
    }

    private func control(_ symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.glyph(.lead))
                .foregroundStyle(theme.inkSecondary)
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                .background(theme.paper, in: Circle())
                .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
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
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("SessionStatsBar · estados") {
    VStack(spacing: 20) {
        SessionStatsBar(volume: "4,880", sets: "12", pulse: "128", onPause: {}, onFocus: {})
        SessionStatsBar(volume: "4,880", sets: "12", onPause: {}, onFocus: {})
        SessionStatsBar(volume: "12,480", sets: "24", pulse: "96", isPaused: true, onPause: {}, onFocus: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("Semana y barra · xxxLarge") {
    VStack(spacing: 20) {
        WeekTokens(days: [.done(.push), .rest, .done(.pull), .rest, .rest, .today(isRest: false), .planned(.legs)],
                   labels: ["L", "M", "X", "J", "V", "S", "D"], action: {})
        SessionStatsBar(volume: "4,880", sets: "12", pulse: "128", onPause: {}, onFocus: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
