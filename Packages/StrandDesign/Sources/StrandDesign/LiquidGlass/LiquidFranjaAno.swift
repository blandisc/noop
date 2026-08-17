import SwiftUI

// MARK: - Liquid Glass · La franja del año (365 días en una tira)
//
// La tira de un año: columnas = semanas (lunes arriba), filas = días de la semana. Cada celda
// se tiñe con el TONO de la métrica según la intensidad de ese día; el día sin lectura va en
// track neutro (nunca el tono al 0 %, que mentiría diciendo «medí y salió mínimo»).
//
// Port de `YearHeatStrip` (§9.4) con tokens Liquid puros y su MISMA geometría de papel
// (celda 12 · separación 3 · radio 2.5 · gutter 24 · renglón de meses 10). La consumen
// Recuperación y Esfuerzo, debajo del calendario de 90 días.
//
// Tres cosas del papel NO se heredan, a propósito:
//  1. El hover (`onContinuousHover`) y su tooltip — muertos en táctil, y el tooltip del papel
//     tiene la palabra «recovery» clavada aunque el componente sirva para cualquier métrica.
//     Esta franja es de LECTURA: no es un instrumento, no tiene gestos.
//  2. El toque celda por celda: 365 celdas no son navegables una por una. La franja es UN SOLO
//     elemento de accesibilidad con label + value que resume el año («248 de 365 días con
//     lectura, media 61»). Quien quiera tocar un día usa el calendario de 90 días, que sí lo es.
//  3. Los defaults del papel apuntan a `InstrumentoTheme.base.*`. Aquí no existe ningún theme:
//     el tono entra por prop y todo lo demás sale de `LiquidColor`.
//
// ── Estrategia de escalado ────────────────────────────────────────────────────────────────
// «El año manda; la celda cede, y el gutter cede antes que el año.» Un año recortado es un año
// que miente, así que la franja NUNCA corta columnas: mide el ancho disponible y comprime.
//
//  a) La celda se resuelve para que las 53 columnas quepan en el ancho medido, y la separación
//     baja CON ella manteniendo la razón del papel (12:3 = 4:1). Comprimir solo la celda dejaría
//     gaps más anchos que los cuadros — un matriz de puntos, no una franja de calor.
//  b) La celda queda acotada a 2…12 pt: nunca más grande que el papel (una iPad no infla los
//     cuadros), nunca por debajo de 2 pt. A 320 pt de ancho la celda cae en ≈4.4 pt, muy por
//     encima del piso; el piso solo mordería en anchos absurdos (<160 pt).
//  c) El gutter de días (24 pt) solo se dibuja si su renglón queda legible — celda ≥ 9 pt — y
//     nunca en tallas de accesibilidad, donde su caja no puede sostener el texto. Al soltarlo,
//     el año se queda con esos 27 pt y la celda crece. El gutter es chrome; el año es el dato.
//  d) El radio de la celda escala con ella (misma razón 2.5:12), para que un cuadro comprimido
//     no se vuelva un círculo.
//
// Por eso NO se mete en un `ScrollView(.horizontal)` (que es como el papel resolvía el ancho):
// la franja ya cabe sola, y dentro de un scroll horizontal solo vería el ancho del viewport.
//
// Contrato: `dias` ya viene ordenado y contiguo, `intensidad` ya viene NORMALIZADA 0…1 (el
// caller conoce su escala: recovery /100, strain /21), y las etiquetas de mes ya vienen
// localizadas («E» «F» «M»…). Aquí no se formatea copy ni se consulta repo.

public struct LiquidFranjaAno: View {

    /// Un día de la franja: su fecha (que decide en qué columna/fila cae) y su intensidad
    /// NORMALIZADA 0…1. `nil` = sin lectura ese día → track neutro, no tono.
    public struct Dia: Sendable {
        public let fecha: Date
        /// 0…1 ya normalizada por el caller. Fuera de rango se clampa; `nil`/NaN = sin dato.
        public let intensidad: Double?

        public init(fecha: Date, intensidad: Double?) {
            self.fecha = fecha
            self.intensidad = intensidad
        }
    }

    /// Una marca de mes en el renglón superior. `indice` es el índice DENTRO de `dias` del
    /// primer día de ese mes (el componente lo traduce a su columna); `etiqueta` es el rótulo
    /// YA localizado y ya abreviado por el caller («E», «F», «M»…). A los anchos de teléfono
    /// una columna mide ≈5 pt, así que quien pase «ENE» verá los meses tocarse: la abreviación
    /// es decisión del caller, y la corta es la que cabe.
    public struct MarcaMes: Sendable {
        public let indice: Int
        public let etiqueta: String

