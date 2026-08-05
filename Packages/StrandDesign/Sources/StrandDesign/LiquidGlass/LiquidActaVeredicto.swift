import SwiftUI

// MARK: - Liquid Glass · «Cómo llegué a este veredicto» — LA BOLETA (rediseño r3)
//
// La hoja que contesta la ÚNICA pregunta que el héroe de Hoy provoca: «¿de dónde salió esa
// palabra?». Rediseñada desde cero como BOLETA de escrutinio (specs /ux + /ui 2026-08-04,
// dirección «acta de escrutinio»): el veredicto manda en `veredictoHoja` (30/700), cada
// votante muestra su voto en un mini-riel (`LiquidVotoRiel` — banda = tu patrón, joya = tu
// amanecer, la palabra del voto debajo), los vigilantes son fichas punteadas que no votan,
// y el párrafo del método bajó ÍNTEGRO al plegable «Cómo se calcula»: la boleta se explica
// sola, el método es letra chica.
//
// REGLAS QUE ESTA HOJA NO ROMPE
//  · El color saturado vive SOLO en la palabra del veredicto, la cláusula del resumen
//    (text-tier AA) y los rieles; el wash de fila fuera va al token de I1. Gotas y fichas
//    en tinta. Sin veredicto: CERO color en toda la hoja.
//  · Paridad héroe↔acta (gate /cso B1): la palabra grande es EXACTAMENTE la del héroe.
//  · Las filas NO son tocables; el riel es decorativo para VoiceOver — la lectura viaja en
//    el label compuesto de cada votante.
//  · El sellado (los votos caen, la palabra se estampa, el wash respira una vez) corre UNA
//    sola vez al abrir y con Reduce Motion aparece asentado (spec /ux D3) — vive en
//    `LiquidBoletaCard`. La siembra de motas se retiró de esta hoja (D10).
//
// Contrato D3: TODOS los strings llegan YA localizados y compuestos del caller. El DS no
// conoce locales ni `Preparedness`; el riel es CUALITATIVO por decisión de producto (la
// allow-list de esta superficie prohíbe publicar números del motor).

public struct LiquidActa: Sendable {

    /// Un votante de la boleta: quién, contra qué, y su voto en el riel.
    public struct Fila: Sendable, Identifiable {
        public let id: String
        /// El glifo de la gota (SIEMPRE pintada en tinta — el hue 1:1 no entra a la boleta).
        public let glifo: LiquidIcon.Glyph
        /// El nombre que el usuario YA ve en el orbe («Autonómico»).
        public let etiqueta: String
        /// Contra qué se comparó, CUALITATIVO («FC en reposo · contra tu base»).
        public let sub: String
        /// El voto dibujado (dentro / fuera-abajo / fuera-arriba / calibrando / sin lectura).
        public let estado: LiquidVotoRiel.Estado
        /// El tipo de umbral — el número de ticks del riel (rango = 2 · mínimo = 1).
        public let umbral: LiquidVotoRiel.Umbral
        /// ¿Esta fila volteó el veredicto? Es la única con wash.
        public let fuera: Bool
        /// El tono del VOTO de esta fila (no del veredicto): con histéresis una fila puede
        /// encender en ámbar bajo una palabra verde.
        public let tonoVoto: Color
        /// La palabra del voto bajo el riel («dentro» / «fuera» / «sin dato» / «··»).
        public let palabra: String
        /// Label compuesto de VoiceOver, YA localizado — el estado es audible sin color.
        public let a11y: String

        public init(id: String, glifo: LiquidIcon.Glyph, etiqueta: String, sub: String,
                    estado: LiquidVotoRiel.Estado, umbral: LiquidVotoRiel.Umbral,
                    fuera: Bool, tonoVoto: Color, palabra: String, a11y: String) {
            self.id = id
            self.glifo = glifo
            self.etiqueta = etiqueta
            self.sub = sub
            self.estado = estado
            self.umbral = umbral
            self.fuera = fuera
            self.tonoVoto = tonoVoto
            self.palabra = palabra
            self.a11y = a11y
        }
    }

    /// Una nota bajo la boleta. `avisa` la sube a `atencionTexto` y la pega a la boleta:
    /// reservado para lo que CAMBIA la lectura (el empujón de tendencia), nunca para el
    /// contexto que solo acompaña (la carga).
    public struct Nota: Sendable, Identifiable {
        public let id: String
        public let texto: String
        public let avisa: Bool

