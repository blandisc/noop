import SwiftUI

// MARK: - Liquid Glass · Hoja del guardián (FER-33 · F3)
//
// La hoja que abre la columna VIGILANDO del Tablero: el centinela (temperatura de piel +
// respiración) explicado con su regla — vigila, no vota; solo la pareja, dos noches
// seguidas, empuja el día a uno más leve. Composición pura sobre piezas de la familia
// (header, frase-nivel, signal rows, dominó, método, chip de origen). Nunca dice
// «enfermedad» ni diagnostica. Todos los strings llegan YA localizados (contrato D3).
//
// Ley de color del eje (hermana de `LiquidAutonomico.tono`): el guardián NUNCA toma hue
// de dato — verde en patrón, ámbar de atención fuera, tinta500 sin base. Los valores y
// las mini-líneas sí van teñidos 1:1. La palabra del héroe es el único gran énfasis.

/// El contenido de la hoja del guardián — strings y series del caller, sin motor.
public struct LiquidGuardianHoja: Sendable {

    /// Una señal vigilada (temperatura o respiración) con su serie de 14 noches.
    public struct Senal: Sendable, Identifiable {
        public let id: String
        public let etiqueta: String
        public let valor: String
        /// Hue 1:1 de la señal (ámbar temp / azul resp).
        public let tono: Color
        public let fuera: Bool
        public let icono: LiquidIcon.Glyph
        public let a11y: String
        /// Serie de la mini-gráfica. `nil` = sin serie (se pinta vacía o cargando).
        public let serie: SerieMini?

        public init(id: String, etiqueta: String, valor: String, tono: Color,
                    fuera: Bool, icono: LiquidIcon.Glyph, a11y: String,
                    serie: SerieMini? = nil) {
            self.id = id
            self.etiqueta = etiqueta
            self.valor = valor
            self.tono = tono
            self.fuera = fuera
            self.icono = icono
            self.a11y = a11y
            self.serie = serie
        }
    }

    /// Datos de la mini-gráfica de 14 noches (banda de patrón + trazo + joya).
    public struct SerieMini: Sendable {
        public let puntos: [(fecha: Date, valor: Double)]
        public let banda: ClosedRange<Double>?
        public let dominio: ClosedRange<Double>
        public let puntoHoy: (fecha: Date, valor: Double)?
        /// Joya hueca cuando anoche no hubo lectura.
        public let hoyAnillo: Bool
        public let a11yLabel: String
        public let formatoValor: @Sendable (Double) -> String
        public let formatoFecha: @Sendable (Date) -> String
        public let vacio: String

        public init(puntos: [(fecha: Date, valor: Double)],
                    banda: ClosedRange<Double>?,
                    dominio: ClosedRange<Double>,
                    puntoHoy: (fecha: Date, valor: Double)?,
                    hoyAnillo: Bool,
                    a11yLabel: String,
                    formatoValor: @escaping @Sendable (Double) -> String,
                    formatoFecha: @escaping @Sendable (Date) -> String,
                    vacio: String) {
            self.puntos = puntos
            self.banda = banda
            self.dominio = dominio
            self.puntoHoy = puntoHoy
            self.hoyAnillo = hoyAnillo
            self.a11yLabel = a11yLabel
            self.formatoValor = formatoValor
            self.formatoFecha = formatoFecha
            self.vacio = vacio
        }
    }

    /// El dominó de la regla (últimas 5 noches del historial del centinela).
    public struct Domino: Sendable {
        public let carriles: [LiquidDominoRegla.Carril]
        public let cercoUltimas: Int?
        public let etiquetas: [String]
        public let consecuencia: String
        public let encendida: Bool
        public let a11yLabel: String

        public init(carriles: [LiquidDominoRegla.Carril],
                    cercoUltimas: Int? = nil,
                    etiquetas: [String],
                    consecuencia: String,
                    encendida: Bool,
                    a11yLabel: String) {
            self.carriles = carriles
            self.cercoUltimas = cercoUltimas
            self.etiquetas = etiquetas
            self.consecuencia = consecuencia
            self.encendida = encendida
            self.a11yLabel = a11yLabel
        }
    }

