import SwiftUI

// MARK: - Liquid Glass · Calendario de 90 días (épico Tendencias Liquid, FER-98)
//
// El calendario teñido de 90 días de las hojas de Tendencias (Recuperación · Sueño · Esfuerzo ·
// Estrés), en vidrio. Es el port de TRES piezas de papel que aquí se vuelven una sola:
//   · `Calendario90` — el envoltorio que MIDE el ancho y dimensiona la celda,
//   · `YearHeatStrip` — la retícula Monday-first (canaleta de días + etiquetas de mes + celdas),
//   · `HeatCalendarSection` + `HeatLegend` — la lectura del día tocado y la leyenda de niveles.
//
// Contrato que cumple (§3 del contrato Liquid): TODO dato llega ya resuelto. En particular
// **este componente no formatea NINGUNA fecha**: la etiqueta de cada día y el rótulo de mes
// llegan como `String` desde el caller. Esa es la corrección de raíz del defecto que dejó a
// `StressDetailScreen` fuera del componente de papel: el formateador interno de
// `HeatCalendarSection` no fija zona horaria, y las pantallas que parsean llaves de día en UTC
// no podían usarlo sin perder su ancla. Aquí no hay formateador que perder.
//
// Diferencias deliberadas con el papel:
//   · el papel tiñe por HUE (el caller devuelve un color de banda por valor); aquí hay UN tono
//     y la INTENSIDAD lo modula en alfa (`alfa(intensidad:)`) — el color sigue siendo el dato;
//   · el papel usa `.onContinuousHover`, que en un iPhone no dispara NUNCA. Aquí el gesto es
//     táctil (`.onTapGesture` por celda), y el mismo toque sobre el día ya seleccionado lo
//     deselecciona;
//   · un día sin lectura se pinta con el track neutro, jamás con el tono al 0 % (si no, un
//     hueco de datos se leería como «tuviste el peor valor posible»).

public struct LiquidCalendario90: View {

    // MARK: - Datos (todo ya resuelto por el caller)

    /// Un día de la ventana. `intensidad` es la ÚNICA fuente de verdad de «hubo lectura»:
    /// `nil` = sin dato, y entonces la celda va al track neutro y la lectura dice «—».
    ///
    /// Sobre `etiqueta` / `valor` / `palabra` — la lectura del día tocado admite DOS formas y
    /// el caller elige una:
    ///   · **compacta**: manda solo `etiqueta` con la línea completa («12 ago · 68») y la
    ///     lectura imprime esa sola línea;
    ///   · **del papel**: manda `etiqueta` con SOLO la fecha («12 ago»), `valor` con el numeral
    ///     («68») y `palabra` con el estado («Listo») — la lectura reparte los tres como el
    ///     papel (kicker · numeral teñido · palabra).
    /// `etiqueta` es además lo que VoiceOver dice de ese día, así que nunca va vacía.
    public struct Dia: Identifiable, Sendable {
        /// Clave de día estable (la llave `yyyy-MM-dd` del caller). Es la identidad de la
        /// selección: el binding viaja por `id`, no por índice ni por `Date`.
        public let id: String
        /// La fecha SOLO se usa para la geometría (en qué columna/fila cae el día). Nunca se
        /// formatea para pintarla — para eso están `etiqueta` y `mes`.
        public let fecha: Date
        /// 0…1, o `nil` si ese día no hubo lectura.
        public let intensidad: Double?
        /// La etiqueta del día YA formateada por el caller.
        public let etiqueta: String
        /// Numeral grande de la lectura, ya formateado (opcional — ver arriba).
        public let valor: String?
        /// Palabra de estado de la lectura, ya localizada (opcional — ver arriba).
        public let palabra: String?
        /// Rótulo de mes YA formateado («ago»), presente SOLO en el primer día de cada mes.
        /// Si ningún día lo trae, la fila de meses no se dibuja (y la retícula sube su origen,
        /// igual que `showsMonthLabels == false` en el papel).
        public let mes: String?

        public init(id: String,
                    fecha: Date,
                    intensidad: Double?,
                    etiqueta: String,
                    valor: String? = nil,
                    palabra: String? = nil,
                    mes: String? = nil) {
            self.id = id
            self.fecha = fecha
            self.intensidad = intensidad
            self.etiqueta = etiqueta
            self.valor = valor
            self.palabra = palabra
            self.mes = mes
        }
    }

    /// Un peldaño de la leyenda: su color y su etiqueta ya localizada. Para que la leyenda no
    /// mienta sobre la retícula, el caller construye los colores con `alfa(intensidad:)` sobre
    /// el mismo `tono` (y el peldaño «sin dato» con el track neutro, `LiquidColor.tinta7`).
    public struct NivelLeyenda: Identifiable, Sendable {
        public let id: String
        public let color: Color
        public let etiqueta: String

