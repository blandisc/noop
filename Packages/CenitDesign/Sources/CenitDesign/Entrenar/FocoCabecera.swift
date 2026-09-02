import SwiftUI

// MARK: - FocoCabecera — grabber + título del modo enfoque (FER-170 · F5 / FER-187)
//
// Mock `hoja-pantallas.html` P6 `.grab` + `.tWc`: asa superior + rótulo uppercase centrado.
// FER-187: el arrastre-para-salir vive SOLO en el grabber (arriba del ScrollView de Foco) —
// nunca en el contenido scrolleable (lección [[scrub-dentro-de-scrollview-roba-el-scroll]]).

/// Constantes locales de la cabecera de foco (mock `.grab` / `.tWc`). No viven en `HojaMetrics`.
private enum FocoCabeceraMetrics {
    /// `.grab` `width: 34px`.
    static var grabAncho: CGFloat { 34 }
    /// `.grab` `height: 4px`.
    static var grabAlto: CGFloat { 4 }
    /// `.grab` `border-radius: 2px`.
    static var grabRadio: CGFloat { 2 }
    /// `.grab` `background: rgba(34,29,22,.18)`.
    static var grabAlfa: Double { 0.18 }
    /// `.grab` `margin: 10px auto 0`.
    static var grabMargenTop: CGFloat { 10 }
    /// `.tWc` `font-size: 9px`.
    static var tituloSize: CGFloat { 9 }
    /// `.tWc` `letter-spacing: 1.2px`.
    static var tituloTracking: CGFloat { 1.2 }
    /// `.tWc` inline `margin-top: 14px`.
    static var tituloMargenTop: CGFloat { 14 }
    /// Blanco táctil mínimo del grabber cuando es botón (HIG).
    static var hitMin: CGFloat { 44 }
    /// FER-187: arrastre hacia abajo ≥ este umbral (pt) dispara cerrar.
    static var arrastreCerrarUmbral: CGFloat { 60 }
    /// FER-187: velocidad hacia abajo (pt/s) que también cierra aunque el desplazamiento
    /// no llegue al umbral — flick corto.
    static var arrastreCerrarVelocidad: CGFloat { 800 }
    /// Distancia mínima antes de reconocer el arrastre (deja vivir el tap del grabber).
    static var arrastreMinimo: CGFloat { 10 }
}

/// Cabecera del sheet de enfoque: grabber + título de ejercicio/serie.
public struct FocoCabecera: View {
    private let titulo: String
    private let onCerrar: (() -> Void)?
    private let onArrastrarCerrar: (() -> Void)?
    private let etiquetaCerrar: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Desplazamiento vertical del asa mientras el dedo arrastra (rebota si no cierra).
    @State private var arrastreY: CGFloat = 0

    /// - Parameters:
    ///   - titulo: ya localizado (p. ej. «Sentadilla · serie 2 de 3»).
    ///   - onCerrar: tap del grabber (además del gesto de dismiss del caller); `nil` → solo dibujo.
    ///   - onArrastrarCerrar: FER-187 — arrastre del grabber hacia abajo past umbral/velocidad;
    ///     `nil` (default) no añade el gesto, para no romper callers que solo pintan.
    ///   - etiquetaCerrar: rótulo VO del grabber cuando es botón; `nil` → «Cerrar enfoque».
    public init(
        titulo: String,
        onCerrar: (() -> Void)? = nil,
        onArrastrarCerrar: (() -> Void)? = nil,
        etiquetaCerrar: String? = nil
    ) {
        self.titulo = titulo
        self.onCerrar = onCerrar
        self.onArrastrarCerrar = onArrastrarCerrar
        self.etiquetaCerrar = etiquetaCerrar
    }

