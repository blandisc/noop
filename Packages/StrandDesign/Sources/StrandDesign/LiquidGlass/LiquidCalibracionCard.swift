import SwiftUI

// MARK: - Liquid Glass · Tarjeta de calibración (épico hoja de resumen, F4)
//
// El estado «calibrando tu base» de la variante clásica (paridad
// `MetricInfoSheet.calibrationCard` :1141-1163), re-vestido: vidrio/superficie, rótulo +
// leyenda ya localizados y una BARRA de progreso — la misma forma que la tarjeta actual
// (revote adversarial F4: los puntos eran rediseño, no re-vestido). Sin animación propia:
// la calibración es un estado quieto — se pinta asentada siempre, con o sin motion.

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
            // Barra de progreso (paridad :1150-1156): pista tenue + relleno del tono.
            // El relleno se pinta SIEMPRE con un mínimo de 6 pt (`s150`), también con
            // `hechas == 0`: el nub es la promesa de que la barra ya empezó a contar —
            // paridad exacta con la vieja (`max(6, …)` sin condicional). `necesarias == 0`
            // no divide entre cero.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(LiquidColor.tinta10).frame(height: LiquidSpace.s150)
                    Capsule().fill(tono)
                        .frame(width: max(LiquidSpace.s150,
                                          geo.size.width * CGFloat(hechas)
                                              / CGFloat(max(necesarias, 1))),
                               height: LiquidSpace.s150)
                }
            }
            .frame(height: LiquidSpace.s150)
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