    public struct Metodo: Sendable {
        public let titulo: String
        public let mostrar: String
        public let ocultar: String
        public let nota: String
        public let origenEtiqueta: String
        public let origenSufijo: String

        public init(titulo: String, mostrar: String, ocultar: String, nota: String,
                    origenEtiqueta: String, origenSufijo: String) {
            self.titulo = titulo
            self.mostrar = mostrar
            self.ocultar = ocultar
            self.nota = nota
            self.origenEtiqueta = origenEtiqueta
            self.origenSufijo = origenSufijo
        }
    }

    public struct Calibracion: Sendable {
        public let titulo: String
        public let leyenda: String
        public let hechas: Int
        public let necesarias: Int

        public init(titulo: String, leyenda: String, hechas: Int, necesarias: Int) {
            self.titulo = titulo
            self.leyenda = leyenda
            self.hechas = hechas
            self.necesarias = necesarias
        }
    }

    public let titulo: String
    public let explicacion: String
    public let infoMostrar: String
    public let infoOcultar: String
    /// Palabra del héroe («Dentro de tu patrón»). `nil` = sin lectura / conociéndote.
    public let nivel: String?
    public let sinLectura: String?
    public let conteo: String
    public let sello: String?
    /// `true` = en patrón (verde). `false` con nivel = fuera (ámbar). Sin nivel = tinta500.
    public let enPatron: Bool
    public let temp: Senal
    public let resp: Senal
    /// Pie de la tarjeta del par («tus últimas 14 noches · la banda es tu patrón»).
    public let pieTarjeta: String
    /// Nota bajo la tarjeta. `nil` = silencio por defecto (estado en patrón).
    public let nota: String?
    /// `true` = la nota avisa (ámbar de atención), no es letra chica.
    public let notaAvisa: Bool
    public let reglaKicker: String
    public let reglaTexto: String
    public let reglaClave: String
    public let domino: Domino
    public let metodo: Metodo
    public let calibracion: Calibracion?

    public init(titulo: String, explicacion: String,
                infoMostrar: String, infoOcultar: String,
                nivel: String?, sinLectura: String? = nil, conteo: String,
                sello: String? = nil, enPatron: Bool,
                temp: Senal, resp: Senal, pieTarjeta: String,
                nota: String? = nil, notaAvisa: Bool = false,
                reglaKicker: String, reglaTexto: String, reglaClave: String,
                domino: Domino, metodo: Metodo,
                calibracion: Calibracion? = nil) {
        self.titulo = titulo
        self.explicacion = explicacion
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
        self.nivel = nivel
        self.sinLectura = sinLectura
        self.conteo = conteo
        self.sello = sello
        self.enPatron = enPatron
        self.temp = temp
        self.resp = resp
        self.pieTarjeta = pieTarjeta
        self.nota = nota
        self.notaAvisa = notaAvisa
        self.reglaKicker = reglaKicker
        self.reglaTexto = reglaTexto
        self.reglaClave = reglaClave
        self.domino = domino
        self.metodo = metodo
        self.calibracion = calibracion
    }

    /// El tono del eje: verde en patrón, ámbar de atención fuera, tinta500 sin base.
    public var tono: Color {
        nivel == nil ? LiquidColor.tinta500
                     : (enPatron ? LiquidColor.verdePrimario : LiquidColor.atencion)
    }
}

// MARK: - La hoja

/// El cuerpo de la hoja del guardián. El caller la envuelve en `LiquidMetricSheet(tono:…,
/// detent: .porContenido)`.
public struct LiquidGuardianScreen: View {
    private let hoja: LiquidGuardianHoja

