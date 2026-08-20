import SwiftUI
import StrandDesign
import StrandAnalytics
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PreparacionDetailScreen — «tus 30 mañanas» en Liquid Glass (FER-119)
//
// La pantalla que sustituye al «Detalle de Recuperación». Aquella dibujaba ocho bloques sobre
// `today.recovery`, un puntaje 0–100 que murió con la banda: los dos escritores de filas guardan
// `recovery: nil`, así que la pantalla llevaba meses abriéndose vacía.
//
// EL DOMINANTE YA NO ES UN NÚMERO, ES UNA HISTORIA. Preparación es un veredicto CATEGÓRICO de
// cuatro estados; promediarlo, sacarle una σ o un coeficiente de variación no significa nada, así
// que los bloques que hacían eso no se «migran», se retiran. Lo que queda es la única pregunta que
// un veredicto categórico sí puede contestar sobre 30 días: **¿cómo han venido tus mañanas?**
//
// EL VEREDICTO DE HOY BAJA A ANCLA. Ponerlo de héroe aquí duplicaría a Hoy, que ya lo dice cada
// mañana con su «por qué» a un toque. Vive en el campo teñido, arriba, y nada más.
//
// LOS CUATRO PELDAÑOS PESAN IGUAL. Ni titular de conteo, ni racha, ni porcentajes: contar «22 días
// buenos» invita a proteger el número en vez de leer el cuerpo, y una racha convierte una noche
// mala en una pérdida. El reparto los enumera y se calla.

struct PreparacionDetailScreen: View {
    let modelo: PreparacionDetalleModelo

    @Environment(\.dynamicTypeSize) private var tipo
    @State private var diaTocado: String? = nil
    @State private var metodoAbierto = false

