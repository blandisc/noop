import SwiftUI

// MARK: - Liquid Glass · «Cómo llegué a este veredicto» (acta de votos)
//
// La hoja que contesta la ÚNICA pregunta que el héroe de Hoy provoca: «¿de dónde salió esa
// palabra?». No es una explicación narrada — es un ACTA: quién votó, qué dijo cada quien,
// contra qué se comparó, y quién no vota.
//
// CERO componentes nuevos: esto es una COMPOSICIÓN con contrato (el mismo patrón de
// `LiquidHoyContent`) sobre piezas que ya existen —`LiquidSheetHeader`, `LiquidFraseNivel`,
// `LiquidReadingLine`, `LiquidBandsTable`, `LiquidNotaLine`, `LiquidCalibracionCard`,
// `LiquidMetodo`, `LiquidVerMas`— más el cascarón `LiquidMetricSheet` que pone el caller.
// Existe como componente (y no suelta en la pantalla) porque el orden de los bloques ES el
// argumento: cambiarlo cambia lo que la hoja afirma.
//
// REGLAS QUE ESTA HOJA NO ROMPE
//  · Un solo énfasis de color: la PALABRA del veredicto. La fila que volteó el veredicto
//    lleva wash + punto (no texto en tono, ver `LiquidBandsTable`), y la barra de
//    calibración solo existe mientras la base todavía se está armando. En el estado bueno
//    la tabla queda ENTERAMENTE gris.
//  · La frase del método va en NEGRITA sobre tinta/900, jamás en el tono (`LiquidReadingLine`
//    nunca es neutral: si no se le pasa `highlight` deriva la primera cláusula y la pinta en
//    verde por default — aquí se le pasan las dos cosas a propósito).
//  · Las filas NO son tocables: la navegación por fila la aprueba /ux, y un chevron que no
//    lleva a ningún lado es peor que ninguno.
//
// Contrato D3: TODOS los strings llegan YA localizados y compuestos del caller. El DS no
// conoce locales, ni `Preparedness`, ni umbrales — la columna «contra qué base» es
// CUALITATIVA por decisión de producto (los cortes del motor son knobs sin firmar por
// `/cso` y la allow-list de esta superficie prohíbe publicar números).

public struct LiquidActa: Sendable {

    /// Una señal del acta: quién votó, qué dijo y contra qué se comparó.
    public struct Fila: Sendable, Identifiable {
        public let id: String
        /// El nombre que el usuario YA ve en el orbe («Autonómico»).
        public let etiqueta: String
        /// Qué dijo esta señal («En tu rango» · «Debajo de tu base» · «Sin datos»).
        public let dijo: String
        /// Contra qué se comparó, CUALITATIVO y corto («contra tu base»). Corto a propósito:
        /// es la cuarta columna de la fila.
        public let base: String
        /// ¿Esta señal es la que volteó el veredicto? Es la única fila con color.
        public let fuera: Bool
        /// Label compuesto de VoiceOver, YA localizado (el color no habla: el estado «fuera»
        /// tiene que ser audible).
        public let a11y: String

        public init(id: String, etiqueta: String, dijo: String, base: String,
                    fuera: Bool, a11y: String) {
            self.id = id
            self.etiqueta = etiqueta
            self.dijo = dijo
            self.base = base
            self.fuera = fuera
            self.a11y = a11y
        }
    }