    public init(_ hoja: LiquidGuardianHoja) {
        self.hoja = hoja
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            // 1 · Cabecera: gota de escudo + UN título + ⓘ.
            LiquidSheetHeader(icono: .escudo, titulo: hoja.titulo, tono: hoja.tono,
                              numeral: nil,
                              explicacion: hoja.explicacion,
                              infoMostrar: hoja.infoMostrar,
                              infoOcultar: hoja.infoOcultar)

            // 2 · Héroe-palabra + sello «ANOCHE · 3 AGO».
            LiquidFraseNivel(nivel: hoja.nivel, conteo: hoja.conteo,
                             tono: hoja.tono, sinLectura: hoja.sinLectura,
                             sello: hoja.sello)

            // 3 · Tarjeta del par vigilado (papel + aurora ámbar/azul).
            parVigilado

            if let nota = hoja.nota {
                LiquidNotaLine(nota, tono: hoja.notaAvisa
                               ? LiquidColor.atencionTexto
                               : LiquidColor.tinta500)
            }

            // 4 · Tarjeta LA REGLA + dominó.
            tarjetaRegla

            // 5 · Calibración (solo «Conociéndote»).
            if let cal = hoja.calibracion {
                LiquidCalibracionCard(titulo: cal.titulo, leyenda: cal.leyenda,
                                      hechas: cal.hechas, necesarias: cal.necesarias,
                                      tono: LiquidColor.tinta500)
            }

            // 6 · Pie: fluye con el contenido (no anclado).
            LiquidMetodo(title: hoja.metodo.titulo,
                         mostrar: hoja.metodo.mostrar,
                         ocultar: hoja.metodo.ocultar) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidNotaLine(hoja.metodo.nota)
                    // Mismo patrón que `origenChipVista` de las 9 hojas de métrica.
                    LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                                     etiqueta: hoja.metodo.origenEtiqueta,
                                     sufijo: hoja.metodo.origenSufijo)
                }
            }
        }
    }

    // MARK: - Par vigilado

    private var parVigilado: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            LiquidSignalList(
                filas: [fila(hoja.temp), fila(hoja.resp)],
                auroraTones: [LiquidColor.ambar, LiquidColor.azul]
            ) { f in
                if f.id == hoja.temp.id, let s = hoja.temp.serie {
                    miniChart(s, tono: hoja.temp.tono)
                } else if f.id == hoja.resp.id, let s = hoja.resp.serie {
                    miniChart(s, tono: hoja.resp.tono)
                }
            }
            Text(verbatim: hoja.pieTarjeta)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }

    private func fila(_ s: LiquidGuardianHoja.Senal) -> LiquidSignalFila {
        LiquidSignalFila(
            id: s.id, etiqueta: s.etiqueta, valor: s.valor, valorTono: s.tono,
            fuera: s.fuera, a11y: s.a11y,
            icono: s.icono, iconoTono: s.tono, anillo: s.fuera)
    }

    @ViewBuilder
    private func miniChart(_ s: LiquidGuardianHoja.SerieMini, tono: Color) -> some View {
        let bandas: [LiquidChartBanda] = {
            guard let b = s.banda else { return [] }
            return [.init(lo: b.lowerBound, hi: b.upperBound, color: tono, activa: true)]
        }()
        // Con UNA sola lectura ya hay algo que enseñar: exigir dos decía «Aún sin lecturas»
        // sobre una noche que sí existe. (Revisión DeepSeek D2.)
        let estado: LiquidChartEstado = s.puntos.isEmpty ? .vacio(s.vacio) : .datos
        LiquidTrendChart(
            titulo: "",
            puntos: s.puntos,
            bandas: bandas,
            dominio: s.dominio,
            ticksY: [],
            tono: tono,
            formatoScrub: { v, f in "\(s.formatoValor(v)) · \(s.formatoFecha(f))" },
            formatoValorScrub: s.formatoValor,
            formatoFechaScrub: s.formatoFecha,
            puntoHoy: s.puntoHoy,
            hoyAnillo: s.hoyAnillo,
            estado: estado,
            a11yLabel: s.a11yLabel,
            densidad: .mini)
    }

    // MARK: - La regla

    private var tarjetaRegla: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(verbatim: hoja.reglaKicker)
                .font(LiquidType.label)
                .tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            // Clave en negrita sobre tinta, NUNCA en el tono del eje.
            LiquidReadingLine(hoja.reglaTexto, highlight: hoja.reglaClave,
                              highlightTone: LiquidColor.tinta900)
            LiquidDominoRegla(
                carriles: hoja.domino.carriles,
                cercoUltimas: hoja.domino.cercoUltimas,
                etiquetas: hoja.domino.etiquetas,
                consecuencia: hoja.domino.consecuencia,
                encendida: hoja.domino.encendida,
                a11yLabel: hoja.domino.a11yLabel)
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
    }
}

