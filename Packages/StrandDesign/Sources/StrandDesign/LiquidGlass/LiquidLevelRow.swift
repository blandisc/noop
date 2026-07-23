import SwiftUI

// MARK: - Liquid Glass · Fila de nivel (épico hoja de resumen, F3b)
//
// La fila TOCABLE de la lista de niveles del explorador (contrato
// docs/design-system/LIQUID-SHEET-CONTRACT.md §3 F3b): punto + etiqueta + rango + conteo,
// con la fila activa iluminada al 12 % del tono (I1, mismo rango 10-16 % que
// `LiquidBandsTable`) y el nivel de HOY marcado con anillo hueco mientras exploras otro
// (paridad `MetricLevelsExplorer:231-237`). Tocar dispara `onTap` — el caller alterna la
// selección y resalta la banda en la gráfica.
//
// Contrato D3: strings YA localizados/formateados («En tu base», «49–71», «12 días»);
// el DS no conoce `MetricLevels` ni locales. `a11yHint` viene del caller por la misma
// regla (el DS no puede acuñar copy).

public struct LiquidLevelRow: View {
    private let etiqueta: String
    private let rango: String
    private let conteo: String
    private let esHoy: Bool
    private let activa: Bool
    private let tono: Color
    private let a11yHint: String?
    private let onTap: () -> Void

    public init(etiqueta: String, rango: String, conteo: String,
                esHoy: Bool, activa: Bool, tono: Color,
                a11yHint: String? = nil, onTap: @escaping () -> Void) {
        self.etiqueta = etiqueta
        self.rango = rango
        self.conteo = conteo
        self.esHoy = esHoy
        self.activa = activa
        self.tono = tono
        self.a11yHint = a11yHint
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: LiquidSpace.s300) {
                punto
                Text(verbatim: etiqueta)
                    .font(LiquidType.cuerpo)
                    .fontWeight(activa ? .semibold : .regular)
                    .foregroundStyle(activa ? LiquidColor.tinta900 : LiquidColor.tinta700)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: rango)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(activa ? tono : LiquidColor.tinta500)
                Text(verbatim: conteo)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(activa ? tono : LiquidColor.tinta500)
                    .frame(minWidth: 50, alignment: .trailing)
            }
            .padding(.horizontal, LiquidSpace.s400)
            .padding(.vertical, LiquidSpace.s300)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            // I1 en la lista: la fila activa se ilumina con el tono (rango 10-16 % del épico).
            .background(activa ? tono.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(activa ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text(verbatim: a11yHint ?? ""))
    }

    /// El punto del nivel: lleno del tono cuando la fila está activa; ANILLO hueco cuando es
    /// el nivel de hoy pero exploras otro (paridad del dot del explorador); tenue si no.
    @ViewBuilder private var punto: some View {
        if esHoy && !activa {
            Circle().strokeBorder(tono, lineWidth: 2).frame(width: 8, height: 8)
        } else {
            Circle().fill(activa ? tono : LiquidColor.tinta10).frame(width: 8, height: 8)
        }
    }
}

#if DEBUG
#Preview("Liquid · LevelRow") {
    VStack(spacing: 0) {
        LiquidLevelRow(etiqueta: "Alto", rango: "≥ 71", conteo: "4 días",
                       esHoy: false, activa: false, tono: LiquidColor.cian, onTap: {})
        Rectangle().fill(LiquidColor.tinta10).frame(height: 1)
            .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
        // Activa (la que exploras): wash del tono + texto en tinta/900.
        LiquidLevelRow(etiqueta: "En tu base", rango: "49–71", conteo: "12 días",
                       esHoy: false, activa: true, tono: LiquidColor.cian, onTap: {})
        Rectangle().fill(LiquidColor.tinta10).frame(height: 1)
            .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
        // Hoy, mientras exploras otro nivel: anillo hueco.
        LiquidLevelRow(etiqueta: "Bajo", rango: "< 49", conteo: "2 días",
                       esHoy: true, activa: false, tono: LiquidColor.cian, onTap: {})
    }
    .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
    .liquidGlass(.superficie)
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}
#endif
