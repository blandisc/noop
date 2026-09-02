import SwiftUI

// MARK: - PaperStepper — el −/+ de papel (FER-987)
//
// La versión «Instrumento diurno» del `Stepper` de iOS: dos `StepperButton` de papel
// en vez de la cápsula gris del sistema. Reemplaza al nativo sin perder lo que el
// nativo daba gratis:
//   · rango y paso respetados por todos los caminos (tap, hold, VoiceOver);
//   · área táctil ≥44×44 pt aunque el glifo visible sea de 34 (mismo truco que la
//     retícula de Constancia, FER-947: pad → shape → pad negativo);
//   · `.adjustable` para VoiceOver (swipe arriba/abajo), anunciando título y valor;
//   · repetición al mantener pulsado (0.45 s de espera, luego un paso cada 0.1 s).

public struct PaperStepper: View {
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let step: Int
    private let label: String
    private let unit: String?

    /// - Parameters:
    ///   - label: nombre del valor, para VoiceOver («Trabajo»).
    ///   - unit: unidad hablada y anunciada («s», «rondas»); nil si el valor va solo.
    public init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
                label: String, unit: String? = nil) {
        self._value = value
        self.range = range
        self.step = step
        self.label = label
        self.unit = unit
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s200) {
            button("minus", delta: -step, enabled: value > range.lowerBound)
            button("plus", delta: step, enabled: value < range.upperBound)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(step)
            case .decrement: nudge(-step)
            @unknown default: break
            }
        }
    }

    private var spokenValue: String {
        unit.map { "\(value) \($0)" } ?? "\(value)"
    }

    private func button(_ system: String, delta: Int, enabled: Bool) -> some View {
        StepperButton(system: system, size: Self.glyphSize, shape: .circle,
                      glyph: StrandFont.glyph(.inline, weight: .semibold)) { nudge(delta) }
            .opacity(enabled ? 1 : Self.disabledOpacity)
            .disabled(!enabled)
            .hitTarget(visible: Self.glyphSize)
            .repeatWhileHeld(enabled: enabled) { nudge(delta) }
    }

    /// Único camino que escribe el valor: siempre en paso y siempre dentro del rango.
    private func nudge(_ delta: Int) {
        value = min(range.upperBound, max(range.lowerBound, value + delta))
    }

    private static let glyphSize: CGFloat = 34   // círculo visible; el hit crece a 44 aparte
    private static let disabledOpacity: Double = 0.35
}

// MARK: - Área táctil ≥44 sin crecer el layout (FER-947)

private extension View {
    func hitTarget(visible: CGFloat) -> some View {
        let pad = max(0, (LiquidControl.hitTarget - visible) / 2)
        return padding(pad).contentShape(Rectangle()).padding(-pad)
    }
}

// MARK: - Repetición al mantener pulsado

private extension View {
    func repeatWhileHeld(enabled: Bool, action: @escaping () -> Void) -> some View {
        modifier(RepeatWhileHeld(enabled: enabled, action: action))
    }
}

private struct RepeatWhileHeld: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    @State private var pressing = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !pressing else { return }
                        pressing = true
                        start()
                    }
                    .onEnded { _ in stop() }
            )
            .onDisappear { stop() }
    }

    private func start() {
        task?.cancel()
        task = Task { @MainActor in
            // El primer paso lo da el `Button` con el tap; aquí solo la repetición.
            try? await Task.sleep(nanoseconds: 450_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stop() {
        pressing = false
        task?.cancel()
        task = nil
    }
}

#if DEBUG
private struct PaperStepperDemo: View {
    @State private var work = 40
    @State private var rounds = 8
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack {
                Text("Trabajo").font(StrandFont.headline).foregroundStyle(LiquidColor.tinta900)
                Spacer()
                Text("\(work)").font(StrandFont.number(24)).foregroundStyle(LiquidColor.ambar)
                PaperStepper(value: $work, in: 10...600, step: 5, label: "Trabajo", unit: "s")
            }
            HStack {
                Text("Rondas").font(StrandFont.headline).foregroundStyle(LiquidColor.tinta900)
                Spacer()
                Text("\(rounds)").font(StrandFont.number(24)).foregroundStyle(LiquidColor.tinta900)
                PaperStepper(value: $rounds, in: 1...50, label: "Rondas", unit: "rondas")
            }
        }
        .padding(LiquidSpace.s600)
        .background(LiquidColor.fondoAlto)
    }
}

#Preview("PaperStepper") { PaperStepperDemo() }
#endif
