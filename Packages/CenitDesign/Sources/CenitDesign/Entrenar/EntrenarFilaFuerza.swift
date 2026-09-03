import SwiftUI

// MARK: - EntrenarFilaFuerza — fila rica de sesión de fuerza (FER-202 · re-piel FER-294)
//
// Consolida el esqueleto triplicado (`WorkoutHistoryScreen.sessionRow` +
// `EntrenarHubHistorial.filaRow` + `EntrenarView.bitacoraRow`): glifo de familia 38 teñido en
// chip `tinta7` · nombre + `EntrenarMarcaChip` opcional · meta ya formateada · dato
// derecho = esfuerzo/21 en `atencionTexto`. Props resueltas (sin repo); el caller cablea
// el tap. Asimetría deliberada frente a `EntrenarFilaCardio` (glifo de familia + marca, no SF
// Symbol neutro ni origen).

public struct EntrenarFilaFuerza: View {
    private let family: EntrenarFamily
    private let nombre: String
    private let meta: String
    private let marcas: Int
    private let esfuerzo: String?
    /// Optional import provenance seal («Strong» / «Hevy» / «Cénit») — FER-333.
    private let origen: String?
    private let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - family: identidad de movimiento (tiñe el glifo).
    ///   - nombre: ya localizado («Empuje A», «Pierna»).
    ///   - meta: ya formateada («vie 10 jul · 48 min · 4.320 kg»).
    ///   - marcas: `0` = sin chip; `>0` = `EntrenarMarcaChip`.
    ///   - esfuerzo: numeral ya formateado («12»); `nil` = «—» (sin `/21`).
    ///   - origen: sello de procedencia importada; `nil` = sesión nacida en Cénit.
    ///   - onTap: navegación al detalle rico.
    public init(family: EntrenarFamily, nombre: String, meta: String,
                marcas: Int = 0, esfuerzo: String? = nil, origen: String? = nil,
                onTap: @escaping () -> Void) {
        self.family = family
        self.nombre = nombre
        self.meta = meta
        self.marcas = marcas
        self.esfuerzo = esfuerzo
        self.origen = origen
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
                    nombreText.lineLimit(1).minimumScaleFactor(0.8)
                    if marcas > 0 { EntrenarMarcaChip(marcas) }
                    if let origen { LiquidOrigenBadge(origen, tono: nil) }
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
                    nombreText.fixedSize(horizontal: false, vertical: true)
                    if marcas > 0 { EntrenarMarcaChip(marcas) }
                    if let origen { LiquidOrigenBadge(origen, tono: nil) }
                }
                metaText.fixedSize(horizontal: false, vertical: true)
                datoDerecho
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Piezas

    private var glifo: some View {
        RoutineRegionGlyph(family.glyph, tint: family.tint())
            .frame(width: Metrics.glyph, height: Metrics.glyph)
            .frame(width: Metrics.chip, height: Metrics.chip)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: LiquidRadius.insetTarjeta, style: .continuous))
            .accessibilityHidden(true)
    }

    private var nombreText: some View {
        Text(verbatim: nombre)
            .font(LiquidType.tituloGemela)
            .foregroundStyle(LiquidColor.tinta900)
    }

    private var metaText: some View {
        Text(verbatim: meta)
            .font(LiquidType.filaConteo)
            .foregroundStyle(LiquidColor.tinta500)
    }

    @ViewBuilder private var datoDerecho: some View {
        if let esfuerzo {
            (Text(verbatim: esfuerzo)
                .font(LiquidType.valorS)
                .foregroundStyle(LiquidColor.atencionTexto)
             + Text(verbatim: "/21")
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500))
        } else {
            Text(verbatim: "—")
                .font(LiquidType.valorS)
                .foregroundStyle(LiquidColor.tinta500)
        }
    }

    private var a11yLabel: Text {
        let dato = esfuerzo.map { "\($0) /21" } ?? "—"
        let origenTxt = origen.map { ". \($0)" } ?? ""
        return Text("Strength")
            + Text(verbatim: ". ")
            + Text(family.label)
            + Text(verbatim: ". \(nombre)\(origenTxt). \(meta). \(dato)")
    }
}

private enum Metrics {
    static let chip: CGFloat = 38
    static let glyph: CGFloat = 22
}

#if DEBUG
#Preview("EntrenarFilaFuerza · con marca y esfuerzo") {
    EntrenarFilaFuerza(family: .push, nombre: "Empuje A",
                       meta: "vie 10 jul · 48 min · 4.320 kg",
                       marcas: 2, esfuerzo: "14", onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaFuerza · sin marca") {
    EntrenarFilaFuerza(family: .pull, nombre: "Jalón B",
                       meta: "mié 8 jul · 41 min · 3.640 kg",
                       marcas: 0, esfuerzo: "11", onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaFuerza · sin esfuerzo") {
    EntrenarFilaFuerza(family: .legs, nombre: "Pierna",
                       meta: "lun 6 jul · 55 min",
                       marcas: 1, esfuerzo: nil, onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
}

#Preview("EntrenarFilaFuerza · AX5") {
    EntrenarFilaFuerza(family: .fullBody, nombre: "Cuerpo completo",
                       meta: "dom 5 jul · 62 min · 5.100 kg",
                       marcas: 3, esfuerzo: "16", onTap: {})
        .padding(.horizontal, LiquidSpace.s400)
        .background(LiquidColor.fondoGradient)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
