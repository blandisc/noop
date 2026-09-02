import SwiftUI

// MARK: - RestBand — la banda de descanso (FER-83 · E2 · FER-167)
//
// El descanso NO es una tarjeta: es una banda de la Matriz, con filo arriba y filo abajo, que ocupa
// el ancho de la pantalla. Dos formas de contar, las dos honestas:
//
//   • Por pulso (con reloj): el headline dice LA META («descanso · baja a 108»), el numeral es el
//     pulso vivo («112 ♥ ahora · va bajando»), el riel dibuja la caída contra el objetivo, y a
//     ≤ 5 lpm aparece la cápsula «CASI»; a los 3:00 el motor te suelta aunque no baje — honesto
//     (`isCeilingRelease`, FER-167 ronda 2 · R13): no dice «Listo» en verde si el pulso sigue
//     arriba, dice el tope tal cual y ofrece SEGUIR.
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

/// El riel del descanso por pulso: la caída de tu corazón hacia el umbral, con la marca del
/// objetivo al final. Vivía dibujado a mano dentro de la sesión (`LiveStrengthSheet.restHRTrack`),
/// que es justo donde no puede estar: el mismo descanso aparece en la sesión en línea, en el
/// descanso a pantalla completa y —E15— en el reloj.
///
/// La geometría es una función pura y aparte (`fraccion`) para que se pueda probar sin pintar nada:
/// es la única parte que puede estar mal de una forma que el ojo no cacha.
struct RestPulseRail: View {

    private let bpm: Int
    private let target: Int?

    @Environment(\.instrumentoTheme) private var theme

    init(bpm: Int, target: Int?) { self.bpm = bpm; self.target = target }

    /// Cuánto se ha recorrido del pico nominal (objetivo + 40) hasta el objetivo. 0 = recién
    /// terminada la serie; 1 = listo. Satura en los dos extremos: un pulso por debajo del objetivo
    /// no llena de más, y uno por encima del pico no devuelve negativo.
    ///
    /// SIN OBJETIVO devuelve 0, no 1. La versión que vivía en la sesión hacía `(target ?? bpm)` en
    /// las dos puntas, o sea 40/40, y pintaba el riel LLENO — que en este instrumento se lee como
    /// «ya estás listo». Sin umbral no hay contra qué compararte, y un riel lleno sin evidencia es
    /// justo la mentira que esta app persigue. Vacío dice lo que de verdad sabemos: nada todavía.
    /// La prueba lo ancla.
    public static func fraccion(bpm: Int, target: Int?) -> Double {
        guard let target else { return 0 }
        let hi = Double(target + 40), lo = Double(target)
        guard hi > lo else { return 1 }
        return max(0, min(1, (hi - Double(bpm)) / (hi - lo)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule()
                    .fill(LinearGradient(colors: [theme.dataHeart, theme.dataRecovery],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * Self.fraccion(bpm: bpm, target: target))
                // La marca del umbral: tinta, no hue — es geometría, no dato (§ADN: el marcador
                // de referencia nunca compite con la señal).
                Rectangle().fill(theme.ink)
                    .frame(width: 2, height: EntrenarMetrics.loadRail + 8)
                    .offset(x: w - 1)
            }
        }
        .frame(height: EntrenarMetrics.loadRail)
        .accessibilityHidden(true)   // el número y su texto ya lo dicen
    }
}

public struct RestBand<Next: View>: View {
    private let kicker: LocalizedStringKey
    private let mode: RestBandMode
    private let note: LocalizedStringKey?
    private let isAlmost: Bool
    private let isReady: Bool
    /// FER-167 ronda 2 (R13, mapa B4): el tope de 3:00 soltó el descanso SIN que el pulso llegara a
    /// la meta (`RestReadyReason.ceiling` con `bpmToReady > 0`). La banda NUNCA dice «Listo» verde en
    /// ese caso — dice el tope tal cual, honesto, y su tecla se vuelve «Continuar ›» en vez de
    /// «Saltar». `false` por defecto: cero cambio de piel para cualquier caller que no lo pase.
    private let isCeilingRelease: Bool
    private let trailing: String?
    /// El pulso con el que empezó este descanso (el máximo visto). Sin él, el riel no coloca punto.
    private let startBpm: Int?
    private let onSkip: (() -> Void)?
    /// «SIGUE» — el próximo ejercicio, thumb 24 + texto (handoff «Sesión en vivo» §6). `EmptyView`
    /// (el `Next` por defecto) cuando el llamador no tiene un siguiente que mostrar — la banda no
    /// reserva espacio para nada, como con `note`/`onSkip`.
    private let next: Next
    /// La variante GRANDE, centrada, que pide DESCANSO en Foco a pantalla completa (FER-135, V6,
    /// revisión ronda 1, hallazgo grave: el prototipo `foco.txt` dibuja un numeral de 52 pt
    /// centrado y un «Saltar» de 46 pt — no los 40 pt/alineado a la izquierda/36 pt de la banda en
    /// línea). `false` por defecto conserva el pixel de siempre en la lista en línea y el reloj — la
    /// lógica del descanso (`RestReadinessRule`) no cambia con esto, solo la piel.
    private let large: Bool