    /// Una nota bajo el acta. `avisa` la sube a `atencionTexto`: reservado para lo que
    /// CAMBIA la lectura de lo que estás viendo (la histéresis, el empujón de tendencia),
    /// nunca para el contexto que solo acompaña (la carga).
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
        /// La base ya es usable pero joven: prosa, SIN barra (una barra de progreso sobre
        /// una base que ya funciona presenta una meta que el motor no tiene).
        case nota(String)
    }

    /// El plegable de transparencia matemática.
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
    /// La palabra del veredicto («Bien, con un detalle»). `nil` = todavía no hay veredicto.
    public let nivel: String?
    /// El texto que sustituye a la palabra cuando no hay veredicto («Aún sin veredicto»).
    public let sinLectura: String?
    /// El conteo que sostiene la palabra («1 de tus 3 señales amaneció fuera de tu rango.»).
    public let conteo: String
    /// La frase que explica el método en llano, con su cláusula clave en negrita.
    public let metodo: String
    public let metodoClave: String
    public let filas: [Fila]
    public let notas: [Nota]
    public let confianza: Confianza?
    public let plegable: Metodo?
    public let verMas: String?
    public let verMasHint: String?
    /// El tono del veredicto — el mismo que ya usa el héroe de Hoy. Sin veredicto:
    /// tinta/500 (y entonces NO hay una sola gota de color en la hoja).
    public let tono: Color
    /// El tono de la fila FUERA. Normalmente es el del veredicto, pero no siempre: con la
    /// histéresis activa el veredicto puede ser verde mientras una señal amaneció fuera, y
    /// pintar esa fila de verde diría justo lo contrario de lo que pasó. El wash de la fila
    /// significa «esta es la que se salió», así que su color lo decide el ESTADO de la fila.
    public let tonoFilas: Color

    public init(titulo: String, procedencia: String, explicacion: String,
                infoMostrar: String, infoOcultar: String,
                nivel: String?, sinLectura: String? = nil, conteo: String,
                metodo: String, metodoClave: String,
                filas: [Fila], notas: [Nota] = [], confianza: Confianza? = nil,
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
        self.metodo = metodo
        self.metodoClave = metodoClave
        self.filas = filas
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

/// El cuerpo de la hoja «Cómo llegué a esto». El caller la envuelve en
/// `LiquidMetricSheet(tono:detent:)` — el cascarón pone fondo, grip, detents y márgenes.
public struct LiquidActaVeredicto: View {
    private let model: LiquidActa
    private let siembra: Bool
    private let onVerMas: (() -> Void)?

    public init(_ model: LiquidActa, siembra: Bool = false,
                onVerMas: (() -> Void)? = nil) {
        self.model = model
        self.siembra = siembra
        self.onVerMas = onVerMas
    }

    public var body: some View {
        // El ritmo de la hoja (s550 entre bloques) es el del cascarón; aquí se repite
        // porque la composición también se renderiza suelta en el arnés de estados.
        VStack(alignment: .leading, spacing: LiquidSpace.s550) {
            // 1 · Qué estoy viendo. Sin glifo (precedente de recovery) y sin numeral: el
            // dato de esta hoja es una PALABRA, y vive en el bloque 2.
            LiquidSheetHeader(icono: nil, titulo: model.titulo, tono: model.tono,
                              numeral: nil,
                              origenEtiqueta: model.procedencia,
                              explicacion: model.explicacion,
                              infoMostrar: model.infoMostrar,
                              infoOcultar: model.infoOcultar)
                // C.4 (FER-21): la SIEMBRA — al abrir, una constelación decorativa
                // llega y se disuelve tras el header (variante A del dueño: saludo de
                // materia, el acta termina en papel puro). El texto real nunca es
                // motas; el overlay no intercepta taps (el ⓘ sigue vivo).
                .background {
                    if siembra {
                        LiquidSiembraMotas(tono: model.tono)
                            .padding(.horizontal, -LiquidSpace.s300)
                            .padding(.top, -LiquidSpace.s300)
                    }
                }

            // 2 · El veredicto COMO DATO + el conteo que lo sostiene.
            LiquidFraseNivel(nivel: model.nivel, conteo: model.conteo,
                             tono: model.tono, sinLectura: model.sinLectura)

            // 3 · Cómo se decide, en una frase. En NEGRITA sobre tinta/900: el único color
            // de la hoja lo tiene la palabra de arriba.
            LiquidReadingLine(model.metodo, highlight: model.metodoClave,
                              highlightTone: LiquidColor.tinta900)

            // 4 · El acta: quién votó y qué dijo.
            LiquidBandsTable(filas: model.filas.map {
                .init(etiqueta: $0.etiqueta, rango: $0.dijo, conteo: $0.base,
                      activa: $0.fuera, a11y: $0.a11y)
            }, tono: model.tonoFilas)

            // 5 · Quién no votó + los avisos que cambian la lectura.
            if !model.notas.isEmpty {
                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    ForEach(model.notas) { nota in
                        LiquidNotaLine(nota.texto,
                                       tono: nota.avisa ? LiquidColor.atencionTexto
                                                        : LiquidColor.tinta500)
                    }
                }
            }

            // 6 · Cuánta base hay debajo.
            confianzaBloque

            // 7 · Letra chica.
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

            // 8 · Salida.
            if let verMas = model.verMas, let onVerMas {
                LiquidVerMas(title: verMas, hint: model.verMasHint, tone: model.tono,
                             anchoCompleto: true, action: onVerMas)
            }
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

// MARK: - Previews por estado (los 7 de la tabla de estados)

/// Los fixtures viven aquí para que cada `#Preview` sea una línea y el arnés de renders
/// (`LiquidSheetEstadosRenderTests`) pueda componer los MISMOS estados sin duplicar copy.
enum LiquidActaFixtures {

    static let plegable = LiquidActa.Metodo(
        titulo: "Cómo se calcula",
        mostrar: "Ver cómo se calcula",
        ocultar: "Ocultar cómo se calcula",
        lineas: [
            "Esta mañana leí 3 de 3 señales del cuerpo.",
            "Un veredicto nuevo tiene que repetirse dos días seguidos antes de reemplazar al anterior.",
            "La VFC de Apple es un promedio del día, no una medición de la ventana de sueño: esto lee tus señales en reposo contra tu propia norma.",
            "Task Force, 1996 · Plews et al., 2013. Aproximado, sin valor clínico.",
        ])

    static let metodo = "Tu VFC, tu pulso en reposo y tu respiración cuentan como una sola lectura, para que una mala noche no cuente tres veces."
    static let metodoClave = "una sola lectura"

    static func fila(_ id: String, _ etiqueta: String, _ dijo: String, _ base: String,
                     fuera: Bool = false) -> LiquidActa.Fila {
        .init(id: id, etiqueta: etiqueta, dijo: dijo, base: base, fuera: fuera,
              a11y: "\(etiqueta), \(dijo.lowercased()), \(base)"
                  + (fuera ? ", fuera de tu rango" : ""))
    }

    static func base(nivel: String?, sinLectura: String? = nil, conteo: String,
                     filas: [LiquidActa.Fila], notas: [LiquidActa.Nota] = [],
                     confianza: LiquidActa.Confianza? = nil,
                     tono: Color, tonoFilas: Color? = nil) -> LiquidActa {
        LiquidActa(
            titulo: "Preparación",
            procedencia: "Apple Salud · esta mañana",
            explicacion: "El veredicto de cómo amaneciste: tus señales contra tu propia base. Es una aproximación, no un diagnóstico.",
            infoMostrar: "Ver explicación", infoOcultar: "Ocultar explicación",
            nivel: nivel, sinLectura: sinLectura, conteo: conteo,
            metodo: metodo, metodoClave: metodoClave,
            filas: filas, notas: notas, confianza: confianza, plegable: plegable,
            verMas: "Ver más en Tendencias", verMasHint: "Abre el detalle",
            tono: tono, tonoFilas: tonoFilas)
    }

    /// Verde: nadie fuera. La tabla queda ENTERAMENTE gris — el único color es la palabra.
    static let verde = base(
        nivel: "Dale con todo",
        conteo: "Tus 3 señales amanecieron en tu rango.",
        filas: [
            fila("autonomico", "Autonómico", "En tu rango", "contra tu base"),
            fila("sueno", "Sueño", "En tu rango", "contra un mínimo fijo"),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [.init(id: "carga", texto: "Hoy hubo entrenamiento. Se mide, pero todavía no cambia tu veredicto.")],
        tono: LiquidColor.verdePrimario)

    /// Ámbar: una fila washeada al 12 %.
    static let ambar = base(
        nivel: "Bien, con un detalle",
        conteo: "1 de tus 3 señales amaneció fuera de tu rango.",
        filas: [
            fila("autonomico", "Autonómico", "En tu rango", "contra tu base"),
            fila("sueno", "Sueño", "Debajo de tu base", "contra un mínimo fijo", fuera: true),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [.init(id: "carga", texto: "Hoy no hubo entrenamiento registrado. La carga se mide, pero todavía no cambia tu veredicto.")],
        confianza: .nota("Tu veredicto se apoya en 8 noches tuyas; a las 14 tu base queda firme."),
        tono: LiquidColor.atencion)

    /// Rojo: dos filas fuera.
    static let rojo = base(
        nivel: "Ándate leve",
        conteo: "2 de tus 3 señales amanecieron fuera de tu rango.",
        filas: [
            fila("autonomico", "Autonómico", "Debajo de tu base", "contra tu base", fuera: true),
            fila("sueno", "Sueño", "Debajo de tu base", "contra un mínimo fijo", fuera: true),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [.init(id: "carga", texto: "Hoy hubo entrenamiento. Se mide, pero todavía no cambia tu veredicto.")],
        tono: LiquidColor.negativo)

    /// Histéresis activa: el acta de HOY no cuadra con el veredicto mostrado. Sin este
    /// aviso, la hoja se contradice sola.
    static let histeresis = base(
        nivel: "Dale con todo",
        conteo: "1 de tus 3 señales amaneció fuera de tu rango.",
        filas: [
            fila("autonomico", "Autonómico", "En tu rango", "contra tu base"),
            fila("sueno", "Sueño", "Debajo de tu base", "contra un mínimo fijo", fuera: true),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [
            .init(id: "hist", texto: "Hoy leí 1 señal fuera de tu rango; el veredicto no cambia hasta que se repita dos días seguidos.", avisa: true),
            .init(id: "carga", texto: "Hoy no hubo entrenamiento registrado. La carga se mide, pero todavía no cambia tu veredicto."),
        ],
        // La palabra es VERDE (el veredicto estable) pero la fila que se salió es ÁMBAR:
        // el wash dice «esta es la que se salió», no «esta está bien».
        tono: LiquidColor.verdePrimario, tonoFilas: LiquidColor.atencion)

    /// Empujón de tendencia: una sola señal fuera, pero la tendencia nocturna viene bajando.
    /// PRECEDE a la nota de histéresis (es otra causa, no la misma).
    static let tendencia = base(
        nivel: "Ándate leve",
        conteo: "1 de tus 3 señales amaneció fuera de tu rango.",
        filas: [
            fila("autonomico", "Autonómico", "Debajo de tu base", "contra tu base", fuera: true),
            fila("sueno", "Sueño", "En tu rango", "contra un mínimo fijo"),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [
            .init(id: "trend", texto: "Una señal fuera de tu rango, y tu tendencia de VFC nocturna viene bajando.", avisa: true),
            .init(id: "carga", texto: "Hoy hubo entrenamiento. Se mide, pero todavía no cambia tu veredicto."),
        ],
        tono: LiquidColor.negativo)

    /// Lectura de día: no hubo noche grabada, así que el sueño no pudo votar.
    static let lecturaDeDia = base(
        nivel: "Dale con todo",
        conteo: "Hoy solo 2 de tus 3 señales tuvieron lectura.",
        filas: [
            fila("autonomico", "Autonómico", "En tu rango", "contra tu base"),
            fila("sueno", "Sueño", "Sin datos", "contra un mínimo fijo"),
            fila("termico", "Térmico", "En tu rango", "contra la base de Apple"),
        ],
        notas: [
            .init(id: "noche", texto: "Sin lectura de sueño anoche; esta lectura es menos precisa.", avisa: true),
            .init(id: "carga", texto: "Hoy no hubo entrenamiento registrado. La carga se mide, pero todavía no cambia tu veredicto."),
        ],
        tono: LiquidColor.verdePrimario)

    /// Sin veredicto: la base todavía se está armando. CERO color en toda la hoja, y el
    /// acta se queda visible en gris — enseña qué se va a medir.
    static let sinVeredicto = base(
        nivel: nil,
        sinLectura: "Aún sin veredicto",
        conteo: "Necesito unas noches tuyas para poder darte un veredicto.",
        filas: [
            fila("autonomico", "Autonómico", "Sin datos", "contra tu base"),
            fila("sueno", "Sueño", "Sin datos", "contra un mínimo fijo"),
            fila("termico", "Térmico", "Sin datos", "contra la base de Apple"),
        ],
        confianza: .calibrando(titulo: "Calibrando tu base", leyenda: "2 de 4 noches",
                               hechas: 2, necesarias: 4),
        tono: LiquidColor.tinta500)

    /// Sin permiso de Apple Salud: mismo cascarón honesto, cerrado con la única salida real.
    static let sinPermiso = base(
        nivel: nil,
        sinLectura: "Aún sin veredicto",
        conteo: "Necesito unas noches tuyas para poder darte un veredicto.",
        filas: [
            fila("autonomico", "Autonómico", "Sin datos", "contra tu base"),
            fila("sueno", "Sueño", "Sin datos", "contra un mínimo fijo"),
            fila("termico", "Térmico", "Sin datos", "contra la base de Apple"),
        ],
        notas: [.init(id: "permiso", texto: "Conecta Apple Salud en Ajustes y tu veredicto diario aparecerá aquí.", avisa: true)],
        tono: LiquidColor.tinta500)
}

private func actaPreview(_ model: LiquidActa) -> some View {
    LiquidActaVeredicto(model, onVerMas: {})
        .padding(LiquidSpace.s550)
        .frame(width: 402, alignment: .topLeading)
        .background(LiquidSheetFondo(tone: model.tono))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Acta · verde (nadie fuera)") { actaPreview(LiquidActaFixtures.verde) }
#Preview("Acta · ámbar (una fuera)") { actaPreview(LiquidActaFixtures.ambar) }
#Preview("Acta · rojo (dos fuera)") { actaPreview(LiquidActaFixtures.rojo) }
#Preview("Acta · histéresis activa") { actaPreview(LiquidActaFixtures.histeresis) }
#Preview("Acta · empujón de tendencia") { actaPreview(LiquidActaFixtures.tendencia) }
#Preview("Acta · lectura de día") { actaPreview(LiquidActaFixtures.lecturaDeDia) }
#Preview("Acta · sin veredicto") { actaPreview(LiquidActaFixtures.sinVeredicto) }
#Preview("Acta · sin permiso de Salud") { actaPreview(LiquidActaFixtures.sinPermiso) }

#Preview("Acta · AX3 (filas apiladas)") {
    actaPreview(LiquidActaFixtures.ambar)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
