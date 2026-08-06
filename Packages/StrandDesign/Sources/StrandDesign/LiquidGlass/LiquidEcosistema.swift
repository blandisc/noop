import SwiftUI

// MARK: - «El Ecosistema» (FER-10) — el héroe de Hoy
//
// Esferas de PARTÍCULAS (la nube es textura; el DATO es el nivel del líquido y el valor
// adentro — los conteos son constantes, no una partícula por lectura) que se funden en el
// orbe del veredicto: las dos decisoras (EN REPOSO · SUEÑO) quedan orbitándolo como lunas con su
// etiqueta, y el guardián (temperatura + respiración) es el tercer orbe menor SIEMPRE
// presente en su órbita externa — el día que sus dos señales van juntas, la abandona y se
// asoma DETRÁS del orbe («el eclipse»). Tap = separar (pegajoso); tap de nuevo = unir.
//
// La física vive en `EcosistemaSimulacion` (pura, testeable — la spec del shader de Fase
// B); aquí solo se dibuja (Canvas + TimelineView 60 Hz pausable) y se compone la capa de
// texto/interacción/accesibilidad. Reduce Motion: cuadro canónico t = 0, transiciones
// instantáneas, toda la información disponible sin el gesto.

/// Los rótulos fijos del Ecosistema, YA localizados (el DS no conoce locales).
public struct EcosistemaRotulos: Sendable {
    public let reposo: String       // «REPOSO» (etiqueta orbital)
    public let sueno: String        // «SUEÑO»
    public let guardian: String     // «GUARDIÁN»
    public let temperatura: String  // «TEMPERATURA»
    public let respiracion: String  // «RESPIRACIÓN»
    public let hintSeparar: String  // «TOCA PARA SEPARAR»
    public let hintUnir: String     // «TOCA PARA UNIR»
    public let accionSeparar: String
    public let accionUnir: String
    public let abrirReposo: String        // «Abrir En reposo» (rotor)
    public let abrirSueno: String
    public let abrirGuardian: String
    public let sinLecturaNoche: String    // «Sin lectura anoche» (badge sin dato)
    public let sinLecturaHoy: String
    public let guardianSinLecturas: String // «Guardián: sin lecturas hoy» (VoiceOver)
    public let anuncioVeredicto: String   // «Tu veredicto llegó: %@» (announcement)
    public let vigiaEnRango: String       // «En rango» (subtítulo de vigía)
    public let vigiaFuera: String         // «Fuera de tu rango»

    public init(reposo: String, sueno: String, guardian: String, temperatura: String,
                respiracion: String, hintSeparar: String, hintUnir: String,
                accionSeparar: String, accionUnir: String,
                abrirReposo: String = "Abrir En reposo",
                abrirSueno: String = "Abrir Sueño",
                abrirGuardian: String = "Abrir Guardián",
                sinLecturaNoche: String = "Sin lectura anoche",
                sinLecturaHoy: String = "Sin lectura hoy",
                guardianSinLecturas: String = "Guardián: sin lecturas hoy",
                anuncioVeredicto: String = "Tu veredicto llegó: %@",
                vigiaEnRango: String = "En rango",
                vigiaFuera: String = "Fuera de tu rango") {
        self.reposo = reposo
        self.sueno = sueno
        self.guardian = guardian
        self.temperatura = temperatura
        self.respiracion = respiracion
        self.hintSeparar = hintSeparar
        self.hintUnir = hintUnir
        self.accionSeparar = accionSeparar
        self.accionUnir = accionUnir
        self.abrirReposo = abrirReposo
        self.abrirSueno = abrirSueno
        self.abrirGuardian = abrirGuardian
        self.sinLecturaNoche = sinLecturaNoche
        self.sinLecturaHoy = sinLecturaHoy
        self.guardianSinLecturas = guardianSinLecturas
        self.anuncioVeredicto = anuncioVeredicto
        self.vigiaEnRango = vigiaEnRango
        self.vigiaFuera = vigiaFuera
    }

    /// El juego BASE (es-MX) — default del modelo para previews/tests del paquete; la app
    /// SIEMPRE pasa el suyo desde el String Catalog (el DS no conoce locales).
    public static let base = EcosistemaRotulos(
        reposo: "REPOSO", sueno: "SUEÑO", guardian: "GUARDIÁN",
        temperatura: "TEMPERATURA", respiracion: "RESPIRACIÓN",
        hintSeparar: "TOCA PARA SEPARAR", hintUnir: "TOCA PARA UNIR",
        accionSeparar: "Separar señales", accionUnir: "Unir señales")
}

public struct LiquidEcosistema: View {
    public typealias Sim = EcosistemaSimulacion

    private let senales: [LiquidHoyModel.Senal]
    private let hero: LiquidHoyModel.Hero
    private let guardian: LiquidHoyModel.Guardian?
    private let ambiente: LiquidAmbiente
    private let calibracion: LiquidHoyModel.Calibracion?
    private let rotulos: EcosistemaRotulos
    private let heroPuerta: String?
    private let heroHint: String?
    private let mostrarHintSeparar: Bool
    private let fusionInicial: Bool
    private let onTapVeredicto: (() -> Void)?
    private let onTapSenal: ((String) -> Void)?
    private let onTapGuardian: (() -> Void)?
    private let onFusionArrancada: (() -> Void)?
    private let onSeparacion: (() -> Void)?

    @State private var fase: Sim.Fase?
    /// Ancla de la GRADUACIÓN en vivo (FER-20): la base se completó con la pantalla
    /// abierta (calibrando → veredicto) y el embrión madura al orbe con un morfo,
    /// en vez del corte al ritual de fusión.
    @State private var graduacionDesde: TimeInterval?
    @State private var escala: CGFloat = 1
    /// ¿El héroe está a la vista? (FER-14 #3) — fuera del viewport el reloj de 60 Hz se
    /// apaga. Arranca en `true`: si el héroe no vive dentro de un ScrollView el modifier
    /// nunca dispara y el default honesto es «visible».
    @State private var visible = true
    private let faseForzada: Sim.Fase?
    /// «El Tablero» (FER-28): presentación compacta — reserva `ecosistemaAltoCompacto` y sube
    /// el lienzo recortando su aire superior, sin tocar el arte. Default `false` = héroe pleno.
    private let compacto: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(senales: [LiquidHoyModel.Senal], hero: LiquidHoyModel.Hero,
                guardian: LiquidHoyModel.Guardian?, ambiente: LiquidAmbiente,
                calibracion: LiquidHoyModel.Calibracion?, rotulos: EcosistemaRotulos,
                heroPuerta: String? = nil, heroHint: String? = nil,
                mostrarHintSeparar: Bool = true, fusionInicial: Bool = false,
                compacto: Bool = false,
                onTapVeredicto: (() -> Void)? = nil, onTapSenal: ((String) -> Void)? = nil,
                onTapGuardian: (() -> Void)? = nil,
                onFusionArrancada: (() -> Void)? = nil, onSeparacion: (() -> Void)? = nil) {
        self.init(senales: senales, hero: hero, guardian: guardian, ambiente: ambiente,
                  calibracion: calibracion, rotulos: rotulos, heroPuerta: heroPuerta,
                  heroHint: heroHint, mostrarHintSeparar: mostrarHintSeparar,
                  fusionInicial: fusionInicial, faseForzada: nil, compacto: compacto,
                  onTapVeredicto: onTapVeredicto, onTapSenal: onTapSenal,
                  onTapGuardian: onTapGuardian,
                  onFusionArrancada: onFusionArrancada, onSeparacion: onSeparacion)
    }