// MARK: - Previews (5 estados + AX3)

#if DEBUG
enum LiquidGuardianFixtures {

    private static let reglaTexto =
        "Una sola señal fuera nunca empuja tu día. Solo la pareja, dos noches seguidas."
    private static let reglaClave = "Solo la pareja, dos noches seguidas."
    private static let pie = "tus últimas 14 noches · la banda es tu patrón"
    private static let metodo = LiquidGuardianHoja.Metodo(
        titulo: "Cómo se obtuvo",
        mostrar: "Ver cómo se obtuvo",
        ocultar: "Ocultar cómo se obtuvo",
        nota: "Las dos señales se leen de tu Apple Watch mientras duermes y se comparan contra tu propio patrón de las últimas semanas, no contra tablas de población. Una desviación aislada se ignora a propósito: un cuarto caliente o una cobija de más la producen solas.",
        origenEtiqueta: "Apple Salud",
        origenSufijo: "anoche")

    private static func serie(valores: [Double], fueraAnoche: Bool,
                              anillo: Bool = false,
                              banda: ClosedRange<Double>,
                              fmt: @escaping @Sendable (Double) -> String,
                              a11y: String) -> LiquidGuardianHoja.SerieMini {
        let cal = Calendar(identifier: .gregorian)
        let hoy = cal.startOfDay(for: Date())
        let puntos: [(fecha: Date, valor: Double)] = valores.enumerated().map { i, v in
            let d = cal.date(byAdding: .day, value: i - (valores.count - 1), to: hoy)!
            return (fecha: d, valor: v)
        }
        let ultimo = puntos.last!
        return .init(
            puntos: puntos,
            banda: banda,
            dominio: (banda.lowerBound - 0.4)...(banda.upperBound + 0.6),
            puntoHoy: fueraAnoche || !anillo ? ultimo : ultimo,
            hoyAnillo: anillo,
            a11yLabel: a11y,
            formatoValor: fmt,
            formatoFecha: { _ in "3 ago" },
            vacio: "Sin lecturas todavía.")
    }

    private static func temp(_ valor: String, fuera: Bool, serie: LiquidGuardianHoja.SerieMini?)
        -> LiquidGuardianHoja.Senal {
        .init(id: "temp", etiqueta: "Temperatura de piel", valor: valor,
              tono: LiquidColor.ambar, fuera: fuera, icono: .termo,
              a11y: "Temperatura de piel, \(valor)"
                  + (fuera ? ", fuera de tu patrón" : ", en tu patrón"),
              serie: serie)
    }

    private static func resp(_ valor: String, fuera: Bool, serie: LiquidGuardianHoja.SerieMini?)
        -> LiquidGuardianHoja.Senal {
        .init(id: "resp", etiqueta: "Respiración", valor: valor,
              tono: LiquidColor.azul, fuera: fuera, icono: .resp,
              a11y: "Respiración, \(valor)"
                  + (fuera ? ", fuera de tu patrón" : ", en tu patrón"),
              serie: serie)
    }

    private static func domino(temp: [LiquidDominoRegla.Punto],
                               resp: [LiquidDominoRegla.Punto],
                               encendida: Bool,
                               a11y: String) -> LiquidGuardianHoja.Domino {
        .init(
            carriles: [
                .init(id: "temp", icono: .termo, tono: LiquidColor.ambar,
                      noches: temp, a11y: "Temperatura de piel"),
                .init(id: "resp", icono: .resp, tono: LiquidColor.azul,
                      noches: resp, a11y: "Respiración"),
            ],
            cercoUltimas: encendida ? 2 : nil,
            etiquetas: ["anteanoche", "anoche"],
            consecuencia: "día más leve",
            encendida: encendida,
            a11yLabel: a11y)
    }

