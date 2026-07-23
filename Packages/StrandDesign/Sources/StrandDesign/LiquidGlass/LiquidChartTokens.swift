import SwiftUI

// MARK: - Liquid Glass · Tokens de gráfica (épico hoja de resumen, F0)
//
// La calibración CERRADA de las gráficas Liquid (explorador de niveles, trend 14d,
// curva FC). Los VALORES de interacción son paridad 1:1 con el explorador Instrumento
// (`GraficaRangos` rev 2026-07-10b) — invariantes del dueño (2026-07-22):
//   I1 la banda activa se ILUMINA (washes 8 % reposo / 16 % activa / 3 % resto),
//   I2 el scrub es una REGLA VERTICAL que corta el plot + anillo en el punto,
//   I3 el selector de rango es RECTANGULAR.
// Lo que cambia en Liquid es la PIEL (tinta/vidrio/papel → tokens Liquid), nunca
// estos números de interacción.

public enum LiquidChart {

    // MARK: Trazo

    /// Grosor de la línea de serie.
    public static let lineaAncho: CGFloat = 1.6
    /// Grosor de la línea tenue (media móvil, serie secundaria).
    public static let lineaSecundariaAncho: CGFloat = 1.2
    /// Alfa de la retícula/grid sobre el vidrio.
    public static let gridAlfa: Double = 0.10
    /// El punto final de la serie: la JOYA (mismo lenguaje que el orbe).
    public static let endpointRadio: CGFloat = 2.8
    /// Borde blanco de la joya del endpoint.
    public static let endpointBorde: CGFloat = 1.2

    // MARK: Bandas (I1 — luminosidad de lo seleccionado)

    /// Wash de banda en reposo.
    public static let bandaReposoAlfa: Double = 0.08
    /// Wash de la banda ACTIVA (la luminosidad que pide el dueño).
    public static let bandaActivaAlfa: Double = 0.16
    /// Wash del resto cuando hay una activa.
    public static let bandaApagadaAlfa: Double = 0.03
    /// Wash de FILA activa (tabla de bandas, fila de nivel) — un solo número para I1
    /// fuera de la gráfica (QA F4-D7).
    public static let filaActivaAlfa: Double = 0.12

    // MARK: Scrub (I2 — regla vertical + anillo)

    /// Alfa de la regla vertical de corte (tinta/900).
    public static let scrubReglaAlfa: Double = 0.35
    /// Ancho de la regla vertical.
    public static let scrubReglaAncho: CGFloat = 1
    /// Diámetro del anillo sobre el punto scrubbeado.
    public static let scrubAnilloDiametro: CGFloat = 10
    /// Grosor del borde del anillo (color de la banda del punto).
    public static let scrubAnilloBorde: CGFloat = 2.5
    /// Alto del chip de valor («56 ms · mar 14»).
    public static let scrubChipAlto: CGFloat = 16
    /// Tipografía del chip (tabular, sobre tinta).
    public static let scrubChipFuente = InstrumentoType.groteskNumber(9.5, weight: .semibold)

    // MARK: Selector de rango (I3 — RECTANGULAR)

    /// Radio del selector de rango: `LiquidRadius.control` — rectangular con esquinas
    /// suaves, NUNCA cápsula (invariante del dueño).
    public static var selectorRadio: CGFloat { LiquidRadius.control }
    /// Alto del selector de rango.
    public static let selectorAlto: CGFloat = 28
}

#if DEBUG
#Preview("Liquid · Chart tokens") {
    // Maqueta mínima que ejercita cada token: banda activa iluminada, serie con joya,
    // regla de scrub + anillo + chip, y el selector rectangular.
    let hue = LiquidColor.cian
    return VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        HStack(spacing: LiquidSpace.s050) {
            ForEach(["7 D", "30 D", "90 D"], id: \.self) { r in
                Text(r).font(LiquidType.microEstado)
                    .foregroundStyle(r == "7 D" ? LiquidColor.papelAlto : LiquidColor.tinta700)
                    .frame(width: 44, height: LiquidChart.selectorAlto)
                    .background(r == "7 D" ? AnyShapeStyle(LiquidColor.tinta900)
                                           : AnyShapeStyle(Color.clear),
                                in: RoundedRectangle(cornerRadius: LiquidChart.selectorRadio,
                                                     style: .continuous))
            }
        }
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle().fill(hue.opacity(LiquidChart.bandaApagadaAlfa)).frame(height: 24)
                Rectangle().fill(hue.opacity(LiquidChart.bandaActivaAlfa)).frame(height: 32)
                Rectangle().fill(hue.opacity(LiquidChart.bandaReposoAlfa)).frame(height: 24)
            }
            Path { p in
                p.move(to: .init(x: 0, y: 52))
                p.addCurve(to: .init(x: 220, y: 38), control1: .init(x: 80, y: 66),
                           control2: .init(x: 150, y: 26))
            }
            .stroke(hue, lineWidth: LiquidChart.lineaAncho)
            Rectangle().fill(LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))
                .frame(width: LiquidChart.scrubReglaAncho, height: 80)
                .offset(x: 140)
            Circle().fill(LiquidColor.papelAlto)
                .overlay(Circle().strokeBorder(hue, lineWidth: LiquidChart.scrubAnilloBorde))
                .frame(width: LiquidChart.scrubAnilloDiametro,
                       height: LiquidChart.scrubAnilloDiametro)
                .offset(x: 135, y: 25)
            Circle().fill(hue)
                .overlay(Circle().strokeBorder(Color.white,
                                               lineWidth: LiquidChart.endpointBorde))
                .frame(width: LiquidChart.endpointRadio * 2,
                       height: LiquidChart.endpointRadio * 2)
                .offset(x: 217, y: 35)
            Text(verbatim: "56 ms · mar 14")
                .font(LiquidChart.scrubChipFuente)
                .foregroundStyle(LiquidColor.papelAlto)
                .padding(.horizontal, 6)
                .frame(height: LiquidChart.scrubChipAlto)
                .background(LiquidColor.tinta900, in: Capsule(style: .continuous))
                .offset(x: 90, y: 2)
        }
        .frame(width: 220, height: 80)
        .liquidGlass(.superficie)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