    private var tono: Color { modelo.tonoHoy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                campo
                switch modelo.estado {
                case .cargando:        cargando
                case .sinPermiso:      bienvenida(modelo.copySinPermiso)
                case .sinHistoria:     bienvenida(modelo.copySinHistoria)
                case .conVentana:      ventana
                }
            }
        }
        // La misma plasta teñida que respira detrás de Sueño (`SleepDetailScreen:110`). El
        // gradiente neutro dejaba esta pantalla plana al lado de sus hermanas.
        .background { LiquidSheetFondo(tone: tono).ignoresSafeArea() }
        .scrollIndicators(.hidden)
    }

    // MARK: - El campo: el veredicto de hoy como ancla, no como titular

    private var campo: some View {
        LiquidCampoMetrica(
            tono: tono,
            titulo: String(localized: "prep.titulo", defaultValue: "Preparation"),
            // SIN GLIFO, a propósito. Los del catálogo son de MÉTRICA y van 1:1 con la suya
            // (luna=Sueño, corazon=FC en reposo, termo=temperatura). Preparación no es una
            // métrica: es un veredicto sobre tres señales, y no tiene glifo propio.
            //
            // Probé dos prestados y los dos estaban mal: `.escudo` es de Guardián, y `.corazon`
            // es de FC en reposo — el usuario lo ve en la Matriz de Hoy
            // (`LiquidHoyBuilder+Matriz.swift:185`) y volvería a verlo aquí significando otra
            // cosa. Cambiar un glifo prestado por otro no arregla nada. Hasta que exista uno
            // acuñado para el veredicto, la cabecera va sin él.
            // El guion viaja por el MISMO canal que la palabra, no por `datos:`. Al darle
            // voz al campo mudo lo metí como numeral, y el numeral del campo se pinta a 56 pt
            // mientras el veredicto real se pinta a 17: la mañana SIN lectura gritaba más que
            // la mañana con ella. Es una costura que se rompió al mover solo la mitad de la
            // pieza: el estado con dato ya había migrado a `veredicto:` y el vacío se quedó en
            // el canal viejo. De paso, el `motivo` del numeral repetía palabra por palabra la
            // cláusula de abajo, y VoiceOver decía la misma frase dos paradas seguidas.
            datos: [],
            veredicto: modelo.palabraHoy ?? "—",
            // Sin `onVolver`: esta pantalla siempre vive dentro de `DetailChrome`, que ya pone
            // su propio «‹ Tendencias». El botón del campo nunca llegaba a pintarse.
            // Sin veredicto la franja quedaba MUDA: solo el rótulo en caja alta sobre color,
            // encima de una bienvenida que sí traía texto. Sueño resuelve el mismo momento con
            // su `campoApagado`, que nunca deja el campo sin numeral ni sin cláusula.
            clausula: modelo.clausulaHoy ?? modelo.clausulaSinVeredicto
        ) {
            if let sello = modelo.selloConfianza {
                LiquidCampoSello(sello)
            }
            if modelo.estado == .sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    // MARK: - La ventana: el mosaico dominante, la atribución, el porqué de hoy, el método

    private var ventana: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiquidFranjaSeccion(String(localized: "prep.mosaico.titulo",
                                       defaultValue: "Your last 30 mornings"),
                                pista: modelo.pistaCobertura, tono: tono)
            LiquidMosaicoVeredictos(
                dias: modelo.rejilla,
                peldanos: modelo.peldanos,
                conteos: modelo.conteos,
                seleccion: $diaTocado,
                unidadDias: PreparacionDetalleModelo.unidadDias,
                a11yLabel: String(localized: "prep.mosaico.a11y",
                                  defaultValue: "Your last 30 mornings"),
                a11yConteo: { hechas, total in
                    String(format: String(localized: "prep.mosaico.conteo.fmt",
                                          defaultValue: "%1$d of %2$d mornings have a reading"),
                           hechas, total)
                },
                inicialesDia: modelo.inicialesDia,
                pistaVacia: String(localized: "prep.mosaico.pista",
                                   defaultValue: "Tap a morning to read it."),
                a11yPista: String(localized: "prep.mosaico.a11yPista",
                                  defaultValue: "Swipe up or down to move between mornings with a reading"))
                .liquidSeccion()

            if let aviso = modelo.avisoVentanaSinVeredicto {
                LiquidNotaLine(aviso).liquidSeccion(top: 0)
            }

            if !modelo.atribucion.isEmpty {
                LiquidFranjaSeccion(String(localized: "prep.atribucion.titulo",
                                           defaultValue: "What went out, and how often"),
                                    tono: tono)
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidCajitaGrid {
                        ForEach(modelo.atribucion) { eje in
                            LiquidCajita(rotulo: eje.nombre,
                                         valor: "\(eje.dias)",
                                         unidad: PreparacionDetalleModelo.unidadDiasCorta(eje.dias),
                                         pie: eje.pie,
                                         a11yValor: PreparacionDetalleModelo.unidadDias(eje.dias))
                        }
                    }
                    // El veredicto de una noche es POST-histéresis y estos ejes son los CRUDOS de
                    // esa noche: una noche mala aislada puede salir «todo en rango» con un eje
                    // fuera. El motor lo advierte por escrito; si la pantalla no lo dijera, los
                    // dos bloques se contradirían solos a la vista del usuario.
                    LiquidNotaLine(String(localized: "prep.atribucion.nota",
                                          defaultValue: "These are the nights each signal came in outside your range. A single night out doesn't move your verdict on its own, so these numbers won't add up to the mosaic above."))
                }
                .liquidSeccion()
            }

            if !modelo.ejesHoy.isEmpty {
                LiquidFranjaSeccion(String(localized: "prep.hoy.titulo",
                                           defaultValue: "Why today"),
                                    tono: tono)
                VStack(spacing: 0) {
                    ForEach(Array(modelo.ejesHoy.enumerated()), id: \.element.id) { i, eje in
                        if i > 0 { LiquidCapilar(eje: .horizontal) }
                        // A tallas de accesibilidad se apila, como el reparto y las cajitas de
                        // esta misma pantalla: `LiquidType.cuerpo` es fijo y `label` escala, así
                        // que en una fila el rótulo se quedaba chico junto a un estado partido
                        // en dos líneas.
                        Group {
                            if tipo.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                                    Text(eje.nombre).font(LiquidType.cuerpo)
                                        .foregroundStyle(LiquidColor.tinta900)
                                    Text(eje.estado).liquidLabel()
                                        .foregroundStyle(eje.fuera ? tono : LiquidColor.tinta500)
                                }
                            } else {
                                HStack(spacing: LiquidSpace.s250) {
                                    Text(eje.nombre).font(LiquidType.cuerpo)
                                        .foregroundStyle(LiquidColor.tinta900)
                                    Spacer(minLength: LiquidSpace.s250)
                                    Text(eje.estado).liquidLabel()
                                        .foregroundStyle(eje.fuera ? tono : LiquidColor.tinta500)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, LiquidSpace.s250)
                        .accessibilityElement(children: .combine)
                    }
                }
                .liquidSeccion()
            }

            metodo
        }
    }

    private var metodo: some View {
        // El capilar y los paddings reducidos son el patrón que Sueño ya fijó para un pie sin
        // franja propia (`pieMetodo`): sin ellos quedan 38 pt de aire sin ninguna costura que
        // los explique, que es el hueco muerto que aquel comentario describe.
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            // El componente compartido de la familia (`LiquidMetodo` + `LiquidNotaLine`), no un
            // bloque a mano: plegable, cerrado por omisión, y CON su cita en pantalla. Sueño ya lo
            // hacía así; aquí las fuentes vivían solo en comentarios del motor, que el usuario
            // nunca ve. CLAUDE.md pide citar el método, y citarlo donde se lee.
            // Las claves que YA usa toda la familia (Sueño, Carga, la hoja de métrica, Hoy y las
            // pantallas de papel). Preparación había acuñado «Ver el método», y era la única voz
            // distinta del app para el mismo control.
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                // Las TRES líneas con `LiquidNotaLine`, como Sueño. `LiquidType.cuerpo` es la
                // fuente del SISTEMA a 12.5, y la cita de abajo ya era Grotesk a 10.5: la
                // explicación y su fuente salían en dos tipografías y dos tamaños distintos
                // dentro del mismo bloque. El tono (700 contra el 500 por omisión) es lo único
                // que separa la explicación de la referencia.
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidNotaLine(String(localized: "prep.metodo.como",
                                          defaultValue: "Every morning I look at three things. Your resting heart rate, against your own base: that's the axis that votes, and your HRV measured while you sleep rides along with it only on nights that have enough of it, never on its own (the all-day HRV you see elsewhere in the app never votes). Your sleep, against the floor sleep science recommends, not against your own history. And the sentinel, skin temperature and breathing, which only counts when both run high together. None out is «all in range»; one is «one signal out»; two or more is «two or more out». A sustained downward trend can also bring that change forward."),
                                   tono: LiquidColor.tinta700)
                    LiquidNotaLine(String(localized: "prep.metodo.limite",
                                          defaultValue: "Each square is judged with the base you had up to that day, so it doesn't change if you come back to look later. What it can't carry is the trend nudge that only applies to the morning you're living: that's why an older square can differ from what Today said out loud that day. Training load doesn't vote here."),
                                   tono: LiquidColor.tinta700)
                    LiquidNotaLine("Hirshkowitz et al., 2015 (sleep need); Task Force of the European Society of Cardiology, 1996 (HRV); Mishra et al., 2020 (illness sentinel).")
                }
            }
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Estados de pantalla

    /// El esqueleto compartido de la familia, no un spinner desnudo: insinúa la forma de lo
    /// que viene. Es lo que usan Sueño y la hoja de métrica para este mismo momento.
    private var cargando: some View {
        LiquidSheetSkeleton(a11yCargando: String(localized: "prep.cargando",
                                                 defaultValue: "Reading your mornings…"))
            .liquidSeccion()
    }

    private func bienvenida(_ copy: PreparacionDetalleModelo.Bienvenida) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(copy.titulo).font(LiquidType.valorL).foregroundStyle(LiquidColor.tinta900)
            Text(copy.cuerpo).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidSeccion(top: LiquidSpace.s550)
    }

    /// Abre Ajustes de iOS en la ficha de la app, que es donde vive el permiso de Salud.
    /// Mismo atajo que la pantalla de Sueño (FER-102).
    private static func abrirAjustesSalud() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - PreparacionDetalleModelo — todo lo que la pantalla dibuja, derivado UNA vez
