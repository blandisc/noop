import SwiftUI

// MARK: - UndoToast (FER-280 · clase 3)
//
// Barra de tinta con CTA de deshacer. Receta pixel-fiel de
// `WeeklyPlanEditorView.swift:748-758` (y su gemela de carpeta :871-883):
//   HStack gap 12 · mensaje `StrandFont.subhead` en `theme.surface` · Spacer min 8 ·
//   CTA grotesk 15 bold · pad H `screenPadding` · V `cardPadding` · fondo `theme.ink` ·
//   radius `cardRadius` · inset exterior H `screenPadding` · bottom 8.
//
// La pieza dibuja la barra; el caller monta el `.task` de auto-descarte y el
// `.transition(LiquidMotion.risingFadeTransition)` (política de producto, no vocabulario).
//
// Cuándo SÍ: snack de «X borrado · Deshacer» tras un delete reversible (rutina, carpeta,
// sesión). Cuándo NO: banner de error de escritura (usa `.saveErrorToast`); aviso Liquid
// de lectura/heads-up (usa `LiquidAviso`); confirmación con consecuencia (usa
// `.instrumentoConfirm`).

/// Constantes de la receta — fuera de la View para que los tests no toquen MainActor.
enum UndoToastMetrics {
    /// `HStack` spacing — literal `12` en WeeklyPlanEditor:749 (= `LiquidSpace.s300`).
    static let hStackSpacing: CGFloat = LiquidSpace.s300
    /// `Spacer(minLength:)` — literal `8` en WeeklyPlanEditor:751 (= `LiquidSpace.s200`).
    static let spacerMin: CGFloat = LiquidSpace.s200
    /// Pad horizontal interno — `LiquidSpace.s600` (WeeklyPlanEditor:757).
    static let padH: CGFloat = LiquidSpace.s600
    /// Pad vertical interno — `LiquidSpace.s400` (WeeklyPlanEditor:757).
    static let padV: CGFloat = LiquidSpace.s400
    /// Radio del fondo de tinta — `LiquidRadius.tarjeta` 18 (FER-294 re-piel; era `cardRadius` 16).
    static let radius: CGFloat = LiquidRadius.tarjeta
    /// Inset horizontal exterior — `LiquidSpace.s600` (WeeklyPlanEditor:759).
    static let outerPadH: CGFloat = LiquidSpace.s600
    /// Inset inferior exterior — literal `8` (WeeklyPlanEditor:760).
    static let outerPadBottom: CGFloat = 8
}

public struct UndoToast: View {
    private let theme: InstrumentoTheme
    private let message: String
    private let cta: String
    private let action: () -> Void

    /// - Parameters:
    ///   - message: texto ya resuelto (`String(localized:)` en el caller) — p. ej. «Routine deleted».
    ///   - cta: rótulo del botón; default «Undo» (paridad con los 3 sitios actuales).
    ///   - theme: tema Instrumento que aporta `ink`/`surface` (la barra es de la era tinta).
    ///   - action: deshacer — el caller decide qué restaurar.
    public init(message: String,
                cta: String = "Undo",
                theme: InstrumentoTheme,
                action: @escaping () -> Void) {
        self.message = message
        self.cta = cta
        self.theme = theme
        self.action = action
    }

    public var body: some View {
        // `theme` se conserva en la API pública; la piel es Liquid (FER-294).
        let _ = theme
        HStack(spacing: UndoToastMetrics.hStackSpacing) {
            Text(verbatim: message)
                .font(LiquidType.cuerpoBanner)
                .foregroundStyle(LiquidColor.papelTarjeta)
            Spacer(minLength: UndoToastMetrics.spacerMin)
            Button(action: action) {
                Text(verbatim: cta)
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.papelTarjeta)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, UndoToastMetrics.padH)
        .padding(.vertical, UndoToastMetrics.padV)
        .background(LiquidColor.tinta900,
                    in: RoundedRectangle(cornerRadius: UndoToastMetrics.radius, style: .continuous))
        .padding(.horizontal, UndoToastMetrics.outerPadH)
        .padding(.bottom, UndoToastMetrics.outerPadBottom)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("UndoToast") {
    let t = InstrumentoTheme.base
    VStack(spacing: LiquidSpace.s400) {
        UndoToast(message: "Routine deleted", theme: t, action: {})
        UndoToast(message: "Folder deleted", theme: t, action: {})
        UndoToast(message: "Workout deleted", cta: "Undo", theme: t, action: {})
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .background(t.paper)
    .instrumentoTheme(t)
}
#endif