        public init(id: String, color: Color, etiqueta: String) {
            self.id = id
            self.color = color
            self.etiqueta = etiqueta
        }
    }

    // MARK: - Props

    private let dias: [Dia]
    private let tono: Color
    private let leyenda: [NivelLeyenda]
    @Binding private var seleccion: String?
    private let a11yLabel: String
    private let pistaVacia: String?
    private let sinLectura: String?
    private let inicialesDia: [String]
    private let a11yConteo: (Int, Int) -> String

    /// La lectura y la leyenda se APILAN en tallas de accesibilidad en vez de recortarse
    /// (la retícula es chrome geométrico y no escala — ver `mesAlto`).
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    /// Con Reduce Motion el anillo de selección y la lectura aparecen COLOCADOS, sin viaje.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ancho disponible medido (0 hasta que el layout resuelve — ver `celda`).
    @State private var anchoMedido: CGFloat = 0

    /// - Parameters:
    ///   - dias: la ventana, en cualquier orden (se ordena por fecha aquí).
    ///   - tono: el hue de la métrica. Tiñe el DATO (celdas + numeral de la lectura), nunca el chrome.
    ///   - leyenda: los peldaños a decodificar bajo la retícula.
    ///   - seleccion: `id` del día tocado; `nil` = ninguno. Re-tocar el mismo día lo suelta.
    ///   - a11yLabel: el nombre de la retícula para VoiceOver, ya localizado.
    ///   - pistaVacia: la frase que invita a tocar un día, ya localizada. `nil` = sin pista.
    ///   - sinLectura: la frase honesta de un día en rango SIN dato, ya localizada. `nil` = solo «—».
    ///   - inicialesDia: las 7 iniciales de la canaleta (Lun · — · Mié · — · Vie · — · Dom).
    ///   - a11yConteo: compone «N de M» para el `accessibilityValue`. El default es un numeral
    ///     crudo a propósito (el componente no inventa copy): pásale una frase localizada.
    public init(dias: [Dia],
                tono: Color,
                leyenda: [NivelLeyenda],
                seleccion: Binding<String?>,
                a11yLabel: String,
                pistaVacia: String? = nil,
                sinLectura: String? = nil,
                inicialesDia: [String] = LiquidCalendario90.inicialesPorLocale(),
                a11yConteo: @escaping (Int, Int) -> String = { "\($0)/\($1)" }) {
        self.dias = dias.sorted { $0.fecha < $1.fecha }
        self.tono = tono
        self.leyenda = leyenda
        self._seleccion = seleccion
        self.a11yLabel = a11yLabel
        self.pistaVacia = pistaVacia
        self.sinLectura = sinLectura
        self.inicialesDia = inicialesDia
        self.a11yConteo = a11yConteo
    }

    // MARK: - Geometría interna (medida del papel, no inventada)
    //
    // Todo lo de aquí es geometría del componente, no del sistema (mismo estatuto que
    // `altoBarra` en `LiquidStageBar`): son las proporciones de `YearHeatStrip`/`Calendario90`
    // portadas tal cual, para que las cuatro hojas de Tendencias midan igual entre sí y que el
    // calendario Liquid mida igual que el de papel mientras ambos coexisten.

    /// Gap entre celdas — 4 pt (`LiquidSpace.s100`), el `spacing` que `Calendario90` fija.
    private static let espacio: CGFloat = LiquidSpace.s100
    /// Canaleta izquierda con las iniciales de día — 24 pt (`LiquidSpace.s600`).
    private static let canaletaAncho: CGFloat = LiquidSpace.s600
    /// Alto de la fila de rótulos de mes — 10 pt (`LiquidSpace.s250`).
    private static let mesAlto: CGFloat = LiquidSpace.s250
    /// Piso y techo de la celda (8…22) — el clamp de `YearHeatStrip.rollingCellSize`.
    private static let celdaMin: CGFloat = LiquidSpace.s200
    private static let celdaMax: CGFloat = LiquidSpace.s550
    /// Celda del primer cuadro, ANTES de que la medición llegue. `Calendario90` hace lo mismo:
    /// el `PreferenceKey` publica el ancho después del primer layout, así que el calendario
    /// dibuja un cuadro con esta celda y re-dimensiona al siguiente. Es un salto de un frame,
    /// invisible en device, y el precio de no exigirle al caller un ancho fijo.
    private static let celdaFallback: CGFloat = 14
    /// Columnas FIJAS para dimensionar (no las vivas): una ventana de 90 días abarca 13 o 14
    /// semanas según en qué día caiga el inicio, y dimensionar a las vivas hacía que la celda
    /// oscilara ≈19.3↔21.1 pt de un día para otro. Paridad con `YearHeatStrip.rollingWindowColumns`.
    private static let columnasFijas: Int = 14