    @Environment(\.instrumentoTheme) private var theme

    public init(kicker: LocalizedStringKey, mode: RestBandMode, trailing: String? = nil,
                note: LocalizedStringKey? = nil, isAlmost: Bool = false, isReady: Bool = false,
                isCeilingRelease: Bool = false,
                startBpm: Int? = nil, large: Bool = false, onSkip: (() -> Void)? = nil,
                @ViewBuilder next: () -> Next = { EmptyView() }) {
        self.kicker = kicker; self.mode = mode; self.trailing = trailing
        self.note = note; self.isAlmost = isAlmost; self.isReady = isReady
        self.isCeilingRelease = isCeilingRelease
        self.startBpm = startBpm; self.large = large; self.onSkip = onSkip; self.next = next()
    }

    public var body: some View {
        VStack(alignment: large ? .center : .leading, spacing: EntrenarMetrics.bandGap) {
            // Ronda 2 revisión final, hallazgo grave (g4-a11y): `.combine` vivía en la VStack completa,
            // fundiendo el botón «Skip» (un hermano real, no contenido de texto) en un solo elemento
            // estático sin acción — VoiceOver perdía el control. Solo el bloque de texto se combina;
            // el botón queda fuera, alcanzable con su propio trait.
            Group {
                // Ronda 4, hallazgo grave: `trailing` (el reloj transcurrido) solo pertenece a la banda
                // en línea, donde comparte la fila con el kicker. La pantalla completa de DESCANSO en
                // Foco ya dice el mismo dato dentro del numeral grande — repetirlo a la derecha rompe la
                // simetría centrada que pide el prototipo y estira un `Spacer` sin ancla en una fila a
                // todo lo ancho de la pantalla.
                if large {
                    Text(kicker).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kicker).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: CenitMetrics.space2)
                        if let trailing {
                            Text(verbatim: trailing)
                                .font(InstrumentoType.groteskNumber(13, weight: .bold, relativeTo: .caption))
                                .foregroundStyle(theme.inkSecondary)
                                .numeroVivo(value: trailing)
                        }
                    }
                }
                headline
                rail
                // El riel solo aparece con el descanso por pulso Y con lectura: sin pulso no hay caída
                // que dibujar, y un riel vacío sería un instrumento que finge medir.
                if case let .heartRate(_, objetivo, actual) = mode, let actual {
                    RestPulseRail(bpm: actual, target: objetivo)
                        .padding(.top, 2)
                }
                if let note {
                    Text(note)
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .multilineTextAlignment(large ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                next
            }
            .accessibilityElement(children: .combine)
            if let onSkip {
                Button(action: onSkip) {
                    // R13: el tope honesto ofrece SEGUIR (no «Saltar» — no hay nada que saltar,
                    // el motor ya soltó el descanso solo).
                    Text(isCeilingRelease ? "Continue" : "Skip rest")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(theme.inkSecondary)
                        .padding(.horizontal, CenitMetrics.gap)
                        .frame(height: large ? EntrenarMetrics.focusRestSkip : EntrenarMetrics.secondaryButton)
                        .background(theme.paper, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                        // dibujo 36 (46 en Foco), toque 44 (HIG)
                        .frame(minHeight: EntrenarMetrics.row)
                        .contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
        .padding(.vertical, EntrenarMetrics.bandGap)
        // Revisión ronda 3, hallazgo grave: los filetes arriba/abajo son gramática de LISTA — separan
        // esta banda de la fila vecina cuando vive en línea. La variante GRANDE de Foco no tiene
        // ninguna fila alrededor (es pantalla completa, sobre papel en blanco); ahí el prototipo no
        // dibuja ningún borde. `!large` evita dos reglas huérfanas flotando solas en Foco.
        .overlay(alignment: .top) { if !large { Rectangle().fill(theme.hairline).frame(height: 1) } }
        .overlay(alignment: .bottom) { if !large { Rectangle().fill(theme.hairline).frame(height: 1) } }
    }

    /// El tamaño del numeral: 40 pt en la lista en línea, 52 pt (`focusRestValue`) en la variante
    /// GRANDE de Foco (revisión ronda 1, hallazgo grave).
    private var headlineSize: CGFloat { large ? EntrenarMetrics.focusRestValue : 40 }

    /// Banda de honestidad del motor: a ≤ N lpm de la meta se pinta la cápsula «CASI».
    /// Misma cifra que documenta el encabezado del archivo y `RestReadinessRule.defaultBandBPM`;
    /// StrandDesign no importa Analytics, así que vive aquí como constante nombrada.
    private static var almostBandBPM: Int { 5 }

    /// El numeral grande. Con pulso: meta («rest · down to N») + pulso vivo; sin pulso, el tiempo.
    @ViewBuilder private var headline: some View {
        switch mode {
        case .heartRate(let remaining, let target, let current):
            if isCeilingRelease {
                // R13 (mapa B4): el tope de 3:00 sin recuperación honesta — nunca «Listo» verde.
                VStack(alignment: large ? .center : .leading, spacing: CenitMetrics.space1) {
                    Text(verbatim: "3:00")
                        .font(InstrumentoType.groteskNumber(headlineSize, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(theme.ink)
                    if let remaining, remaining > 0 {
                        Text("still \(remaining) bpm up · not on you")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                }
                .multilineTextAlignment(large ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            } else if isReady {
                Text("Ready")
                    .font(InstrumentoType.grotesk(headlineSize, weight: .bold, relativeTo: .largeTitle))
                    .foregroundStyle(theme.positiveText)
            } else if let current {
                // FER-167: la meta + el pulso vivo (mock P4). «te faltan N bpm» muere en iPhone.
                VStack(alignment: large ? .center : .leading, spacing: CenitMetrics.space1) {
                    HStack(spacing: CenitMetrics.space2) {
                        Text("rest · down to \(target)")
                            .instrumentoOverline()
                            .foregroundStyle(theme.inkTertiary)
                        if showsAlmostCapsule(remaining: remaining) {
                            // Cápsula «CASI»: reusa `isAlmost` del caller y/o remaining ≤ almostBandBPM.
                            Text("Almost")
                                .font(StrandFont.caption.weight(.semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(theme.inkSecondary)
                                .padding(.horizontal, CenitMetrics.space2)
                                .padding(.vertical, CenitMetrics.space1)
                                .background(theme.paper, in: Capsule())
                                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                        }
                    }
                    (Text(verbatim: "\(current)")
                        .font(InstrumentoType.groteskNumber(headlineSize, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(theme.dataHeart)
                     + Text(verbatim: " ")
                     + Text("♥ now · dropping")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary))
                        .multilineTextAlignment(large ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // El BPM que más cambia de todo Entrenar (FER-222) — el dato vivo por
                        // excelencia del descanso.
                        .numeroVivo(value: current)
                }
            } else {
                // Sin Watch / sin lectura: no inventar un numeral de pulso.
                Text("Waiting for your pulse")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        case .clock(let elapsed, let target):
            (Text(verbatim: elapsed)
                .font(InstrumentoType.groteskNumber(headlineSize, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(theme.ink)
             + Text(verbatim: " ")
             + Text("of \(target)").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary))
                .multilineTextAlignment(large ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .numeroVivo(value: elapsed)
        }
    }

    /// «CASI» cuando el caller ya marcó `isAlmost`, o cuando `remainingBpm` cae en la banda.
    private func showsAlmostCapsule(remaining: Int?) -> Bool {
        if isAlmost { return true }
        guard let remaining else { return false }
        return remaining <= Self.almostBandBPM
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
        // Lejos de la meta: meta + pulso vivo, sin cápsula.
        RestBand(kicker: "REST · SET 1 → 2",
                 mode: .heartRate(remainingBpm: 18, targetBpm: 108, currentBpm: 126),
                 trailing: "1:18",
                 note: "at 5 bpm I say «almost» · at 3:00 I let you go even if it hasn't dropped",
                 onSkip: {})
        // CASI: remaining ≤ almostBandBPM → cápsula junto a la meta.
        RestBand(kicker: "REST · SET 2 → 3",
                 mode: .heartRate(remainingBpm: 4, targetBpm: 108, currentBpm: 112),
                 trailing: "1:52", isAlmost: true, onSkip: {})
        // R13: el tope de 3:00 soltó SIN recuperación honesta — nunca «Listo» verde.
        RestBand(kicker: "REST · SET 3 → 4",
                 mode: .heartRate(remainingBpm: 12, targetBpm: 108, currentBpm: 120),
                 trailing: "3:00", isCeilingRelease: true, onSkip: {})
        // Sin Watch: no se inventa un numeral de pulso.
        RestBand(kicker: "REST", mode: .heartRate(remainingBpm: nil, targetBpm: 108, currentBpm: nil),
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