        public init(indice: Int, etiqueta: String) {
            self.indice = indice
            self.etiqueta = etiqueta
        }
    }

    private let dias: [Dia]
    private let tono: Color
    private let meses: [MarcaMes]
    private let a11yLabel: String
    private let a11yValue: String

    /// Ancho medido del contenedor. 0 = todavía sin medir → la franja se dibuja al tamaño
    /// natural del papel y se re-acomoda en el siguiente paso (mismo comportamiento que
    /// `Calendario90`, que arranca con su celda de 14).
    @State private var anchoDisponible: CGFloat = 0

    /// En tallas de accesibilidad el gutter de días se suelta: su caja de 24 × celda no puede
    /// sostener texto AX sin recortarlo, y la voz de la franja ya vive en `a11yValue`.
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public init(dias: [Dia], tono: Color, meses: [MarcaMes], a11yLabel: String, a11yValue: String) {
        self.dias = dias
        self.tono = tono
        self.meses = meses
        self.a11yLabel = a11yLabel
        self.a11yValue = a11yValue
    }

    // MARK: Geometría interna (la del papel, `YearHeatStrip`)
    //
    // No son tokens de `LiquidSpace`/`LiquidRadius`: son la retícula de ESTE componente, portada
    // 1:1 del papel para que la franja y el calendario de 90 días lean como la misma familia.

    /// 12 — lado de la celda a tamaño natural, y también su TECHO (nunca crece más).
    static let celdaBase: CGFloat = 12
    /// 2 — piso absoluto de la celda. Por debajo la franja dejaría de leerse como días.
    static let celdaMinima: CGFloat = 2
    /// 4 — razón celda:separación del papel (12:3). La separación se deriva de la celda para
    /// que al comprimir no se invierta la jerarquía (gap más ancho que el cuadro).
    static let razonSeparacion: CGFloat = 4
    /// 2.5 : 12 — razón radio:celda del papel; el radio escala con la celda.
    static let razonRadio: CGFloat = 2.5 / 12
    /// 24 — ancho del gutter con las iniciales de los días.
    static let anchoGutter: CGFloat = 24
    /// 9 — celda mínima para que el gutter sea legible: dos renglones (celda + sep + celda ≈
    /// 20 pt) tienen que sostener una línea de ~14 pt. Por debajo, el gutter se suelta.
    static let celdaMinimaGutter: CGFloat = 9
    /// 10 — alto del renglón de marcas de mes.
    static let altoMes: CGFloat = 10
    /// 0.5 — hairline del borde de una celda SIN dato. No se comprime: por debajo de 0.5 pt
    /// un trazo deja de existir en pantalla.
    private let bordeCeldaVacia: CGFloat = 0.5

    /// 0.20 — alfa piso del tono: un día MEDIDO en el mínimo sigue leyéndose como dato. El
    /// rango 0.20…1.00 es el del heatmap de apego ya en producción (`DietCaptureView`:
    /// `opacity(0.20 + 0.80 * score/100)`), adoptado aquí para que las dos rejillas de calor
    /// del app tengan la misma rampa.
    static let alfaPiso: Double = 0.20
    /// 1.00 — alfa techo: el día más intenso del año va a tono pleno.
    static let alfaTecho: Double = 1.00

    // MARK: Rejilla (semanas empezando en lunes — paridad `YearHeatStrip`)

    /// Calendario gregoriano con la semana empezando en LUNES, como el papel. Se construye una
    /// vez por pasada de layout y se pasa a mano, en vez de recrearlo por día.
    static func calendarioSemanal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// Fila de la celda: `weekday` de Foundation (1 = domingo … 7 = sábado) mapeado a
    /// lunes-primero 0…6.
    static func filaSemana(_ fecha: Date, _ cal: Calendar) -> Int {
        (cal.component(.weekday, from: fecha) + 5) % 7
    }

