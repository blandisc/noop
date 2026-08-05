import SwiftUI

// MARK: - Liquid Glass · Detalle del eje AUTONÓMICO (FER-1045)
//
// La hoja que abre el orbe «Autonómico» del héroe de Hoy y contesta la pregunta que ese eje
// provoca: «¿qué señal amaneció fuera, y cuánto pesó en el veredicto?». El eje NO es una sola
// métrica — es el promedio ponderado de TRES señales del cuerpo en reposo (FC en reposo, VFC y
// respiración). Esta hoja las abre: cada una con su estado y el porcentaje del voto que cargó.
//
// CERO componentes nuevos de dato: es una COMPOSICIÓN con contrato (el mismo patrón que
// `LiquidActaVeredicto`) sobre piezas que ya existen —`LiquidSheetHeader`, `LiquidFraseNivel`,
// `LiquidReadingLine`, `LiquidMetodo`, `LiquidNotaLine`— más una fila propia (`LiquidSignalRow`)
// para las tres señales, hermana de `LiquidLevelRow` pero NO tocable (no lleva a ningún lado) y
// con la columna de «voto» en vez de «rango/conteo». El orden de las filas ES el argumento:
// llegan ordenadas por peso (el caller las ordena), la que más pesa arriba.
//
// REGLAS QUE ESTA HOJA NO ROMPE
//  · El eje NO toma hue de dato (nada de cian/rosa/azul): habla en VERDE cuando amaneció en tu
//    rango y en ÁMBAR de atención cuando una señal lo sacó. Un solo énfasis de color: la palabra
//    del veredicto del eje. La señal que lo volteó lleva wash + punto (no texto en tono), igual
//    que `LiquidBandsTable`. En el estado bueno la lista queda ENTERAMENTE gris.
//  · La frase del método va en NEGRITA sobre tinta/900, nunca en el tono.
//
// Contrato D3: TODOS los strings llegan YA localizados y compuestos del caller (estado, voto,
// notas, a11y). El DS no conoce locales, ni `Preparedness`, ni umbrales. El porcentaje del voto
// llega como texto formateado («40 %») — el DS no formatea números con locale.

public struct LiquidAutonomico: Sendable {

    /// Una señal del eje: quién es, qué dijo, y cuánto pesó su voto.
    public struct Senal: Sendable, Identifiable {
        public let id: String
        /// El nombre de la señal, ya localizado («FC en reposo», «VFC», «Respiración»).
        public let etiqueta: String
        /// Qué dijo esta señal («En tu rango» · «Debajo de tu base» · «Sin base»).
        public let estado: String
        /// La columna derecha, YA localizada: el porcentaje del voto que cargó («40 %») cuando la
        /// señal vota y no es el votante único; el rótulo «referencia» cuando NO vota (v3: VFC y
        /// respiración son read-out); `nil` cuando es el único votante («100 %» sería ruido) o no
        /// hay lectura.
        public let voto: String?
        /// ¿Esta señal amaneció fuera de tu rango? Es la única fila con color (wash + punto ámbar).
        /// Solo la señal que VOTA puede encenderse: una fila de referencia nunca tiñe.
        public let fuera: Bool
        /// Nota opcional bajo la fila, ya localizada. `nil` = sin nota.
        public let nota: String?
        /// Label compuesto de VoiceOver, YA localizado (el color no habla: el estado «fuera» y el
        /// peso del voto tienen que ser audibles).
        public let a11y: String

        public init(id: String, etiqueta: String, estado: String, voto: String?,
                    fuera: Bool, nota: String? = nil, a11y: String) {
            self.id = id
            self.etiqueta = etiqueta
            self.estado = estado
            self.voto = voto
            self.fuera = fuera
            self.nota = nota
            self.a11y = a11y
        }
    }

    /// El plegable de transparencia matemática (mismo shape que `LiquidActa.Metodo`).
    public struct Metodo: Sendable {
        public let titulo: String
        public let mostrar: String
        public let ocultar: String
        public let lineas: [String]

        public init(titulo: String, mostrar: String, ocultar: String, lineas: [String]) {
            self.titulo = titulo
            self.mostrar = mostrar
            self.ocultar = ocultar
            self.lineas = lineas
        }
    }