//
// La capa de datos, fuera de la vista. La pantalla es presentación pura sobre esto; el call site
// lo construye desde el tablero en memoria, así que no toca la base de datos.
//
// CONSUME `StrandAnalytics` tal cual: el veredicto y su historia salen de `Preparedness.Read`,
// las palabras de `LiquidHoyBuilder` (las MISMAS que pinta Hoy). Cero matemática nueva.

struct PreparacionDetalleModelo {

    enum Estado: Equatable { case cargando, sinPermiso, sinHistoria, conVentana }

    struct Bienvenida: Equatable {
        let titulo: String
        let cuerpo: String
    }

    /// Un eje de la atribución: cuántas de las 30 noches vino fuera.
    struct EjeAtribucion: Identifiable, Equatable {
        let id: String
        let nombre: String
        let dias: Int
        let pie: String
    }

    /// Una fila del «por qué hoy», derivada de `Read.drivers`.
    struct EjeHoy: Identifiable, Equatable {
        let id: String
        let nombre: String
        let estado: String
        let fuera: Bool
    }

    let estado: Estado
    let palabraHoy: String?
    let clausulaHoy: String?
    let selloConfianza: String?
    let tonoHoy: Color
    let rejilla: [LiquidMosaicoVeredictos.Dia?]
    let peldanos: [LiquidMosaicoVeredictos.Peldano]
    let conteos: [String: Int]
    let pistaCobertura: String?
    let avisoVentanaSinVeredicto: String?
    let atribucion: [EjeAtribucion]
    let ejesHoy: [EjeHoy]
    let copySinPermiso: Bienvenida
    let copySinHistoria: Bienvenida
    /// Lo que dice el campo cuando NO hay veredicto. Tres estados, tres frases: una franja
    /// teñida con solo su rótulo no le dice nada a nadie.
    var clausulaSinVeredicto: String {
        switch estado {
        case .cargando:    return String(localized: "prep.campo.cargando",
                                         defaultValue: "Reading your mornings…")
        case .sinPermiso:  return String(localized: "prep.campo.sinPermiso",
                                         defaultValue: "I can't read you yet.")
        default:           return String(localized: "prep.campo.sinVeredicto",
                                         defaultValue: "No verdict this morning.")
        }
    }
    /// Las 7 iniciales de la canaleta, YA rotadas al día en que arranca esta ventana.
    let inicialesDia: [String]