    /// Radio de la celda — 5. `Calendario90` sobrescribe con 5 el default 2.5 de `YearHeatStrip`
    /// (el 2.5 es del Tendencias oscuro legado): las hojas «Instrumento» quieren celda redonda.
    /// No es `LiquidRadius.control` (12) — a 12 la celda de 14 pt se vuelve un círculo.
    private static let radioCelda: CGFloat = 5
    /// Radio del anillo de selección — 3, continuo (paridad del papel: el anillo abraza la celda
    /// desde afuera, así que su curva es MENOR que la de la celda o se ve un halo cuadrado).
    private static let radioAnillo: CGFloat = 3
    /// Radio del swatch de la leyenda — 2, continuo (paridad `HeatLegend`; mismo valor que el
    /// swatch de `LiquidStageBar`).
    static let radioSwatch: CGFloat = 2
    /// Grosor del borde del día VACÍO — 0.5 (paridad `YearHeatStrip.cell`).
    private static let bordeVacio: CGFloat = 0.5
    /// Grosor del anillo de selección — 2 (paridad `YearHeatStrip`).
    private static let anilloBorde: CGFloat = 2
    /// Cuánto crece el anillo respecto de la celda — 4 (`LiquidSpace.s100`).
    private static let anilloHolgura: CGFloat = LiquidSpace.s100
    /// Lado del swatch de la leyenda — 8 (`LiquidSpace.s200`), paridad `HeatLegend`.
    static let swatchLado: CGFloat = LiquidSpace.s200

    /// Alfa del relleno teñido por intensidad. El rango NO se inventó: se midió de la rampa de
    /// un mismo hue que el papel ya usa para el calor (Esfuerzo, `InstrumentoTheme`), compuesta
    /// sobre el papel `#F4F1E8`:
    ///   · `strainRampLow`  `#EBC7AF` ≈ `dataStrain` `#C4631F` al **26 %**,
    ///   · `strainRampMid`  `#DC9A72` ≈ el mismo hue al **57 %**,
    ///   · `dataStrain`     el hue lleno = **100 %** (la celda con dato se pinta al full en el papel).
    /// De ahí el piso 0.26 y el techo 1.0. El piso importa tanto como el techo: por debajo de
    /// ~0.25 el día menos intenso deja de distinguirse del track neutro (7 % de tinta) y la
    /// retícula empieza a mentir sobre dónde hubo lectura.
    private static let alfaMin: Double = 0.26
    private static let alfaMax: Double = 1.0

    /// El alfa con el que `tono` tiñe la celda de un día de intensidad `intensidad` (0…1).
    /// Público a propósito: la leyenda la construye el caller, y si no pudiera pedir estos
    /// mismos alfas sus swatches derivarían de la retícula que dicen decodificar.
    public static func alfa(intensidad: Double) -> Double {
        let t = min(max(intensidad, 0), 1)
        return alfaMin + (alfaMax - alfaMin) * t
    }

    /// El tamaño de celda que hace que 14 columnas llenen `ancho`. Misma fórmula (y mismos
    /// números) que `YearHeatStrip.rollingCellSize` — se re-declara aquí para que el componente
    /// Liquid no cuelgue de una pieza de papel, y un test cierra la puerta a que las dos deriven.
    static func tamanoCelda(ancho: CGFloat) -> CGFloat {
        guard ancho > 0 else { return celdaFallback }
        let cols = CGFloat(columnasFijas)
        return max(celdaMin,
                   min(celdaMax, (ancho - canaletaAncho - espacio - (cols - 1) * espacio) / cols))
    }

    /// x de la primera columna de semana (después de la canaleta + su gap).
    private static var origenX: CGFloat { canaletaAncho + espacio }
    /// y de la primera fila de celdas (bajo la fila opcional de meses).
    private static func origenY(conMeses: Bool) -> CGFloat { conMeses ? mesAlto + espacio : 0 }

    private var celda: CGFloat {
        anchoMedido > 0 ? Self.tamanoCelda(ancho: anchoMedido) : Self.celdaFallback
    }

    // MARK: - Semanas (Monday-first, port de `YearHeatStrip.buildWeeks`)

    /// Una columna de la retícula: 7 filas (0 = lunes … 6 = domingo) y su rótulo de mes.
    struct Semana: Identifiable {
        let id: Int
        var celdas: [Dia?]
        var mes: String?
    }

    /// El calendario de la retícula: gregoriano con la semana empezando en LUNES. Es geometría
    /// (en qué columna cae un día), no formato — por eso sí vive aquí.
    static var calendarioLunes: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// Fila 0…6 Monday-first del `weekday` de Foundation (1 = domingo … 7 = sábado).
    static func fila(de fecha: Date, en calendario: Calendar) -> Int {
        (calendario.component(.weekday, from: fecha) + 5) % 7
    }

