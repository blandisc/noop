import SwiftUI
import StrandDesign

/// Strain/illness early-warning banner. Observes AppModel in isolation so the ~1 Hz HR stream
/// re-renders only this small view, not the whole screen. Renders nothing when there's no alert.
///
/// Liquid Glass · El Eje (FER-245): `LiquidPatternBlock` inside `liquidTarjetaSeccion` — same
/// aviso recipe as DataSourcesView. Judgment color lives only on the 2.5 pt side bar; overline
/// is tinta500, body is tinta700. No warning triangle.
struct HealthAlertBanner: View {
    @Environment(AppModel.self) var model

    /// Visual severity for the side bar. AppModel today only surfaces a non-nil `healthAlert`
    /// for illness `.raised`; that path maps to atención (amber heads-up). Crítico is wired
    /// for a louder level without changing what fires the banner.
    private enum Severidad {
        case atencion
        case critico

        var tono: Color {
            switch self {
            case .atencion: return LiquidColor.atencion
            case .critico: return LiquidColor.negativo
            }
        }

        var overline: String {
            switch self {
            case .atencion:
                return String(localized: "healthAlert.overline.atencion",
                              defaultValue: "Heads up")
            case .critico:
                return String(localized: "healthAlert.overline.alerta",
                              defaultValue: "Alert")
            }
        }
    }

    var body: some View {
        if let alert = model.healthAlert {
            contenido(alert, severidad: .atencion)
        }
    }

    private func contenido(_ alert: String, severidad: Severidad) -> some View {
        LiquidPatternBlock(
            overline: severidad.overline,
            lineas: [alert],
            tono: severidad.tono)
        .liquidTarjetaSeccion()
    }
}

#if DEBUG
#Preview("HealthAlert · Atención") {
    LiquidPatternBlock(
        overline: String(localized: "healthAlert.overline.atencion", defaultValue: "Heads up"),
        lineas: ["Your resting heart rate has been higher than usual. Consider easing up today."],
        tono: LiquidColor.atencion)
    .liquidTarjetaSeccion()
    .padding(.horizontal, LiquidSpace.s600)
    .background(LiquidColor.papelGradient)
}

#Preview("HealthAlert · Alerta") {
    LiquidPatternBlock(
        overline: String(localized: "healthAlert.overline.alerta", defaultValue: "Alert"),
        lineas: ["Signals look strained beyond your normal. Take it easy and check how you feel."],
        tono: LiquidColor.negativo)
    .liquidTarjetaSeccion()
    .padding(.horizontal, LiquidSpace.s600)
    .background(LiquidColor.papelGradient)
}
#endif