    /// `faseForzada` — SOLO tests/renders (p. ej. `.separada` para `estado_separado.png`).
    init(senales: [LiquidHoyModel.Senal], hero: LiquidHoyModel.Hero,
         guardian: LiquidHoyModel.Guardian?, ambiente: LiquidAmbiente,
         calibracion: LiquidHoyModel.Calibracion?, rotulos: EcosistemaRotulos,
         heroPuerta: String? = nil, heroHint: String? = nil,
         mostrarHintSeparar: Bool = true, fusionInicial: Bool = false,
         faseForzada: Sim.Fase?, compacto: Bool = false,
         onTapVeredicto: (() -> Void)? = nil, onTapSenal: ((String) -> Void)? = nil,
         onTapGuardian: (() -> Void)? = nil,
         onFusionArrancada: (() -> Void)? = nil, onSeparacion: (() -> Void)? = nil) {
        self.compacto = compacto
        self.senales = senales
        self.hero = hero
        self.guardian = guardian
        self.ambiente = ambiente
        self.calibracion = calibracion
        self.rotulos = rotulos
        self.heroPuerta = heroPuerta
        self.heroHint = heroHint
        self.mostrarHintSeparar = mostrarHintSeparar
        self.fusionInicial = fusionInicial
        self.faseForzada = faseForzada
        self.onTapVeredicto = onTapVeredicto
        self.onTapSenal = onTapSenal
        self.onTapGuardian = onTapGuardian
        self.onFusionArrancada = onFusionArrancada
        self.onSeparacion = onSeparacion
        if let faseForzada {
            _fase = State(initialValue: faseForzada)
        }
    }

    // MARK: Proyección semántica (modelo → coreografía)

    /// Deriva la coreografía de campos que YA existen en el modelo — sin campo nuevo.
    static func coreografia(hero: LiquidHoyModel.Hero, ambiente: LiquidAmbiente,
                            guardianEstado: LiquidHoyModel.Guardian.Estado?,
                            lunaSueno: Bool,
                            calibracion: LiquidHoyModel.Calibracion?) -> Sim.Coreografia {
        if let calibracion {
            return .calibrando(noche: calibracion.noche, total: calibracion.total)
        }
        switch hero {
        case .veredicto:
            switch ambiente {
            case .bien: return .enRango
            case .atencion: return .atencion(eclipse: guardianEstado == .juntas)
            case .alerta: return .desgaste
            case .neutro: return .neutra(lunaSueno: lunaSueno)
            }
        case .demotado:
            return .neutra(lunaSueno: lunaSueno)
        }
    }

    private var coreo: Sim.Coreografia {
        Self.coreografia(hero: hero, ambiente: ambiente, guardianEstado: guardian?.estado,
                         lunaSueno: senales.dropFirst().first?.progress != nil,
                         calibracion: calibracion)
    }

    private var still: Bool { reduceMotion || motionDisabled }

    /// La identidad del veredicto visible (nil = demotado/calibrando): el ciclo de vida
    /// observa CAMBIOS de palabra, no solo el flanco con-fusión (Grok #2).
    private var tituloVeredicto: String? {
        if case .veredicto(let title, _, _, _, _) = hero, coreo.conFusion { return title }
        return nil
    }

    // MARK: Body

    public var body: some View {
        if dynamicTypeSize >= .xxxLarge {
            // xxxLarge+: el héroe abandona la física — variante lista con TODOS los datos.
            // El corte NO espera a AX1 (FER-14 #2): el lienzo mide 364×324 fijos y entre
            // xxxLarge y accessibility1 la tipografía ya crece lo suficiente para que la
            // palabra del veredicto se encime al orbe. El colapso temprano es honesto —
            // ningún dato se pierde, solo la física.
            EcosistemaListado(senales: senales, hero: hero, guardian: guardian,
                              calibracion: calibracion, rotulos: rotulos,
                              heroPuerta: heroPuerta,
                              onTapVeredicto: onTapVeredicto, onTapSenal: onTapSenal,
                              onTapGuardian: onTapGuardian)
        } else {
            lienzo
        }
    }

    /// Cuánto sube el lienzo en modo compacto (SOLO el aire superior recortado), escalado con
    /// el lienzo. El aire de ABAJO lo recorta el jalón del veredicto (`acercaVeredicto`). 0 en
    /// modo pleno.
    private var recorteCompacto: CGFloat {
        // En SEPARADO el contenido sube (las etiquetas «en tu rango» viven ARRIBA de las esferas):
        // jalar el aire superior le recorta la cabeza al hero. El estado separado no lleva veredicto
        // abajo, así que ahí NO jalamos — el recorte de altura se come el aire de abajo, vacío.
        guard compacto, !esSeparadaEstable else { return 0 }
        return LiquidSpace.ecosistemaRecorteTop * escala
    }