    private static let tempSerieIn =
        serie(valores: [0.1, 0.0, -0.1, 0.2, 0.1, -0.05, 0.15, 0.05, -0.1, 0.0, 0.1, 0.05, 0.0, 0.1],
              fueraAnoche: false, banda: -0.8...0.8,
              fmt: { String(format: "%+.1f°", $0) },
              a11y: "Temperatura de piel, 14 noches")
    private static let tempSerieOut =
        serie(valores: [0.1, 0.0, -0.1, 0.2, 0.1, -0.05, 0.15, 0.05, -0.1, 0.0, 0.1, 0.3, 0.6, 0.9],
              fueraAnoche: true, banda: -0.8...0.8,
              fmt: { String(format: "%+.1f°", $0) },
              a11y: "Temperatura de piel, 14 noches")
    private static let respSerieIn =
        serie(valores: [14, 13.5, 14.2, 14, 13.8, 14.1, 14, 13.9, 14.3, 14, 13.7, 14.1, 14, 14],
              fueraAnoche: false, banda: 12...18,
              fmt: { "\(Int($0.rounded())) rpm" },
              a11y: "Respiración, 14 noches")
    private static let respSerieOut =
        serie(valores: [14, 13.5, 14.2, 14, 13.8, 14.1, 14, 13.9, 14.3, 14, 15, 16, 18, 19],
              fueraAnoche: true, banda: 12...18,
              fmt: { "\(Int($0.rounded())) rpm" },
              a11y: "Respiración, 14 noches")

    static let enPatron = LiquidGuardianHoja(
        titulo: "El guardián",
        explicacion: "Vigila dos señales de tu noche, tu temperatura de piel y tu respiración, contra tu propio patrón de las últimas semanas. No vota tu veredicto: solo lo empuja hacia un día más leve cuando las dos se salen juntas. Es una aproximación, no un diagnóstico.",
        infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
        nivel: "Dentro de tu patrón",
        conteo: "Tus dos señales de la noche amanecieron donde siempre.",
        sello: "ANOCHE · 3 AGO", enPatron: true,
        temp: temp("+0.1°", fuera: false, serie: tempSerieIn),
        resp: resp("14 rpm", fuera: false, serie: respSerieIn),
        pieTarjeta: pie, nota: nil,
        reglaKicker: "LA REGLA", reglaTexto: reglaTexto, reglaClave: reglaClave,
        domino: domino(temp: [.dentro, .dentro, .dentro, .dentro, .dentro],
                       resp: [.dentro, .dentro, .dentro, .dentro, .dentro],
                       encendida: false,
                       a11y: "Temperatura: en patrón las últimas noches. Respiración: en patrón las últimas noches."),
        metodo: metodo)

    static let unaFuera = LiquidGuardianHoja(
        titulo: "El guardián",
        explicacion: enPatron.explicacion,
        infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
        nivel: "Una señal fuera",
        conteo: "Tu temperatura amaneció fuera de tu patrón; la respiración, donde siempre.",
        sello: "ANOCHE · 3 AGO", enPatron: false,
        temp: temp("+0.9°", fuera: true, serie: tempSerieOut),
        resp: resp("14 rpm", fuera: false, serie: respSerieIn),
        pieTarjeta: pie,
        nota: "Una sola puede ser el cuarto, la cobija o la noche. El guardián espera.",
        notaAvisa: false,
        reglaKicker: "LA REGLA", reglaTexto: reglaTexto, reglaClave: reglaClave,
        domino: domino(temp: [.dentro, .dentro, .dentro, .dentro, .fuera],
                       resp: [.dentro, .dentro, .dentro, .dentro, .dentro],
                       encendida: false,
                       a11y: "Temperatura: fuera anoche. Respiración: en patrón. El guardián espera."),
        metodo: metodo)

    static let juntas = LiquidGuardianHoja(
        titulo: "El guardián",
        explicacion: enPatron.explicacion,
        infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
        nivel: "Juntas, fuera",
        conteo: "Tus dos señales amanecieron fuera de tu patrón, por segunda noche.",
        sello: "ANOCHE · 3 AGO", enPatron: false,
        temp: temp("+0.9°", fuera: true, serie: tempSerieOut),
        resp: resp("19 rpm", fuera: true, serie: respSerieOut),
        pieTarjeta: pie,
        nota: "El guardián no diagnostica: solo te baja el ritmo.",
        notaAvisa: true,
        reglaKicker: "LA REGLA", reglaTexto: reglaTexto, reglaClave: reglaClave,
        domino: domino(temp: [.dentro, .dentro, .dentro, .fuera, .fuera],
                       resp: [.dentro, .dentro, .dentro, .fuera, .fuera],
                       encendida: true,
                       a11y: "Temperatura: fuera anteanoche y anoche. Respiración: fuera anteanoche y anoche. Tu día se empujó a uno más leve."),
        metodo: metodo)

