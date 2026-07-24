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
    public static let endpointRadio: CGFloat = 3.6   // > puntoDatoRadio 3.0 (pasada UI H5: la jerarquía estaba invertida)
    /// Grosor del borde de la joya del endpoint. El COLOR es `LiquidColor.papelAlto` (el
    /// papel del contenedor), el mismo del anillo del scrub y del anillo de «hoy» — nunca
    /// blanco duro.
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
    /// Diámetro de la gota de color del popup del scrub (tiñe la BANDA del punto, mismo
    /// resolver que el anillo — el popup explica el color que ves).
    public static let popupPuntoDiametro: CGFloat = 7

    // MARK: Eje X (fila de fechas bajo el plot)

    /// Alto de la franja reservada BAJO el área de datos para la fila de fechas.
    /// 22 = caja de línea de `LiquidType.unidadCompacta` (≈12.5) + respiro arriba y abajo;
    /// con 18 el descendente se colaba al bloque siguiente (el plot no clipa).
    /// El eje va DENTRO del alto nominal de la gráfica: si creciera el total, `.datos`
    /// mediría distinto que `.vacio`/`.cargando` y la hoja brincaría al cargar.
    /// DECISIÓN (revote /inject): la etiqueta del eje es CHROME GEOMÉTRICO y NO escala con
    /// Dynamic Type — misma voz y misma exención que los labels del eje Y, que ya usan
    /// `unidadCompacta`. La lectura accesible la sirve el `accessibilityValue` de la
    /// gráfica, que sí escala sin tope.
    public static let ejeXAlto: CGFloat = 22

    // MARK: Puntos por dato

    /// Radio del disco que marca cada muestra cuando la serie es corta.
    public static let puntoDatoRadio: CGFloat = 3.0   // 2.2 → 3.0 (pedido del dueño: más peso)
    /// Hueco mínimo VISIBLE entre los BORDES de dos discos vecinos. Es lo que separa «una
    /// ventana contable» de «una tira de discos pegados»: por debajo de esto el ojo deja de
    /// distinguir cuántas lecturas hay y el disco pasa de dato a textura.
    public static let puntoDatoHueco: CGFloat = 3
    /// Distancia mínima entre CENTROS, en puntos (no en múltiplos del radio): dos radios +
    /// el hueco. Se expresa así a propósito — el gate viejo era `radio * 4`, atado al radio,
    /// así que cuando el dueño subió el radio de 2.2 a 3.0 el corte se movió solo de n≈34 a
    /// n≈26 y la ventana «M» (30 lecturas) perdió sus discos sin que nadie lo pidiera.
    public static var puntoDatoSeparacion: CGFloat { puntoDatoRadio * 2 + puntoDatoHueco }
    /// Tope de muestras para dibujar un disco por dato.
    /// INVARIANTE: debe quedar POR DEBAJO del tope de decimación del caller (80 puntos,
    /// `MetricWindowMath.decimatedPoints`). Los discos hacen CONTABLE la ventana; si la
    /// serie viene decimada, el usuario contaría 7 discos donde la fila de nivel afirma
    /// «9 noches». Subir este número sin subir el tope de decimación vuelve la hoja
    /// mentirosa en silencio.
    /// OJO: en un iPhone real NUNCA es este número el que muerde. Con ~300 pt de plot útil
    /// y `puntoDatoSeparacion` = 9, la geometría corta en n≈34: 60 es el techo de honestidad
    /// (decimación), no el límite operativo. Quien lea «60» aquí y espere ver 60 discos se
    /// equivoca — manda `hayEspacioParaPuntos(centros:)`.
    public static let puntoDatoUmbral: Int = 60
    /// Alfa de los puntos FUERA de la banda activa (paridad `GraficaRangos`: el punto
    /// acompaña al wash, nunca compite con él — I1 se juega en 13 puntos de alfa).
    public static let puntoApagadoAlfa: Double = 0.25
    /// Escala del radio de esos mismos puntos apagados.
    public static let puntoApagadoEscala: CGFloat = 0.7

    /// ¿Cabe un disco por muestra? Dos condiciones, las dos del mismo invariante («la
    /// ventana tiene que quedar CONTABLE»): que la serie no venga decimada
    /// (`puntoDatoUmbral`) y que ningún par de discos vecinos se toque.
    ///
    /// La separación se mide sobre los CENTROS YA CALCULADOS, no sobre el promedio
    /// `plotW / (n − 1)`: las tres gráficas de la familia reparten por TIEMPO real
    /// (`mapeoPorTiempo`), así que en una serie con huecos —12 lecturas en 90 días— el
    /// promedio dice «27 pt de aire» mientras dos lecturas de días consecutivos caen a 3 pt
    /// una de otra. Con el promedio, esos dos discos se dibujaban encimados y el usuario
    /// contaba 11 donde la fila de nivel afirmaba 12; medir el paso MÍNIMO prefiere no
    /// dibujar ninguno a dibujar una cuenta falsa.
    static func hayEspacioParaPuntos(centros: [CGFloat]) -> Bool {
        guard centros.count > 1, centros.count <= puntoDatoUmbral else { return false }
        var minPaso = CGFloat.greatestFiniteMagnitude
        for i in centros.indices.dropFirst() {
            minPaso = Swift.min(minPaso, abs(centros[i] - centros[i - 1]))
        }
        return minPaso >= puntoDatoSeparacion
    }

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
                .overlay(Circle().strokeBorder(LiquidColor.papelAlto,
                                               lineWidth: LiquidChart.endpointBorde))
                .frame(width: LiquidChart.endpointRadio * 2,
                       height: LiquidChart.endpointRadio * 2)
                .offset(x: 217, y: 35)
            // Puntos por dato: encendidos en la banda activa, apagados fuera de ella.
            ForEach([0, 1, 2, 3], id: \.self) { (k: Int) in
                let encendido: Bool = k >= 1 && k <= 2
                let r: CGFloat = encendido
                    ? LiquidChart.puntoDatoRadio
                    : LiquidChart.puntoDatoRadio * LiquidChart.puntoApagadoEscala
                Circle().fill(hue)
                    .opacity(encendido ? 1 : LiquidChart.puntoApagadoAlfa)
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: CGFloat(30 + k * 55) - r, y: CGFloat(50 - k * 4) - r)
            }
            LiquidScrubPopup(valor: "56 ms", fecha: "mar 14 jul", color: hue)
                .offset(x: 74, y: 2)
        }
        .frame(width: 220, height: 80)
        .liquidGlass(.superficie)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
