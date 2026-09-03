import SwiftUI
import TipKit

// MARK: - LiquidConsejo (ola 1 · E12) — estilo «tinta sobre vidrio» para los consejos de TipKit
//
// Capa 2 del tutorial sin tour (issue 12-vocabulario-tutorial, artefacto `ola1-pantallas.html` §4):
// un consejo en el lugar donde el concepto aparece, una sola vez, cerrado con «Entendido». TipKit
// (iOS 17 mínimo — ya es el mínimo del repo) trae la lógica de «una sola vez»; esta pieza solo le
// da el dibujo del sistema en vez del recuadro gris genérico de Apple.
//
// Se aplica UNA vez en la raíz de la app: `.tipViewStyle(LiquidConsejoTipStyle())`. Cada sitio de
// anclaje en Cenit/ solo escribe `TipView(MiTip(), arrowEdge: nil)` o `.popoverTip(MiTip())` — el
// estilo se hereda del entorno, no se repite.
//
// GAP conocido (ver reporte de la rama): TipKit no expone una API pública para desactivar la
// transición de aparición/cierre propia del framework (no hay `tipTransition`/equivalente en la
// documentación de Apple) — esta pieza no añade NINGUNA animación propia (ni al texto ni al botón),
// así que lo único no gobernado por Reduce Motion es el fundido que TipKit dibuja internamente.

/// «Tinta sobre vidrio»: receta `.dialogo` (lente, flotante) + tipografía/color de `LiquidType`/
/// `LiquidColor`, y un botón «Entendido» que invalida el tip explícitamente (además de la `×` de
/// cierre, fiel al preview aprobado por el dueño). `Tip.MaxDisplayCount(1)` en cada `Tip` concreto
/// ya evita que vuelva a aparecer; el botón es el camino principal, documentado en el criterio de
/// aceptación del issue.
public struct LiquidConsejoTipStyle: TipViewStyle {
    public init() {}

    public func makeBody(configuration: TipViewStyle.Configuration) -> some View {
        LiquidConsejoBody(configuration: configuration)
    }
}

/// Vista propia (en vez de un `View` anónimo) para que `@Environment` — Reduce Motion — funcione
/// sin ambigüedad dentro de `makeBody`.
private struct LiquidConsejoBody: View {
    let configuration: TipViewStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(alignment: .top, spacing: LiquidSpace.s200) {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    if let title = configuration.title {
                        title.font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    if let message = configuration.message {
                        message.font(LiquidType.caption).foregroundStyle(LiquidColor.tinta700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: LiquidSpace.s200)
                Button {
                    configuration.tip.invalidate(reason: .tipClosed)
                } label: {
                    Image(systemName: "xmark")
                        .font(LiquidType.iconSF(size: 11).weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta500)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            Button {
                configuration.tip.invalidate(reason: .actionPerformed)
            } label: {
                Text("Got it")
                    .font(LiquidType.cuerpo.weight(.semibold))
                    .foregroundStyle(LiquidColor.verdePrimario)
            }
            .buttonStyle(.plain)
        }
        .padding(LiquidSpace.s400)
        .liquidGlass(.dialogo)
        .frame(maxWidth: 320)
        // Nada propio que animar aquí — ver el GAP arriba sobre la transición interna de TipKit.
        .transaction { t in if reduceMotion { t.animation = nil } }
    }
}

#if DEBUG
private struct ConsejoPreviewTip: Tip {
    var title: Text { Text(verbatim: "Serie «las que puedas»") }
    var message: Text? {
        Text(verbatim: "Haz todas las reps que puedas con buena forma y anota cuántas salieron. Cuenta para tus récords y para subir.")
    }
}

#Preview("Consejo · Liquid Glass") {
    VStack {
        Spacer()
        TipView(ConsejoPreviewTip(), arrowEdge: nil)
            .tipViewStyle(LiquidConsejoTipStyle())
            .padding(.horizontal, LiquidSpace.s600)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LiquidColor.fondoAlto)
    .task {
        try? Tips.resetDatastore()
        try? Tips.configure()
    }
}
#endif