    static let sinLectura = LiquidGuardianHoja(
        titulo: "El guardián",
        explicacion: enPatron.explicacion,
        infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
        nivel: nil,
        sinLectura: "Sin lectura anoche",
        conteo: "Sin noche grabada, el guardián no tiene contra qué comparar.",
        sello: "ANOCHE · 3 AGO", enPatron: false,
        temp: temp("—", fuera: false, serie: serie(
            valores: [0.1, 0.0, -0.1, 0.2, 0.1, -0.05, 0.15, 0.05, -0.1, 0.0, 0.1, 0.05, 0.0, 0.0],
            fueraAnoche: false, anillo: true, banda: -0.8...0.8,
            fmt: { String(format: "%+.1f°", $0) },
            a11y: "Temperatura de piel, 14 noches")),
        resp: resp("—", fuera: false, serie: serie(
            valores: [14, 13.5, 14.2, 14, 13.8, 14.1, 14, 13.9, 14.3, 14, 13.7, 14.1, 14, 14],
            fueraAnoche: false, anillo: true, banda: 12...18,
            fmt: { "\(Int($0.rounded())) rpm" },
            a11y: "Respiración, 14 noches")),
        pieTarjeta: pie,
        nota: "Duerme con tu Apple Watch y mañana vuelve a vigilar.",
        reglaKicker: "LA REGLA", reglaTexto: reglaTexto, reglaClave: reglaClave,
        domino: domino(temp: [.dentro, .dentro, .dentro, .dentro, .sinDato],
                       resp: [.dentro, .dentro, .dentro, .dentro, .sinDato],
                       encendida: false,
                       a11y: "Sin lectura anoche en temperatura ni respiración."),
        metodo: metodo)

    static let conociendote = LiquidGuardianHoja(
        titulo: "El guardián",
        explicacion: enPatron.explicacion,
        infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
        nivel: nil,
        sinLectura: "Conociéndote",
        conteo: "Necesito unas noches tuyas para aprender tu patrón.",
        sello: "ANOCHE · 3 AGO", enPatron: false,
        temp: temp("+0.1°", fuera: false, serie: tempSerieIn),
        resp: resp("14 rpm", fuera: false, serie: respSerieIn),
        pieTarjeta: pie,
        nota: "Mientras tanto, las lecturas se muestran sin comparación.",
        reglaKicker: "LA REGLA", reglaTexto: reglaTexto, reglaClave: reglaClave,
        domino: domino(temp: [.sinDato, .sinDato, .sinDato, .dentro, .dentro],
                       resp: [.sinDato, .sinDato, .sinDato, .sinDato, .sinDato],
                       encendida: false,
                       a11y: "Aprendiendo tu patrón: noches previas sin base todavía."),
        metodo: metodo,
        calibracion: .init(titulo: "Aprendiendo tu patrón",
                           leyenda: "8 de 14 noches", hechas: 8, necesarias: 14))
}

private func guardianPreview(_ model: LiquidGuardianHoja) -> some View {
    ScrollView {
        LiquidGuardianScreen(model)
            .padding(LiquidSpace.s550)
    }
    .frame(width: 402, alignment: .topLeading)
    .background(LiquidSheetFondo(tone: model.tono))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Guardián · dentro de tu patrón") { guardianPreview(LiquidGuardianFixtures.enPatron) }
#Preview("Guardián · una señal fuera") { guardianPreview(LiquidGuardianFixtures.unaFuera) }
#Preview("Guardián · juntas, fuera") { guardianPreview(LiquidGuardianFixtures.juntas) }
#Preview("Guardián · sin lectura anoche") { guardianPreview(LiquidGuardianFixtures.sinLectura) }
#Preview("Guardián · conociéndote") { guardianPreview(LiquidGuardianFixtures.conociendote) }

#Preview("Guardián · AX3") {
    guardianPreview(LiquidGuardianFixtures.unaFuera)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