    private var lienzo: some View {
        ZStack(alignment: .topLeading) {
            // Lector de ancho (una vía): el hueco reservado escala CON el lienzo — en un
            // SE/mini no queda banda muerta bajo el héroe (Grok #13).
            GeometryReader { geo in
                Color.clear
                    .onAppear { escala = min(1, geo.size.width / Sim.Geometria.lienzo.width) }
                    .onChange(of: geo.size.width) { _, w in
                        escala = min(1, w / Sim.Geometria.lienzo.width)
                    }
            }
            .frame(height: 0)
            escena
                .frame(width: Sim.Geometria.lienzo.width,
                       height: Sim.Geometria.lienzo.height)
                .scaleEffect(escala, anchor: .top)
                .frame(maxWidth: .infinity)
                // Compacto (FER-28): sube el lienzo recortando su aire superior — el arte no
                // cambia, solo se presenta más apretado. El estado separado sigue librando.
                // FER-46: el offset se ANIMA con la separación — antes saltaba de golpe
                // (recorteCompacto → 0) mientras palabra/valores sí se fundían, y el orbe
                // daba un brinco seco al separar y al reunir. Al UNIR, además, ESPERA a
                // que las esferas viajen de vuelta (mismo retardo que la palabra): subir
                // el lienzo antes de tiempo les cortaba la cabeza a los vigías contra el
                // clipped() del contenedor.
                .offset(y: -recorteCompacto)
                // Pulido /inject (ojo del dueño): ambient (ease-in-out) en vez de glass-out
                // — el arranque del glass-out se sentía un empujón. Al SEPARAR el lienzo
                // espera la anticipación (el orbe toma aire) y PLANEA hacia abajo; al UNIR
                // espera a que las esferas aterricen y sube como un solo gesto final.
                .animation(still ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                                 : (esSeparadaEstable
                                    ? LiquidMotion.ambient(0.9)
                                        .delay(LiquidEcosistemaMotion.anticipacion)
                                    : LiquidMotion.ambient(0.9)
                                        .delay(LiquidEcosistemaMotion.fusionDur * 0.85)),
                           value: esSeparadaEstable)
        }
        .frame(height: (compacto ? LiquidSpace.ecosistemaAltoCompacto
                                 : LiquidSpace.ecosistemaAlto) * escala,
               alignment: .top)
        .clipped()
        .modifier(EcosistemaVisibilidad { visible = $0 })
        .onAppear {
            guard fase == nil else { return }
            let ahora = Date().timeIntervalSinceReferenceDate
            if fusionInicial && coreo.conFusion {
                // El ritual del día corre (con Reduce Motion aparece asentado, pero el
                // día SÍ se consume: recibió su veredicto). El usuario de VoiceOver
                // también lo oye en el cold start (Grok #6).
                fase = still ? .viva(desde: ahora) : .formando(inicio: ahora)
                onFusionArrancada?()
                anunciarVeredicto()
            } else {
                // SIN veredicto aún («Leyendo…», calibrando): el día NO se marca — el
                // ritual espera a que el veredicto se estrene (D1 del gate de QA).
                fase = .viva(desde: ahora)
            }
        }
        // El veredicto se estrena o CAMBIA con la pantalla abierta (sync matutino,
        // backfill que voltea el día): corre el ritual de nuevo + announcement (Grok #2).
        // Esto también resuelve el edge de QA R1 (FER-14 #4): si el dato se borra el
        // héroe cae a demotado (`tituloVeredicto` = nil) y, cuando el veredicto REGRESA
        // el mismo día, la palabra vuelve a cambiar y el ritual SÍ corre. Es lo correcto:
        // el ritual es «tu veredicto llegó», y para el usuario acaba de llegar otra vez.
        // El día ya se consumió en `fusionDay`, así que `onFusionArrancada` no se vuelve
        // a llamar — la re-fusión es visual, no re-marca el día.
        .onChange(of: tituloVeredicto) { antes, ahora in
            guard ahora != nil, antes != ahora, fase != nil else { return }
            let t = Date().timeIntervalSinceReferenceDate
            // Si la GRADUACIÓN acaba de anclar (calibrando→veredicto en vivo, FER-20),
            // este flanco no corre el ritual de fusión: el morfo del embrión es el
            // ritual. El guard cubre ambos órdenes de disparo de los dos onChange.
            if let g = graduacionDesde, t - g < LiquidEcosistemaMotion.graduacionDur + 1 {
                return
            }
            fase = still ? .viva(desde: t) : .formando(inicio: t)
            if fusionInicial { onFusionArrancada?() }
            anunciarVeredicto()
        }
        // GRADUACIÓN en vivo (FER-20, decisión del dueño): si calibrando termina con la
        // pantalla abierta y llega un veredicto con fusión, el embrión MADURA al orbe
        // (morfo mismo-conteo) — las dos decisoras nunca aparecen. Con Reduce Motion,
        // corte honesto al cuadro asentado.
        .onChange(of: esCalibrando) { antes, ahora in
            guard antes, !ahora, coreo.conFusion, fase != nil else { return }
            let t = Date().timeIntervalSinceReferenceDate
            if still {
                fase = .viva(desde: t)
            } else {
                graduacionDesde = t
                fase = .viva(desde: t + LiquidEcosistemaMotion.graduacionDur)
            }
            if fusionInicial { onFusionArrancada?() }
            anunciarVeredicto()
        }
        // Medianoche con la app viva: cuando el día local cambia y el body se re-evalúa,
        // `fusionInicial` vuelve a true — el ritual del día nuevo corre (Grok #3).
        .onChange(of: fusionInicial) { antes, ahora in
            guard ahora, !antes, coreo.conFusion, fase != nil else { return }
            let t = Date().timeIntervalSinceReferenceDate
            fase = still ? .viva(desde: t) : .formando(inicio: t)
            onFusionArrancada?()
        }
        // La separación es una consulta momentánea: al salir de la tab o backgroundear,
        // el héroe regresa a fundido (su reposo ES el veredicto) — sin re-fusión.
        .onDisappear { normalizarFase() }
        .onChange(of: ambientPaused) { _, paused in
            if paused { normalizarFase() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Text(verbatim: a11yCompuesta))
        .accessibilityHint(Text(verbatim: heroHint ?? ""))
        .modifier(EcosistemaA11yAcciones(
            separable: coreo.separable,
            separada: esSeparadaEstable,
            rotulos: rotulos, senales: senales, heroPuerta: heroPuerta,
            onToggle: { alternar() }, onTapVeredicto: onTapVeredicto,
            onTapSenal: onTapSenal, onTapGuardian: onTapGuardian))
    }

    /// ¿La fase actual es (o desemboca en) separada? — para hints y acciones AX.
    private var esSeparadaEstable: Bool {
        switch fase {
        case .separada, .separando: return true
        default: return false
        }
    }

    private var escena: some View {
        ZStack(alignment: .topLeading) {
            EcosistemaEscenario(coreo: coreo, fase: fase ?? .viva(desde: 0),
                                graduacionDesde: graduacionDesde,
                                senales: senales, guardianJuntas: guardian?.estado == .juntas,
                                vigiaFuera: [
                                    guardian?.estado == .tempFuera || guardian?.estado == .juntas,
                                    guardian?.estado == .respFuera || guardian?.estado == .juntas,
                                ],
                                guardianHueco: guardian == nil
                                    || (guardian?.temp == "—" && guardian?.resp == "—"),
                                rotulos: rotulos, still: still,
                                paused: still || ambientPaused || !visible)
                .contentShape(Rectangle())
                .onTapGesture { alternar() }
            overlays
        }
    }

    private func alternar() {
        guard coreo.separable, let actual = fase else { return }
        let ahora = Date().timeIntervalSinceReferenceDate
        // Sin taps DURANTE la graduacion (FER-20): el morfo embrion-orbe dura ~1.4 s
        // y un separar a medio morfo mezclaria dos coreografias.
        if let g = graduacionDesde, ahora - g < LiquidEcosistemaMotion.graduacionDur {
            return
        }
        // La fase VENCIDA se resuelve a su sucesora antes de decidir: el primer tap
        // sobre un estado asentado siempre actúa (sin esto, `.separando` vencida se
        // re-etiquetaba `.separada` y el tap de unir moría — cazado en simulador).
        switch Sim.faseEfectiva(actual, t: ahora) {
        case .formando:
            // Tap DURANTE la fusión = saltar al estado fundido final (HIG: nunca
            // atrapar al usuario en una animación). No cuenta como separación.
            fase = .viva(desde: ahora)
        case .viva:
            fase = still ? .separada : .separando(desde: ahora)
            onSeparacion?()
        case .separando:
            fase = .separada                    // completar la transición al instante
        case .separada:
            fase = still ? .viva(desde: ahora) : .uniendo(desde: ahora)
        case .uniendo:
            fase = .viva(desde: ahora)          // completar la transición al instante
        }
    }

    /// El reposo del héroe es el veredicto: cualquier separación viva vuelve a fundido.
    private func normalizarFase() {
        switch fase {
        case .separada, .separando:
            fase = .viva(desde: Date().timeIntervalSinceReferenceDate)
        default:
            break
        }
    }

    /// Announcement de VoiceOver al estrenar el veredicto (jamás durante la coreografía
    /// se repite: una sola vez, al llegar).
    private func anunciarVeredicto() {
        #if canImport(UIKit) && !os(watchOS)
        guard case .veredicto(let title, _, _, _, _) = hero else { return }
        let plano = title.replacingOccurrences(of: "\n", with: " ")
        UIAccessibility.post(notification: .announcement,
                             argument: String(format: rotulos.anuncioVeredicto, plano))
        #endif
    }

    // MARK: Overlays (texto real — jamás dibujado en partículas)

    @ViewBuilder private var overlays: some View {
        let G = Sim.Geometria.self
        // Hint: arriba en fundido; en separado BAJA al centro vacío del lienzo para no
        // chocar con los mini-orbes del guardián (revisión de usuario en simulador).
        if coreo.separable {
            // Dos textos FIJOS que se cruzan en fundido (oleada «costuras»: el texto
            // único con offset animado VOLABA 218 pt por el lienzo al cambiar de modo).
            // Cada hint entra retardado — cuando su escena ya aterrizó — y sale al tap.
            let retardoHint = LiquidEcosistemaMotion.anticipacion
                + LiquidEcosistemaMotion.fusionDur * 0.8
            Group {
                Text(rotulos.hintSeparar)
                    .offset(y: 8)
                    .opacity(!esSeparadaEstable && mostrarHintSeparar ? 1 : 0)
                    .animation(esSeparadaEstable
                               ? LiquidMotion.glassOut(LiquidMotion.quick)
                               : LiquidMotion.glassOut(LiquidMotion.quick).delay(retardoHint),
                               value: esSeparadaEstable)
                Text(rotulos.hintUnir)
                    .offset(y: 226)
                    .opacity(esSeparadaEstable ? 1 : 0)
                    .animation(esSeparadaEstable
                               ? LiquidMotion.glassOut(LiquidMotion.quick).delay(retardoHint)
                               : LiquidMotion.glassOut(LiquidMotion.quick),
                               value: esSeparadaEstable)
            }
            .font(LiquidType.microEstado).tracking(LiquidType.labelTracking)
            .foregroundStyle(LiquidColor.tinta500.opacity(0.6))
            .frame(width: G.lienzo.width)
            // El hint invita al tap: JAMÁS debe comérselo (un Text con hit-testing
            // default encima del canvas bloquea el gesto — cazado en simulador).
            .allowsHitTesting(false)
        }
        // Valores ADENTRO de las esferas (estado separado). `allowsHitTesting` sigue a la
        // visibilidad: un botón invisible jamás intercepta el tap del lienzo (D11).
        Group {
            valoresSeparados
            guardianSeparado
        }
        // El contenedor solo DESTAPA (paso 2 de la opción «escrito en partículas»): la
        // entrada condensada de blur/scale fue sustituida por la FORMACIÓN real de las
        // motas dentro de `DatoDeMotas` — cada dígito se arma desde la materia del orbe.
        // El destape espera a que las esferas estén aterrizando; la salida es inmediata
        // (las motas se disuelven de regreso mientras el contenedor se apaga).
        .opacity(esSeparadaEstable ? 1 : 0)
        // Asentado sutil (ronda quirurgica): el valor no APARECE, se sienta.
        .scaleEffect(esSeparadaEstable ? 1 : 0.97)
        .allowsHitTesting(esSeparadaEstable)
        .animation(still ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                         : (esSeparadaEstable
                            // FER-54 (revisión del dueño): primero ATERRIZA el orbe,
                            // después habla el texto — 0.45 destapaba a mitad del vuelo.
                            ? LiquidMotion.glassOut(LiquidMotion.quick)
                                .delay(LiquidEcosistemaMotion.anticipacion
                                       + LiquidEcosistemaMotion.fusionDur * 0.85)
                            : LiquidMotion.glassOut(LiquidMotion.quick)),
                   value: esSeparadaEstable)
        // La palabra del veredicto (abajo, centrada) — se oculta en separado. En compacto
        // (FER-28) sube `acercaVeredicto` hacia el orbe (recorta el aire de abajo).
        palabra
            .frame(width: G.lienzo.width)
            .frame(height: G.lienzo.height - 34
                   - (compacto ? LiquidSpace.ecosistemaAcercaVeredicto : 0), alignment: .bottom)
            .opacity(esSeparadaEstable ? 0 : 1)
            // Deriva sutil (overlapping action, ojo del dueño): la palabra no aparece —
            // ATERRIZA. Al separar se hunde 10 pt (la misma dirección en la que el orbe
            // va a bajar); al unir viaja esos 10 pt de vuelta a su asiento mientras
            // funde. Reduce Motion: cero viaje, solo crossfade.
            .offset(y: still ? 0 : (esSeparadaEstable ? 10 : 0))
            // La palabra es puro texto (la puerta vive aparte): NUNCA intercepta el tap
            // del lienzo — tocar el veredicto también separa (Grok #1).
            .allowsHitTesting(false)
            // Al SEPARAR se desvanece de inmediato (se hace a un lado, ambient suave);
            // al UNIR llega ~0.45 s DESPUÉS de que la subida arrancó — primero se mueve
            // el objeto, después habla el texto. Todo al unísono se sentía mecánico.
            .animation(still ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                             : (esSeparadaEstable
                                ? LiquidMotion.ambient(LiquidEcosistemaMotion.palabraDur)
                                : LiquidMotion.ambient(0.75)
                                    .delay(LiquidEcosistemaMotion.fusionDur * 0.85 + 0.45)),
                       value: esSeparadaEstable)
        // La PUERTA al acta («Cómo llegué a esto») vive en AMBOS modos (D10): el tap del
        // lienzo ya no navega, así que esta pastilla es la única entrada visible.
        if let heroPuerta {
            botonPuerta(heroPuerta)
                .frame(width: G.lienzo.width)
                .frame(height: G.lienzo.height
                       - (compacto ? LiquidSpace.ecosistemaAcercaVeredicto : 0), alignment: .bottom)
        }
    }

    @ViewBuilder private var valoresSeparados: some View {
        let G = Sim.Geometria.self
        ForEach(Array(senales.prefix(2).enumerated()), id: \.element.id) { i, senal in
            let centro = i == 0 ? G.p1 : G.p2
            let etiqueta = i == 0 ? rotulos.reposo : rotulos.sueno
            VStack(spacing: LiquidSpace.s050) {
                Text(etiqueta)
                    .font(LiquidType.micro).tracking(LiquidType.microTracking)
                    .foregroundStyle(LiquidColor.tinta700)   // FER-45: contraste legible
            }
            .position(x: centro.x, y: 74)
            // Opción 2 «escrito en partículas» (decisión del dueño /inject, tras probar
            // A y B): el número está HECHO de la misma materia del orbe — una matriz de
            // motas en tinta, más densas y grandes que la nube. Sin respaldo ni vidrio:
            // el orbe habla con su propia materia (el vapor a 0.12 le despeja el aire).
            // Los rótulos y captions siguen siendo texto real (la regla del plan).
            botonSenal(senal) {
                // El número en el COLOR del orbe (revisión del dueño: la tinta neutra
                // desconectaba al dato de su esfera) — verde profundo, el mismo verde
                // del clima dicho en voz de texto; en atención, el rojo de siempre.
                // Tipografía SÓLIDA (FER-22, revisión del dueño: los dígitos de motas
                // no se veían bien). Tinta negra; rojo solo en atención — semántica.
                Text(verbatim: senal.badge?.valor ?? senal.valor ?? "—")
                    .font(LiquidType.valorL)
                    .foregroundStyle(senal.state == .atencion
                                     ? LiquidColor.negativo : LiquidColor.tinta900)
                    .padding(LiquidSpace.s300)
                    .frame(minWidth: 60, minHeight: LiquidControl.hitTarget)
            }
            .position(x: centro.x, y: centro.y - 4)
            // La frase baja al PAPEL limpio bajo la esfera (revisión del dueño: dentro
            // del orbe competía con las partículas y no se leía) y sube de peso.
            // Sin dato: la honestidad tiene voz («Sin lectura anoche/hoy»), no un guion.
            Text(senal.badge?.contexto
                 ?? (i == 1 ? rotulos.sinLecturaNoche : rotulos.sinLecturaHoy))
                .font(LiquidType.captionLectura)   // FER-31: ya es medium; se quitó el .fontWeight(.medium) redundante
                .foregroundStyle(LiquidColor.tinta900)
                .opacity(senal.badge != nil || senal.progress == nil ? 1 : 0)
                .position(x: centro.x, y: centro.y + G.radioSeparada + 18)
                .allowsHitTesting(false)
        }
    }

    /// El guardián también da la cara SIEMPRE al separar (default confirmado FER-10):
    /// sus dos señales con su dato, haya alerta o no. Es UN target conjunto ≥44 pt que
    /// navega al mismo destino que la franja (D3 del gate de QA).
    @ViewBuilder private var guardianSeparado: some View {
        let G = Sim.Geometria.self
        let juntas = guardian?.estado == .juntas
        let tempFuera = guardian?.estado == .tempFuera || juntas
        let respFuera = guardian?.estado == .respFuera || juntas
        // «Etiqueta de espécimen» espejo (revisión del dueño): títulos arriba del orbe;
        // las CIFRAS hacia afuera — temperatura a la izquierda de su orbe, respiración
        // a la derecha del suyo — conectadas por el puente de materia y por la
        // formación que llega desde el lado del orbe.
        let contenido = ZStack {
            vigiaColumna(valor: guardian?.temp ?? "—", rotulo: rotulos.temperatura,
                         fuera: tempFuera, x: G.guardianSeparado1.x, lado: -1)
            vigiaColumna(valor: guardian?.resp ?? "—", rotulo: rotulos.respiracion,
                         fuera: respFuera, x: G.guardianSeparado2.x, lado: 1)
        }
        .frame(width: G.lienzo.width, height: 64)
        .contentShape(Rectangle())
        Group {
            if let onTapGuardian {
                Button(action: onTapGuardian) { contenido }
                    .buttonStyle(.liquidPress)
            } else {
                contenido
            }
        }
        .position(x: Sim.Geometria.centro.x,
                  y: (G.guardianSeparado1.y + G.guardianSeparado2.y) / 2)
    }

    /// Una columna de vigía en coordenadas locales del ZStack del guardián separado.
    /// «Etiqueta de espécimen» espejo (revisión del dueño): la cifra vive AL LADO de
    /// su orbe, hacia afuera — temperatura a la izquierda, respiración a la derecha
    /// (`lado` −1/+1) — sobre papel limpio y a tamaño pleno. La conexión se VE dos
    /// veces: un puente de motas del limbo del orbe hacia la cifra, y la formación
    /// misma, cuya materia llega DESDE el lado del orbe (`origenLado`).
    @ViewBuilder private func vigiaColumna(valor: String, rotulo: String, fuera: Bool,
                                           x: CGFloat, lado: CGFloat) -> some View {
        let rOrbe = Sim.Geometria.radioGuardianSeparado
        let tinta = fuera ? LiquidColor.atencionTexto : LiquidColor.tinta900
        let materia = fuera ? LiquidColor.atencionTexto : LiquidColor.azul
        Text(rotulo)
            .font(LiquidType.orbita).tracking(LiquidType.orbitaTracking)
            .fontWeight(.medium)
            .foregroundStyle(tinta)
            .fixedSize()
            .position(x: x, y: 6)
        // (El puente de motas al número murió — revisión del dueño: la conexión que
        // importa es la MIRADA del vigía al orbe principal, que vive en el plan.)
        let _ = materia
        // Tipografía SÓLIDA (FER-22) + SUBTÍTULO (revisión del dueño: la misma voz
        // que «En tu base» de rest/sleep — el vigía también dice cómo amaneció).
        VStack(alignment: lado > 0 ? .leading : .trailing, spacing: LiquidSpace.s050) {
            Text(verbatim: valor)
                .font(LiquidType.datoMenor)
                .foregroundStyle(tinta)
                .fixedSize()
            Text(fuera ? rotulos.vigiaFuera : rotulos.vigiaEnRango)
                .font(LiquidType.captionLectura)
                .foregroundStyle(fuera ? LiquidColor.atencionTexto : LiquidColor.tinta700)
                // Sin fixedSize (ronda quirurgica): «Fuera de tu rango» rebasaba el
                // lienzo por la izquierda; envuelto a 2 lineas cabe en la caja.
                .lineLimit(2)
                .multilineTextAlignment(lado > 0 ? .leading : .trailing)
        }
        .frame(width: 120, alignment: lado > 0 ? .leading : .trailing)
        // FER-46 (ojo del dueño): el gap geométrico era idéntico (18 pt por lado), pero la
        // temperatura REMATA hacia el orbe con «°» — glifo chico y ligero — mientras la
        // respiración arranca con dígitos pesados. Compensación ÓPTICA: el lado izquierdo
        // se acerca 6 pt para que ambas cifras se PERCIBAN igual de ancladas a su orbe.
        .position(x: x + lado * (rOrbe + (lado > 0 ? 18 : 12) + 60), y: 36)
    }

    // (miniGuardian murió con la gramática de columnas: ver `vigiaColumna`.)

    // (El respaldo esmerilado y los dígitos de motas murieron — FER-22: los valores
    // del estado separado son tipografía sólida en tinta, sin velo ni partículas.)

    @ViewBuilder private func botonSenal<C: View>(_ senal: LiquidHoyModel.Senal,
                                                  @ViewBuilder _ contenido: () -> C) -> some View {
        if let onTapSenal {
            Button { onTapSenal(senal.id) } label: { contenido() }
                .buttonStyle(.liquidPress)
        } else {
            contenido()
        }
    }

    // MARK: La palabra del veredicto

    @ViewBuilder private var palabra: some View {
        VStack(spacing: LiquidSpace.s150) {
            switch hero {
            case .veredicto(let title, let highlight, let tone, let subtitle, let confianza):
                palabraVeredicto(title: title, highlight: highlight, tone: tone)
                Text(subtitle)
                    .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
                    .multilineTextAlignment(.center)
                if let confianza {
                    Text(confianza)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            case .demotado(let kicker, let title, let subtitle):
                if let kicker {
                    Text(kicker).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                }
                // Los estados sin veredicto hablan bajito (displayS): un titular
                // demotado de 2 líneas en displayL se encimaba al orbe (revisión en
                // simulador con «Aún no conozco tu base»).
                Text(title)
                    .font(LiquidType.displayS)
                    .tracking(LiquidType.displaySTracking)
                    .foregroundStyle(esCalibrando ? LiquidColor.tinta700 : LiquidColor.tinta900)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
                    .multilineTextAlignment(.center)
            }
            if case .calibrando(let noche, let total) = coreo {
                puntosProgreso(noche: noche, total: total)
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.bottom, LiquidSpace.s050)
    }

    private var esCalibrando: Bool {
        if case .calibrando = coreo { return true }
        return false
    }

    private func palabraVeredicto(title: String, highlight: String, tone: Color) -> some View {
        let texto: Text
        if let range = title.range(of: highlight, options: .backwards) {
            texto = Text(title[..<range.lowerBound]).foregroundColor(LiquidColor.tinta900)
                + Text(title[range]).foregroundColor(tone)
                + Text(title[range.upperBound...]).foregroundColor(LiquidColor.tinta900)
        } else {
            texto = Text(title).foregroundColor(LiquidColor.tinta900)
        }
        return texto
            .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
            .multilineTextAlignment(.center)
    }

    private func puntosProgreso(noche: Int, total: Int) -> some View {
        HStack(spacing: LiquidSpace.s125) {
            ForEach(0..<max(1, total), id: \.self) { i in
                Circle()
                    .fill(i < noche ? LiquidColor.particulaNeutra : LiquidColor.tinta10)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)   // el caption ya dice «Noche n de m».
    }

    @ViewBuilder private func botonPuerta(_ puerta: String) -> some View {
        // Revisión del dueño en vivo (FER-51): la puerta era invisible en tinta500 —
        // sube a tinta700 con un punto más de aire; sigue siendo pastilla de vidrio.
        let etiqueta = HStack(spacing: LiquidSpace.s150) {
            Text(puerta)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
            LiquidIcon(.chevron, size: 9, color: LiquidColor.tinta700)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s100)
        .background {
            Capsule().fill(LiquidColor.vidrioPastilla)
            Capsule().strokeBorder(LiquidColor.vidrioBordePastilla, lineWidth: 0.5)
        }
        if let onTapVeredicto {
            Button(action: onTapVeredicto) {
                etiqueta
                    .frame(minHeight: LiquidControl.hitTarget)      // target real ≥44 pt (D10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        } else {
            etiqueta
        }
    }

    // MARK: Accesibilidad compuesta

    /// VoiceOver lee veredicto + valores + guardián — JAMÁS la física. Idéntica fundida o
    /// separada (la separación es puramente visual).
    var a11yCompuesta: String {
        var partes: [String] = []
        switch hero {
        case .veredicto(let title, _, _, let subtitle, let confianza):
            partes.append(title.replacingOccurrences(of: "\n", with: " "))
            partes.append(subtitle)
            if let confianza { partes.append(confianza) }
        case .demotado(let kicker, let title, let subtitle):
            if let kicker { partes.append(kicker) }
            partes.append(title)
            partes.append(subtitle)
        }
        for (i, senal) in senales.prefix(2).enumerated() {
            let etiqueta = i == 0 ? rotulos.reposo : rotulos.sueno
            let valor = senal.badge.map { "\($0.valor) \($0.contexto)" }
                ?? senal.valor ?? senal.caption
            partes.append("\(etiqueta): \(valor)")
        }
        if let guardian {
            partes.append(guardian.a11y ?? "\(guardian.label): \(guardian.temp), \(guardian.resp)")
        } else {
            // El guardián es una promesa constante: sin lecturas también da la cara (D9).
            partes.append(rotulos.guardianSinLecturas)
        }
        return partes.reduce("") { acc, parte in
            acc.isEmpty ? parte : acc + (acc.hasSuffix(".") ? " " : ". ") + parte
        }
    }
}

// MARK: - Acciones de rotor (equivalencia sin física)

private struct EcosistemaA11yAcciones: ViewModifier {
    let separable: Bool
    let separada: Bool
    let rotulos: EcosistemaRotulos
    let senales: [LiquidHoyModel.Senal]
    let heroPuerta: String?
    let onToggle: () -> Void
    let onTapVeredicto: (() -> Void)?
    let onTapSenal: ((String) -> Void)?
    let onTapGuardian: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        let base = content
            .accessibilityAction(named: Text(verbatim: heroPuerta ?? "")) {
                onTapVeredicto?()
            }
            .accessibilityAction(named: Text(verbatim: rotulos.abrirReposo)) {
                if let id = senales.first?.id { onTapSenal?(id) }
            }
            .accessibilityAction(named: Text(verbatim: rotulos.abrirSueno)) {
                if let id = senales.dropFirst().first?.id { onTapSenal?(id) }
            }
            .accessibilityAction(named: Text(verbatim: rotulos.abrirGuardian)) {
                onTapGuardian?()
            }
        // La acción de separar/unir solo se OFRECE cuando existe (calibrando no la
        // tiene — un rotor que miente es peor que uno corto, Grok #10).
        if separable {
            base.accessibilityAction(named: Text(verbatim: separada ? rotulos.accionUnir
                                                                    : rotulos.accionSeparar)) {
                onToggle()
            }
        } else {
            base
        }
    }
}

// MARK: - Pausa por viewport (FER-14 #3)

/// El reloj del héroe no corre si el héroe no está en pantalla: en Hoy el hero vive
/// arriba de un scroll largo y su `TimelineView` seguía latiendo a 60 Hz al bajar (QA R5).
/// `onScrollVisibilityChange` es iOS 18+/macOS 15+; por debajo el héroe se comporta como
/// siempre (visible), que es el estado seguro.
private struct EcosistemaVisibilidad: ViewModifier {
    let cambio: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
            content.onScrollVisibilityChange(threshold: 0.01) { cambio($0) }
        } else {
            content
        }
    }
}

// MARK: - Rótulos orbitales ya resueltos (FER-14 #1)

/// `GraphicsContext.resolve` construye el layout del texto: hacerlo por rótulo POR FRAME
/// era el costo real del canvas a 60 Hz (Grok #7). Los rótulos son un puñado de constantes
/// («REPOSO», «SUEÑO», «GUARDIÁN»), así que se resuelven UNA vez y se reusan; el fade con
/// la profundidad de la órbita lo pone la opacidad del contexto, no un color nuevo (que
/// obligaría a re-resolver cada frame). La caché se tira si cambia el entorno que el
/// resuelto congela (esquema de color).
private final class EcosistemaEtiquetas {
    private var resueltas: [String: GraphicsContext.ResolvedText] = [:]

    func resuelta(_ texto: String, en ctx: GraphicsContext) -> GraphicsContext.ResolvedText {
        if let hit = resueltas[texto] { return hit }
        // Espaciado de las versalitas orbitales: «R E P O S O».
        let v = ctx.resolve(Text(texto.map(String.init).joined(separator: " "))
            .font(LiquidType.orbita)
            // FER-45: tinta700 (no tinta500) — el fade orbital multiplica por la opacidad del
            // contexto, así que un base más claro dejaba los rótulos ilegibles sobre el papel.
            .foregroundColor(LiquidColor.tinta700))
        resueltas[texto] = v
        return v
    }

    func vaciar() { resueltas.removeAll() }
}

// MARK: - El escenario (el reloj, el ancla del eclipse y QUÉ backend pinta)

/// Un solo reloj para todo el héroe. Decide entre el shader de Metal (Fase B, FER-13) y el
/// Canvas de Fase A: en iOS con Metal disponible pinta las partículas la GPU y este Canvas
/// queda SOLO para los rótulos; en macOS/watchOS, en previews y mientras el shader se
/// compila, el Canvas pinta el plan completo. Los dos recorren el MISMO plan.
private struct EcosistemaEscenario: View {
    typealias Sim = EcosistemaSimulacion

    let coreo: Sim.Coreografia
    let fase: Sim.Fase
    /// Ancla de la graduacion en vivo (FER-20) — nil = sin graduacion.
    let graduacionDesde: TimeInterval?
    let senales: [LiquidHoyModel.Senal]
    let guardianJuntas: Bool
    let vigiaFuera: [Bool]
    let guardianHueco: Bool
    let rotulos: EcosistemaRotulos
    let still: Bool
    let paused: Bool

    /// Ancla del eclipse (el guardián viaja al asomarse; con `still` aparece colocado).
    @State private var eclipseDesde: TimeInterval?
    #if os(iOS) && canImport(MetalKit)
    @ObservedObject private var metal = EcosistemaMetal.compartido
    #endif

    var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloPleno, paused: paused)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            capas(t: t, escena: escena(t: t))
        }
        .accessibilityHidden(true)
        .onAppear {
            if case .atencion(eclipse: true) = coreo, eclipseDesde == nil {
                eclipseDesde = Date().timeIntervalSinceReferenceDate
            }
            #if os(iOS) && canImport(MetalKit)
            metal.preparar()
            #endif
        }
        .onChange(of: guardianJuntas) { _, juntas in
            eclipseDesde = juntas ? Date().timeIntervalSinceReferenceDate : nil
        }
    }

    @ViewBuilder private func capas(t: TimeInterval, escena: Sim.Escena) -> some View {
        #if os(iOS) && canImport(MetalKit)
        if let recursos = metal.recursos {
            ZStack {
                EcosistemaMetalLienzo(recursos: recursos, escena: escena, t: t,
                                      paleta: .desde(clima: coreo.tintaClima))
                EcosistemaCanvas(coreo: coreo, escena: escena, t: t, rotulos: rotulos,
                                 soloEtiquetas: true)
            }
        } else {
            EcosistemaCanvas(coreo: coreo, escena: escena, t: t, rotulos: rotulos)
        }
        #else
        EcosistemaCanvas(coreo: coreo, escena: escena, t: t, rotulos: rotulos)
        #endif
    }

    /// Lo que el plan necesita saber del modelo, en el instante `t`.
    private func escena(t: TimeInterval) -> Sim.Escena {
        Sim.Escena(
            coreo: coreo, fase: fase, still: still,
            niveles: (0..<2).map { senales.indices.contains($0) ? senales[$0].progress : nil },
            fuera: (0..<2).map { senales.indices.contains($0) && senales[$0].state == .atencion },
            guardianJuntas: guardianJuntas, guardianHueco: guardianHueco,
            eclipse: eclipseProgreso(t: t),
            vigiaFuera: vigiaFuera,
            graduacion: graduacionDesde.map {
                min(1, max(0, (t - $0) / LiquidEcosistemaMotion.graduacionDur))
            })
    }

    private func eclipseProgreso(t: TimeInterval) -> Double {
        guard case .atencion(eclipse: true) = coreo else { return 0 }
        if still { return 1 }
        guard let desde = eclipseDesde else { return 1 }
        return min(1, max(0, (t - desde) / LiquidEcosistemaMotion.eclipseDur))
    }
}

