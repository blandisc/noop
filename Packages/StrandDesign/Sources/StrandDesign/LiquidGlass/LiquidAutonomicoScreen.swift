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
        /// El porcentaje del voto que cargó, YA formateado con locale («40 %»); `nil` cuando la
        /// señal no votó (sin base / sin lectura) — entonces la columna se queda muda.
        public let voto: String?
        /// ¿Esta señal amaneció fuera de tu rango? Es la única fila con color (wash + punto ámbar).
        public let fuera: Bool
        /// Nota bajo la fila, ya localizada — reservada para la respiración cuando cruzó el umbral
        /// por su cuenta («Tu respiración sola bastó para marcar el eje»). `nil` = sin nota.
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
    /// El conteo que sostiene la palabra («Tus 3 señales pesan como una sola lectura.»).
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

/// Las tres filas del eje dentro de su superficie de vidrio: separadores sangrados tras el punto,
/// esquinas del DS. Hermana de `LiquidLevelsList` pero con filas NO tocables y columna de voto.
struct LiquidSignalList: View {
    let senales: [LiquidAutonomico.Senal]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(senales.enumerated()), id: \.element.id) { (i, s) in
                LiquidSignalRow(senal: s)
                if i < senales.count - 1 {
                    Rectangle()
                        .fill(LiquidColor.tinta10)
                        .frame(height: 1)
                        // Sangría: margen de la fila + el punto + su gap, para que la línea
                        // arranque bajo el TEXTO y la columna de puntos se lea como un riel.
                        .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficie)
    }
}

/// Una fila de señal: punto + nombre · estado · voto, con la señal FUERA iluminada al 12 % de
/// ámbar (mismo rango que `LiquidBandsTable`/`LiquidLevelRow`) y su punto lleno; las que están en
/// rango quedan en gris — color solo en la que se salió. Bajo la fila, una nota opcional (la
/// respiración que cruzó sola). NO es tocable: el desglose no navega a ningún lado.
struct LiquidSignalRow: View {
    let senal: LiquidAutonomico.Senal

    /// El nombre escala con Dynamic Type junto a su estado y su voto (`captionLectura`), para que a
    /// tamaños AX no quede más chico que el número que lo acompaña. Mismo token que `LiquidLevelRow`.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = LiquidType.cuerpoLecturaBase

    /// El ámbar de atención para texto chico (AA): el estado «fuera» y el voto de la fila que se
    /// salió se leen en `atencionTexto`, no en el ámbar crudo (mismo criterio que `LiquidLevelRow`).
    private var tintaEstado: Color { senal.fuera ? LiquidColor.atencionTexto : LiquidColor.tinta500 }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s300) {
                punto
                Text(verbatim: senal.etiqueta)
                    .font(.system(size: etiquetaPt))
                    .fontWeight(senal.fuera ? .semibold : .regular)
                    .foregroundStyle(senal.fuera ? LiquidColor.tinta900 : LiquidColor.tinta700)
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: senal.estado)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(tintaEstado)
                if let voto = senal.voto {
                    Text(verbatim: voto)
                        .font(LiquidType.captionLectura)
                        .monospacedDigit()
                        .foregroundStyle(senal.fuera ? LiquidColor.tinta900 : LiquidColor.tinta500)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            if let nota = senal.nota {
                LiquidNotaLine(nota, tono: LiquidColor.atencionTexto)
                    // Alineada con el TEXTO de la fila (tras el punto y su gap).
                    .padding(.leading, 8 + LiquidSpace.s300)
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        // La fila FUERA se ilumina con el ámbar (rango 10-16 % del épico). Las demás, gris.
        .background(senal.fuera ? LiquidColor.atencion.opacity(LiquidChart.filaActivaAlfa)
                                : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: senal.a11y))
    }

    /// El punto de la señal: lleno de ámbar cuando está fuera; tenue si está en rango.
    @ViewBuilder private var punto: some View {
        Circle()
            .fill(senal.fuera ? LiquidColor.atencion : LiquidColor.tinta10)
            .frame(width: 8, height: 8)
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
            "Tu FC en reposo, tu VFC y tu respiración se promedian con peso (40 % · 35 % · 25 %) contra tu propia base.",
            "La respiración puede marcar el eje por su cuenta si sube bastante, aunque el promedio no cruce.",
            "La VFC de Apple es un promedio del día, no una medición de la ventana de sueño: esto lee tus señales en reposo contra tu propia norma.",
            "Task Force, 1996 · Plews et al., 2013. Aproximado, sin valor clínico.",
        ])

    static let metodo = "Tus tres señales cuentan como una sola lectura, para que una mala noche no cuente tres veces."
    static let metodoClave = "una sola lectura"

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
            explicacion: "Tu sistema nervioso en reposo: FC en reposo, VFC y respiración contra tu propia base. Es una aproximación, no un diagnóstico.",
            infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
            nivel: nivel, sinLectura: sinLectura, conteo: conteo,
            metodo: metodo, metodoClave: metodoClave,
            senales: senales, plegable: plegable, enRango: enRango)
    }

    /// En rango: nadie fuera. La lista queda ENTERAMENTE gris — el único color es la palabra verde.
    static let enRango = base(
        nivel: "En tu rango",
        conteo: "Tus 3 señales amanecieron en tu rango.",
        senales: [
            senal("rhr", "FC en reposo", "En tu rango", "40 %"),
            senal("hrv", "VFC", "En tu rango", "35 %"),
            senal("resp", "Respiración", "En tu rango", "25 %"),
        ],
        enRango: true)

    /// Una señal fuera: la VFC amaneció debajo de tu base. Fila washeada al 12 % de ámbar.
    static let unaFuera = base(
        nivel: "Fuera de tu rango",
        conteo: "1 de tus 3 señales amaneció fuera de tu rango.",
        senales: [
            senal("rhr", "FC en reposo", "En tu rango", "40 %"),
            senal("hrv", "VFC", "Debajo de tu base", "35 %", fuera: true),
            senal("resp", "Respiración", "En tu rango", "25 %"),
        ],
        enRango: false)

    /// Respiración sola: cruzó el umbral por su cuenta y marcó el eje aunque el promedio no cruzara.
    static let respSola = base(
        nivel: "Fuera de tu rango",
        conteo: "Tu respiración marcó el eje por su cuenta.",
        senales: [
            senal("rhr", "FC en reposo", "En tu rango", "40 %"),
            senal("hrv", "VFC", "En tu rango", "35 %"),
            senal("resp", "Respiración", "Bastante arriba", "25 %", fuera: true,
                  nota: "Tu respiración sola bastó para marcar el eje esta mañana."),
        ],
        enRango: false)

    /// Sin base: la base todavía se está armando. CERO color; las señales quedan grises y sin voto.
    static let sinBase = base(
        nivel: nil,
        sinLectura: "Sin base todavía",
        conteo: "Necesito unas noches tuyas para medir tu eje autonómico.",
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
#Preview("Autonómico · una señal fuera") { autonomicoPreview(LiquidAutonomicoFixtures.unaFuera) }
#Preview("Autonómico · respiración sola") { autonomicoPreview(LiquidAutonomicoFixtures.respSola) }
#Preview("Autonómico · sin base") { autonomicoPreview(LiquidAutonomicoFixtures.sinBase) }

#Preview("Autonómico · AX3 (filas apiladas)") {
    autonomicoPreview(LiquidAutonomicoFixtures.unaFuera)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