    public let titulo: String
    public let procedencia: String
    public let explicacion: String
    public let infoMostrar: String
    public let infoOcultar: String
    /// La palabra del veredicto DEL EJE («En tu rango» · «Fuera de tu rango»). `nil` = todavía no
    /// hay base para un veredicto (se muestra `sinLectura`).
    public let nivel: String?
    /// El texto que sustituye a la palabra cuando no hay veredicto («Sin base todavía»).
    public let sinLectura: String?
    /// El conteo que sostiene la palabra («Tu pulso en reposo amaneció en tu rango.»).
    public let conteo: String
    /// La frase que explica el método en llano, con su cláusula clave en negrita.
    public let metodo: String
    public let metodoClave: String
    public let senales: [Senal]
    public let plegable: Metodo?
    /// ¿El eje amaneció en tu rango? Decide el ÚNICO tono de la hoja: verde en rango, ámbar de
    /// atención fuera. El eje jamás toma un hue de dato.
    public let enRango: Bool

    public init(titulo: String, procedencia: String, explicacion: String,
                infoMostrar: String, infoOcultar: String,
                nivel: String?, sinLectura: String? = nil, conteo: String,
                metodo: String, metodoClave: String,
                senales: [Senal], plegable: Metodo? = nil, enRango: Bool) {
        self.titulo = titulo
        self.procedencia = procedencia
        self.explicacion = explicacion
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
        self.nivel = nivel
        self.sinLectura = sinLectura
        self.conteo = conteo
        self.metodo = metodo
        self.metodoClave = metodoClave
        self.senales = senales
        self.plegable = plegable
        self.enRango = enRango
    }

    /// El tono del eje: verde en rango, ámbar de atención fuera. Sin base (nivel == nil) el eje no
    /// tiene color — la palabra vive en tinta/500 y toda la hoja queda gris.
    public var tono: Color {
        nivel == nil ? LiquidColor.tinta500
                     : (enRango ? LiquidColor.verdePrimario : LiquidColor.atencion)
    }
}

// MARK: - La hoja

/// El cuerpo de la hoja del eje autonómico. El caller la envuelve en `LiquidMetricSheet(tono:…)`
/// — el cascarón pone fondo, grip, detents y márgenes.
public struct LiquidAutonomicoScreen: View {
    private let model: LiquidAutonomico

    public init(_ model: LiquidAutonomico) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            // 1 · Qué estoy viendo. Sin glifo ni numeral: el dato de esta hoja es una PALABRA
            // (el veredicto del eje) más el desglose de sus señales.
            LiquidSheetHeader(icono: nil, titulo: model.titulo, tono: model.tono,
                              numeral: nil,
                              origenEtiqueta: model.procedencia,
                              explicacion: model.explicacion,
                              infoMostrar: model.infoMostrar,
                              infoOcultar: model.infoOcultar)

            // 2 · El veredicto del eje COMO DATO + el conteo que lo sostiene.
            LiquidFraseNivel(nivel: model.nivel, conteo: model.conteo,
                             tono: model.tono, sinLectura: model.sinLectura)

            // 3 · Cómo se decide, en una frase. En NEGRITA sobre tinta/900: el único color de la
            // hoja lo tiene la palabra de arriba.
            LiquidReadingLine(model.metodo, highlight: model.metodoClave,
                              highlightTone: LiquidColor.tinta900)

            // 4 · El desglose: las tres señales, ordenadas por peso, con su voto y su estado.
            LiquidSignalList(senales: model.senales)