    /// La ventana del mosaico. Fija: la histéresis pide dos días para mover el veredicto, así que
    /// 30 días son ~15 tramos independientes — alargarla aparenta una resolución que no existe.
    static let ventana = 30

    // MARK: - Vocabulario NEUTRO de los peldaños
    //
    // Las palabras de Hoy son lecturas dirigidas al lector sobre HOY: «Hoy ve leve» lleva la
    // palabra «hoy» dentro y «Recupera» es un imperativo. Como etiqueta de un día de hace tres
    // semanas se contradicen solas. Estas nombran el ESTADO en tercera persona, y salen literales
    // de la regla del motor: cuenta cuántos de los tres ejes vinieron fuera.
    static func peldano(_ v: Preparedness.Verdict) -> String {
        switch v {
        case .full:      return String(localized: "prep.peldano.full", defaultValue: "All in range")
        case .caution:   return String(localized: "prep.peldano.caution", defaultValue: "One signal out")
        case .easy:      return String(localized: "prep.peldano.easy", defaultValue: "Two or more out")
        case .lowSignal: return String(localized: "prep.peldano.sin", defaultValue: "No reading")
        }
    }

    /// Los ejes que vinieron fuera esa noche, nombrados. Son los CRUDOS de la noche: pueden no
    /// cuadrar con el veredicto, que es post-histéresis, y por eso la nota de la atribución lo
    /// advierte. Nombrarlos es lo único que contesta «¿cuál fue?» de un día pasado.
    /// Cuántos de los tres ejes vinieron fuera esa noche, en crudo.
    static func ejesFuera(_ n: Preparedness.VerdictNight) -> Int {
        (n.autonomicOut ? 1 : 0) + (n.sleepOut ? 1 : 0) + (n.sentinelOut ? 1 : 0)
    }

