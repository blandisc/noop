import SwiftUI

// MARK: - LiquidAviso (FER-280 · clase 3)
//
// La receta ÚNICA de aviso Liquid. Extraída de la ganadora ya viva en app:
// `HealthAlertBanner` = `LiquidPatternBlock` + `liquidTarjetaSeccion`
// (`Cenit/Screens/HealthAlertBanner.swift:46-50`). Sin icono ni CTA, el body es
// EXACTAMENTE esa composición — adopción cero-pixel del banner de salud.
//
// Slots opcionales para matar los otros dialectos en la ola de adopción:
//   · `icono` - leading `LiquidIcon` (connectNudge / CuerpoView)
//   · `cta` + `accion` - rótulo quiet bajo el cuerpo; si hay `accion`, toda la
//     tarjeta es tocable (AvisoDesconexion con tap a Salud)
//
// Cuándo SÍ: heads-up / desconexión / nudge / lectura de aviso en pantalla Liquid.
// Cuándo NO: snack de deshacer (`UndoToast`); error de escritura (`.saveErrorToast`).
// FER-342: `TodayBanner` (Instrumento) se borró; Hoy monta `LiquidAviso` cuando hace falta.

/// Constantes de la receta — fuera de la View para que los tests no toquen MainActor.
enum LiquidAvisoMetrics {
    /// Pad de la tarjeta — default de `liquidTarjetaSeccion` (HealthAlertBanner:50).
    static let tarjetaPadding: CGFloat = LiquidSpace.s400
    /// Tamaño del icono opcional — `connectNudge` (CuerpoView:1172) usa 17.
    public static let iconSize: CGFloat = 17
    /// Separación icono↔bloque / bloque↔CTA — `LiquidSpace.s300`.
    static let slotSpacing: CGFloat = LiquidSpace.s300
    /// Ancho de la barra lateral — el de `LiquidPatternBlock` (2.5).
    static let barraAncho: CGFloat = 2.5
}

public struct LiquidAviso: View {
    private let titulo: String
    private let lineas: [String]
    private let tono: Color
    private let icono: LiquidIcon.Glyph?
    private let cta: String?
    private let accion: (() -> Void)?
    private let pie: AnyView?

    /// Aviso de una sola línea de cuerpo (paridad con HealthAlertBanner).
    /// - Parameters:
    ///   - titulo: overline ya localizado (p. ej. «Heads up»).
    ///   - cuerpo: frase ya localizada.
    ///   - tono: color de la barra lateral (juicio: `atencion` / `negativo` / identidad).
    ///   - icono: glifo leading opcional; `nil` = receta ganadora pura.
    ///   - cta: rótulo quiet opcional bajo el cuerpo.
    ///   - accion: si no es `nil`, toda la tarjeta es un botón (`.liquidPress`).
    public init(titulo: String,
                cuerpo: String,
                tono: Color,
                icono: LiquidIcon.Glyph? = nil,
                cta: String? = nil,
                accion: (() -> Void)? = nil) {
        self.titulo = titulo
        self.lineas = [cuerpo]
        self.tono = tono
        self.icono = icono
        self.cta = cta
        self.accion = accion
        self.pie = nil
    }

    /// Aviso con varias líneas de cuerpo (paridad con `LiquidPatternBlock.lineas`).
    public init(titulo: String,
                lineas: [String],
                tono: Color,
                icono: LiquidIcon.Glyph? = nil,
                cta: String? = nil,
                accion: (() -> Void)? = nil) {
        self.titulo = titulo
        self.lineas = lineas
        self.tono = tono
        self.icono = icono
        self.cta = cta
        self.accion = accion
        self.pie = nil
    }

    /// Aviso con pie libre (acciones extra bajo el cuerpo; FER-339, adopta call-sites de `NoteStrip`).
    /// Con `pie`, la tarjeta NO es un botón global — los controles viven en el pie.
    public init<Pie: View>(titulo: String,
                           cuerpo: String,
                           tono: Color,
                           icono: LiquidIcon.Glyph? = nil,
                           @ViewBuilder pie: () -> Pie) {
        self.titulo = titulo
        self.lineas = cuerpo.isEmpty ? [] : [cuerpo]
        self.tono = tono
        self.icono = icono
        self.cta = nil
        self.accion = nil
        self.pie = AnyView(pie())
    }

    /// Igual que el init con `cuerpo` + `pie`, pero con varias líneas.
    public init<Pie: View>(titulo: String,
                           lineas: [String],
                           tono: Color,
                           icono: LiquidIcon.Glyph? = nil,
                           @ViewBuilder pie: () -> Pie) {
        self.titulo = titulo
        self.lineas = lineas
        self.tono = tono
        self.icono = icono
        self.cta = nil
        self.accion = nil
        self.pie = AnyView(pie())
    }

    public var body: some View {
        let card = nucleo
            .liquidTarjetaSeccion(padding: LiquidAvisoMetrics.tarjetaPadding)
            .accessibilityElement(children: pie == nil ? .combine : .contain)

        if let accion, pie == nil {
            Button(action: accion) {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        } else {
            card
        }
    }

    /// Sin icono ni CTA ni pie → `LiquidPatternBlock` solo (HealthAlertBanner bit-a-bit).
    @ViewBuilder
    private var nucleo: some View {
        if icono == nil && cta == nil && pie == nil {
            LiquidPatternBlock(overline: titulo, lineas: lineas, tono: tono)
        } else {
            VStack(alignment: .leading, spacing: LiquidAvisoMetrics.slotSpacing) {
                if !lineas.isEmpty || (titulo.isEmpty == false) || icono != nil {
                    HStack(alignment: .top, spacing: LiquidAvisoMetrics.slotSpacing) {
                        if let icono {
                            LiquidIcon(icono,
                                       size: LiquidAvisoMetrics.iconSize,
                                       color: tono)
                        }
                        if !lineas.isEmpty {
                            LiquidPatternBlock(overline: titulo.isEmpty ? nil : titulo,
                                               lineas: lineas, tono: tono)
                        }
                    }
                }
                if let cta {
                    Text(verbatim: cta)
                        .font(LiquidType.boton)
                        .tracking(LiquidType.botonTracking)
                        .foregroundStyle(LiquidColor.verdeProfundo)
                }
                if let pie {
                    pie
                }
            }
        }
    }
}

#if DEBUG
#Preview("Liquid · Aviso") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        Text("ganadora · HealthAlertBanner").font(LiquidType.caption)
            .foregroundStyle(LiquidColor.tinta500)
        LiquidAviso(
            titulo: "Heads up",
            cuerpo: "Your resting heart rate has been higher than usual. Consider easing up today.",
            tono: LiquidColor.atencion)

        Text("alerta").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        LiquidAviso(
            titulo: "Alert",
            cuerpo: "Signals look strained beyond your normal. Take it easy and check how you feel.",
            tono: LiquidColor.negativo)

        Text("con icono + CTA").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        LiquidAviso(
            titulo: "Apple Salud",
            cuerpo: "Connect Apple Health to fill steps and more.",
            tono: LiquidColor.azul,
            icono: .corazon,
            cta: "Conectar →",
            accion: {})
    }
    .padding(.horizontal, LiquidSpace.s600)
    .padding(.vertical, LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