    /// Agrupa los días en columnas de semana, rellenando con `nil` lo que cae fuera de la
    /// ventana (el papel pinta esos huecos transparentes, no vacíos).
    static func semanas(de dias: [Dia],
                        calendario: Calendar = LiquidCalendario90.calendarioLunes) -> [Semana] {
        guard let primero = dias.first?.fecha else { return [] }
        var salida: [Semana] = []
        var actual = Semana(id: 0, celdas: Array(repeating: nil, count: 7), mes: nil)
        // Rellena la primera semana para que el primer día caiga en SU fila.
        var llenasEstaSemana = fila(de: primero, en: calendario)

        for dia in dias {
            let f = fila(de: dia.fecha, en: calendario)
            if f == 0 && llenasEstaSemana > 0 {
                salida.append(actual)
                actual = Semana(id: salida.count, celdas: Array(repeating: nil, count: 7), mes: nil)
                llenasEstaSemana = 0
            }
            actual.celdas[f] = dia
            if actual.mes == nil, let mes = dia.mes { actual.mes = mes }
            llenasEstaSemana += 1
        }
        if llenasEstaSemana > 0 { salida.append(actual) }
        return salida
    }

    // MARK: - Contratos puros (los mismos que leen la vista, VoiceOver y el test)

    /// Cuántos días traen lectura, de cuántos hay en la ventana.
    static func conteo(_ dias: [Dia]) -> (conDato: Int, total: Int) {
        (dias.reduce(0) { $0 + ($1.intensidad == nil ? 0 : 1) }, dias.count)
    }

    /// Lo que dicta VoiceOver sobre la retícula: el conteo de días con lectura y, si hay uno
    /// tocado, su etiqueta (así el barrido de ajuste no repite siempre la misma frase).
    static func a11yValor(dias: [Dia], seleccion: String?, conteo formato: (Int, Int) -> String) -> String {
        let c = conteo(dias)
        let base = formato(c.conDato, c.total)
        guard let id = seleccion, let dia = dias.first(where: { $0.id == id }) else { return base }
        return base + ", " + dia.etiqueta
    }

    /// Tocar un día lo selecciona; tocar el YA seleccionado lo suelta. Es lo que hace que la
    /// lectura desaparezca al re-tocar (regla de la pieza).
    static func alterna(seleccion actual: String?, toca id: String) -> String? {
        actual == id ? nil : id
    }

    /// El vecino con dato al que salta el gesto de ajuste de VoiceOver (`paso` ±1). Camina solo
    /// los días CON lectura: los huecos ya los reporta el conteo del `accessibilityValue`.
    static func vecino(dias: [Dia], desde seleccion: String?, paso: Int) -> String? {
        let conDato = dias.filter { $0.intensidad != nil }
        guard !conDato.isEmpty else { return nil }
        guard let id = seleccion, let i = conDato.firstIndex(where: { $0.id == id }) else {
            return paso > 0 ? conDato.first?.id : conDato.last?.id
        }
        return conDato[min(max(i + paso, 0), conDato.count - 1)].id
    }

    /// Las 7 iniciales de la canaleta en el locale del sistema. `shortWeekdaySymbols` SIEMPRE
    /// viene indexado desde domingo (da igual el `firstWeekday` del locale), así que se toman
    /// Lun(1) · Mié(3) · Vie(5) · Dom(0) y las intermedias quedan en blanco — la retícula es
    /// Monday-first por geometría, no por locale. No formatea ninguna fecha: son símbolos.
    public static func inicialesPorLocale(_ calendario: Calendar = .current) -> [String] {
        let s = calendario.shortWeekdaySymbols
        guard s.count == 7 else { return Array(repeating: "", count: 7) }
        return [s[1], "", s[3], "", s[5], "", s[0]]
    }

    // MARK: - Vista

    private var diaSeleccionado: Dia? {
        guard let seleccion else { return nil }
        return dias.first { $0.id == seleccion }
    }