/// La tinta del clima: verde / roja / neutra según el veredicto (todo de tokens).
extension EcosistemaSimulacion.Coreografia {
    var tintaClima: Color {
        switch self {
        case .enRango: return LiquidColor.particulaVerde
        // FER-22 (decisión B del dueño): en atención el ORBE absorbe el ámbar — la
        // propagación es literal, no solo ambiental.
        case .atencion: return LiquidColor.particulaAmbar
        case .desgaste: return LiquidColor.particulaRoja
        case .neutra, .calibrando: return LiquidColor.particulaNeutra
        }
    }
}

// MARK: - El canvas de partículas (decorativo: la a11y vive en el elemento compuesto)

private struct EcosistemaCanvas: View {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria

    /// Solo para la tinta del clima; la coreografía completa llega en `escena`.
    let coreo: Sim.Coreografia
    let escena: Sim.Escena
    let t: TimeInterval
    let rotulos: EcosistemaRotulos
    /// Modo capa-de-texto: el shader de Metal ya pintó las partículas y este Canvas queda
    /// SOLO para los rótulos orbitales (FER-13). En el camino de Fase A vale `false` y el
    /// Canvas pinta el plan completo.
    var soloEtiquetas: Bool = false

    /// Esferas fibonacci precomputadas (una vez por proceso).
    private static let dEsfera = Sim.fibonacci(G.nEsfera)
    private static let dLuna = Sim.fibonacci(G.nLuna)
    private static let dGuardian = Sim.fibonacci(G.nGuardian)