    static func quienSeSalio(_ n: Preparedness.VerdictNight) -> String {
        var partes: [String] = []
        if n.autonomicOut { partes.append(String(localized: "Resting HR")) }
        if n.sleepOut { partes.append(String(localized: "Sleep")) }
        if n.sentinelOut {
            partes.append(String(localized: "prep.atr.centinela.nombre",
                                 defaultValue: "Temperature and breathing"))
        }
        return ListFormatter.localizedString(byJoining: partes)
    }

    /// 🔴 La canaleta tiene que decir el día REAL de cada columna.
    ///
    /// El default del componente venía de `LiquidCalendario90.inicialesPorLocale()`, una fila
    /// FIJA lunes-primero. Aquella pieza puede permitírselo porque ancla sus columnas a semanas
    /// de calendario, rellenando el arranque. Esta NO: son 30 días consecutivos que terminan
    /// hoy, partidos en bloques de 7, así que la primera columna es el día que caiga hace 29 y
    /// **rota cada día**. La fila fija acertaba 1 de cada 7 días del año; los otros 6 le decía
    /// «lunes» a una columna de martes. (Cazado por la revisión de UI; el día que se revisó en
    /// el simulador la ventana arrancaba en lunes por casualidad, así que se veía bien.)
    ///
    /// Se conserva el ritmo disperso de la hermana (etiqueta sí, etiqueta no) para que las dos
    /// canaletas se lean igual.
    static func inicialesDesde(_ inicio: Date, calendario: Calendar = .current) -> [String] {
        let simbolos = calendario.shortWeekdaySymbols
        guard simbolos.count == 7 else { return Array(repeating: "", count: 7) }
        return (0..<7).map { i in
            guard i % 2 == 0 else { return "" }
            let d = calendario.date(byAdding: .day, value: i, to: inicio) ?? inicio
            // `weekday` es 1-based (1 = domingo), y `shortWeekdaySymbols` es 0-based.
            return simbolos[calendario.component(.weekday, from: d) - 1]
        }
    }

    /// «5 días» / «1 día». Reusa la clave que YA pluraliza bien y que Hoy y el onboarding ya
    /// usan: yo había acuñado una clave PLANA (`prep.dias.fmt` = «%d días»), que con un solo
    /// día imprimía «1 días» en el reparto, en la atribución y en el sello. Cazado por la
    /// revisión quisquillosa.
    static func unidadDias(_ n: Int) -> String {
        String(format: String(localized: "%lld days"), n)
    }