    private var animacion: Animation? {
        reduceMotion ? nil : LiquidMotion.glassOut(LiquidMotion.quick)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            reticula
            lectura
            leyendaVista
        }
        .animation(animacion, value: seleccion)
    }

    // MARK: Retícula

    private var reticula: some View {
        let semanas = Self.semanas(de: dias)
        let conMeses = dias.contains { $0.mes != nil }
        let origenY = Self.origenY(conMeses: conMeses)
        let ancho = Self.origenX + CGFloat(semanas.count) * (celda + Self.espacio) - Self.espacio
        let alto = origenY + 7 * (celda + Self.espacio) - Self.espacio

        return VStack(alignment: .leading, spacing: Self.espacio) {
            if conMeses { filaMeses(semanas) }
            HStack(alignment: .top, spacing: Self.espacio) {
                canaleta
                ForEach(semanas) { semana in
                    VStack(spacing: Self.espacio) {
                        ForEach(0..<7, id: \.self) { fila in
                            celdaVista(semana.celdas[fila])
                        }
                    }
                }
            }
        }
        .frame(width: ancho, height: alto, alignment: .topLeading)
        // La medición vive FUERA del frame fijo de la retícula (patrón exacto de `Calendario90`):
        // el `GeometryReader` cuelga de la caja que ocupa TODO el ancho disponible, no de la
        // retícula ya dimensionada — si midiera la retícula, la celda se realimentaría a sí misma.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: LiquidCalendarioAnchoKey.self, value: g.size.width)
        })
        .onPreferenceChange(LiquidCalendarioAnchoKey.self) { anchoMedido = $0 }
        // Una retícula de 90 celdas son 90 paradas de VoiceOver: se colapsa en UNA sola,
        // con el conteo honesto de días con lectura como valor, y el gesto de AJUSTE
        // (deslizar arriba/abajo) camina los días con dato — que es lo que el toque hace
        // para quien ve. La lectura y la leyenda siguen hablando por su cuenta, abajo.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: Self.a11yValor(dias: dias, seleccion: seleccion,
                                                          conteo: a11yConteo)))
        .accessibilityAdjustableAction { direccion in
            switch direccion {
            case .increment: seleccion = Self.vecino(dias: dias, desde: seleccion, paso: 1)
            case .decrement: seleccion = Self.vecino(dias: dias, desde: seleccion, paso: -1)
            @unknown default: break
            }
        }
    }

    /// Fila de rótulos de mes, alineada a la primera columna de semana.
    private func filaMeses(_ semanas: [Semana]) -> some View {
        HStack(spacing: Self.espacio) {
            Color.clear.frame(width: Self.origenX - Self.espacio, height: Self.mesAlto)
            ForEach(semanas) { semana in
                Text(verbatim: semana.mes ?? "")
                    .font(LiquidType.unidad)
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(width: celda, alignment: .leading)
            }
        }
    }

    /// Canaleta de iniciales de día: 7 filas de la altura de la celda, alineadas a la derecha.
    private var canaleta: some View {
        VStack(alignment: .trailing, spacing: Self.espacio) {
            ForEach(0..<7, id: \.self) { fila in
                Text(verbatim: fila < inicialesDia.count ? inicialesDia[fila] : "")
                    .font(LiquidType.unidad)
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(width: Self.canaletaAncho, height: celda, alignment: .trailing)
            }
        }
    }

    /// Una celda: con dato (tono al alfa de su intensidad), en rango SIN dato (track neutro con
    /// filo), o fuera de la ventana (transparente, para que la retícula conserve su cuadrícula).
    @ViewBuilder private func celdaVista(_ dia: Dia?) -> some View {
        let forma = RoundedRectangle(cornerRadius: Self.radioCelda)
        let seleccionada = dia.map { $0.id == seleccion } ?? false
        Group {
            if let dia, let intensidad = dia.intensidad {
                forma
                    .fill(tono.opacity(Self.alfa(intensidad: intensidad)))
                    .frame(width: celda, height: celda)
            } else if dia != nil {
                // Sin lectura ≠ intensidad 0: track neutro (`tinta7`) con filo apenas más
                // oscuro (`tinta10`). El papel usa `hairline` de relleno y `hairlineStrong` de
                // filo — medidos sobre papel son ≈8 % y ≈17 % de tinta, o sea el FILO es el
                // oscuro. Mapear por nombre (hairline→tinta10, hairlineStrong→tinta7) habría
                // invertido ese par y dejado un relleno más oscuro que su propio borde.
                forma
                    .fill(LiquidColor.tinta7)
                    .overlay(forma.stroke(LiquidColor.tinta10, lineWidth: Self.bordeVacio))
                    .frame(width: celda, height: celda)
            } else {
                forma.fill(Color.clear).frame(width: celda, height: celda)
            }
        }
        .overlay {
            // El día tocado se marca con ANILLO, nunca cambiando su relleno: el relleno ES el
            // dato, y aclararlo para «señalar» haría que la selección mintiera sobre el valor.
            if seleccionada {
                RoundedRectangle(cornerRadius: Self.radioAnillo, style: .continuous)
                    .stroke(LiquidColor.tinta900, lineWidth: Self.anilloBorde)
                    .frame(width: celda + Self.anilloHolgura, height: celda + Self.anilloHolgura)
            }
        }
        // EXCEPCIÓN SANCIONADA al piso táctil de 44 pt (`LiquidControl.hitTarget`): la celda
        // mide 8…22 pt y no puede crecer sin dejar de ser una retícula de 90 días — el mismo
        // trato que Apple le da a su propio calendario de actividad, donde el objetivo también
        // es la celda. Se compensa por accesibilidad, no por tamaño: la retícula entera es UN
        // elemento de VoiceOver con acción de ajuste (arriba), así que quien no puede apuntar a
        // 14 pt sigue pudiendo recorrer los días. Solo los días EN RANGO son tocables (con dato
        // o sin él: un hueco también tiene una lectura honesta que dar).
        .contentShape(Rectangle())
        .onTapGesture {
            guard let dia else { return }
            seleccion = Self.alterna(seleccion: seleccion, toca: dia.id)
        }
    }

    // MARK: Lectura del día tocado

    @ViewBuilder private var lectura: some View {
        if let dia = diaSeleccionado {
            lecturaFila(dia)
                .accessibilityElement(children: .combine)
        } else if let pistaVacia {
            Text(verbatim: pistaVacia)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// En tallas de accesibilidad la lectura se APILA (fecha arriba, dato abajo) en vez de
    /// competir por el ancho con el numeral y recortarse.
    @ViewBuilder private func lecturaFila(_ dia: Dia) -> some View {
        if tamanoTexto.isAccessibilitySize {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                fechaLectura(dia)
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) { datoLectura(dia) }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                fechaLectura(dia)
                Spacer(minLength: LiquidSpace.s200)
                datoLectura(dia)
            }
        }
    }

    private func fechaLectura(_ dia: Dia) -> some View {
        Text(verbatim: dia.etiqueta)
            .liquidKicker()
            .foregroundStyle(LiquidColor.tinta500)
    }

    /// El dato del día tocado: numeral teñido + palabra de estado, o la lectura honesta de un
    /// hueco («—» + la frase del caller), toda ella en tinta terciaria para que se lea como
    /// AUSENCIA y no como un valor bajo.
    @ViewBuilder private func datoLectura(_ dia: Dia) -> some View {
        if dia.intensidad != nil {
            if let valor = dia.valor {
                Text(verbatim: valor)
                    .font(LiquidType.valorL)
                    .foregroundStyle(tono)
            }
            if let palabra = dia.palabra {
                Text(verbatim: palabra)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta700)
            }
        } else {
            Text(verbatim: "—")
                .font(LiquidType.valorL)
                .foregroundStyle(LiquidColor.tinta500)
            if let sinLectura {
                Text(verbatim: sinLectura)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }

    // MARK: Leyenda

    /// Fila de peldaños; en tallas de accesibilidad, rejilla 2×2 (mismo trato que la leyenda de
    /// `LiquidStageBar`). El gap del papel es 14 pt, un paso que la escala Liquid no tiene: se
    /// usa `s400` (16), el token más cercano hacia arriba.
    private var leyendaVista: some View { LiquidLeyendaNiveles(leyenda) }
}