            // 5 · Letra chica: cómo se calcula, plegable.
            if let plegable = model.plegable {
                LiquidMetodo(title: plegable.titulo,
                             mostrar: plegable.mostrar, ocultar: plegable.ocultar) {
                    VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                        ForEach(Array(plegable.lineas.enumerated()), id: \.offset) { _, linea in
                            LiquidNotaLine(linea)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - La lista de señales (el chrome que las vuelve una tabla)

/// Fila de señal reutilizable (eje autonómico + guardián): marca + nombre + columna derecha,
/// wash ámbar cuando está fuera, hit target ≥44, a11y compuesto del caller. NO navega.
///
/// La marca puede ser el punto del eje autonómico o la gota-icono del guardián (con anillo
/// cuando esa señal amaneció fuera). El valor teñido 1:1 y el hueco de la mini-gráfica son
/// opcionales: el eje no los usa; el guardián sí.
public struct LiquidSignalFila: Sendable, Identifiable {
    public let id: String
    public let etiqueta: String
    /// Texto de estado a la derecha del nombre («En tu rango»). `nil` = no se pinta.
    public let estado: String?
    /// Columna secundaria («40 %», «referencia»). `nil` = no se pinta.
    public let voto: String?
    /// Valor teñido 1:1 a la derecha («+0.4°», «14 rpm»). `nil` = no se pinta.
    public let valor: String?
    /// Tono del valor (hue 1:1 de la señal). Solo aplica si hay `valor`.
    public let valorTono: Color?
    public let fuera: Bool
    public let nota: String?
    public let a11y: String
    /// `nil` = punto del eje; con glifo = gota del guardián.
    public let icono: LiquidIcon.Glyph?
    public let iconoTono: Color?
    /// Anillo ámbar alrededor de la gota cuando la señal amaneció fuera.
    public let anillo: Bool

    public init(id: String, etiqueta: String, estado: String? = nil, voto: String? = nil,
                valor: String? = nil, valorTono: Color? = nil, fuera: Bool,
                nota: String? = nil, a11y: String,
                icono: LiquidIcon.Glyph? = nil, iconoTono: Color? = nil,
                anillo: Bool = false) {
        self.id = id
        self.etiqueta = etiqueta
        self.estado = estado
        self.voto = voto
        self.valor = valor
        self.valorTono = valorTono
        self.fuera = fuera
        self.nota = nota
        self.a11y = a11y
        self.icono = icono
        self.iconoTono = iconoTono
        self.anillo = anillo
    }

    /// Proyección del modelo del eje autonómico.
    public init(_ senal: LiquidAutonomico.Senal) {
        self.init(id: senal.id, etiqueta: senal.etiqueta, estado: senal.estado,
                  voto: senal.voto, fuera: senal.fuera, nota: senal.nota, a11y: senal.a11y)
    }
}

/// Las filas del eje/guardián dentro de su superficie de papel: separadores sangrados tras
/// la marca, esquinas del DS. Hermana de `LiquidLevelsList` pero con filas NO tocables.
/// Papel opaco (`.superficieSolida`) — las tarjetas internas de la hoja no muestrean el fondo.
public struct LiquidSignalList<Mini: View>: View {
    private let filas: [LiquidSignalFila]
    private let auroraTones: [Color]?
    private let mini: (LiquidSignalFila) -> Mini

    /// Lista del eje autonómico (sin mini-gráfica, sin aurora).
    public init(senales: [LiquidAutonomico.Senal]) where Mini == EmptyView {
        self.filas = senales.map(LiquidSignalFila.init)
        self.auroraTones = nil
        self.mini = { _ in EmptyView() }
    }

    /// Lista genérica (guardián): filas + mini-gráfica opcional por fila + filo de aurora.
    public init(filas: [LiquidSignalFila],
                auroraTones: [Color]? = nil,
                @ViewBuilder mini: @escaping (LiquidSignalFila) -> Mini) {
        self.filas = filas
        self.auroraTones = auroraTones
        self.mini = mini
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.element.id) { (i, f) in
                LiquidSignalRow(fila: f, mini: { mini(f) })
                if i < filas.count - 1 {
                    Rectangle()
                        .fill(LiquidColor.tinta10)
                        .frame(height: 1)
                        // Sangría: margen + marca (gota 24 o punto 8) + gap.
                        .padding(.leading, LiquidSpace.s400 + marcaAncho(f) + LiquidSpace.s300)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
        .overlay {
            if let tones = auroraTones, !tones.isEmpty {
                LiquidAuroraEdge(tones: tones, period: 44, radius: LiquidRadius.tarjeta)
            }
        }
    }

    private func marcaAncho(_ f: LiquidSignalFila) -> CGFloat {
        // Misma geometría que `LiquidSignalRow` (gota 24 / punto 8).
        f.icono != nil ? 24 : 8
    }
}

/// Geometría de la marca de `LiquidSignalRow` (file-level: los tipos genéricos no admiten
/// `static let` almacenados, ni siquiera en enums anidados).
private enum LiquidSignalMarcaGeo {
    /// Gota de señal (misma caja que la gota de tile por defecto).
    static let gotaSize: CGFloat = 24
    static let gotaIconSize: CGFloat = 13
    /// Punto del eje autonómico (riel de estado).
    static let puntoDiametro: CGFloat = 8
}

/// Una fila de señal: marca + nombre · (estado/voto o valor teñido), con la señal FUERA
/// iluminada al wash ámbar de la familia y su marca activa. Bajo la fila, nota y mini-gráfica
/// opcionales. NO es tocable: el desglose no navega a ningún lado.
public struct LiquidSignalRow<Mini: View>: View {
    private let fila: LiquidSignalFila
    private let mini: Mini

    /// El nombre escala con Dynamic Type junto a su estado y su voto (`captionLectura`), para que a
    /// tamaños AX no quede más chico que el número que lo acompaña. Mismo token que `LiquidLevelRow`.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = LiquidType.cuerpoLecturaBase

    /// El ámbar de atención para texto chico (AA): el estado «fuera» se lee en `atencionTexto`,
    /// no en el ámbar crudo (mismo criterio que `LiquidLevelRow`).
    private var tintaEstado: Color { fila.fuera ? LiquidColor.atencionTexto : LiquidColor.tinta500 }

    /// #inject r5 · El valor teñido con su hue 1:1, pero el ámbar de dato demotado a su voz
    /// de TEXTO: el ámbar crudo (#C4631F) mide ~4.1:1 sobre la tarjeta blanca — bajo el
    /// 4.5:1 de AA para el `datoMenor` (15) — y baja a `atencionTexto` (6.1:1), mismo
    /// criterio que `tintaEstado` y `LiquidLevelRow` (revisión adversarial DeepSeek+Grok).
    private var valorTinta: Color {
        guard let t = fila.valorTono else { return LiquidColor.tinta700 }
        return (t == LiquidColor.ambar || t == LiquidColor.atencion) ? LiquidColor.atencionTexto : t
    }

    public init(fila: LiquidSignalFila, @ViewBuilder mini: () -> Mini) {
        self.fila = fila
        self.mini = mini()
    }

    public init(senal: LiquidAutonomico.Senal) where Mini == EmptyView {
        self.init(fila: LiquidSignalFila(senal), mini: { EmptyView() })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            // Cabecera de la fila: UN elemento de a11y (label compuesto del caller). La
            // mini-gráfica vive FUERA para heredar su propio descriptor de gráfica.
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                HStack(spacing: LiquidSpace.s300) {
                    marca
                    Text(verbatim: fila.etiqueta)
                        .font(.system(size: etiquetaPt))
                        .fontWeight(fila.fuera ? .semibold : .regular)
                        .foregroundStyle(fila.fuera ? LiquidColor.tinta900 : LiquidColor.tinta700)
                    Spacer(minLength: LiquidSpace.s200)
                    if let valor = fila.valor {
                        Text(verbatim: valor)
                            .font(LiquidType.datoMenor)
                            .monospacedDigit()
                            .foregroundStyle(valorTinta)
                    } else {
                        if let estado = fila.estado {
                            Text(verbatim: estado)
                                .font(LiquidType.captionLectura)
                                .foregroundStyle(tintaEstado)
                        }
                        if let voto = fila.voto {
                            Text(verbatim: voto)
                                .font(LiquidType.captionLectura)
                                .monospacedDigit()
                                .foregroundStyle(fila.fuera ? LiquidColor.tinta900 : LiquidColor.tinta500)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                    }
                }
                if let nota = fila.nota {
                    LiquidNotaLine(nota, tono: LiquidColor.atencionTexto)
                        .padding(.leading, marcaAncho + LiquidSpace.s300)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: LiquidControl.hitTarget)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: fila.a11y))

            mini
                .padding(.leading, marcaAncho + LiquidSpace.s300)
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        .frame(maxWidth: .infinity, alignment: .leading)
        // La fila FUERA se ilumina con el ámbar (rango 10-16 % del épico). Las demás, gris.
        .background(fila.fuera ? LiquidColor.atencion.opacity(LiquidChart.filaActivaAlfa)
                               : Color.clear)
    }

    private var marcaAncho: CGFloat {
        fila.icono != nil ? LiquidSignalMarcaGeo.gotaSize : LiquidSignalMarcaGeo.puntoDiametro
    }

    @ViewBuilder private var marca: some View {
        if let icono = fila.icono {
            LiquidIconDrop(icono, tone: fila.iconoTono ?? LiquidColor.tinta500,
                           size: LiquidSignalMarcaGeo.gotaSize,
                           iconSize: LiquidSignalMarcaGeo.gotaIconSize)
                .overlay {
                    if fila.anillo {
                        Circle()
                            .strokeBorder(
                                LiquidColor.atencion.opacity(LiquidChart.marcaAnilloAlfa),
                                lineWidth: LiquidChart.marcaAnilloBorde)
                    }
                }
        } else {
            Circle()
                .fill(fila.fuera ? LiquidColor.atencion : LiquidColor.tinta10)
                .frame(width: LiquidSignalMarcaGeo.puntoDiametro,
                       height: LiquidSignalMarcaGeo.puntoDiametro)
        }
    }
}

#if DEBUG

// MARK: - Previews por estado

enum LiquidAutonomicoFixtures {

    static let plegable = LiquidAutonomico.Metodo(
        titulo: "Cómo se calcula",
        mostrar: "Ver cómo se calcula",
        ocultar: "Ocultar cómo se calcula",
        lineas: [
            "Tu FC en reposo contra tu propia base es el voto: la señal más densa y confiable de Apple, así carga este eje por sí sola.",
            "La VFC y la respiración se muestran como contexto, pero aquí no votan: la VFC de todo el día de Apple es demasiado ruidosa para confiar en ella, y la respiración la vigila el centinela junto con tu temperatura.",
            "La VFC de Apple es un promedio del día, no una lectura de la ventana de sueño, así que aquí es referencia y no voto.",
            "O'Grady et al., 2024 · Task Force, 1996 · Plews et al., 2013. Aproximado, sin valor clínico.",
        ])

    static let metodo = "Este eje cuenta como un solo voto, así una mañana pesada no puede empujar tu día hacia abajo más de una vez."
    static let metodoClave = "un solo voto"

    static func senal(_ id: String, _ etiqueta: String, _ estado: String, _ voto: String?,
                      fuera: Bool = false, nota: String? = nil) -> LiquidAutonomico.Senal {
        .init(id: id, etiqueta: etiqueta, estado: estado, voto: voto, fuera: fuera, nota: nota,
              a11y: "\(etiqueta), \(estado.lowercased())"
                  + (voto.map { ", \($0) del voto" } ?? "")
                  + (fuera ? ", fuera de tu rango" : ""))
    }

    static func base(nivel: String?, sinLectura: String? = nil, conteo: String,
                     senales: [LiquidAutonomico.Senal], enRango: Bool) -> LiquidAutonomico {
        LiquidAutonomico(
            titulo: "AUTONÓMICO",
            procedencia: "Apple Salud · esta mañana",
            explicacion: "Tu sistema nervioso en reposo, leído sobre todo desde tu pulso en reposo comparado con tu propia base. La VFC y la respiración también se muestran, pero no cargan el voto. Una aproximación, no un diagnóstico.",
            infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
            nivel: nivel, sinLectura: sinLectura, conteo: conteo,
            metodo: metodo, metodoClave: metodoClave,
            senales: senales, plegable: plegable, enRango: enRango)
    }

    /// En rango: la FC en reposo (el votante) amaneció en tu rango. VFC/respiración van como
    /// referencia. La lista queda ENTERAMENTE gris — el único color es la palabra verde.
    static let enRango = base(
        nivel: "En tu rango",
        conteo: "Tu pulso en reposo amaneció en tu rango.",
        senales: [
            senal("rhr", "FC en reposo", "En tu rango", nil),
            senal("hrv", "VFC", "En tu rango", "referencia"),
            senal("resp", "Respiración", "En tu rango", "referencia"),
        ],
        enRango: true)

    /// Fuera: la FC en reposo —el único votante en v3— amaneció por arriba de tu base. Solo esa
    /// fila se ilumina; VFC/respiración siguen como referencia gris (no votan, no tiñen).
    static let unaFuera = base(
        nivel: "Fuera de tu rango",
        conteo: "Tu pulso en reposo amaneció por arriba de tu base.",
        senales: [
            senal("rhr", "FC en reposo", "Arriba de tu base", nil, fuera: true),
            senal("hrv", "VFC", "Debajo de tu base", "referencia"),
            senal("resp", "Respiración", "En tu rango", "referencia"),
        ],
        enRango: false)

    /// Sin base: la base de FC todavía se está armando. CERO color; las señales quedan grises.
    static let sinBase = base(
        nivel: nil,
        sinLectura: "Sin base todavía",
        conteo: "Necesito algunas de tus propias noches para leer tu pulso en reposo.",
        senales: [
            senal("rhr", "FC en reposo", "Sin base", nil),
            senal("hrv", "VFC", "Sin base", nil),
            senal("resp", "Respiración", "Sin base", nil),
        ],
        enRango: false)
}

private func autonomicoPreview(_ model: LiquidAutonomico) -> some View {
    LiquidAutonomicoScreen(model)
        .padding(LiquidSpace.s550)
        .frame(width: 402, alignment: .topLeading)
        .background(LiquidSheetFondo(tone: model.tono))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Autonómico · en rango") { autonomicoPreview(LiquidAutonomicoFixtures.enRango) }
#Preview("Autonómico · FC fuera") { autonomicoPreview(LiquidAutonomicoFixtures.unaFuera) }
#Preview("Autonómico · sin base") { autonomicoPreview(LiquidAutonomicoFixtures.sinBase) }

#Preview("Autonómico · AX3 (filas apiladas)") {
    autonomicoPreview(LiquidAutonomicoFixtures.unaFuera)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