        public init(id: String, texto: String, avisa: Bool = false) {
            self.id = id
            self.texto = texto
            self.avisa = avisa
        }
    }

    /// La profundidad de la base sobre la que se para el veredicto.
    public enum Confianza: Sendable {
        /// La base todavía NO alcanza para votar: tarjeta con barra de progreso.
        case calibrando(titulo: String, leyenda: String, hechas: Int, necesarias: Int)
        /// La base ya es usable pero joven: prosa, SIN barra.
        case nota(String)
    }

    /// El plegable de transparencia matemática (ahora también carga el método en llano).
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
    /// Procedencia + sello de fecha, YA compuestos («Apple Salud · esta mañana · 4 AGO») —
    /// el micro-momento de acta oficial (spec /ux D2).
    public let procedencia: String
    public let explicacion: String
    public let infoMostrar: String
    public let infoOcultar: String
    /// La palabra grande — la del veredicto (paridad héroe) o la del estado sin veredicto
    /// («Conociéndote», «Sin lectura», «Lectura de día»). Nunca nil en la boleta.
    public let nivel: String?
    public let sinLectura: String?
    /// La frase-resumen bajo la palabra: sostiene el veredicto o cuenta el desfase de
    /// histéresis (spec /ux D5). Su cláusula clave va en `conteoClave`.
    public let conteo: String
    public let conteoClave: String?
    public let filas: [Fila]
    /// «Vigilan sin votar» + fichas — vacío cuando no hay veredicto (spec /ux D7).
    public let vigilantesLabel: String?
    public let vigilantes: [String]
    public let vigilantesA11y: String?
    public let notas: [Nota]
    public let confianza: Confianza?
    public let plegable: Metodo?
    public let verMas: String?
    public let verMasHint: String?
    /// El tono del veredicto — el del héroe. Sin veredicto: tinta/500 y cero color.
    public let tono: Color
    /// El tono de la fila FUERA (histéresis: puede ser ámbar bajo palabra verde).
    public let tonoFilas: Color

    public init(titulo: String, procedencia: String, explicacion: String,
                infoMostrar: String, infoOcultar: String,
                nivel: String?, sinLectura: String? = nil,
                conteo: String, conteoClave: String? = nil,
                filas: [Fila],
                vigilantesLabel: String? = nil, vigilantes: [String] = [],
                vigilantesA11y: String? = nil,
                notas: [Nota] = [], confianza: Confianza? = nil,
                plegable: Metodo? = nil, verMas: String? = nil, verMasHint: String? = nil,
                tono: Color, tonoFilas: Color? = nil) {
        self.titulo = titulo
        self.procedencia = procedencia
        self.explicacion = explicacion
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
        self.nivel = nivel
        self.sinLectura = sinLectura
        self.conteo = conteo
        self.conteoClave = conteoClave
        self.filas = filas
        self.vigilantesLabel = vigilantesLabel
        self.vigilantes = vigilantes
        self.vigilantesA11y = vigilantesA11y
        self.notas = notas
        self.confianza = confianza
        self.plegable = plegable
        self.verMas = verMas
        self.verMasHint = verMasHint
        self.tono = tono
        self.tonoFilas = tonoFilas ?? tono
    }
}

// MARK: - La hoja

/// El cuerpo de la boleta. El caller la envuelve en `LiquidMetricSheet(tono:detent:)`.
public struct LiquidActaVeredicto: View {
    private let model: LiquidActa
    private let onVerMas: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public init(_ model: LiquidActa, siembra: Bool = false,
                onVerMas: (() -> Void)? = nil) {
        // `siembra` se conserva en la firma por compatibilidad y se IGNORA: la entrada de
        // esta hoja es el sellado de los votos (spec /ux D3/D10), no las motas.
        self.model = model
        self.onVerMas = onVerMas
    }

