#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import Foundation

// FER-105 · TND-32: la franja se separó de `TrainingLoadSheet.swift` para que la HOJA quede
// libre de referencias a «Instrumento» (su migración a Liquid Glass). La franja SIGUE en
// «Instrumento» —excepción sancionada, como `LiquidHill`; su gemelo Liquid es la Hoy Liquid—,
// así que su código se mudó tal cual, sin re-tokenizar.

// FER-119: vivía en `RecoveryDetailScreen`, que se retiró con el puntaje 0–100. Sus tres
// consumidores siguen vivos (las columnas de Cuerpo y la hoja de carga), así que la extensión se
// mudó al archivo de la carga —su usuario principal— en vez de irse con la pantalla.
extension ReadinessEngine.Flag {
    /// El único mapeo bandera → color «Instrumento»: bien → veredicto, neutro → tinta quieta,
    /// vigilar → aviso, mal → crítico.
    func color(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .good:    return theme.verdict
        case .neutral: return theme.inkSecondary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }
}

// MARK: - Franja de carga (bloque fijo de «Hoy») — Instrumento (sin cambios en la migración Liquid)

/// La franja de dos filas en SEÑALES (única superficie de Hoy): label + palabra de banda + ratio + chevron,
/// y una escala de 4 cápsulas con el punto de hoy. Tocarla abre la hoja. No respira (no es un dato vivo
/// intradía) y no participa del pull-to-refresh; solo el punto se reposiciona si el ratio cambió al sincronizar.
struct TrainingLoadStrip: View {
    let model: TrainingLoadModel
    var theme: InstrumentoTheme = .base
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ReadinessEngine.LoadBand? { model.band }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
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
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Load")
                .groteskOverline(small: true)
                .foregroundStyle(theme.inkMuted)
            Spacer(minLength: 8)
            if let band, let acwr = model.acwr {
                Text(band.shortLabel)
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(band.flag.color(theme))
                Text(String(format: "%.2f", acwr))
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
                StrandIcon.disclosure.image
                    .font(.system(size: 9, weight: .semibold)) // token-exempt: microtexto <10pt
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            } else {
                Text("Calibrating")
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkMuted)
                Text(verbatim: "··")
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            }
        }
    }

    private var scaleRow: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(LoadScale.bounds, id: \.lo) { seg in
                        Capsule()
                            .fill(seg.band == band ? seg.band.flag.color(theme) : theme.hairline)
                            .frame(width: max(0, w * (seg.hi - seg.lo) / LoadScale.max - 2), height: 6)
                    }
                }
                .frame(height: 12, alignment: .center)
                if let acwr = model.acwr {
                    let x = min(max(acwr / LoadScale.max, 0.05), 0.95)
                    Circle()
                        .fill(theme.surface)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: 3))
                        .frame(width: 12, height: 12)
                        .offset(x: w * x - 6, y: 0)
                        .strandAnimation(.spring(response: 0.5, dampingFraction: 0.8), value: acwr)
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Franja") {
    VStack(spacing: 24) {
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.09, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: nil, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.62, series: [], days: []), theme: .base, onTap: {})
    }
    .padding(24).background(InstrumentoTheme.base.paper)
}
#endif
#endif
