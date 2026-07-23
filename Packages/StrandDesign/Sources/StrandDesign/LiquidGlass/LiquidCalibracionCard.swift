import SwiftUI

// MARK: - Liquid Glass · Tarjeta de calibración (épico hoja de resumen, F4)
//
// El estado «calibrando tu base» de la variante clásica (paridad
// `MetricInfoSheet.calibrationCard` :1141-1163), re-vestido: vidrio/superficie, rótulo +
// leyenda ya localizados y PUNTOS de progreso (uno por noche necesaria; los hechos se
// llenan con el tono de la métrica). Sin animación propia: la calibración es un estado
// quieto — se pinta asentada siempre, con o sin motion.

public struct LiquidCalibracionCard: View {
    private let titulo: String
    private let leyenda: String
    private let hechas: Int
    private let necesarias: Int
    private let tono: Color

    public init(titulo: String, leyenda: String, hechas: Int, necesarias: Int, tono: Color) {
        self.titulo = titulo
        self.leyenda = leyenda
        self.hechas = hechas
        self.necesarias = necesarias
        self.tono = tono
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                Text(verbatim: titulo)
                    .liquidLabel()
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: leyenda)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta700)
            }
            HStack(spacing: LiquidSpace.s200) {
                ForEach(0..<max(necesarias, 1), id: \.self) { i in
                    Circle()
                        .fill(i < hechas ? tono : LiquidColor.tinta10)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficie)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(titulo), \(leyenda)"))
    }
}

#if DEBUG
#Preview("Liquid · CalibracionCard") {
    VStack(spacing: LiquidSpace.s400) {
        LiquidCalibracionCard(titulo: "Calibrando tu base",
                              leyenda: "2 de 4 noches",
                              hechas: 2, necesarias: 4,
                              tono: LiquidColor.verdePrimario)
        LiquidCalibracionCard(titulo: "Calibrando tu base",
                              leyenda: "0 de 7 noches",
                              hechas: 0, necesarias: 7,
                              tono: LiquidColor.cian)
        LiquidCalibracionCard(titulo: "Calibrando tu base",
                              leyenda: "6 de 7 noches",
                              hechas: 6, necesarias: 7,
                              tono: LiquidColor.ambar)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo())
    .environment(\.liquidMotionDisabled, true)
}
#endif