    /// Reparte los días en columnas de 7 filas y, de paso, deja el mapa índice → columna que
    /// las marcas de mes necesitan para saber sobre qué columna se paran. La primera semana se
    /// rellena con huecos hasta que el primer día cae en su fila (paridad `buildWeeks`).
    static func rejilla(_ dias: [Dia]) -> (semanas: [[Dia?]], columnaPorIndice: [Int]) {
        guard !dias.isEmpty else { return ([], []) }
        let cal = calendarioSemanal()
        var semanas: [[Dia?]] = []
        var actual = [Dia?](repeating: nil, count: 7)
        var columnaPorIndice = [Int](repeating: 0, count: dias.count)
        // Padding de la primera semana: las filas anteriores al primer día ya cuentan como
        // «llenas», para que un lunes inicial no dispare un corte de columna en falso.
        var llenas = filaSemana(dias[0].fecha, cal)

        for (i, dia) in dias.enumerated() {
            let fila = filaSemana(dia.fecha, cal)
            if fila == 0 && llenas > 0 {
                semanas.append(actual)
                actual = [Dia?](repeating: nil, count: 7)
                llenas = 0
            }
            actual[fila] = dia
            columnaPorIndice[i] = semanas.count
            llenas += 1
        }
        if llenas > 0 { semanas.append(actual) }
        return (semanas, columnaPorIndice)
    }

    /// Cuántas columnas de semana ocupa este conjunto de días. Es el MISMO recorrido que dibuja
    /// la franja, no una fórmula paralela: así el marco y la rejilla no pueden discrepar.
    /// (Para un año contiguo coincide con `ceil((primeraFila + total) / 7)`, la fórmula del
    /// papel — hay una prueba que lo amarra.)
    public static func columnas(para dias: [Dia]) -> Int {
        rejilla(dias).semanas.count
    }

    // MARK: Medidas (la resolución de layout — una sola, compartida con las pruebas)

    /// El resultado de resolver la franja contra un ancho medido.
    public struct Medidas: Sendable {
        public let columnas: Int
        public let celda: CGFloat
        public let separacion: CGFloat
        /// ¿Se dibuja el gutter de iniciales de día?
        public let conGutter: Bool
        /// Ancho y alto que la franja va a ocupar de verdad.
        public let ancho: CGFloat
        public let alto: CGFloat
    }

    static func separacion(para celda: CGFloat) -> CGFloat { celda / razonSeparacion }

    /// La celda que hace caber `columnas` columnas (más el gutter, si va) en `ancho`,
    /// manteniendo la razón celda:separación. Con `ancho == 0` (aún sin medir) devuelve el
    /// tamaño natural del papel.
    ///
    /// Despeje, con s = c/4:
    ///   con gutter: ancho = (gutter + s) + n·(c + s) − s = gutter + n·c·1.25
    ///   sin gutter: ancho = n·(c + s) − s = c·(n·1.25 − 0.25)
    static func celda(paraAncho ancho: CGFloat, columnas: Int, conGutter: Bool) -> CGFloat {
        guard columnas > 0, ancho > 0 else { return celdaBase }
        let n = CGFloat(columnas)
        let k = 1 / razonSeparacion
        let libre = conGutter ? ancho - anchoGutter : ancho
        let divisor = conGutter ? n * (1 + k) : n * (1 + k) - k
        guard divisor > 0, libre > 0 else { return celdaMinima }
        return min(celdaBase, max(celdaMinima, libre / divisor))
    }

    /// Resuelve TODA la geometría para un ancho medido. La usa el `body` y la verifican las
    /// pruebas — una sola fuente, para que «cabe en el test» y «cabe en pantalla» sean lo mismo.
    ///
    /// El gutter se decide con la celda calculada CON gutter (no con la de después de soltarlo):
    /// así la decisión es monótona y no oscila entre las dos configuraciones.
    static func medidas(columnas: Int, ancho: CGFloat, gutterPermitido: Bool, conMeses: Bool) -> Medidas {
        let cabeElGutter = gutterPermitido
            && celda(paraAncho: ancho, columnas: columnas, conGutter: true) >= celdaMinimaGutter
        let c = celda(paraAncho: ancho, columnas: columnas, conGutter: cabeElGutter)
        let s = separacion(para: c)
        let origenX = cabeElGutter ? anchoGutter + s : 0
        let origenY = conMeses ? altoMes + s : 0
        let n = CGFloat(max(0, columnas))
        let w = columnas > 0 ? origenX + n * (c + s) - s : 0
        let h = columnas > 0 ? origenY + 7 * (c + s) - s : 0
        return Medidas(columnas: columnas, celda: c, separacion: s, conGutter: cabeElGutter,
                       ancho: w, alto: h)
    }

    // MARK: Tono