    public var body: some View {
        // Ritmo a 3 velocidades (spec /ui §7): apretado dentro de un elemento (s150),
        // medio dentro de un grupo (s300/s400), s550 solo ENTRE grupos.
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            // 1 · Identidad: título + ⓘ + procedencia con sello de fecha.
            LiquidSheetHeader(icono: nil, titulo: model.titulo, tono: model.tono,
                              numeral: nil,
                              origenEtiqueta: model.procedencia,
                              explicacion: model.explicacion,
                              infoMostrar: model.infoMostrar,
                              infoOcultar: model.infoOcultar)

            // 2 · Veredicto + boleta (la evidencia del resumen es la tarjeta: mismo grupo).
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    Text(verbatim: model.nivel ?? model.sinLectura ?? "")
                        .font(LiquidType.veredictoHoja)
                        .tracking(LiquidType.veredictoHojaTracking)
                        .foregroundStyle(model.tono)
                    LiquidReadingLine(model.conteo, highlight: model.conteoClave,
                                      highlightTone: tonoResumen)
                }
                // Veredicto + resumen = UNA parada de VoiceOver con rasgo de encabezado.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidBoletaCard(votantes: model.filas.map {
                        .init(id: $0.id, glifo: $0.glifo, nombre: $0.etiqueta, sub: $0.sub,
                              estado: $0.estado, umbral: $0.umbral, fuera: $0.fuera,
                              tonoVoto: $0.tonoVoto, palabra: $0.palabra, a11y: $0.a11y)
                    })
                    // El aviso que cambia la lectura va PEGADO a la boleta (spec /ux D1).
                    ForEach(model.notas.filter(\.avisa)) { nota in
                        LiquidNotaLine(nota.texto, tono: LiquidColor.atencionTexto)
                    }
                    vigilantesFila
                }

                ForEach(model.notas.filter { !$0.avisa }) { nota in
                    LiquidNotaLine(nota.texto, tono: LiquidColor.tinta500)
                }
            }

            // 3 · Letra chica: confianza + método + salida.
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                confianzaBloque
                if let plegable = model.plegable {
                    LiquidMetodo(title: plegable.titulo,
                                 mostrar: plegable.mostrar,
                                 ocultar: plegable.ocultar) {
                        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                            ForEach(Array(plegable.lineas.enumerated()), id: \.offset) { _, linea in
                                LiquidNotaLine(linea)
                            }
                        }
                    }
                }
                if let verMas = model.verMas, let onVerMas {
                    LiquidVerMas(title: verMas, hint: model.verMasHint, tone: model.tono,
                                 anchoCompleto: true, action: onVerMas)
                }
            }
        }
    }

    /// La cláusula del resumen en la voz de TEXTO del tono (pisos AA §8.6): verde baja a
    /// profundo, ámbar a su lectura; sin veredicto habla en tinta plena.
    private var tonoResumen: Color {
        if model.tono == LiquidColor.verdePrimario { return LiquidColor.verdeProfundo }
        if model.tono == LiquidColor.atencion || model.tono == LiquidColor.ambar {
            return LiquidColor.atencionTexto
        }
        if model.tono == LiquidColor.tinta500 { return LiquidColor.tinta900 }
        return model.tono
    }

    @ViewBuilder private var vigilantesFila: some View {
        if let label = model.vigilantesLabel, !model.vigilantes.isEmpty {
            Group {
                if tamanoTexto >= .accessibility1 {
                    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                        Text(verbatim: label)
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                        HStack(spacing: LiquidSpace.s150) {
                            ForEach(model.vigilantes, id: \.self) { LiquidVigilanteChip(nombre: $0) }
                        }
                    }
                } else {
                    HStack(spacing: LiquidSpace.s200) {
                        Text(verbatim: label)
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                        ForEach(model.vigilantes, id: \.self) { LiquidVigilanteChip(nombre: $0) }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: model.vigilantesA11y ?? label))
        }
    }

    @ViewBuilder private var confianzaBloque: some View {
        switch model.confianza {
        case .calibrando(let titulo, let leyenda, let hechas, let necesarias):
            LiquidCalibracionCard(titulo: titulo, leyenda: leyenda,
                                  hechas: hechas, necesarias: necesarias, tono: model.tono)
        case .nota(let texto):
            LiquidNotaLine(texto)
        case nil:
            EmptyView()
        }
    }
}

#if DEBUG

// MARK: - Fixtures por estado (los mismos nombres que consume el arnés de renders)

enum LiquidActaFixtures {

    private static let plegableLineas = [
        "Tu FC en reposo y tu sueño se leen como votos separados, para que una mala noche no cuente dos veces. Tu respiración y tu temperatura solo vigilan: aquí no votan.",
        "Un veredicto nuevo tiene que repetirse dos días seguidos antes de reemplazar al anterior.",
        "La VFC de Apple es un promedio de día, no una medición de la ventana de sueño: esto lee tus señales en reposo contra tu propia norma.",
        "O'Grady et al., 2024 · Task Force, 1996 · Plews et al., 2013. Aproximado, sin claim clínico.",
    ]