    public var body: some View {
        VStack(spacing: 0) {
            grabber
                .padding(.top, FocoCabeceraMetrics.grabMargenTop)

            Text(verbatim: titulo)
                .font(InstrumentoType.grotesk(
                    FocoCabeceraMetrics.tituloSize,
                    weight: .bold,
                    relativeTo: .caption2))
                .tracking(FocoCabeceraMetrics.tituloTracking)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity)
                .padding(.top, FocoCabeceraMetrics.tituloMargenTop)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var grabber: some View {
        let asa = Capsule()
            .fill(LiquidColor.tinta900.opacity(FocoCabeceraMetrics.grabAlfa))
            .frame(
                width: FocoCabeceraMetrics.grabAncho,
                height: FocoCabeceraMetrics.grabAlto)

        // Sin callbacks: solo dibujo (preview / callers decorativos).
        if onCerrar == nil, onArrastrarCerrar == nil {
            asa.accessibilityHidden(true)
        } else if onArrastrarCerrar == nil, let onCerrar {
            // Solo tap — Button plano, misma API que FER-170 (callers sin arrastre intactos).
            Button(action: onCerrar) {
                asa
                    .frame(
                        minWidth: FocoCabeceraMetrics.hitMin,
                        minHeight: FocoCabeceraMetrics.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(etiquetaAccesibilidad)
        } else {
            // Tap + arrastre en UN solo DragGesture: un Button + Drag simultaneous dispara el
            // action del Button al soltar un arrastre que rebotó — cerraría el foco por error.
            asa
                .frame(
                    minWidth: FocoCabeceraMetrics.hitMin,
                    minHeight: FocoCabeceraMetrics.hitMin)
                .contentShape(Rectangle())
                .offset(y: arrastreY)
                .gesture(tapOArrastreGesto)
                .accessibilityLabel(etiquetaAccesibilidad)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onCerrar?() }
        }
    }

    private var etiquetaAccesibilidad: Text {
        // R6 (ronda 2 del gate, Grok G9): el default también vía `String(localized:)` — un
        // literal `Text(verbatim:)` en español hardcodeado nunca traduciría para un caller que
        // omitiera `etiquetaCerrar`. Misma clave que YA usan los call sites de Foco
        // (`RoutineSheetLiveFoco.swift`), así que el default coincide con lo que de verdad se ve.
        Text(verbatim: etiquetaCerrar ?? String(localized: "Close focus mode", bundle: .main))
    }

    /// Un solo gesto: desplazamiento ≈ 0 → tap (`onCerrar`); hacia abajo past umbral/velocidad →
    /// `onArrastrarCerrar`; en medio → rebote (corte seco con Reduce Motion).
    private var tapOArrastreGesto: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                // Solo hacia abajo: un jalón hacia arriba no mueve el asa.
                arrastreY = max(0, g.translation.height)
            }
            .onEnded { g in
                let dy = g.translation.height
                let dx = g.translation.width
                // Tap limpio: el dedo casi no se movió.
                if hypot(dx, dy) < FocoCabeceraMetrics.arrastreMinimo {
                    arrastreY = 0
                    onCerrar?()
                    return
                }
                let predicted = g.predictedEndTranslation.height
                let vy = g.velocity.height
                let cierra = dy >= FocoCabeceraMetrics.arrastreCerrarUmbral
                    || predicted >= FocoCabeceraMetrics.arrastreCerrarUmbral
                    || vy >= FocoCabeceraMetrics.arrastreCerrarVelocidad
                if cierra {
                    // Reduce Motion: cierre en corte seco (sin animar el offset).
                    arrastreY = 0
                    onArrastrarCerrar?()
                } else if reduceMotion {
                    arrastreY = 0
                } else {
                    withAnimation(StrandMotion.interactive) {
                        arrastreY = 0
                    }
                }
            }
    }
}

#if DEBUG
#Preview("FocoCabecera · con cerrar") {
    FocoCabecera(
        titulo: "Sentadilla · serie 2 de 3",
        onCerrar: {},
        onArrastrarCerrar: {},
        etiquetaCerrar: "Cerrar enfoque")
    .padding(.bottom, 24)
    .background(LiquidColor.fondoGradient)
}

#Preview("FocoCabecera · solo dibujo") {
    FocoCabecera(titulo: "Curl femoral · serie 1 de 3")
        .padding(.bottom, 24)
        .background(LiquidColor.fondoGradient)
}
#endif
