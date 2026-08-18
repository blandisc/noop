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
    var onCerrar: (() -> Void)? = nil

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
        .background(LiquidColor.fondoGradient.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }

    // MARK: - El campo: el veredicto de hoy como ancla, no como titular

    private var campo: some View {
        LiquidCampoMetrica(
            tono: tono,
            titulo: String(localized: "prep.titulo", defaultValue: "Preparation"),
            datos: [],
            veredicto: modelo.palabraHoy,
            clausula: modelo.clausulaHoy,
            volverTitulo: String(localized: "prep.volver", defaultValue: "Back"),
            onVolver: onCerrar
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
                pistaVacia: String(localized: "prep.mosaico.pista",
                                   defaultValue: "Tap a morning to read it."))
                .liquidSeccion()

            if let aviso = modelo.avisoVentanaSinVeredicto {
                Text(aviso)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta700)
                    .liquidSeccion(top: 0)
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
                    Text(String(localized: "prep.atribucion.nota",
                                defaultValue: "These are the nights each signal came in outside your range. A single night out doesn't move your verdict on its own, so these numbers won't add up to the mosaic above."))
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
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
                        HStack(spacing: LiquidSpace.s250) {
                            Text(eje.nombre).font(LiquidType.cuerpo)
                                .foregroundStyle(LiquidColor.tinta900)
                            Spacer(minLength: LiquidSpace.s250)
                            Text(eje.estado).font(LiquidType.label)
                                .foregroundStyle(eje.fuera ? tono : LiquidColor.tinta500)
                        }
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
        VStack(alignment: .leading, spacing: 0) {
            LiquidFranjaSeccion(String(localized: "prep.metodo.titulo",
                                       defaultValue: "See the method"), tono: tono)
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text(String(localized: "prep.metodo.como",
                            defaultValue: "Every morning I compare three resting signals against your own baseline: the autonomic one (your resting heart rate and HRV), your sleep, and the sentinel (skin temperature and breathing, which only counts when both run high together). None outside is «all in range»; one is «one signal out»; two or more is «two or more out». It takes two days in a row for a change to move your verdict, so one odd night doesn't tip it."))
                // §4: el mosaico se recalcula con la base de HOY. Decirlo no es un detalle legal:
                // sin esta línea la pantalla afirmaría, sin querer, que muestra lo que el usuario
                // leyó cada una de esas mañanas.
                Text(String(localized: "prep.metodo.limite",
                            defaultValue: "Each square is recalculated with what I know about you today — it isn't a snapshot of what you saw that morning. If your baseline has moved since then, an older day can read differently now. Training load doesn't vote here."))
            }
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
            .liquidSeccion()
        }
    }

    // MARK: - Estados de pantalla

    private var cargando: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            ProgressView().tint(LiquidColor.tinta500)
            Text(String(localized: "prep.cargando", defaultValue: "Reading your mornings…"))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
        }
        .liquidSeccion(top: LiquidSpace.s550)
        .accessibilityElement(children: .combine)
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

    static func unidadDias(_ n: Int) -> String {
        String(format: String(localized: "prep.dias.fmt", defaultValue: "%d days"), n)
    }

    static func unidadDiasCorta(_ n: Int) -> String {
        String(localized: "prep.dias.corta", defaultValue: "days")
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
        copySinPermiso: bienvenidaSinPermiso, copySinHistoria: bienvenidaSinHistoria)

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
            return .init(id: clave, fecha: fecha, peldano: idPeldano(noche.verdict),
                         etiqueta: "\(etiquetaDia) · \(lectura)")
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
                  pie: String(localized: "prep.atr.auto",
                              defaultValue: "Your resting heart rate or HRV came in outside your base")),
            .init(id: "sleep", nombre: String(localized: "Sleep"),
                  dias: leidas.filter(\.sleepOut).count,
                  pie: String(localized: "prep.atr.sueno",
                              defaultValue: "You slept less than your body asks for")),
            .init(id: "sentinel", nombre: String(localized: "prep.atr.centinela.nombre",
                                                 defaultValue: "Temperature and breathing"),
                  dias: leidas.filter(\.sentinelOut).count,
                  pie: String(localized: "prep.atr.centinela",
                              defaultValue: "Both ran high together — one alone never counts")),
            .init(id: "leidas", nombre: String(localized: "prep.atr.leidas.nombre",
                                               defaultValue: "Mornings read"),
                  dias: conLectura,
                  pie: String(localized: "prep.atr.leidas",
                              defaultValue: "The rest didn't have enough signal")),
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

        let estado: Estado
        if !healthConnected { estado = .sinPermiso }
        else if (prep?.verdictHistory ?? []).isEmpty && !ventanaVacia { estado = .sinHistoria }
        else if prep == nil { estado = .sinHistoria }
        else { estado = .conVentana }

        return PreparacionDetalleModelo(
            estado: estado,
            palabraHoy: hayVeredicto ? LiquidHoyBuilder.palabraVeredicto(prep!.verdict) : nil,
            clausulaHoy: hayVeredicto ? LiquidHoyBuilder.clausulaVeredicto(prep) : nil,
            selloConfianza: sello(prep),
            tonoHoy: hayVeredicto ? tono(prep!.verdict) : LiquidColor.tinta500,
            rejilla: rejilla,
            peldanos: peldanosBase,
            conteos: conteos,
            pistaCobertura: String(format: String(localized: "prep.cobertura.fmt",
                                                  defaultValue: "%d with a reading"), conLectura),
            avisoVentanaSinVeredicto: ventanaVacia ? avisoVacio(prep) : nil,
            atribucion: atribucion,
            ejesHoy: ejesHoy,
            copySinPermiso: bienvenidaSinPermiso,
            copySinHistoria: bienvenidaSinHistoria)
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
                          defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in — if you don't wear your watch at night, I won't be able to read them.")
        }
        return String(format: String(localized: "prep.vacio.formando.fmt",
                                     defaultValue: "None of these 30 mornings had a verdict yet: I'm still learning your normal. You have %d nights so far."),
                      prep.autonomicNights)
    }

    private static func sello(_ prep: Preparedness.Read?) -> String? {
        guard let prep, prep.verdict != .lowSignal, prep.isNightAnchored else { return nil }
        return String(format: String(localized: "prep.sello.fmt",
                                     defaultValue: "%d nights of your baseline"),
                      prep.autonomicNights)
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