    private static let plegable = LiquidActa.Metodo(
        titulo: "Cómo se calcula", mostrar: "Mostrar método", ocultar: "Ocultar método",
        lineas: plegableLineas)

    private static func filaAuto(_ estado: LiquidVotoRiel.Estado, fuera: Bool,
                                 tonoVoto: Color, palabra: String,
                                 sub: String = "FC en reposo · contra tu base") -> LiquidActa.Fila {
        .init(id: "auto", glifo: .corazon, etiqueta: "Autonómico", sub: sub,
              estado: estado, umbral: .rango, fuera: fuera, tonoVoto: tonoVoto,
              palabra: palabra,
              a11y: "Autonómico, \(palabra), \(sub)\(fuera ? ", fuera de tu rango" : "").")
    }

    private static func filaSueno(_ estado: LiquidVotoRiel.Estado, fuera: Bool,
                                  tonoVoto: Color, palabra: String,
                                  sub: String = "anoche · contra un mínimo fijo") -> LiquidActa.Fila {
        .init(id: "sleep", glifo: .luna, etiqueta: "Sueño", sub: sub,
              estado: estado, umbral: .minimo, fuera: fuera, tonoVoto: tonoVoto,
              palabra: palabra,
              a11y: "Sueño, \(palabra), \(sub)\(fuera ? ", fuera de tu rango" : "").")
    }

    private static func base(nivel: String?, sinLectura: String? = nil,
                             conteo: String, conteoClave: String? = nil,
                             filas: [LiquidActa.Fila],
                             conVigilantes: Bool = true,
                             notas: [LiquidActa.Nota] = [],
                             confianza: LiquidActa.Confianza? = nil,
                             tono: Color, tonoFilas: Color? = nil) -> LiquidActa {
        LiquidActa(
            titulo: "Preparación",
            procedencia: "Apple Salud · esta mañana · 4 AGO",
            explicacion: "El veredicto de cómo amaneciste: tus señales contra tu propia base. Es una aproximación, no un diagnóstico.",
            infoMostrar: "Mostrar explicación", infoOcultar: "Ocultar explicación",
            nivel: nivel, sinLectura: sinLectura,
            conteo: conteo, conteoClave: conteoClave,
            filas: filas,
            vigilantesLabel: conVigilantes ? "Vigilan sin votar" : nil,
            vigilantes: conVigilantes ? ["Respiración", "Temperatura"] : [],
            vigilantesA11y: conVigilantes
                ? "Vigilan sin votar: respiración y temperatura." : nil,
            notas: notas, confianza: confianza, plegable: plegable,
            verMas: "Ver más en Tendencias", verMasHint: "Abre el detalle",
            tono: tono, tonoFilas: tonoFilas)
    }

    static let verde = base(
        nivel: "En rango",
        conteo: "Tus dos votos cayeron dentro.", conteoClave: "dentro",
        filas: [filaAuto(.dentro, fuera: false, tonoVoto: LiquidColor.verdePrimario, palabra: "dentro"),
                filaSueno(.dentro, fuera: false, tonoVoto: LiquidColor.verdePrimario, palabra: "dentro")],
        notas: [.init(id: "carga", texto: "Hoy hubo entrenamiento. Se mide, pero no cambia tu veredicto.")],
        confianza: .nota("Tu veredicto se apoya en 9 noches tuyas; a las 14 tu base queda firme."),
        tono: LiquidColor.verdePrimario)

    static let ambar = base(
        nivel: "Hoy ve leve",
        conteo: "El sueño votó fuera; lo autonómico, dentro.", conteoClave: "votó fuera",
        filas: [filaAuto(.dentro, fuera: false, tonoVoto: LiquidColor.verdePrimario, palabra: "dentro"),
                filaSueno(.fueraAbajo, fuera: true, tonoVoto: LiquidColor.atencion, palabra: "fuera")],
        notas: [.init(id: "voto", texto: "Un voto fuera aligera el día; no lo tumba.")],
        tono: LiquidColor.atencion)

