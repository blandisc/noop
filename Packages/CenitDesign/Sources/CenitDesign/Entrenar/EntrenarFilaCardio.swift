import SwiftUI

// MARK: - EntrenarFilaCardio — fila de actividad Apple Health / manual (FER-202 · re-piel FER-294)
//
// Hermana simétrica de `EntrenarFilaFuerza` (mismo esqueleto: glifo 38 · título+meta · dato
// derecho) con asimetría deliberada: SF Symbol NEUTRO del deporte (`tinta700` — Cénit no
// tiñe lo que no mide) + chip de origen (`LiquidOrigenBadge` Apple/Manual) + dato = FC media o
// duración (NUNCA esfuerzo/21: la escala de cardio puede no ser la misma). No reusa
// `TarjetaSesion` (queda huérfana al retirar WorkoutsView).

public struct EntrenarFilaCardio: View {
    /// Origen de la actividad — tiñe el `LiquidOrigenBadge`.
    public enum Origen: Sendable, Hashable {
        case apple
        case manual
    }

    /// Dato derecho ya resuelto (FC media, duración, …).
    public struct Dato: Sendable {
        public let valor: String
        public let unidad: String
        public let tono: Color

        public init(valor: String, unidad: String, tono: Color) {
            self.valor = valor
            self.unidad = unidad
            self.tono = tono
        }
    }

    private let sfSymbol: String
    private let deporte: String
    private let origen: Origen
    private let meta: String
    private let dato: Dato
    private let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - sfSymbol: nombre SF Symbol del deporte (`figure.run`, `dumbbell.fill`, …).
    ///   - deporte: ya localizado («Correr», «Ciclismo»).
    ///   - origen: `.apple` → badge «Apple» en azul; `.manual` → «Manual» neutro.
    ///   - meta: ya formateada («mié 8 jul · 30 min · 5,2 km»).
    ///   - dato: valor + unidad + tono (rosa AA para FC, tinta para duración).
    ///   - onTap: navegación al detalle Apple/manual.
    public init(sfSymbol: String, deporte: String, origen: Origen,
                meta: String, dato: Dato, onTap: @escaping () -> Void) {
        self.sfSymbol = sfSymbol
        self.deporte = deporte
        self.origen = origen
        self.meta = meta
        self.dato = dato
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            Group {
                if typeSize.isAccessibilitySize {
                    filaAccesible
                } else {
                    filaCompacta
                }
            }
            .padding(.vertical, LiquidSpace.s225)
            .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    // MARK: Layouts

    private var filaCompacta: some View {
        HStack(spacing: LiquidSpace.s300) {
            glifo
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                HStack(spacing: LiquidSpace.s100) {
                    deporteText.lineLimit(1).minimumScaleFactor(0.8)
                    origenBadge
                }
                metaText.lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: LiquidSpace.s200)
            datoDerecho
        }
    }

    /// AX5: el dato baja bajo el título; la meta envuelve — la fila no se corta.
    private var filaAccesible: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s300) {
            glifo
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                HStack(spacing: LiquidSpace.s100) {
                    deporteText.fixedSize(horizontal: false, vertical: true)
                    origenBadge
                }
                metaText.fixedSize(horizontal: false, vertical: true)
                datoDerecho
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Piezas

    private var glifo: some View {
        Image(systemName: sfSymbol)
            .font(.system(size: Metrics.symbolSize, weight: .regular))
            .foregroundStyle(LiquidColor.tinta700)
            .frame(width: Metrics.chip, height: Metrics.chip)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var deporteText: some View {
        Text(verbatim: deporte)
            .font(LiquidType.tituloGemela)
            .foregroundStyle(LiquidColor.tinta900)
    }

    private var metaText: some View {
        Text(verbatim: meta)
            .font(LiquidType.filaConteo)
            .foregroundStyle(LiquidColor.tinta500)
    }

    private var origenBadge: some View {
        switch origen {
        case .apple:
            LiquidOrigenBadge(String(localized: "Apple"), tono: LiquidColor.azul)
        case .manual:
            LiquidOrigenBadge(String(localized: "Manual"), tono: nil)
        }
    }

    private var datoDerecho: some View {
        (Text(verbatim: dato.valor)
            .font(LiquidType.valorS)
            .foregroundStyle(dato.tono)
         + Text(verbatim: dato.unidad.isEmpty ? "" : "\(dato.unidad)")
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500))
    }

    private var a11yLabel: Text {
        let origenTxt: LocalizedStringKey = origen == .apple ? "Apple" : "Manual"
        return Text(verbatim: "\(deporte). ")
            + Text(origenTxt)
            + Text(verbatim: ". \(meta). \(dato.valor) \(dato.unidad)")
    }
}

private enum Metrics {
    static let chip: CGFloat = 38
    static let symbolSize: CGFloat = 18
}

#if DEBUG
#Preview("EntrenarFilaCardio · Apple + FC") {
    EntrenarFilaCardio(
        sfSymbol: "figure.run", deporte: "Correr", origen: .apple,
        meta: "mié 8 jul · 30 min · 5,2 km",
        dato: .init(valor: "148", unidad: "bpm", tono: LiquidTono.rosa.rotulo),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · Manual + duración") {
    EntrenarFilaCardio(
        sfSymbol: "figure.outdoor.cycle", deporte: "Ciclismo", origen: .manual,
        meta: "mar 7 jul · 45 min",
        dato: .init(valor: "45", unidad: "min", tono: LiquidColor.tinta700),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · Apple fuerza-like (no rica)") {
    EntrenarFilaCardio(
        sfSymbol: "dumbbell.fill", deporte: "Fuerza", origen: .apple,
        meta: "jue 9 jul · 38 min",
        dato: .init(valor: "132", unidad: "bpm", tono: LiquidTono.rosa.rotulo),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
}

#Preview("EntrenarFilaCardio · AX5") {
    EntrenarFilaCardio(
        sfSymbol: "figure.run", deporte: "Correr", origen: .apple,
        meta: "mié 8 jul · 30 min · 5,2 km",
        dato: .init(valor: "148", unidad: "bpm", tono: LiquidTono.rosa.rotulo),
        onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .instrumentoTheme(.base)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
