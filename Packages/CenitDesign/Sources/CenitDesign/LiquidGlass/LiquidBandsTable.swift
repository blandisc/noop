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
        /// Eco visual del scrub tabla↔gráfica: wash tenue del tono (más suave que `activa`).
        /// Si `activa && resaltada`, gana `activa`. No altera VoiceOver (el scrub se narra
        /// en la gráfica).
        public let resaltada: Bool
        /// Label COMPUESTO de VoiceOver para la fila, YA localizado. Sin él, la fila se lee
        /// con `.combine` (etiqueta, rango, conteo) — que no dice si la fila está ACTIVA:
        /// el wash de color es la única señal, y el color no habla. Los callers cuyo estado
        /// activo significa algo (p. ej. «fuera de tu rango») lo pasan explícito.
        public let a11y: String?

        public init(etiqueta: String, rango: String, conteo: String? = nil,
                    activa: Bool = false, resaltada: Bool = false, a11y: String? = nil) {
            self.etiqueta = etiqueta
            self.rango = rango
            self.conteo = conteo
            self.activa = activa
            self.resaltada = resaltada
            self.a11y = a11y
        }
    }

    private let filas: [Fila]
    private let tono: Color

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// La etiqueta escala con Dynamic Type como su rango y su conteo (`captionLectura`,
    /// relativo a `.caption2`). Con el `LiquidType.cuerpo` fijo de antes, a tamaños AX el
    /// nombre de la banda terminaba MÁS CHICO que el número que lo acompaña.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = LiquidType.cuerpoLecturaBase

    public init(filas: [Fila], tono: Color) {
        self.filas = filas
        self.tono = tono
    }

    /// A tamaños de ACCESIBILIDAD la fila deja de ser cuatro columnas y se apila en dos
    /// renglones (nombre arriba; rango + conteo abajo, sangrados tras el punto). Con cuatro
    /// columnas de texto en 402 pt, AX1+ aplasta o trunca — y `Spacer(minLength:)` solo
    /// reparte el daño. Mismo espíritu que el `limiteNumeral` de `LiquidSheetHeader` (B4).
    private var forzarApilada: Bool { tamanoTexto >= .accessibility1 }

    /// El apilado no depende SOLO del tamaño de texto: depende de si el texto cabe.
    ///
    /// Con el umbral en AX, el acta del veredicto ya se rompía en `.large` —el tamaño POR
    /// OMISIÓN— porque sus columnas no son «≥ 71 · 4 días» sino prosa («contra un mínimo
    /// fijo»): una fila envolvía en dos renglones mientras sus hermanas cabían en uno y la
    /// tabla se leía irregular. `ViewThatFits` decide midiendo, y decide para la TABLA
    /// COMPLETA (no fila por fila: filas mezcladas se verían peor que cualquiera de las dos
    /// formas). El umbral AX se conserva encima porque el arnés de renders corre en macOS,
    /// donde las fuentes no escalan con Dynamic Type y solo esta rama declara la intención.
    public var body: some View {
        if forzarApilada {
            tabla(apilada: true)
        } else {
            ViewThatFits(in: .horizontal) {
                tabla(apilada: false)
                tabla(apilada: true)
            }
        }
    }

    private func tabla(apilada: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { i, fila in
                self.fila(fila, apilada: apilada)
                if i < filas.count - 1 {
                    separador
                }
            }
        }
        // El clip va ANTES del vidrio: el wash de la fila activa respeta las esquinas
        // también en el camino nativo (glassEffect no recorta el contenido).
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
    }

    private func fila(_ f: Fila, apilada: Bool) -> some View {
        Group {
            if apilada {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    HStack(spacing: LiquidSpace.s300) {
                        punto(f)
                        etiqueta(f)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: LiquidSpace.s300) {
                        secundario(f, f.rango)
                        if let conteo = f.conteo { secundario(f, conteo) }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 8 + LiquidSpace.s300)
                }
            } else {
                // Los tres textos van a UNA LÍNEA, sin ceder ancho: así el tamaño de esta
                // rama ES su ancho sin envolver, que es justo lo que `ViewThatFits` mide
                // para decidir si cabe. Sin esto el `Spacer` se llevaba el aire, una fila
                // envolvía «contra un mínimo fijo» en dos renglones mientras sus hermanas
                // cabían en uno, y la rama apilada nunca llegaba a entrar.
                HStack(spacing: LiquidSpace.s300) {
                    punto(f)
                    etiqueta(f).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: LiquidSpace.s200)
                    secundario(f, f.rango)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    if let conteo = f.conteo {
                        secundario(f, conteo)
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 50, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        // I1: activa = wash fuerte; resaltada (scrub eco) = wash tenue; activa gana si ambas.
        .background(washFila(f))
        .accessibilityElement(children: .combine)
        .modifier(LiquidFilaLabel(label: f.a11y))
    }

    /// Wash de la fila: `activa` manda; `resaltada && !activa` es el eco del scrub.
    private func washFila(_ f: Fila) -> Color {
        if f.activa { return tono.opacity(LiquidChart.filaActivaAlfa) }
        if f.resaltada { return tono.opacity(LiquidChart.filaResaltadaAlfa) }
        return Color.clear
    }

    private func punto(_ f: Fila) -> some View {
        Circle()
            .fill(f.activa ? tono : LiquidColor.tinta10)
            .frame(width: 8, height: 8)
    }

    private func etiqueta(_ f: Fila) -> some View {
        Text(verbatim: f.etiqueta)
            // Escala con Dynamic Type como su rango y su conteo (ver `etiquetaPt`).
            .font(.system(size: etiquetaPt))
            .fontWeight(f.activa ? .semibold : .regular)
            .foregroundStyle(f.activa ? LiquidColor.tinta900 : LiquidColor.tinta700)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Rango y conteo. Pasada UI H2 (la MISMA corrección que ya traía su hermano
    /// `LiquidLevelRow:16-18`, que a esta tabla nunca le llegó): con la fila activa NO van
    /// en `tono` — medido, el ámbar de dato (#C4631F) da 3.14:1 sobre el wash al 12 % y
    /// 3.61:1 sobre el papel limpio, y esto es texto de 10.5. El color lo llevan el punto y
    /// el wash; el dato se lee en tinta/900.
    private func secundario(_ f: Fila, _ texto: String) -> some View {
        Text(verbatim: texto)
            .font(LiquidType.captionLectura)
            .monospacedDigit()
            .foregroundStyle(f.activa ? LiquidColor.tinta900 : LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var separador: some View {
        Rectangle()
            .fill(LiquidColor.tinta10)
            .frame(height: 1)
            .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
    }
}

/// Pone el label de VoiceOver de la fila SOLO si el caller lo mandó; sin él se conserva el
/// `.combine` de siempre (ningún caller viejo cambia de voz).
private struct LiquidFilaLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(Text(verbatim: label))
        } else {
            content
        }
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

/// Diálogo tabla↔gráfica: fila resaltada (scrub) vs fila activa (hoy) — washes distintos.
#Preview("Liquid · BandsTable — resaltada vs activa") {
    LiquidBandsTable(
        filas: [
            .init(etiqueta: "Alto", rango: "≥ 71", conteo: "4 días", resaltada: true),
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

/// AX: la fila se apila en dos renglones en vez de aplastar cuatro columnas de texto.
#Preview("Liquid · BandsTable AX") {
    LiquidBandsTable(
        filas: [
            .init(etiqueta: "Autonómico", rango: "En tu rango", conteo: "contra tu base",
                  a11y: "Autonómico, en tu rango, contra tu base"),
            .init(etiqueta: "Sueño", rango: "Debajo de tu base", conteo: "contra un mínimo fijo",
                  activa: true, a11y: "Sueño, debajo de tu base, contra un mínimo fijo, fuera de tu rango"),
            .init(etiqueta: "Térmico", rango: "En tu rango", conteo: "contra la base de Apple",
                  a11y: "Térmico, en tu rango, contra la base de Apple"),
        ],
        tono: LiquidColor.atencion)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.atencion))
        .environment(\.dynamicTypeSize, .accessibility3)
        .environment(\.liquidMotionDisabled, true)
}
#endif
