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
            // FER-129: la palabra va por `palabra:` (displayL, 30), el slot que ocupa el hueco
            // del numeral. Con `veredicto:` (17 pt) el campo no tenía nada que lo sostuviera y
            // el rótulo se comía con el chrome. Es el mismo token que la palabra de Hoy.
            palabra: modelo.palabraHoy ?? "—",
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

            // ── «Los votos»: DOS PISOS, dos relojes ─────────────────────────────
            // El estado de HOY es crudo; el mosaico de arriba es post-histéresis. Mezclarlos en
            // una fila hacía que un cuadro verde con «FC · HOY FUERA» al lado se leyera como
            // bug aunque sea la histéresis funcionando (lo cazaron los dos revisores; el motor
            // lo advierte por escrito en `VerdictNight`). Cada piso con su subtítulo y su pieza.
            // La sección se pinta si hay CUALQUIERA de los dos pisos: son dos relojes
            // independientes, y un usuario que no durmió con el reloj anoche (sin boleta de
            // hoy) no pierde por eso la vista de sus 30 días.
            //
            // El título NO es «Tus tres señales»: ese marco está PROHIBIDO por nombre en el
            // allow-list de ESTA pantalla (`docs/ANALYTICS.md`, «3 signals / tus 3 señales»),
            // porque cuenta como tres cosas iguales lo que son dos votos más un par que solo
            // vigila. La sección son los VOTOS, que es como la boleta de Hoy ya lo llama.
            if modelo.actaHoy != nil || !modelo.conteosSenal.isEmpty {
                LiquidFranjaSeccion(String(localized: "prep.votos.titulo",
                                           defaultValue: "The votes"),
                                    tono: tono)
                VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                  if let acta = modelo.actaHoy {
                    // Piso «Hoy»: la boleta tal cual la pinta el acta de Hoy. Misma función
                    // (`LiquidHoyBuilder.acta`), mismas filas, mismos vigilantes — cero tablas
                    // propias. Temp y respiración NO son fila hermana de FC/sueño: son fichas de
                    // «vigilan sin votar», la distinción que el acta ya había hecho.
                    VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                        Text(String(localized: "prep.senales.hoy", defaultValue: "Today"))
                            .liquidLabel()
                            .foregroundStyle(LiquidColor.tinta500)
                        LiquidBoletaCard(votantes: acta.filas.map {
                            .init(id: $0.id, glifo: $0.glifo, nombre: $0.etiqueta, sub: $0.sub,
                                  estado: $0.estado, umbral: $0.umbral, fuera: $0.fuera,
                                  tonoVoto: $0.tonoVoto, palabra: $0.palabra,
                                  hueMetrica: $0.hueMetrica, a11y: $0.a11y,
                                  magnitud: $0.magnitud)
                        })
                        if let etiqueta = acta.vigilantesLabel, !acta.vigilantes.isEmpty {
                            // Calcado de `LiquidActaVeredicto.vigilantesFila`: a tallas de
                            // accesibilidad el rótulo y las fichas se apilan; en una sola fila
                            // el texto inflado empujaba los chips fuera del ancho.
                            Group {
                                if tipo >= .accessibility1 {
                                    VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                                        Text(verbatim: etiqueta)
                                            .font(LiquidType.captionLectura)
                                            .foregroundStyle(LiquidColor.tinta500)
                                        HStack(spacing: LiquidSpace.s150) {
                                            ForEach(acta.vigilantes, id: \.self) { LiquidVigilanteChip(nombre: $0) }
                                        }
                                    }
                                } else {
                                    HStack(spacing: LiquidSpace.s200) {
                                        Text(verbatim: etiqueta)
                                            .font(LiquidType.captionLectura)
                                            .foregroundStyle(LiquidColor.tinta500)
                                        ForEach(acta.vigilantes, id: \.self) { LiquidVigilanteChip(nombre: $0) }
                                    }
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: acta.vigilantesA11y ?? etiqueta))
                        }
                    }

                  }

                    // Piso «el mes»: cuántas noches se salió cada señal, en barras con color de
                    // IDENTIDAD sobre la escala compartida de la ventana. «Cuál» lo dice la barra;
                    // el veredicto lo dice el mosaico. Solo días CON veredicto.
                    if !modelo.conteosSenal.isEmpty {
                        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                            // No es un kicker: `.liquidLabel()` es para 1-3 palabras en caja alta
                            // («HOY»), y esto es una oración de seis. Va en el registro de la
                            // etiqueta de vigilantes de la misma sección.
                            Text(String(localized: "prep.senales.mes",
                                        defaultValue: "Nights out, over 30 days"))
                                .font(LiquidType.captionLectura)
                                .foregroundStyle(LiquidColor.tinta500)
                            VStack(alignment: .leading, spacing: LiquidSpace.s250) {
                                ForEach(Array(modelo.conteosSenal.enumerated()), id: \.element.id) { i, c in
                                    LiquidBarraConteo(glifo: c.glifo, rotulo: c.nombre,
                                                      conteo: c.dias, escala: PreparacionDetalleModelo.ventana,
                                                      tono: c.tono, valorTexto: c.valorTexto,
                                                      indice: i, a11yLabel: c.nombre,
                                                      a11yValue: c.a11y)
                                }
                            }
                            LiquidNotaLine(modelo.notaConteos)
                        }
                    }
                }
                .liquidSeccion()
            }

            metodo
        }
    }

    private var metodo: some View {
        // El capilar y los paddings reducidos son el patrón que Sueño fijó para un pie sin
        // franja propia (`pieMetodo`). El método va PLEGADO con TODO adentro —prosa, regla de
        // dos días y cita, como el plegable del acta de Hoy— y afuera queda SOLO la leyenda
        // de los cuadros: es lo único del método que el ojo necesita sin leer, porque
        // decodifica el mosaico. La leyenda es la MISMA pieza que la del calendario de 90
        // (`LiquidLeyendaNiveles`), con sus cuatro peldaños incluido «sin lectura».
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidLeyendaNiveles(modelo.leyenda)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    LiquidNotaLine(String(localized: "prep.metodo.como",
                                          defaultValue: "Every morning I look at three things. Your resting heart rate, against your own base: that's the axis that votes, and your HRV measured while you sleep rides along with it only on nights that have enough of it, never on its own (the all-day HRV you see elsewhere in the app never votes). Your sleep, against the floor sleep science recommends, not against your own history, and it votes out if it came short or broken up. And the sentinel, skin temperature and breathing, which only counts when both run high together. None out is «all in range»; one is «one signal out»; two or more is «two or more out». A sustained downward trend can also bring that change forward."),
                                   tono: LiquidColor.tinta700)
                    LiquidNotaLine(String(localized: "prep.metodo.limite",
                                          defaultValue: "Each square is judged with the base you had up to that day, so it doesn't change if you come back to look later. What it can't carry is the trend nudge that only applies to the morning you're living: that's why an older square can differ from what Today said out loud that day. Training load doesn't vote here."),
                                   tono: LiquidColor.tinta700)
                    LiquidNotaLine(String(localized: "prep.metodo.regla",
                                          defaultValue: "Two days in a row move the verdict."),
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

    /// Una señal del piso «el mes»: cuántas de las noches LEÍDAS vino fuera. Color y glifo
    /// de IDENTIDAD (el mismo que su celda en la Matriz de Hoy), nunca de juicio.
    struct ConteoSenal: Identifiable, Equatable {
        let id: String
        let glifo: LiquidIcon.Glyph
        let nombre: String
        let dias: Int?
        let tono: Color
        let valorTexto: String
        let a11y: String
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
    /// El piso «hoy» de «Los votos»: la boleta TAL CUAL la arma Hoy
    /// (`LiquidHoyBuilder.acta`) — misma función, mismas filas, mismos vigilantes. Cero tablas
    /// propias: cada vez que cada superficie tuvo la suya terminaron contradiciéndose.
    /// `nil` cuando no hay veredicto anclado a la noche (no se pinta el piso).
    let actaHoy: LiquidActa?
    /// El piso «el mes»: las tres señales con su conteo de noches fuera, sobre la ventana.
    let conteosSenal: [ConteoSenal]
    let notaConteos: String
    /// La leyenda de los cuadros del mosaico, reusando la pieza del calendario.
    let leyenda: [LiquidCalendario90.NivelLeyenda]
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
                                 defaultValue: "Temp and breathing"))
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
        pistaCobertura: nil, avisoVentanaSinVeredicto: nil, actaHoy: nil, conteosSenal: [],
        notaConteos: "", leyenda: [],
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
        let hayVeredicto = prep != nil && prep?.verdict != .lowSignal && prep?.isNightAnchored == true

        // Piso «el mes». Solo días CON veredicto (contar ejes sobre días que no se leyeron
        // inventaría noches). El par cuenta solo noches CORROBORADAS (`sentinelOut` es AND):
        // una sola señal alta se vigila, no se cuenta. El color es de IDENTIDAD: rosa FC,
        // índigo sueño y `doradoTemp` para el par — NO el ámbar, que es el MISMO hex que el
        // ámbar de juicio «una señal fuera» y esta hoja enseña a distinguirlos.
        func conteo(_ id: String, _ glifo: LiquidIcon.Glyph, _ nombre: String,
                    _ dias: Int?, _ tono: Color) -> ConteoSenal {
            let valor = dias.map { String(format: String(localized: "prep.dias.corto.fmt",
                                                          defaultValue: "%d d"), $0) }
                ?? LiquidCajita.sinDato
            let a11y = dias.map {
                String(format: String(localized: "prep.conteo.a11y.fmt",
                                      defaultValue: "%1$d of %2$d nights out"), $0, ventana)
            } ?? String(localized: "no data")
            return ConteoSenal(id: id, glifo: glifo, nombre: nombre, dias: dias,
                               tono: tono, valorTexto: valor, a11y: a11y)
        }
        let conteosSenal: [ConteoSenal] = leidas.isEmpty ? [] : [
            conteo("autonomic", .corazon, String(localized: "Resting HR"),
                   leidas.filter(\.autonomicOut).count, LiquidColor.rosa),
            conteo("sleep", .luna, String(localized: "Sleep"),
                   leidas.filter(\.sleepOut).count, LiquidColor.indigo),
            conteo("sentinel", .termo, String(localized: "prep.atr.centinela.nombre",
                                               defaultValue: "Temp and breathing"),
                   leidas.filter(\.sentinelOut).count, LiquidColor.doradoTemp),
        ]
        let notaConteos = String(format: String(localized: "prep.conteos.nota.fmt",
                                                defaultValue: "Out of %d mornings with a reading. A single night out doesn't move your verdict on its own, which is why these counts won't add up to the squares above."),
                                 conLectura)

        // Piso «hoy»: la MISMA acta que Hoy. Solo con veredicto anclado a la noche — sin él
        // el acta de Hoy pinta sus propios estados («Conociéndote», «Lectura de día») que
        // aquí ya dice el campo; no se duplica.
        let actaHoy: LiquidActa? = hayVeredicto
            ? LiquidHoyBuilder.acta(prep: prep, healthConnected: healthConnected)
            : nil

        let leyenda: [LiquidCalendario90.NivelLeyenda] = [
            .init(id: "full", color: tono(.full), etiqueta: peldano(.full)),
            .init(id: "caution", color: tono(.caution), etiqueta: peldano(.caution)),
            .init(id: "easy", color: tono(.easy), etiqueta: peldano(.easy)),
            .init(id: "none", color: LiquidColor.celdaVaciaPip, etiqueta: peldano(.lowSignal)),
        ]

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
            actaHoy: actaHoy,
            conteosSenal: conteosSenal,
            notaConteos: notaConteos,
            leyenda: leyenda,
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
                       defaultValue: "I build Preparation from what your watch already saves in Apple Health: resting heart rate, HRV, sleep, temperature and breathing. Without that permission I have nothing to read. Everything stays on your iPhone."))

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
