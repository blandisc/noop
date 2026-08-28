import SwiftUI

// MARK: - FocoCabecera — grabber + título del modo enfoque (FER-170 · F5)
//
// Mock `hoja-pantallas.html` P6 `.grab` + `.tWc`: asa superior + rótulo uppercase centrado.

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
}

/// Cabecera del sheet de enfoque: grabber + título de ejercicio/serie.
public struct FocoCabecera: View {
    private let titulo: String
    private let onCerrar: (() -> Void)?
    private let etiquetaCerrar: String?

    /// - Parameters:
    ///   - titulo: ya localizado (p. ej. «Sentadilla · serie 2 de 3»).
    ///   - onCerrar: tap del grabber (además del gesto de dismiss del caller); `nil` → solo dibujo.
    ///   - etiquetaCerrar: rótulo VO del grabber cuando es botón; `nil` → «Cerrar enfoque».
    public init(
        titulo: String,
        onCerrar: (() -> Void)? = nil,
        etiquetaCerrar: String? = nil
    ) {
        self.titulo = titulo
        self.onCerrar = onCerrar
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

        if let onCerrar {
            Button(action: onCerrar) {
                asa
                    .frame(
                        minWidth: FocoCabeceraMetrics.hitMin,
                        minHeight: FocoCabeceraMetrics.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // R6 (ronda 2 del gate, Grok G9): el default también vía `String(localized:)` — un
            // literal `Text(verbatim:)` en español hardcodeado nunca traduciría para un caller que
            // omitiera `etiquetaCerrar`. Misma clave que YA usan los tres call sites de Foco
            // (`RoutineSheetLiveFoco.swift`), así que el default coincide con lo que de verdad se ve.
            .accessibilityLabel(Text(verbatim: etiquetaCerrar ?? String(localized: "Close focus mode", bundle: .main)))
        } else {
            asa
                .accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("FocoCabecera · con cerrar") {
    FocoCabecera(
        titulo: "Sentadilla · serie 2 de 3",
        onCerrar: {},
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
