#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import Foundation

// FER-105 · TND-32: la franja se separó de `TrainingLoadSheet.swift` para que la HOJA migrara
// sola a Liquid Glass. FER-304: la franja también pasa a tokens Liquid · El Eje.

// FER-119: vivía en `RecoveryDetailScreen`, que se retiró con el puntaje 0–100. Sus tres
// consumidores siguen vivos (las columnas de Cuerpo y la hoja de carga), así que la extensión se
// mudó al archivo de la carga —su usuario principal— en vez de irse con la pantalla.
extension ReadinessEngine.Flag {
    /// El único mapeo bandera → color Liquid: bien → verde, neutro → tinta, vigilar → aviso, mal → negativo.
    func color() -> Color {
        switch self {
        case .good:    return LiquidColor.verdePrimario
        case .neutral: return LiquidColor.tinta700
        case .watch:   return LiquidColor.atencion
        case .bad:     return LiquidColor.negativo
        }
    }
}

// MARK: - Franja de carga (bloque fijo de «Hoy») — Liquid Glass · El Eje (FER-304)

/// La franja de dos filas en SEÑALES (única superficie de Hoy): label + palabra de banda + ratio + chevron,
/// y una escala de 4 cápsulas con el punto de hoy. Tocarla abre la hoja. No respira (no es un dato vivo
/// intradía) y no participa del pull-to-refresh; solo el punto se reposiciona si el ratio cambió al sincronizar.
struct TrainingLoadStrip: View {
    let model: TrainingLoadModel
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ReadinessEngine.LoadBand? { model.band }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                labelRow
                scaleRow
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Training load"))
        .accessibilityValue(model.acwr == nil ? Text("Calibrating")
                            : Text(band?.shortLabel ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: .zero) {
            Text("Load")
                .liquidKicker()
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: LiquidSpace.s200)
            if let band, let acwr = model.acwr {
                Text(band.shortLabel)
                    .font(LiquidType.captionNegrita)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(band.flag.color())
                Text(String(format: "%.2f", acwr))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.leading, LiquidSpace.s150)
                CenitIcon.disclosure.image
                    .font(.system(size: 9, weight: .semibold))  // token-exempt(falta-pieza): microtexto <10pt
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.leading, LiquidSpace.s150)
            } else {
                Text("Calibrating")
                    .font(LiquidType.captionNegrita)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(verbatim: "··")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.leading, LiquidSpace.s150)
            }
        }
    }

    private var scaleRow: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: LiquidSpace.s050) {
                    ForEach(LoadScale.bounds, id: \.lo) { seg in
                        let tono = seg.band == band ? seg.band.flag.color() : LiquidColor.tinta10
                        LiquidBarraProgreso(fraccion: 1, tono: tono, pista: tono,
                                            altura: LiquidSpace.s150, animada: false)
                            .frame(width: max(0, w * (seg.hi - seg.lo) / LoadScale.max - 2),
                                   height: LiquidSpace.s150)
                    }
                }
                .frame(height: 12, alignment: .center)
                if let acwr = model.acwr {
                    let x = min(max(acwr / LoadScale.max, 0.05), 0.95)
                    Circle()
                        .fill(LiquidColor.papelTarjeta)
                        .overlay(Circle().strokeBorder(LiquidColor.tinta900, lineWidth: 3))
                        .frame(width: 12, height: 12)
                        .offset(x: w * x - 6, y: 0)
                        .strandAnimation(.spring(response: 0.5, dampingFraction: 0.8), value: acwr)  // token-exempt(unico): marcador ACWR sobre la franja de carga — spring único de esta geometría
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Franja") {
    VStack(spacing: LiquidSpace.s600) {
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.09, series: [], days: []), onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: nil, series: [], days: []), onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.62, series: [], days: []), onTap: {})
    }
    .padding(LiquidSpace.s600).background(LiquidColor.fondoAlto)
}
#endif
#endif