/// El ancho disponible que mide la retícula (port del `CalWidthKey` de `Calendario90`).
private struct LiquidCalendarioAnchoKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// La leyenda de peldaños de una retícula: swatch + palabra por nivel, en fila; a tallas de
/// accesibilidad en rejilla 2×2 para que no se recorte. Nació dentro de `LiquidCalendario90`
/// y sale a pieza (FER-129) porque el mosaico de Preparación la necesitaba y la estaba
/// REDIBUJANDO a mano con otro swatch, otro radio y sin la rama AX — tres revisores lo cazaron.
/// Una sola leyenda para todas las retículas del sistema.
public struct LiquidLeyendaNiveles: View {
    private let niveles: [LiquidCalendario90.NivelLeyenda]
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public init(_ niveles: [LiquidCalendario90.NivelLeyenda]) { self.niveles = niveles }

    public var body: some View {
        Group {
            if tamanoTexto.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                    GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: LiquidSpace.s200) {
                    ForEach(niveles) { item($0) }
                }
            } else {
                // Un layout de FLUJO, no un HStack: con cuatro peldaños en español («Una señal
                // fuera» es largo) a 1× no caben en una fila y el HStack partía UNA etiqueta en
                // dos líneas mientras las otras tres quedaban en una — la fila dispareja que
                // se vio en el simulador. El flujo pasa el peldaño entero al renglón siguiente.
                LiquidFlujoLeyenda(espacioH: LiquidSpace.s400, espacioV: LiquidSpace.s200) {
                    ForEach(niveles) { item($0) }
                }
            }
        }
    }

    /// Cada peldaño es SU PROPIA parada de VoiceOver (swatch + palabra combinados), como era en
    /// el calendario de 90 antes de la extracción. La primera versión de esta pieza movió el
    /// `.combine` al contenedor y fundió los cuatro peldaños en una sola parada concatenada —
    /// una regresión de accesibilidad silenciosa en Sueño, que está en producción, que el QA
    /// cazó y que ninguna prueba vigilaba. Ahora la vigila `LiquidLeyendaNivelesTests`.
    private func item(_ nivel: LiquidCalendario90.NivelLeyenda) -> some View {
        HStack(spacing: LiquidSpace.s125) {
            RoundedRectangle(cornerRadius: LiquidCalendario90.radioSwatch, style: .continuous)
                .fill(nivel.color)
                .frame(width: LiquidCalendario90.swatchLado, height: LiquidCalendario90.swatchLado)
            Text(verbatim: nivel.etiqueta)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Contratos puros (los lee la prueba)

    /// Cuántas paradas de VoiceOver produce la leyenda: UNA por peldaño, nunca una sola para
    /// todos. Es la forma de fijar el agrupamiento sin renderizar.
    public static func paradasDeVoiceOver(_ niveles: [LiquidCalendario90.NivelLeyenda]) -> Int {
        niveles.count
    }

    /// Lo que dicta cada parada: swatch y palabra combinados en una sola frase por peldaño.
    public static func dictado(_ nivel: LiquidCalendario90.NivelLeyenda) -> String {
        nivel.etiqueta
    }
}

/// Layout de flujo para leyendas: coloca los hijos en fila y pasa al renglón siguiente el
/// que ya no cabe ENTERO — nunca parte un hijo en dos. Es lo que un `HStack` no sabe hacer.
public struct LiquidFlujoLeyenda: Layout {
    private let espacioH: CGFloat
    private let espacioV: CGFloat

    public init(espacioH: CGFloat, espacioV: CGFloat) {
        self.espacioH = espacioH
        self.espacioV = espacioV
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, altoFila: CGFloat = 0, anchoMax: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > ancho { x = 0; y += altoFila + espacioV; altoFila = 0 }
            x += t.width + espacioH
            altoFila = max(altoFila, t.height)
            anchoMax = max(anchoMax, x - espacioH)
        }
        return CGSize(width: ancho == .infinity ? anchoMax : min(ancho, anchoMax), height: y + altoFila)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, altoFila: CGFloat = 0
        for sub in subviews {
            let t = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX { x = bounds.minX; y += altoFila + espacioV; altoFila = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += t.width + espacioH
            altoFila = max(altoFila, t.height)
        }
    }
}

#if DEBUG
// El caller es quien formatea: estos helpers hacen de pantalla de Tendencias para las previews
// (fechas → etiquetas y rótulos de mes) justo como lo hacen las hojas de detalle. Cada closure
// y literal va con su tipo explícito: la preview del componente de papel tumbó una vez el build
// de CI por inferencia («unable to type-check this expression in reasonable time», FER-985).
private enum CalendarioDemo {
    static let cal: Calendar = LiquidCalendario90.calendarioLunes
    // Computados (no `static let`): `DateFormatter` no es `Sendable` y el paquete compila con
    // StrictConcurrency. Una preview no necesita caché.
    static var fmtMes: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }
    static var fmtDia: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }
    static var fmtLlave: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }

    /// 90 días terminando hoy. `huecoCada` deja sin lectura 1 de cada N días; `sinDatos` los
    /// deja TODOS sin lectura (el estado vacío honesto).
    static func dias(huecoCada: Int, sinDatos: Bool = false) -> [LiquidCalendario90.Dia] {
        let hoy: Date = Date()
        let mesF: DateFormatter = fmtMes
        let diaF: DateFormatter = fmtDia
        let llaveF: DateFormatter = fmtLlave
        var mesPrevio: Int = -1
        return (0..<90).map { (i: Int) -> LiquidCalendario90.Dia in
            let fecha: Date = cal.date(byAdding: .day, value: i - 89, to: hoy) ?? hoy
            let mesNum: Int = cal.component(.month, from: fecha)
            var mes: String? = nil
            if mesNum != mesPrevio {
                mes = mesF.string(from: fecha)
                mesPrevio = mesNum
            }
            let hueco: Bool = sinDatos || (huecoCada > 0 && i % huecoCada == 0)
            var intensidad: Double? = nil
            var valor: String? = nil
            var palabra: String? = nil
            var etiqueta: String = diaF.string(from: fecha)
            if !hueco {
                let pct: Int = (i * 13) % 100
                intensidad = Double(pct) / 100.0
                valor = "\(pct)"
                if pct >= 67 { palabra = "Listo" } else if pct >= 34 { palabra = "Recuperando" } else { palabra = "Bajo" }
                etiqueta = "\(diaF.string(from: fecha)) · \(pct)"
            }
            return LiquidCalendario90.Dia(
                id: llaveF.string(from: fecha),
                fecha: fecha,
                intensidad: intensidad,
                etiqueta: etiqueta,
                valor: valor,
                palabra: palabra,
                mes: mes)
        }
    }

    /// La ventana con huecos, compartida por las previews que además arrancan con un día tocado
    /// (así el `id` de la selección y el del arreglo son literalmente el mismo).
    static let conHuecos: [LiquidCalendario90.Dia] = dias(huecoCada: 5)

    /// La leyenda decodifica la MISMA rampa que pinta la retícula (por eso pide sus alfas al
    /// componente) más el track neutro del día sin lectura.
    static func leyenda(_ tono: Color) -> [LiquidCalendario90.NivelLeyenda] {
        [
            .init(id: "bajo", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 0.15)),
                  etiqueta: "bajo"),
            .init(id: "medio", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 0.55)),
                  etiqueta: "medio"),
            .init(id: "alto", color: tono.opacity(LiquidCalendario90.alfa(intensidad: 1)),
                  etiqueta: "alto"),
            .init(id: "sindato", color: LiquidColor.tinta7, etiqueta: "sin dato"),
        ]
    }
}

