import SwiftUI
import StrandDesign

// MARK: - Custom numeric keypad for the strength session (FER-716)
//
// The «Flujo Entrenar v3» handoff replaces the system keyboard with a purpose-built pad: an accessory
// bar of session actions over a 3-column keycap grid. It edits the ACTIVE cell (weight / reps) directly,
// no modal «Foco». Keycaps calque UIKit — the ONE white surface the paper language allows (`keyCap`),
// each with a hairline-thin drop. The «Siguiente» accessory is the confirmation affordance (the ink
// keyboard idiom's blue «return»), so it carries the one accent (`dataRecovery`).

struct SessionKeypad: View {
    let theme: InstrumentoTheme
    /// Label for the ± quick-step pill (metric «±2,5», imperial «±5»).
    let stepLabel: String
    /// Whether «copiar anterior» is available (there's a «last time» to copy).
    let canCopyPrevious: Bool
    /// Whether the plate-math «⛓ discos» accessory is live (F5). Placeholder-disabled until then.
    var platesEnabled: Bool = false

    let onDigit: (Character) -> Void
    let onComma: () -> Void
    let onBackspace: () -> Void
    let onNext: () -> Void
    let onCopyPrevious: () -> Void
    let onStep: () -> Void
    /// «Copiar arriba» (FER-88 · E7, co-edición quirúrgica): copia el valor de la MISMA columna de
    /// la serie ANTERIOR dentro de la MISMA prescripción — un atajo del editor de rutina, no una
    /// lectura de historial (eso es `onCopyPrevious`, que el editor mantiene apagado a propósito).
    /// `nil` oculta el accesorio por completo (mismo patrón que `onRPE`): la sesión en vivo no lo
    /// pasa, así que nunca dibuja una pastilla muerta.
    var onCopyAbove: (() -> Void)? = nil
    /// Opens the RPE picker. nil until RPE capture lands (FER-815) → the «RPE ▾» accessory is hidden, not
    /// shown disabled (no dead buttons).
    var onRPE: (() -> Void)? = nil
    var onPlates: () -> Void = {}
    /// Hides the keypad without registering anything (canvas pass 2026-07-15) — every keystroke has
    /// already committed live to the model, so dismissing loses nothing.
    var onHide: () -> Void = {}
    /// Pausa/reanuda sin cerrar el teclado (FER-86). El teclado OCUPA el sitio de la barra de estado,
    /// que es donde vive la pausa; sin este accesorio, el control desaparece justo mientras registras
    /// una serie — que es cuando te interrumpen. `nil` lo oculta, nunca lo deshabilita.
    var onPause: (() -> Void)? = nil
    /// Qué cara pone el accesorio: ❚❚ para pausar, ▶ para reanudar.
    var isPaused: Bool = false
    /// «QUEDABAN» — RIR (reps in reserve) capturado junto con la serie (FER-134, prototipo «Sesión en
    /// vivo»): 0 · 1 · 2 · 3 · 4+, índice en `Self.rirLabels`. Se guarda como RPE = 10 − RIR al
    /// palomear (mismo campo `WorkingSet.rpe` que ya usa `onRPE` — no es un dato nuevo, es otra cara
    /// del mismo). `nil` oculta la fila entera (mismo patrón que `onRPE`/`onCopyAbove`): sin un
    /// destino que la lea, la fila sería un control muerto.
    var selectedRIR: Int? = nil
    var onSelectRIR: ((Int) -> Void)? = nil

    static let rirLabels = ["0", "1", "2", "3", "4+"]

