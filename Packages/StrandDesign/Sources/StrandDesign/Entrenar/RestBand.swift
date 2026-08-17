import SwiftUI

// MARK: - RestBand — la banda de descanso (FER-83 · E2)
//
// El descanso NO es una tarjeta: es una banda de la Matriz, con filo arriba y filo abajo, que ocupa
// el ancho de la pantalla. Dos formas de contar, las dos honestas:
//
//   • Por pulso (con reloj): el numeral dice cuánto FALTA en latidos («te faltan 18 lpm»), el riel
//     dibuja dónde va tu pulso contra el objetivo, y la nota confiesa las dos reglas del motor: a
//     5 lpm te dice «casi», y a los 2:30 te suelta aunque no baje.
//   • Reloj fijo (sin pulso): el numeral es el tiempo («1:18 de 2:30») en tinta, sin inventar un
//     número de latidos ni un color de fisiología que no se midió.
//
// El hue del pulso (rosa) vive SOLO en el numeral y en el punto del riel; el resto es tinta.

public enum RestBandMode: Sendable, Hashable {
    /// Descanso por frecuencia cardiaca. `remainingBpm` nil = todavía sin lectura de pulso.
    case heartRate(remainingBpm: Int?, targetBpm: Int, currentBpm: Int?)
    /// Reloj fijo: transcurrido y objetivo, ya formateados.
    case clock(elapsed: String, target: String)
}

public struct RestBand: View {
    private let kicker: LocalizedStringKey
    private let mode: RestBandMode
    private let note: LocalizedStringKey?
    private let isAlmost: Bool
    private let isReady: Bool
    private let trailing: String?
    /// El pulso con el que empezó este descanso (el máximo visto). Sin él, el riel no coloca punto.
    private let startBpm: Int?
    private let onSkip: (() -> Void)?

    @Environment(\.instrumentoTheme) private var theme

    public init(kicker: LocalizedStringKey, mode: RestBandMode, trailing: String? = nil,
                note: LocalizedStringKey? = nil, isAlmost: Bool = false, isReady: Bool = false,
                startBpm: Int? = nil, onSkip: (() -> Void)? = nil) {
        self.kicker = kicker; self.mode = mode; self.trailing = trailing
        self.note = note; self.isAlmost = isAlmost; self.isReady = isReady
        self.startBpm = startBpm; self.onSkip = onSkip
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EntrenarMetrics.bandGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(kicker).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: CenitMetrics.space2)
                if let trailing {
                    Text(verbatim: trailing)
                        .font(InstrumentoType.groteskNumber(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            headline
            rail
            if let note {
                Text(note)
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onSkip {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(theme.inkSecondary)
                        .padding(.horizontal, CenitMetrics.gap)
                        .frame(height: EntrenarMetrics.secondaryButton)
                        .background(theme.paper, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                        // dibujo 36, toque 44 (HIG)
                        .frame(minHeight: EntrenarMetrics.row)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, EntrenarMetrics.bandGap)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.hairline).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// El numeral grande. Con pulso, el dato es cuánto falta EN LATIDOS; sin pulso, el tiempo.
    @ViewBuilder private var headline: some View {
        switch mode {
        case .heartRate(let remaining, _, _):
            if isReady {
                Text("Ready")
                    .font(InstrumentoType.grotesk(40, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(theme.positiveText)
            } else if isAlmost {
                // La banda de honestidad del motor (5 lpm) tiene su propia palabra, la que la nota
                // promete: sin esto, «casi» era un parámetro que nadie leía y una promesa incumplida.
                Text("Almost")
                    .font(InstrumentoType.grotesk(40, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(OKLab.darkened(theme.dataHeart, toContrast: 4.5, against: theme.paper))
            } else if let remaining {
                (Text("you need").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                 + Text(verbatim: " ")
                 + Text(verbatim: "\(remaining)")
                    .font(InstrumentoType.groteskNumber(40, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(theme.dataHeart)
                 + Text(verbatim: " ")
                 + Text("bpm more").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Waiting for your pulse")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        case .clock(let elapsed, let target):
            (Text(verbatim: elapsed)
                .font(InstrumentoType.groteskNumber(40, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(theme.ink)
             + Text(verbatim: " ")
             + Text("of \(target)").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El riel: tinta de fondo, punto de pulso en rosa y un tick para el OBJETIVO. Sin pulso el riel
    /// dibuja el avance del reloj, en tinta — nunca en el hue de una señal que no se midió.
    ///
    /// El punto se coloca contra el objetivo REAL que recibe la banda, no contra una escala
    /// inventada: el recorrido va del pulso con el que llegaste (el máximo visto en este descanso,
    /// que el caller pasa como `startBpm`) hasta el objetivo. Sin ese dato, el riel no dibuja punto:
    /// prefiere no decir nada a colocarlo en un lugar que no significa nada.
    @ViewBuilder private var rail: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                if let p = railProgress {
                    Circle()
                        .fill(isReady ? theme.positiveText : theme.dataHeart)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, w * p - 5))
                }
            }
            .overlay(alignment: .trailing) {
                // El tick del objetivo: donde el descanso se da por cumplido.
                Rectangle().fill(theme.inkTertiary).frame(width: 1, height: 10)
            }
        }
        .frame(height: 4)
    }

    /// Cuánto del camino al objetivo llevas, 0…1. `nil` = no hay con qué colocarlo.
    private var railProgress: Double? {
        switch mode {
        case .heartRate(let remaining, let target, let current):
            guard let current, let start = startBpm, start > target else {
                // Sin punto de partida no hay recorrido que dibujar; con el pulso ya en el objetivo,
                // el punto se planta al final.
                return (remaining.map { $0 <= 0 } ?? false) ? 1 : nil
            }
            let done = Double(start - current) / Double(start - target)
            return max(0, min(1, done))
        case .clock(let elapsed, let target):
            guard let e = Self.seconds(elapsed), let t = Self.seconds(target), t > 0 else { return nil }
            return max(0, min(1, Double(e) / Double(t)))
        }
    }

    /// «1:18» → 78. Devuelve nil si el texto no tiene esa forma (el componente no adivina).
    static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
        return m * 60 + s
    }
}

#if DEBUG
#Preview("RestBand · por pulso") {
    VStack(spacing: 28) {
        RestBand(kicker: "REST · SET 1 → 2",
                 mode: .heartRate(remainingBpm: 18, targetBpm: 110, currentBpm: 128),
                 trailing: "1:18",
                 note: "at 5 bpm I say «almost» · at 2:30 I let you go even if it hasn't dropped",
                 onSkip: {})
        RestBand(kicker: "REST · SET 2 → 3",
                 mode: .heartRate(remainingBpm: 4, targetBpm: 110, currentBpm: 114),
                 trailing: "1:52", isAlmost: true, onSkip: {})
        RestBand(kicker: "REST · SET 3 → 4",
                 mode: .heartRate(remainingBpm: 0, targetBpm: 110, currentBpm: 108),
                 trailing: "2:04", isReady: true, onSkip: {})
        RestBand(kicker: "REST", mode: .heartRate(remainingBpm: nil, targetBpm: 110, currentBpm: nil),
                 trailing: "0:12")
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("RestBand · reloj y xxxLarge") {
    VStack(spacing: 28) {
        RestBand(kicker: "REST · SET 1 → 2", mode: .clock(elapsed: "1:18", target: "2:30"),
                 trailing: "2:30", onSkip: {})
        RestBand(kicker: "REST · SET 1 → 2", mode: .clock(elapsed: "1:18", target: "2:30"),
                 note: "no watch: fixed clock", onSkip: {})
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
