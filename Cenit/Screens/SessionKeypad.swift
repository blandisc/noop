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
    /// Magnitud del paso rápido, con el signo `±` (métrico «±2,5», imperial «±5», reps «±1») — la
    /// rejilla la parte en las dos teclas «+…»/«−…» (FER-134 ítem 8; antes era el texto de una sola
    /// píldora que solo sumaba).
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
    /// Sube el valor de la celda activa un paso (tecla «+…» de la rejilla).
    let onStep: () -> Void
    /// Baja el valor de la celda activa un paso (tecla «−…» de la rejilla). Mismo paso que `onStep`,
    /// dirección opuesta — antes el teclado solo subía (FER-134 ítem 8: la rejilla del handoff trae
    /// las dos direcciones como teclas propias, ya no una sola píldora que solo sumaba).
    var onStepDown: () -> Void = {}
    /// Habilita la tecla «−…»: se atenúa (no desaparece) donde no hay una dirección de baja real —
    /// el editor de rutina, por ejemplo, prescribe (solo sube), no registra en vivo (FER-134 ítem 8).
    var stepDownEnabled: Bool = true
    /// «Copiar arriba» (FER-88 · E7, co-edición quirúrgica): copia el valor de la MISMA columna de
    /// la serie ANTERIOR dentro de la MISMA prescripción — un atajo del editor de rutina, no una
    /// lectura de historial (eso es `onCopyPrevious`, que el editor mantiene apagado a propósito).
    /// `nil` oculta el accesorio por completo: la sesión en vivo no lo pasa, así que nunca dibuja una
    /// pastilla muerta.
    var onCopyAbove: (() -> Void)? = nil
    var onPlates: () -> Void = {}
    /// Palomea (o desmarca) la serie de la celda activa — la MISMA acción que el ✓ de `SetTable`
    /// (FER-134 ítem 8: la rejilla absorbe la confirmación como su propia tecla «✓ Serie», no un
    /// accesorio aparte). La sesión en vivo pasa aquí `confirmOrToggleSet(ei:si:)`.
    var onConfirmSet: () -> Void = {}
    /// Habilita «✓ Serie»: se atenúa (no desaparece) donde no hay una serie que palomear — el editor
    /// de rutina prescribe, no registra (mismo motivo que `stepDownEnabled`).
    var confirmSetEnabled: Bool = true
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
    /// palomear (mismo campo `WorkingSet.rpe`). `nil` oculta la fila entera (mismo patrón que
    /// `onCopyAbove`): sin un destino que la lea, la fila sería un control muerto.
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
    //
    // FER-134 ítem 8: la rejilla de abajo absorbe el paso (`stepLabel`), «RPE ▾» (lo lee el segmento
    // QUEDABAN) y «discos» (ahora tecla propia) — esta fila se queda solo con lo que la rejilla NO
    // dibuja: ocultar, pausa, copiar (anterior/arriba) y «Siguiente».

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
                        // Revisión final (FER-140), hallazgo grave: el dibujo se queda en 34pt (el
                        // handoff), pero el toque se extiende al mínimo HIG de 44pt.
                        .contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Hide keyboard"))
                if let onPause {
                    Button(action: onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle().inset(by: -5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPaused ? Text("Resume session") : Text("Pause session"))
                }
                pill(String(localized: "copy last"), enabled: canCopyPrevious, action: onCopyPrevious)
                if let onCopyAbove {
                    pill(String(localized: "copy above"), action: onCopyAbove)
                }
                Spacer(minLength: 4)
                Button(action: onNext) {
                    Text("Next").font(StrandFont.subhead).fontWeight(.semibold)
                        .foregroundStyle(theme.dataRecovery)
                        .padding(.horizontal, 12).frame(height: 34)
                        // Revisión final (FER-140), hallazgo menor: 34pt de alto queda bajo el mínimo
                        // HIG en el eje vertical; se extiende el toque sin tocar el dibujo.
                        .contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Next field"))
            }
            .padding(.horizontal, CenitMetrics.cardPadding).padding(.vertical, CenitMetrics.space2)
        }
    }

    private func pill(_ text: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(text).font(StrandFont.caption)
                .foregroundStyle(enabled ? theme.ink : theme.inkMuted)
                .padding(.horizontal, 11).frame(height: 34)
                .background(Capsule().fill(Color.clear))
                .overlay(Capsule().strokeBorder(enabled ? theme.hairlineStrong : theme.hairline, lineWidth: 1))
                .contentShape(Rectangle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Keys — rejilla 4×4 (FER-134 ítem 8, handoff «Sesión en vivo» bloque teclado)
    //
    // Fila 1: 1 · 2 · 3 · discos — Fila 2: 4 · 5 · 6 · +paso — Fila 3: 7 · 8 · 9 · −paso —
    // Fila 4: , · 0 · ⌫ · ✓ Serie. Las cuatro teclas de la columna derecha son ACCIÓN (fondo tinta,
    // texto papel); las doce numéricas son DATO (fondo `keyCap`, texto tinta) — el mismo contraste
    // que ya distinguía «Siguiente» del resto, ahora dentro de la rejilla en vez de en la barra.

    /// Una tecla de la rejilla: numérica (dato) o de acción (comando).
    private enum Key: Hashable { case digit(Character), comma, backspace, plates, stepUp, stepDown, confirmSet }

    private var keys: some View {
        VStack(spacing: EntrenarMetrics.keyGap) {
            ForEach(keyRows, id: \.self) { row in
                HStack(spacing: EntrenarMetrics.keyGap) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        // Mismo inset que la fila QUEDABAN y la barra de accesorios: en el prototipo las tres viven
        // en el mismo contenedor (10 16 18), así que el borde de «1 · 4 · 7 · ,» se alinea con ellas.
        .padding(.horizontal, CenitMetrics.cardPadding).padding(.top, CenitMetrics.space2).padding(.bottom, 22)   // bottom respects the home indicator
    }

    private var keyRows: [[Key]] {
        [
            [.digit("1"), .digit("2"), .digit("3"), .plates],
            [.digit("4"), .digit("5"), .digit("6"), .stepUp],
            [.digit("7"), .digit("8"), .digit("9"), .stepDown],
            [.comma, .digit("0"), .backspace, .confirmSet]
        ]
    }

    /// La magnitud desnuda de `stepLabel` (quita el `±`) para rotular «+…»/«−…» — reps «±1» da
    /// «+1»/«−1», kg «±2,5» da «+2,5»/«−2,5», libras «±5» da «+5»/«−5».
    private var stepMagnitude: String { stepLabel.hasPrefix("±") ? String(stepLabel.dropFirst()) : stepLabel }

    @ViewBuilder private func keyButton(_ key: Key) -> some View {
        switch key {
        case .comma:
            digitKey(",") { onComma() }
        case .backspace:
            digitKey("⌫", size: 17, accessibilityLabel: Text("Delete")) { onBackspace() }
        case .digit(let c):
            digitKey(String(c)) { onDigit(c) }
        case .plates:
            actionKey(String(localized: "plates"), enabled: platesEnabled,
                      accessibilityLabel: Text("plates"), action: onPlates)
        case .stepUp:
            actionKey("+\(stepMagnitude)", accessibilityLabel: Text("Increase by \(stepMagnitude)"), action: onStep)
        case .stepDown:
            actionKey("−\(stepMagnitude)", enabled: stepDownEnabled,
                      accessibilityLabel: Text("Decrease by \(stepMagnitude)"), action: onStepDown)
        case .confirmSet:
            actionKey(String(localized: "✓ Serie"), enabled: confirmSetEnabled,
                      accessibilityLabel: Text("Mark set as done"), action: onConfirmSet)
        }
    }

    /// Tecla DATO — el keycap blanco calcado de UIKit (`keyCap`), numerales o glifos de edición.
    private func digitKey(_ glyph: String, size: CGFloat = 20, accessibilityLabel: Text? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: size)).foregroundStyle(theme.ink) // token-exempt: numeral de tecla del keypad
                .frame(maxWidth: .infinity).frame(height: EntrenarMetrics.keyCap)
                .background(RoundedRectangle(cornerRadius: EntrenarMetrics.keyRadius, style: .continuous).fill(theme.keyCap))
                .shadow(color: theme.ink.opacity(0.08), radius: 0, x: 0, y: 1) // token-exempt: sombra sutil <0.10
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? Text(glyph))
    }

    /// Tecla ACCIÓN — fondo tinta (`theme.ink`, NO un hue: es tinta900), texto papel, glifo/etiqueta
    /// 13/600. Se atenúa (no desaparece) cuando `enabled` es falso para que la rejilla no salte.
    private func actionKey(_ label: String, enabled: Bool = true, accessibilityLabel: Text,
                            action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(label)
                .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity).frame(height: EntrenarMetrics.keyCap)
                .background(RoundedRectangle(cornerRadius: EntrenarMetrics.keyRadius, style: .continuous).fill(theme.ink))
                .opacity(enabled ? 1 : StrandPalette.disabledOpacity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
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