#Preview("Calendario · con datos") {
    struct Demo: View {
        @State private var seleccion: String? = nil
        var body: some View {
            LiquidCalendario90(
                dias: CalendarioDemo.dias(huecoCada: 0),
                tono: LiquidColor.verdePrimario,
                leyenda: CalendarioDemo.leyenda(LiquidColor.verdePrimario),
                seleccion: $seleccion,
                a11yLabel: "Calendario de 90 días",
                pistaVacia: "Toca un día para ver tu recuperación.",
                sinLectura: "sin lectura",
                a11yConteo: { (con: Int, total: Int) -> String in "\(con) de \(total) días con lectura" })
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
        }
    }
    return Demo()
}

/// Huecos de verdad: 1 de cada 5 días sin lectura. Ninguno se pinta con el tono al 0 % — van al
/// track neutro, que es lo que separa «no medimos» de «mediste lo peor».
#Preview("Calendario · con huecos") {
    struct Demo: View {
        @State private var seleccion: String? = nil
        var body: some View {
            LiquidCalendario90(
                dias: CalendarioDemo.conHuecos,
                tono: LiquidColor.indigo,
                leyenda: CalendarioDemo.leyenda(LiquidColor.indigo),
                seleccion: $seleccion,
                a11yLabel: "Calendario de 90 noches",
                pistaVacia: "Toca una noche para ver tu sueño.",
                sinLectura: "sin lectura",
                a11yConteo: { (con: Int, total: Int) -> String in "\(con) de \(total) noches con lectura" })
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        }
    }
    return Demo()
}

