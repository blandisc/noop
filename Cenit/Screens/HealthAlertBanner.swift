import SwiftUI
import CenitDesign

/// Strain/illness early-warning banner. Observes AppModel in isolation so the ~1 Hz HR stream
/// re-renders only this small view, not the whole screen. Renders nothing when there's no alert.
///
/// Liquid Glass · El Eje (FER-245 / FER-280·2c): receta → `LiquidAviso` (ganadora
/// `LiquidPatternBlock` + `liquidTarjetaSeccion`). Judgment color lives only on the side bar;
/// overline is tinta500, body is tinta700. No warning triangle.
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
        LiquidAviso(titulo: severidad.overline, cuerpo: alert, tono: severidad.tono)
    }
}

#if DEBUG
#Preview("HealthAlert · Atención") {
    LiquidAviso(
        titulo: String(localized: "healthAlert.overline.atencion", defaultValue: "Heads up"),
        cuerpo: "Your resting heart rate has been higher than usual. Consider easing up today.",
        tono: LiquidColor.atencion)
    .padding(.horizontal, LiquidSpace.s600)
    .background(LiquidColor.papelGradient)
}

#Preview("HealthAlert · Alerta") {
    LiquidAviso(
        titulo: String(localized: "healthAlert.overline.alerta", defaultValue: "Alert"),
        cuerpo: "Signals look strained beyond your normal. Take it easy and check how you feel.",
        tono: LiquidColor.negativo)
    .padding(.horizontal, LiquidSpace.s600)
    .background(LiquidColor.papelGradient)
}
#endif