    static let rojo = base(
        nivel: "Recupera",
        conteo: "Tus dos votos cayeron fuera.", conteoClave: "fuera",
        filas: [filaAuto(.fueraArriba, fuera: true, tonoVoto: LiquidColor.negativo, palabra: "fuera"),
                filaSueno(.fueraAbajo, fuera: true, tonoVoto: LiquidColor.negativo, palabra: "fuera")],
        notas: [.init(id: "aviso", texto: "Los dos fuera a la vez: hoy toca recuperar, no empujar.", avisa: true)],
        tono: LiquidColor.negativo)

    static let histeresis = base(
        nivel: "En rango",
        conteo: "Hoy hubo un voto fuera. Un veredicto nuevo necesita repetirse dos días para reemplazar al de ayer.",
        conteoClave: "un voto fuera",
        filas: [filaAuto(.dentro, fuera: false, tonoVoto: LiquidColor.verdePrimario, palabra: "dentro"),
                filaSueno(.fueraAbajo, fuera: true, tonoVoto: LiquidColor.atencion, palabra: "fuera")],
        tono: LiquidColor.verdePrimario, tonoFilas: LiquidColor.atencion)

    static let tendencia = base(
        nivel: "Recupera",
        conteo: "Un voto cayó fuera y tu VFC nocturna viene bajando: por eso hoy pide recuperar.",
        conteoClave: "viene bajando",
        filas: [filaAuto(.fueraArriba, fuera: true, tonoVoto: LiquidColor.negativo, palabra: "fuera"),
                filaSueno(.dentro, fuera: false, tonoVoto: LiquidColor.verdePrimario, palabra: "dentro")],
        tono: LiquidColor.negativo)

    static let lecturaDeDia = base(
        nivel: "Lectura de día",
        conteo: "Anoche no se grabó sueño: sin su voto no hay quórum para un veredicto.",
        filas: [filaAuto(.dentro, fuera: false, tonoVoto: LiquidColor.tinta500, palabra: "dentro"),
                filaSueno(.sinLectura, fuera: false, tonoVoto: LiquidColor.tinta500, palabra: "sin dato")],
        conVigilantes: false,
        notas: [.init(id: "noche", texto: "Duerme con tu Apple Watch y mañana la boleta se llena sola.")],
        tono: LiquidColor.tinta500)

    static let sinVeredicto = base(
        nivel: "Conociéndote",
        conteo: "La boleta se está formando con tus primeras noches.",
        filas: [filaAuto(.calibrando, fuera: false, tonoVoto: LiquidColor.tinta500,
                         palabra: "··", sub: "aprendiendo tu base"),
                filaSueno(.dentro, fuera: false, tonoVoto: LiquidColor.tinta500, palabra: "dentro")],
        conVigilantes: false,
        confianza: .calibrando(titulo: "Calibrando tu base", leyenda: "2 de 4 noches",
                               hechas: 2, necesarias: 4),
        tono: LiquidColor.tinta500)

    static let sinPermiso = base(
        nivel: "Sin lectura",
        conteo: "Sin conexión con Apple Salud no hay nada que contar.",
        filas: [filaAuto(.sinLectura, fuera: false, tonoVoto: LiquidColor.tinta500, palabra: "sin dato",
                         sub: "contra tu base"),
                filaSueno(.sinLectura, fuera: false, tonoVoto: LiquidColor.tinta500, palabra: "sin dato",
                          sub: "contra un mínimo fijo")],
        conVigilantes: false,
        notas: [.init(id: "permiso",
                      texto: "Conecta Apple Salud en Ajustes y tu veredicto de cada mañana aparecerá aquí.",
                      avisa: true)],
        tono: LiquidColor.tinta500)
}

#Preview("Acta · En rango") {
    ScrollView {
        LiquidActaVeredicto(LiquidActaFixtures.verde, onVerMas: {})
            .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Acta · Una fuera") {
    ScrollView {
        LiquidActaVeredicto(LiquidActaFixtures.ambar, onVerMas: {})
            .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Acta · Histéresis") {
    ScrollView {
        LiquidActaVeredicto(LiquidActaFixtures.histeresis, onVerMas: {})
            .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Acta · Conociéndote") {
    ScrollView {
        LiquidActaVeredicto(LiquidActaFixtures.sinVeredicto, onVerMas: {})
            .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.tinta500))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Acta · AX5") {
    ScrollView {
        LiquidActaVeredicto(LiquidActaFixtures.ambar, onVerMas: {})
            .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
    .environment(\.dynamicTypeSize, .accessibility5)
    .environment(\.liquidMotionDisabled, true)
}
#endif