/// Ventana COMPLETA sin una sola lectura: la retícula existe (90 días en rango, todos en track
/// neutro) y la pista sigue invitando. El componente no finge: si ni la ventana existiera, es el
/// CALLER quien no debe pintar el calendario.
#Preview("Calendario · vacío") {
    struct Demo: View {
        @State private var seleccion: String? = nil
        var body: some View {
            LiquidCalendario90(
                dias: CalendarioDemo.dias(huecoCada: 0, sinDatos: true),
                tono: LiquidColor.ambar,
                leyenda: CalendarioDemo.leyenda(LiquidColor.ambar),
                seleccion: $seleccion,
                a11yLabel: "Calendario de 90 días",
                pistaVacia: "Toca un día para ver tu esfuerzo.",
                sinLectura: "sin lectura",
                a11yConteo: { (con: Int, total: Int) -> String in "\(con) de \(total) días con lectura" })
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.ambar))
        }
    }
    return Demo()
}

/// Día tocado: anillo de tinta sobre la celda (su relleno NO cambia) y la lectura abajo. Volver a
/// tocarlo la suelta.
#Preview("Calendario · día tocado") {
    struct Demo: View {
        @State private var seleccion: String? = CalendarioDemo.conHuecos.last?.id
        var body: some View {
            LiquidCalendario90(
                dias: CalendarioDemo.conHuecos,
                tono: LiquidColor.cian,
                leyenda: CalendarioDemo.leyenda(LiquidColor.cian),
                seleccion: $seleccion,
                a11yLabel: "Calendario de 90 días",
                pistaVacia: "Toca un día para ver tu estrés.",
                sinLectura: "sin lectura",
                a11yConteo: { (con: Int, total: Int) -> String in "\(con) de \(total) días con lectura" })
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.cian))
        }
    }
    return Demo()
}

/// Talla de accesibilidad: la retícula NO escala (es geometría), pero la lectura se apila y la
/// leyenda pasa a rejilla 2×2 — nada se recorta.
#Preview("Calendario · AX") {
    struct Demo: View {
        @State private var seleccion: String? = CalendarioDemo.conHuecos.last?.id
        var body: some View {
            LiquidCalendario90(
                dias: CalendarioDemo.conHuecos,
                tono: LiquidColor.verdePrimario,
                leyenda: CalendarioDemo.leyenda(LiquidColor.verdePrimario),
                seleccion: $seleccion,
                a11yLabel: "Calendario de 90 días",
                pistaVacia: "Toca un día para ver tu recuperación.",
                sinLectura: "sin lectura",
                a11yConteo: { (con: Int, total: Int) -> String in "\(con) de \(total) días con lectura" })
            .padding(LiquidSpace.s550)
            .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
            .environment(\.dynamicTypeSize, .accessibility3)
        }
    }
    return Demo()
}
#endif