    /// Alfa del tono para una intensidad normalizada 0…1, o `nil` cuando no hay lectura (y
    /// entonces no hay tono que pintar: la celda va en track neutro).
    ///
    /// El piso de 0.20 es deliberado: sin él, un día medido en el mínimo saldría transparente
    /// y se confundiría con el hueco. Sin dato ≠ tono al 0 %.
    public static func alfa(_ intensidad: Double?) -> Double? {
        guard let intensidad, intensidad.isFinite else { return nil }
        let k = min(1, max(0, intensidad))
        return alfaPiso + (alfaTecho - alfaPiso) * k
    }

    // MARK: Cuerpo

    public var body: some View {
        let rejilla = Self.rejilla(dias)
        let m = Self.medidas(columnas: rejilla.semanas.count,
                             ancho: anchoDisponible,
                             gutterPermitido: !tamanoTexto.isAccessibilitySize,
                             conMeses: !meses.isEmpty)
        let etiquetas = Self.etiquetasPorColumna(meses: meses,
                                                 columnaPorIndice: rejilla.columnaPorIndice,
                                                 columnas: m.columnas)

        VStack(alignment: .leading, spacing: m.separacion) {
            // Sin días no hay franja: ni renglón de meses ni gutter sueltos sobre un marco de 0.
            if m.columnas > 0 {
                if !meses.isEmpty { renglonMeses(m, etiquetas: etiquetas) }
                HStack(alignment: .top, spacing: m.separacion) {
                    if m.conGutter { gutterDias(m) }
                    ForEach(0..<m.columnas, id: \.self) { columna in
                        VStack(spacing: m.separacion) {
                            ForEach(0..<7, id: \.self) { fila in
                                celdaVista(rejilla.semanas[columna][fila], m)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: m.ancho, height: m.alto, alignment: .topLeading)
        // El marco de arriba fija la franja a su tamaño dibujado; este segundo marco es el que
        // se deja medir — mide el CONTENEDOR, no la rejilla, que es lo que hay que repartir.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: LiquidFranjaAnoAnchoKey.self, value: g.size.width)
        })
        .onPreferenceChange(LiquidFranjaAnoAnchoKey.self) { anchoDisponible = $0 }
        // Un año no se navega celda por celda: la franja habla una sola vez, con el resumen
        // que el caller ya redactó.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11yValue))
    }

    /// Marca de mes → columna. Si dos meses caen en la misma columna gana el primero (el que
    /// se lee antes); los índices fuera de `dias` se ignoran en vez de reventar.
    static func etiquetasPorColumna(meses: [MarcaMes], columnaPorIndice: [Int],
                                    columnas: Int) -> [Int: String] {
        var mapa: [Int: String] = [:]
        for marca in meses {
            guard marca.indice >= 0, marca.indice < columnaPorIndice.count else { continue }
            let columna = columnaPorIndice[marca.indice]
            guard columna < columnas, mapa[columna] == nil else { continue }
            mapa[columna] = marca.etiqueta
        }
        return mapa
    }

    /// Renglón de marcas de mes. Va en tinta terciaria y NUNCA teñido: es el eje, no el dato.
    /// Tipo `caption` (10.5, tamaño fijo): es chrome de eje — una rejilla de 53 columnas no
    /// puede escalar con Dynamic Type sin dejar de ser un año, y la lectura accesible de la
    /// franja vive en su `accessibilityValue`, no en estas iniciales.
    private func renglonMeses(_ m: Medidas, etiquetas: [Int: String]) -> some View {
        HStack(spacing: m.separacion) {
            if m.conGutter { Color.clear.frame(width: Self.anchoGutter, height: Self.altoMes) }
            ForEach(0..<m.columnas, id: \.self) { columna in
                Text(verbatim: etiquetas[columna] ?? "")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize()
                    .frame(width: m.celda, height: Self.altoMes, alignment: .leading)
            }
        }
    }

    /// Iniciales de día (lunes / miércoles / viernes / domingo; los renglones pares quedan en
    /// blanco para que cada rótulo tenga aire). Salen de los símbolos del sistema, no de copy
    /// del app: `shortWeekdaySymbols` está indexado desde el DOMINGO en toda configuración
    /// regional, así que se eligen a mano 1/3/5/0 — las filas son lunes-primero.
    private func gutterDias(_ m: Medidas) -> some View {
        let s = Calendar.current.shortWeekdaySymbols
        let filas: [String] = s.count == 7 ? [s[1], "", s[3], "", s[5], "", s[0]]
                                           : Array(repeating: "", count: 7)
        return VStack(alignment: .trailing, spacing: m.separacion) {
            ForEach(0..<7, id: \.self) { fila in
                Text(verbatim: filas[fila])
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize()
                    .frame(width: Self.anchoGutter, height: m.celda, alignment: .trailing)
            }
        }
    }

    /// Tres celdas posibles: con lectura (tono a su alfa), en rango pero sin lectura (track
    /// neutro con hairline — el hueco se ve, no se esconde), y fuera de rango (nada).
    @ViewBuilder
    private func celdaVista(_ dia: Dia?, _ m: Medidas) -> some View {
        let forma = RoundedRectangle(cornerRadius: m.celda * Self.razonRadio, style: .continuous)
        if let dia, let alfa = Self.alfa(dia.intensidad) {
            forma
                .fill(tono.opacity(alfa))
                .frame(width: m.celda, height: m.celda)
        } else if dia != nil {
            forma
                .fill(LiquidColor.tinta10)
                .overlay(forma.stroke(LiquidColor.tinta7, lineWidth: bordeCeldaVacia))
                .frame(width: m.celda, height: m.celda)
        } else {
            forma
                .fill(Color.clear)
                .frame(width: m.celda, height: m.celda)
        }
    }
}

/// Ancho del contenedor de la franja — lo que hay que repartir entre las 53 columnas.
private struct LiquidFranjaAnoAnchoKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG

/// Un año de muestra terminado hoy: onda suave con huecos regulares, ya normalizada 0…1.
/// `sinDatoDesde` deja en blanco los primeros N días (el año a medias).
private func muestraFranjaAno(sinDatoDesde primeros: Int = 0, todoVacio: Bool = false)
    -> [LiquidFranjaAno.Dia] {
    let cal = Calendar.current
    let hoy = Date()
    return (0..<365).map { i in
        let fecha = cal.date(byAdding: .day, value: -(364 - i), to: hoy)!
        if todoVacio || i < primeros || i % 23 == 0 {
            return LiquidFranjaAno.Dia(fecha: fecha, intensidad: nil)
        }
        let onda = 0.28 * sin(Double(i) / 11.0)
        let ruido = Double((i * 31) % 17) / 100.0 - 0.08
        return LiquidFranjaAno.Dia(fecha: fecha, intensidad: 0.55 + onda + ruido)
    }
}

/// Marcas de mes de una muestra: la inicial del mes en el índice donde el mes cambia.
private func muestraMesesFranja(_ dias: [LiquidFranjaAno.Dia]) -> [LiquidFranjaAno.MarcaMes] {
    let iniciales = ["E", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
    let cal = Calendar.current
    var marcas: [LiquidFranjaAno.MarcaMes] = []
    var ultimo = -1
    for (i, dia) in dias.enumerated() {
        let mes = cal.component(.month, from: dia.fecha)
        if mes != ultimo {
            marcas.append(.init(indice: i, etiqueta: iniciales[mes - 1]))
            ultimo = mes
        }
    }
    return marcas
}

private func muestraFranjaVista(_ dias: [LiquidFranjaAno.Dia], _ valor: String) -> some View {
    LiquidFranjaAno(dias: dias,
                    tono: LiquidColor.verdePrimario,
                    meses: muestraMesesFranja(dias),
                    a11yLabel: "Recuperación, último año",
                    a11yValue: valor)
        .padding(LiquidSpace.s550)
        .frame(width: 390)
        .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
}

#Preview("Franja · año completo") {
    let dias = muestraFranjaAno()
    return muestraFranjaVista(dias, "349 de 365 días con lectura, media 61")
}

/// Año a medias: solo los últimos 4 meses traen lectura. Los días previos NO se borran —
/// se dibujan como hueco, que es la verdad («no medí»), no como si el año empezara en agosto.
#Preview("Franja · año a medias") {
    let dias = muestraFranjaAno(sinDatoDesde: 243)
    return muestraFranjaVista(dias, "112 de 365 días con lectura, media 58")
}

/// Sin una sola lectura: el año conserva su forma en track neutro. Nunca el tono al 0 %.
#Preview("Franja · vacía") {
    let dias = muestraFranjaAno(todoVacio: true)
    return muestraFranjaVista(dias, "Sin lecturas en el último año")
}

/// Talla de accesibilidad: el gutter de días se suelta (su caja no sostiene texto AX) y el año
/// se queda con ese ancho. La franja sigue siendo UN elemento de VoiceOver con su resumen.
#Preview("Franja · AX") {
    let dias = muestraFranjaAno()
    return muestraFranjaVista(dias, "349 de 365 días con lectura, media 61")
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