    /// La unidad suelta de una cajita, que ya lleva su número aparte: también tiene que
    /// concordar con él.
    static func unidadDiasCorta(_ n: Int) -> String {
        String(format: String(localized: "%lld days"), n)
            .replacingOccurrences(of: "\(n)", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func tono(_ v: Preparedness.Verdict) -> Color {
        switch v {
        case .full:      return LiquidColor.verdePrimario
        case .caution:   return LiquidColor.atencion
        case .easy:      return LiquidColor.negativo
        case .lowSignal: return LiquidColor.tinta500
        }
    }

    static let peldanosBase: [LiquidMosaicoVeredictos.Peldano] = [
        .init(id: "full", color: tono(.full), etiqueta: peldano(.full)),
        .init(id: "caution", color: tono(.caution), etiqueta: peldano(.caution)),
        .init(id: "easy", color: tono(.easy), etiqueta: peldano(.easy)),
        .init(id: "none", color: LiquidColor.celdaVaciaPip, etiqueta: peldano(.lowSignal)),
    ]

    private static func idPeldano(_ v: Preparedness.Verdict) -> String? {
        switch v {
        case .full: return "full"
        case .caution: return "caution"
        case .easy: return "easy"
        case .lowSignal: return nil
        }
    }

    // MARK: - Construcción

    static let cargando = PreparacionDetalleModelo(
        estado: .cargando, palabraHoy: nil, clausulaHoy: nil, selloConfianza: nil,
        tonoHoy: LiquidColor.tinta500, rejilla: [], peldanos: peldanosBase, conteos: [:],
        pistaCobertura: nil, avisoVentanaSinVeredicto: nil, atribucion: [], ejesHoy: [],
        copySinPermiso: bienvenidaSinPermiso, copySinHistoria: bienvenidaSinHistoria,
        inicialesDia: Array(repeating: "", count: 7))

    /// Se lee del repo en main y se deriva FUERA (patrón FER-955/FER-1040): el pliegue sobre 30
    /// días no tiene por qué correr en el hilo que dibuja.
    @MainActor
    static func buildDetached(repo: Repository, healthConnected: Bool) async -> PreparacionDetalleModelo {
        let prep = repo.todayPreparedness
        let conectado = healthConnected
        let ahora = Date()
        return await Task.detached(priority: .userInitiated) {
            build(prep: prep, healthConnected: conectado, asOf: ahora)
        }.value
    }

    /// - Parameters:
    ///   - asOf: el día que cierra la ventana. Se inyecta para que las pruebas no dependan del reloj.
    static func build(prep: Preparedness.Read?,
                      healthConnected: Bool,
                      asOf: Date,
                      calendario: Calendar = .current) -> PreparacionDetalleModelo {

        // La serie del motor es DISPERSA: una noche sin fila no viene en `nil`, NO VIENE. Se
        // construyen 30 claves de calendario densas y se busca cada una por diccionario. Pasar la
        // serie cruda dibujaría dos noches separadas por una semana como vecinas, y VoiceOver
        // diría «8 de 22» sobre una ventana de 30.
        let porDia = Dictionary(uniqueKeysWithValues:
            (prep?.verdictHistory ?? []).map { ($0.day, $0) })
        let claves = dayKeys(endingAt: asOf, calendar: calendario, count: ventana)
        let fmtDia = DateFormatter()
        fmtDia.calendar = calendario
        fmtDia.locale = .autoupdatingCurrent
        fmtDia.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let parser = DateFormatter()
        parser.calendar = calendario
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendario.timeZone
        parser.dateFormat = "yyyy-MM-dd"

        let rejilla: [LiquidMosaicoVeredictos.Dia?] = claves.map { clave in
            guard let noche = porDia[clave], let fecha = parser.date(from: clave) else { return nil }
            let etiquetaDia = fmtDia.string(from: fecha)
            let lectura = peldano(noche.verdict)
            // El motor ya sabe CUÁL eje se salió esa noche; sin decirlo, tocar un cuadro rojo
            // dejaba al usuario con la pregunta obvia («¿cuál de las dos fue?») sin respuesta
            // para cualquier día que no fuera hoy.
            var quienes = quienSeSalio(noche)
            // 🔴 El veredicto de esta celda es POST-histéresis y, en el día de hoy, además lleva
            // el empujón de tendencia; los tres ejes son los CRUDOS de esa noche. Cuando el
            // empujón sube un día de «una señal fuera» a «dos o más», la etiqueta decía «Dos o
            // más fuera · FC en reposo» nombrando UNA sola: se lee como un bug aunque no lo sea.
            // Si el peldaño promete más ejes de los que hay, se dice quién lo empujó.
            if noche.verdict == .easy && ejesFuera(noche) < 2 {
                let empujon = String(localized: "prep.dia.tendencia",
                                     defaultValue: "downward trend")
                // Con «·» y no con coma: la etiqueta separa todas sus cláusulas así, y
                // `quienSeSalio` une SEÑALES con «y». Una coma metía «tendencia a la baja» en
                // la lista de señales, como si fuera una tercera constante vital.
                quienes = quienes.isEmpty ? empujon : quienes + " · " + empujon
            }
            let cola = quienes.isEmpty ? "" : " · " + quienes
            return .init(id: clave, fecha: fecha, peldano: idPeldano(noche.verdict),
                         etiqueta: "\(etiquetaDia) · \(lectura)\(cola)")
        }

        // Los días SIN fila y los días con veredicto `lowSignal` caen en el MISMO peldaño: el
        // usuario no puede distinguirlos mirando su calendario, y separarlos serían dos escalones
        // que no significan nada para él. El denominador son siempre 30 días de calendario.
        var conteos: [String: Int] = [:]
        for celda in rejilla {
            let id = celda?.peldano ?? "none"
            conteos[id, default: 0] += 1
        }

        let conLectura = ventana - (conteos["none"] ?? 0)
        let ventanaVacia = conLectura == 0

        // La atribución solo mira los días CON veredicto: contar ejes sobre días que no se
        // leyeron inventaría noches que nunca existieron.
        let leidas = (prep?.verdictHistory ?? []).filter { $0.verdict != .lowSignal }
        let atribucion: [EjeAtribucion] = leidas.isEmpty ? [] : [
            .init(id: "autonomic", nombre: String(localized: "Resting HR"),
                  dias: leidas.filter(\.autonomicOut).count,
                  // La VFC de Apple no vota (`wHRV = 0`) y la RMSSD nocturna «nunca sola, nunca
                  // históricamente»: sobre 30 días este eje es SOLO la FC en reposo.
                  pie: String(localized: "prep.atr.auto",
                              defaultValue: "outside your base")),
            .init(id: "sleep", nombre: String(localized: "Sleep"),
                  dias: leidas.filter(\.sleepOut).count,
                  // El eje vota con `shortVsNeed || poorEfficiency`: decir solo «dormiste menos»
                  // deja fuera la noche fragmentada de duración normal, que vota igual.
                  pie: String(localized: "prep.atr.sueno",
                              defaultValue: "short or broken up")),
            .init(id: "sentinel", // Corto A PROPÓSITO: con `lineLimit(2)` el nombre largo ocupaba dos líneas y su
                  // vecino de fila una, así que la rejilla no cerraba pareja. De los cuatro
                  // rótulos solo este era largo, y siempre cae junto a uno corto.
                  nombre: String(localized: "prep.atr.centinela.nombre",
                                 defaultValue: "Temp and breathing"),
                  dias: leidas.filter(\.sentinelOut).count,
                  pie: String(localized: "prep.atr.centinela",
                              defaultValue: "both, never one alone")),
            .init(id: "leidas", nombre: String(localized: "prep.atr.leidas.nombre",
                                               defaultValue: "Mornings read"),
                  dias: conLectura,
                  pie: String(localized: "prep.atr.leidas",
                              defaultValue: "the rest had no signal")),
        ]

        let hayVeredicto = prep != nil && prep?.verdict != .lowSignal && prep?.isNightAnchored == true

        let ejesHoy: [EjeHoy] = hayVeredicto ? (prep?.drivers ?? []).compactMap { d in
            guard d.axis == .autonomic || d.axis == .sleep else { return nil }
            return EjeHoy(id: "\(d.axis)",
                          nombre: d.axis == .sleep ? String(localized: "Sleep")
                                                   : String(localized: "Resting HR"),
                          estado: d.state.isOut
                              ? String(localized: "prep.eje.fuera", defaultValue: "Outside your range")
                              : String(localized: "prep.eje.dentro", defaultValue: "In your range"),
                          fuera: d.state.isOut)
        } : []

        // Dos vacíos que NO son el mismo, y el orden importa:
        //   · SERIE VACÍA (sin historia, o sin permiso) → no se dibuja mosaico: 30 cuadros
        //     grises no son información, son un reproche. Va el estado de bienvenida.
        //   · VENTANA SIN VEREDICTO (hay noches, todas sin lectura) → el mosaico SÍ se dibuja,
        //     entero en el peldaño vacío, y lo dice. Nunca «0 de 0»: el denominador son 30.
        //
        // La versión anterior escribía la primera rama como `historia.isEmpty && !ventanaVacia`,
        // que es una contradicción: sin historia TODAS las celdas caen en «sin lectura», así que
        // `ventanaVacia` siempre es cierto y la rama nunca corría. El usuario sin historia veía
        // un mosaico de 30 huecos en vez de su bienvenida.
        let estado: Estado
        if !healthConnected { estado = .sinPermiso }
        else if prep == nil || (prep?.verdictHistory ?? []).isEmpty { estado = .sinHistoria }
        else { estado = .conVentana }

        let primerDia = claves.first.flatMap { parser.date(from: $0) } ?? asOf
        return PreparacionDetalleModelo(
            estado: estado,
            palabraHoy: hayVeredicto ? LiquidHoyBuilder.palabraVeredicto(prep!.verdict) : nil,
            clausulaHoy: hayVeredicto ? LiquidHoyBuilder.clausulaVeredicto(prep) : nil,
            selloConfianza: sello(prep),
            tonoHoy: hayVeredicto ? tono(prep!.verdict) : LiquidColor.tinta500,
            rejilla: rejilla,
            peldanos: peldanosBase,
            conteos: conteos,
            // La pista se basta sola: «22 de 30», no «22» a secas. Es el patrón que el propio
            // `LiquidFranjaSeccion` documenta en su preview («24 de 30 noches suficientes»).
            pistaCobertura: String(format: String(localized: "prep.cobertura.fmt",
                                                  defaultValue: "%1$d of %2$d with a reading"),
                                   conLectura, ventana),
            avisoVentanaSinVeredicto: ventanaVacia ? avisoVacio(prep) : nil,
            atribucion: atribucion,
            ejesHoy: ejesHoy,
            copySinPermiso: bienvenidaSinPermiso,
            copySinHistoria: bienvenidaSinHistoria,
            inicialesDia: inicialesDesde(primerDia, calendario: calendario))
    }

    /// Las tres razones de «sin veredicto» NO son la misma, y por eso no comparten frase: al que
    /// nunca duerme con reloj el motor advierte que «tu base se está formando» no se cumple nunca.
    private static func avisoVacio(_ prep: Preparedness.Read?) -> String {
        guard let prep else {
            return String(localized: "prep.vacio.sinDatos",
                          defaultValue: "None of these 30 mornings had enough signal to read.")
        }
        if !prep.autonomicPossible {
            return String(localized: "prep.vacio.imposible",
                          defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in: if you don't wear your watch at night, I won't be able to read them.")
        }
        return String(format: String(localized: "prep.vacio.formando.fmt",
                                     defaultValue: "None of these 30 mornings had a verdict yet: I'm still learning your normal. Night %1$d of %2$d."),
                      prep.autonomicNights, Baselines.minNightsSeed)
    }

    private static func sello(_ prep: Preparedness.Read?) -> String? {
        guard let prep, prep.verdict != .lowSignal, prep.isNightAnchored else { return nil }
        // Mismo caso: «1 noches de tu base» con una sola noche.
        return String(format: String(localized: "prep.sello.fmt",
                                     defaultValue: "%1$@ of your baseline"),
                      String(format: String(localized: "%lld nights"), prep.autonomicNights))
    }

    static let bienvenidaSinPermiso = Bienvenida(
        titulo: String(localized: "prep.permiso.titulo", defaultValue: "I need to see your Health"),
        cuerpo: String(localized: "prep.permiso.cuerpo",
                       defaultValue: "Preparation is built from what your watch already saves in Apple Health: resting heart rate, HRV, sleep, temperature and breathing. Without that permission there's nothing to read. Everything stays on your iPhone."))

    static let bienvenidaSinHistoria = Bienvenida(
        titulo: String(localized: "prep.sinHistoria.titulo", defaultValue: "Your first mornings"),
        cuerpo: String(localized: "prep.sinHistoria.cuerpo",
                       defaultValue: "There's no history to show yet. Sleep with your watch on and this fills in on its own, one morning at a time."))

    /// yyyy-MM-dd local, del más viejo al más nuevo, cerrando en el día civil de `now`. Es el
    /// MISMO patrón que la Matriz de Hoy (`LiquidHoyBuilder+Matriz.dayKeys`), replicado aquí
    /// porque aquel es privado de su archivo.
    static func dayKeys(endingAt now: Date, calendar: Calendar, count: Int) -> [String] {
        let inicio = calendar.startOfDay(for: now)
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return (0..<count).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: inicio) ?? inicio
            return f.string(from: d)
        }
    }
}

// MARK: - Sheet item

/// Envoltura `Identifiable` para que la pantalla viaje en `.sheet(item:)`. El `id` explícito deja
/// que el modelo ya construido entre bajo la MISMA identidad de presentación (patrón FER-954).
struct PreparacionDetalleItem: Identifiable {
    let id: UUID
    let modelo: PreparacionDetalleModelo
    init(id: UUID = UUID(), modelo: PreparacionDetalleModelo) { self.id = id; self.modelo = modelo }
}