    var body: some View {
        VStack(spacing: 0) {
            if let onSelectRIR {
                rirRow(onSelectRIR)
                Rectangle().fill(theme.hairline).frame(height: 1)
            }
            accessoryBar
            Rectangle().fill(theme.hairline).frame(height: 1)
            keys
        }
        .background(theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 1) }
    }

    // MARK: QUEDABAN (RIR)

    private func rirRow(_ onSelectRIR: @escaping (Int) -> Void) -> some View {
        HStack(spacing: CenitMetrics.space2) {
            // Clave propia, distinta de «Remaining» (que IntervalTimerView ya usa para el tiempo
            // restante del temporizador de intervalos): compartir esa clave habría pisado su copy
            // es-MX con «quedaban» (revisión ronda 3, hallazgo grave).
            Text("Reps left kicker").entrenarKeypadKicker().textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            // `footnote` (11pt/`.caption2`) es el token existente más cercano al 11.5 SF del handoff —
            // `.caption` (12pt) quedaba un escalón grande de más (revisión ronda 2, hallazgo menor).
            Text("at check-off").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer(minLength: CenitMetrics.space2)
            // Un solo gesto sobre TODA la píldora, no cinco `Button`s vecinos con `contentShape`
            // agrandado: cinco blancos de 44pt apretados en 30pt de dibujo se traslapan entre sí
            // (revisión ronda 3, hallazgo menor — un toque cerca del filo visual podía registrar el
            // RIR del vecino). Un solo reconocedor que reparte la posición del toque en cinco tercios
            // iguales no tiene esa ambigüedad: cada toque cae en exactamente una franja.
            GeometryReader { geo in
                let slice = geo.size.width / CGFloat(Self.rirLabels.count)
                HStack(spacing: 0) {
                    ForEach(Array(Self.rirLabels.enumerated()), id: \.offset) { idx, label in
                        let selected = selectedRIR == idx
                        Text(label).font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(selected ? theme.paper : theme.inkSecondary)
                            .frame(width: EntrenarMetrics.rirButton, height: EntrenarMetrics.rirButton)
                            .background(selected ? theme.ink : Color.clear)
                            .frame(maxWidth: .infinity)
                            // Elemento propio para VoiceOver (revisión ronda 3): el gesto de posición
                            // que reparte el toque en tercios es para dedos que VEN el filo; VoiceOver
                            // navega elemento por elemento y activa por acción, nunca por coordenada,
                            // así que cada franja lleva su propio elemento + acción `onSelectRIR(idx)`
                            // directa, sin pasar por la matemática de posición.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Reps in reserve: \(label)"))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityAction { onSelectRIR(idx) }
                        if idx < Self.rirLabels.count - 1 {
                            Rectangle().fill(theme.hairlineStrong)
                                .frame(width: EntrenarMetrics.rirHairline, height: EntrenarMetrics.rirDivider)
                        }
                    }
                }
                // El contenido visible (30pt) se centra dentro del `GeometryReader`, que ahora mide el
                // mínimo de toque completo (44pt) — así el `contentShape`/`gesture` de abajo cubre el
                // área táctil REAL, no solo el dibujo (revisión ronda 4, hallazgo grave: el padding
                // exterior agrandaba la píldora visualmente pero nunca movía al gesto, que seguía
                // midiendo 30pt).
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    // `DragGesture(minimumDistance: 0)` en vez de `onTapGesture`: es la única forma en
                    // SwiftUI de leer la posición X del toque para repartirla en tercios iguales.
                    DragGesture(minimumDistance: 0).onEnded { value in
                        let idx = slice > 0 ? Int((value.location.x / slice).rounded(.down)) : 0
                        onSelectRIR(min(max(idx, 0), Self.rirLabels.count - 1))
                    }
                )
            }
            .frame(height: CenitMetrics.touchTarget)
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: EntrenarMetrics.rirHairline))
            .clipShape(Capsule())
        }
        .padding(.horizontal, CenitMetrics.cardPadding).padding(.vertical, CenitMetrics.space2)
    }

    // MARK: Accessory bar

    private var accessoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Hide-keyboard at the far LEFT (mirror of «Next»), subordinated ink — never reads as
                // «register». VoiceOver: «Hide keyboard», not «Done»/«Close».
                Button(action: onHide) {
                    Image(systemName: "chevron.down")
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(theme.inkSecondary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide keyboard"))
                if let onPause {
                    Button(action: onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPaused ? Text("Resume session") : Text("Pause session"))
                }
                pill(String(localized: "copy last"), enabled: canCopyPrevious, action: onCopyPrevious)
                if let onCopyAbove {
                    pill(String(localized: "copy above"), action: onCopyAbove)
                }
                pill(stepLabel, action: onStep)
                // FER-815: each accessory appears only when its function exists — never a permanent
                // disabled placeholder. RPE shows once a handler is wired; plates once the math is on.
                if let onRPE { pill("RPE ▾", action: onRPE) }
                // r16: fuera el glifo «⛓» (tofu en Grotesk) — la pastilla queda en el puro «discos».
                if platesEnabled { pill(String(localized: "plates"), action: onPlates) }
                Spacer(minLength: 4)
                Button(action: onNext) {
                    Text("Next").font(StrandFont.subhead).fontWeight(.semibold)
                        .foregroundStyle(theme.dataRecovery)
                        .padding(.horizontal, 12).frame(height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Next field"))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func pill(_ text: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(text).font(StrandFont.caption)
                .foregroundStyle(enabled ? theme.ink : theme.inkMuted)
                .padding(.horizontal, 11).frame(height: 34)
                .background(Capsule().fill(Color.clear))
                .overlay(Capsule().strokeBorder(enabled ? theme.hairlineStrong : theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Keys

    private var keys: some View {
        VStack(spacing: 6) {
            ForEach(keyRows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 22)   // bottom respects the home indicator
    }

    private var keyRows: [[String]] {
        [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [",", "0", "⌫"]]
    }

    @ViewBuilder private func keyButton(_ key: String) -> some View {
        switch key {
        case ",":
            flatKey(",") { onComma() }
        case "⌫":
            flatKey("⌫", size: 17) { onBackspace() }
        default:
            Button { if let c = key.first { onDigit(c) } } label: {
                Text(key)
                    .font(.system(size: 20)).foregroundStyle(theme.ink) // token-exempt: numeral de tecla del keypad
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.keyCap)) // token-exempt: geometría de dato
                    .shadow(color: theme.ink.opacity(0.08), radius: 0, x: 0, y: 1) // token-exempt: sombra sutil <0.10
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(key))
        }
    }

    private func flatKey(_ glyph: String, size: CGFloat = 20, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: size)).foregroundStyle(theme.inkSecondary) // token-exempt: tamaño de tecla derivado (parámetro)
                .frame(maxWidth: .infinity).frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(glyph == "⌫" ? "Delete" : glyph))
    }
}

#if DEBUG
#Preview("SessionKeypad") {
    let t = InstrumentoTheme.base
    return VStack {
        Spacer()
        SessionKeypad(theme: t, stepLabel: "±2,5", canCopyPrevious: true,
                      onDigit: { _ in }, onComma: {}, onBackspace: {}, onNext: {},
                      onCopyPrevious: {}, onStep: {})
    }
    .background(t.paper)
    .preferredColorScheme(.light)
}
#endif