    /// Rótulos orbitales resueltos una sola vez (FER-14 #1).
    @State private var etiquetas = EcosistemaEtiquetas()

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, _ in
            dibujar(ctx: &ctx, t: t)
        }
        .accessibilityHidden(true)
        // Un `ResolvedText` congela el entorno con el que se resolvió: si el esquema
        // cambia, los rótulos cacheados dejan de ser válidos.
        .onChange(of: colorScheme) { _, _ in etiquetas.vaciar() }
    }

    // MARK: Colores por clase (todo de tokens — cero hex aquí)

    private var tintaClima: Color { coreo.tintaClima }

    private func color(_ clase: Sim.ClaseParticula, tinta: Sim.Tinta) -> Color {
        switch clase {
        case .base, .menisco, .vapor: return color(tinta)
        case .capAmbar: return LiquidColor.atencion
        case .liquidoBajo: return LiquidColor.negativo
        }
    }

    /// Un ROL del plan → su token. El plan vive fuera de SwiftUI y no conoce `Color`.
    private func color(_ tinta: Sim.Tinta) -> Color {
        switch tinta {
        case .clima: return tintaClima
        case .atencion: return LiquidColor.atencion
        case .negativo: return LiquidColor.negativo
        case .neutra: return LiquidColor.particulaNeutra
        // La voz de VIGILANDO: el azul de respiración/SpO₂ — las señales que el vigía
        // custodia (decisión del dueño /inject; el gris lo hacía mueble).
        case .vigia: return LiquidColor.azul
        case .blanco: return LiquidColor.particulaBlanca
        case .sueno: return Self.mezclada(LiquidColor.indigo, hacia: tintaClima)
        case .reposo: return Self.mezclada(LiquidColor.rosa, hacia: tintaClima)
        case .vigiaTemp: return Self.mezclada(LiquidColor.doradoTemp, hacia: tintaClima)
        case .vigiaResp: return Self.mezclada(LiquidColor.azul, hacia: tintaClima)
        }
    }

    /// Identidad besada por el clima (70/30): el morado sigue siendo morado, pero la
    /// atmósfera del veredicto lo entinta — mismo lerp que la paleta Metal.
    private static func mezclada(_ identidad: Color, hacia clima: Color, k: Double = 0.30) -> Color {
        let a = identidad.resolve(in: EnvironmentValues())
        let b = clima.resolve(in: EnvironmentValues())
        func l(_ x: Float, _ y: Float) -> Double { Double(x) + (Double(y) - Double(x)) * k }
        return Color(.sRGB, red: l(a.red, b.red), green: l(a.green, b.green),
                     blue: l(a.blue, b.blue), opacity: l(a.opacity, b.opacity))
    }

    private func rotulo(_ cual: Sim.RotuloOrbital) -> String {
        switch cual {
        case .reposo: return rotulos.reposo
        case .sueno: return rotulos.sueno
        case .guardian: return rotulos.guardian
        }
    }

    // MARK: Dibujo (recorre el PLAN — la coreografía vive en `EcosistemaSimulacion.plan`)

    private func dibujar(ctx: inout GraphicsContext, t: TimeInterval) {
        for trazo in Sim.plan(t: t, escena: escena) {
            switch trazo {
            case .rotulo(let cual, let punto, let alfa):
                etiqueta(ctx: &ctx, texto: rotulo(cual), en: punto, alfa: alfa)
            // Con `soloEtiquetas` el Canvas es la capa de TEXTO sobre el shader de Metal
            // (FER-13): las partículas ya las pintó la GPU, aquí solo van los rótulos.
            case .nube(let nube):
                if soloEtiquetas { break }
                dibujarNube(ctx: &ctx, nube: nube, t: t)
            case .nubeMorfo(let a, let b, let mezcla):
                if soloEtiquetas { break }
                dibujarNubeMorfo(ctx: &ctx, a: a, b: b, mezcla: mezcla, t: t)
            case .disco(let centro, let radio, let tinta, let alfa):
                if soloEtiquetas { break }
                ctx.fill(circulo(centro, radio), with: .color(color(tinta).opacity(recorte(alfa))))
            case .anillo(let centro, let radio, let grosor, let tinta, let alfa):
                if soloEtiquetas { break }
                ctx.stroke(circulo(centro, radio),
                           with: .color(color(tinta).opacity(recorte(alfa))), lineWidth: grosor)
            case .halo(let centro, let radio, let foco, let radioIni, let tinta, let alfa):
                if soloEtiquetas { break }
                let c = color(tinta)
                ctx.fill(circulo(centro, radio), with: .radialGradient(
                    Gradient(colors: [c.opacity(recorte(alfa)), c.opacity(0)]),
                    center: foco, startRadius: radioIni, endRadius: radio))
            }
        }
    }

    private func circulo(_ centro: CGPoint, _ radio: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centro.x - radio, y: centro.y - radio,
                               width: radio * 2, height: radio * 2))
    }

    private func recorte(_ alfa: Double) -> Double { min(1, max(0, alfa)) }

    // MARK: Primitivas de dibujo (bucketing: un Path por clase×alfa, ≤40 fills/frame)

    /// Las direcciones fuente de una nube. Las variantes RALAS no son otro arreglo: la
    /// partícula `i` toma la dirección `i·paso` de la misma esfera (así el shader de Fase
    /// B puede derivarlas por índice sin subir tablas a la GPU).
    private static func direcciones(_ n: Int) -> [SIMD3<Double>] {
        switch n {
        case G.nEsfera: return dEsfera
        case G.nLuna: return dLuna
        default: return dGuardian
        }
    }

    private func dibujarNube(ctx: inout GraphicsContext, nube: Sim.Nube, t: TimeInterval) {
        let dirs = Self.direcciones(nube.n)
        var buckets: [Int: Path] = [:]
        var clases: [Int: Sim.ClaseParticula] = [:]
        for i in 0..<nube.cuenta {
            let p = Sim.particula(dir: dirs[i * nube.paso], indice: i, centro: nube.centro,
                                  radio: nube.radio, rotacion: nube.rotacion,
                                  jitterAmp: nube.jitterAmp, t: t, alfaK: nube.alfaK,
                                  stretch: nube.stretch, nivel: nube.nivel,
                                  nivelMezcla: nube.nivelMezcla,
                                  nivelBajo: nube.nivelBajo, capAmbar: nube.capAmbar)
            let alfaIdx = min(11, max(0, Int(p.alfa * 12)))
            let clave = claseIndice(p.clase) * 16 + alfaIdx
            buckets[clave, default: Path()].addEllipse(in: CGRect(
                x: p.pos.x - p.tamano, y: p.pos.y - p.tamano,
                width: p.tamano * 2, height: p.tamano * 2))
            clases[clave] = p.clase
        }
        for (clave, path) in buckets {
            let alfa = (Double(clave % 16) + 0.5) / 12
            ctx.fill(path, with: .color(color(clases[clave] ?? .base, tinta: nube.tinta)
                                            .opacity(min(1, alfa))))
        }
    }

    /// El espejo Canvas de `vsNubeMorfo` (FER-19 · C.2): mismas direcciones, misma ley
    /// (`particulaMorfo`), mismo bucketing que `dibujarNube` — migración por índice.
    private func dibujarNubeMorfo(ctx: inout GraphicsContext, a: Sim.Nube, b: Sim.Nube,
                                  mezcla: Double, t: TimeInterval) {
        let dirs = Self.direcciones(a.n)
        var buckets: [Int: Path] = [:]
        var clases: [Int: Sim.ClaseParticula] = [:]
        for i in 0..<a.cuenta {
            let p = Sim.particulaMorfo(dir: dirs[i * a.paso], indice: i,
                                       a: a, b: b, mezcla: mezcla, t: t)
            let alfaIdx = min(11, max(0, Int(p.alfa * 12)))
            let clave = claseIndice(p.clase) * 16 + alfaIdx
            buckets[clave, default: Path()].addEllipse(in: CGRect(
                x: p.pos.x - p.tamano, y: p.pos.y - p.tamano,
                width: p.tamano * 2, height: p.tamano * 2))
            clases[clave] = p.clase
        }
        for (clave, path) in buckets {
            let alfa = (Double(clave % 16) + 0.5) / 12
            ctx.fill(path, with: .color(color(clases[clave] ?? .base, tinta: a.tinta)
                                            .opacity(min(1, alfa))))
        }
    }

    private func claseIndice(_ c: Sim.ClaseParticula) -> Int {
        switch c {
        case .base: return 0
        case .menisco: return 1
        case .vapor: return 2
        case .capAmbar: return 3
        case .liquidoBajo: return 4
        }
    }

    private func etiqueta(ctx: inout GraphicsContext, texto: String, en punto: CGPoint,
                          alfa: Double) {
        let resuelto = etiquetas.resuelta(texto, en: ctx)
        let previa = ctx.opacity
        ctx.opacity = previa * alfa
        ctx.draw(resuelto, at: punto, anchor: .center)
        ctx.opacity = previa
    }
}

