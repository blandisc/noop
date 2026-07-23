import SwiftUI

// MARK: - Liquid Glass · Tabla de bandas (épico hoja de resumen, F4)
//
// Las filas de referencia bajo el trend clásico (paridad `MetricInfoSheet.bandsTable`
// :786-825): punto + etiqueta + rango + conteo opcional (aparece cuando el trend cargó).
// La fila ACTIVA se ilumina con el tono de la métrica al 12 % y su texto sube a tinta/900;
// separadores en tinta/10 con sangría tras el punto. Strings YA localizados/formateados
// (contrato D3) — el conteo llega compuesto («12 días») desde `BandSummaryCopy` en el app.

public struct LiquidBandsTable: View {

    public struct Fila {
        public let etiqueta: String
        public let rango: String
        public let conteo: String?
        public let activa: Bool

        public init(etiqueta: String, rango: String, conteo: String? = nil, activa: Bool = false) {
            self.etiqueta = etiqueta
            self.rango = rango
            self.conteo = conteo
            self.activa = activa
        }
    }

    private let filas: [Fila]
    private let tono: Color

    public init(filas: [Fila], tono: Color) {
        self.filas = filas
        self.tono = tono
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { i, fila in
                self.fila(fila)
                if i < filas.count - 1 {
                    separador
                }
            }
        }
        // El clip va ANTES del vidrio: el wash de la fila activa respeta las esquinas
        // también en el camino nativo (glassEffect no recorta el contenido).
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficie)
    }

    private func fila(_ f: Fila) -> some View {
        HStack(spacing: LiquidSpace.s300) {
            Circle()
                .fill(f.activa ? tono : LiquidColor.tinta10)
                .frame(width: 8, height: 8)
            Text(verbatim: f.etiqueta)
                .font(LiquidType.cuerpo)
                .fontWeight(f.activa ? .semibold : .regular)
                .foregroundStyle(f.activa ? LiquidColor.tinta900 : LiquidColor.tinta700)
            Spacer(minLength: LiquidSpace.s200)
            Text(verbatim: f.rango)
                .font(LiquidType.captionLectura)
                .monospacedDigit()
                .foregroundStyle(f.activa ? tono : LiquidColor.tinta500)
            if let conteo = f.conteo {
                Text(verbatim: conteo)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(f.activa ? tono : LiquidColor.tinta500)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        // I1 en la tabla: la fila activa se ilumina con el tono (rango 10-16 % del épico).
        .background(f.activa ? tono.opacity(LiquidChart.filaActivaAlfa) : Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var separador: some View {
        Rectangle()
            .fill(LiquidColor.tinta10)
            .frame(height: 1)
            .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
    }
}

#if DEBUG
#Preview("Liquid · BandsTable — activa con conteos") {
    LiquidBandsTable(
        filas: [
            .init(etiqueta: "Alto", rango: "≥ 71", conteo: "4 días"),
            .init(etiqueta: "En tu base", rango: "49–71", conteo: "8 días", activa: true),
            .init(etiqueta: "Bajo", rango: "< 49", conteo: "2 días"),
        ],
        tono: LiquidColor.cian)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · BandsTable — sin conteos (trend cargando) y reposo") {
    VStack(spacing: LiquidSpace.s400) {
        // Sin conteos: el trend aún no carga.
        LiquidBandsTable(
            filas: [
                .init(etiqueta: "Óptimo", rango: "7–9 h", activa: true),
                .init(etiqueta: "Adecuado", rango: "6–7 h"),
                .init(etiqueta: "Corto", rango: "< 6 h"),
            ],
            tono: LiquidColor.indigo)
        // Reposo: sin dato hoy, ninguna fila activa.
        LiquidBandsTable(
            filas: [
                .init(etiqueta: "Óptimo", rango: "7–9 h", conteo: "9 noches"),
                .init(etiqueta: "Adecuado", rango: "6–7 h", conteo: "4 noches"),
                .init(etiqueta: "Corto", rango: "< 6 h", conteo: "1 noche"),
            ],
            tono: LiquidColor.indigo)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
    .environment(\.liquidMotionDisabled, true)
}
#endif