// MARK: - Variante lista (AX1+ — sin canvas, todos los datos navegables)

private struct EcosistemaListado: View {
    let senales: [LiquidHoyModel.Senal]
    let hero: LiquidHoyModel.Hero
    let guardian: LiquidHoyModel.Guardian?
    let calibracion: LiquidHoyModel.Calibracion?
    let rotulos: EcosistemaRotulos
    let heroPuerta: String?
    let onTapVeredicto: (() -> Void)?
    let onTapSenal: ((String) -> Void)?
    let onTapGuardian: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            encabezado
            ForEach(Array(senales.prefix(2).enumerated()), id: \.element.id) { i, senal in
                filaSenal(senal, etiqueta: i == 0 ? rotulos.reposo : rotulos.sueno)
            }
            if let guardian {
                let fueraGuardian: Bool = {
                    switch guardian.estado {
                    case .tempFuera, .respFuera, .juntas: return true
                    // `.incompleto` no es «fuera»: es «todavía no sé». Se lista explícito
                    // para que el compilador vuelva a avisar si el enum crece otra vez.
                    case .tranquilo, .sinLectura, .conociendote, .incompleto: return false
                    }
                }()
                let filaGuardian = fila(rotulos.guardian,
                                        valor: "\(guardian.temp) · \(guardian.resp)",
                                        fuera: fueraGuardian)
                if let onTapGuardian {
                    Button(action: onTapGuardian) { filaGuardian }
                        .buttonStyle(.liquidPress)
                } else {
                    filaGuardian
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var encabezado: some View {
        switch hero {
        case .veredicto(let title, let highlight, let tone, let subtitle, _):
            Group {
                if let range = title.range(of: highlight, options: .backwards) {
                    Text(title[..<range.lowerBound]).foregroundColor(LiquidColor.tinta900)
                    + Text(title[range]).foregroundColor(tone)
                    + Text(title[range.upperBound...]).foregroundColor(LiquidColor.tinta900)
                } else {
                    Text(title).foregroundColor(LiquidColor.tinta900)
                }
            }
            .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
            Text(subtitle).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
            puerta
        case .demotado(let kicker, let title, let subtitle):
            if let kicker {
                Text(kicker).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            }
            Text(title)
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(subtitle).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
            puerta
        }
    }

    @ViewBuilder private var puerta: some View {
        if let heroPuerta, let onTapVeredicto {
            Button(action: onTapVeredicto) {
                HStack(spacing: LiquidSpace.s150) {
                    Text(heroPuerta)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                    LiquidIcon(.chevron, size: 9, color: LiquidColor.tinta500)
                }
            }
            .buttonStyle(.liquidPress)
        }
    }

    @ViewBuilder private func filaSenal(_ senal: LiquidHoyModel.Senal,
                                        etiqueta: String) -> some View {
        let contenido = fila(etiqueta,
                             valor: senal.badge.map { "\($0.valor) · \($0.contexto)" }
                                ?? senal.valor ?? senal.caption,
                             fuera: senal.state == .atencion)
        if let onTapSenal {
            Button { onTapSenal(senal.id) } label: { contenido }
                .buttonStyle(.liquidPress)
        } else {
            contenido
        }
    }

    private func fila(_ etiqueta: String, valor: String, fuera: Bool) -> some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(etiqueta)
                .font(LiquidType.label).tracking(LiquidType.labelTracking)
                .foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 0)
            Text(valor)
                .font(LiquidType.datoMenor)
                .foregroundStyle(fuera ? LiquidColor.atencionTexto : LiquidColor.tinta900)
        }
        .padding(.vertical, LiquidSpace.s225)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla) // token-exempt: pastilla del heroe de Hoy, sobre el orbe
    }
}

#if DEBUG
#Preview("Ecosistema · En rango (vivo)") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        LiquidEcosistema(
            senales: LiquidHoyModel.ejemplo.senales,
            hero: LiquidHoyModel.ejemplo.hero,
            guardian: LiquidHoyModel.ejemplo.guardian,
            ambiente: .bien, calibracion: nil,
            rotulos: .base, heroPuerta: "Cómo llegué a esto",
            fusionInicial: true)
            .padding(.horizontal, LiquidSpace.s550)
    }
}

#Preview("Ecosistema · separado (sin motion)") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        LiquidEcosistema(
            senales: LiquidHoyModel.ejemplo.senales,
            hero: LiquidHoyModel.ejemplo.hero,
            guardian: LiquidHoyModel.ejemplo.guardian,
            ambiente: .bien, calibracion: nil,
            rotulos: .base, heroPuerta: "Cómo llegué a esto",
            faseForzada: .separada)
            .padding(.horizontal, LiquidSpace.s550)
    }
    .environment(\.liquidMotionDisabled, true)
}

#endif
