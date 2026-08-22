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
    public let sinLecturaNoche: String    // «Sin lectura de anoche» (badge sin dato)
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
                sinLecturaNoche: String = "Sin lectura de anoche",
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

/// El frame REAL del orbe del héroe en pantalla (coords globales), que la ANIMACIÓN DE ENTRADA
/// lee para aterrizar sin costura sobre él. `nil` = aún no medido (o no hay héroe en pantalla)
/// → la entrada cae a su cénit fijo. `reduce` conserva el último no-nil (el héroe puede salir
/// de vista al scrollear; el frame de reposo sigue siendo el bueno para la entrada).
public struct HeroOrbeFrameKey: PreferenceKey {
    public static let defaultValue: CGRect? = nil
    public static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

public struct LiquidEcosistema: View {
    public typealias Sim = EcosistemaSimulacion

    /// El frame global del orbe del héroe, derivado del contenedor YA dispuesto (no del arte
    /// escalado: un `GeometryReader` lee la geometría de LAYOUT, anterior al `scaleEffect`, así
    /// que el frame del arte escalado saldría sin escalar). El `scaleEffect(anchor: .top)` baja
    /// el centro a `centro.y·escala` desde el tope del contenedor; el ancho lo centra el
    /// `maxWidth`, así que `midX` es el centro. En reposo (la entrada corre antes de tocar) el
    /// `offset` de compacto vale 0, así que no hace falta descontarlo.
    /// FER-73 · M2: el radio publicado es el REAL de la coreografía —el orbe mide 50 en
    /// «Recover» (desgaste) y 30 mientras calibra (embrión)— no siempre 56. Con el radio fijo,
    /// la entrada aterrizaba con un tamaño que no era el del orbe que la recibe.
    static func orbeFrameGlobal(contenedor: CGRect, escala: CGFloat,
                                radio: CGFloat = Sim.Geometria.radioOrbe) -> CGRect {
        let r = radio * escala
        let cx = contenedor.midX
        let cy = contenedor.minY + Sim.Geometria.centro.y * escala
        return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    }

    private let senales: [LiquidHoyModel.Senal]
    private let hero: LiquidHoyModel.Hero
    private let guardian: LiquidHoyModel.Guardian?
    private let ambiente: LiquidAmbiente
    private let calibracion: LiquidHoyModel.Calibracion?
    private let rotulos: EcosistemaRotulos
    private let heroPuerta: String?
    /// La puerta es INFORMATIVA → ⓘ en el titular; false → pastilla de texto (acción).
    private let heroInfo: Bool
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// El subtítulo del héroe ESCALA con Dynamic Type (`cuerpoLecturaBase` + `@ScaledMetric`):
    /// era la única frase de Hoy clavada en 12.5 mientras filas y celdas crecían (FER-128 r10).
    @ScaledMetric(relativeTo: .footnote) private var subtituloPt: CGFloat = LiquidType.cuerpoLecturaBase

    public init(senales: [LiquidHoyModel.Senal], hero: LiquidHoyModel.Hero,
                guardian: LiquidHoyModel.Guardian?, ambiente: LiquidAmbiente,
                calibracion: LiquidHoyModel.Calibracion?, rotulos: EcosistemaRotulos,
                heroPuerta: String? = nil, heroInfo: Bool = false, heroHint: String? = nil,
                mostrarHintSeparar: Bool = true, fusionInicial: Bool = false,
                compacto: Bool = false,
                onTapVeredicto: (() -> Void)? = nil, onTapSenal: ((String) -> Void)? = nil,
                onTapGuardian: (() -> Void)? = nil,
                onFusionArrancada: (() -> Void)? = nil, onSeparacion: (() -> Void)? = nil) {
        self.init(senales: senales, hero: hero, guardian: guardian, ambiente: ambiente,
                  calibracion: calibracion, rotulos: rotulos, heroPuerta: heroPuerta,
                  heroInfo: heroInfo,
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
         heroPuerta: String? = nil, heroInfo: Bool = false, heroHint: String? = nil,
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
        self.heroInfo = heroInfo
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

    /// El alto que el héroe RESERVA en el scroll (FER-79 · D4). Compacto manda sobre separado:
    /// «El Tablero» ya viene apretado por su propia presentación.
    /// ALTURA FIJA (revisión del dueño 2026-08-17, viéndolo en el teléfono). Separar el orbe ya
    /// NO mueve nada: el veredicto y todo lo que va debajo se quedan clavados donde estaban.
    ///
    /// Esto retira la decisión D4 de FER-79 («cierra el hueco»), que animaba el alto reservado
    /// 320 → 244 al separar para que el modo separado no dejara aire muerto abajo. El precio de
    /// aquello era que la página entera subía y bajaba con cada toque, y en el teléfono ese
    /// movimiento pesa más que el hueco que evitaba: el usuario toca para MIRAR una señal, no
    /// para reacomodar la pantalla. El aire de abajo vuelve, y es el trato aceptado.
    private var altoReservado: CGFloat {
        compacto ? LiquidSpace.ecosistemaAltoCompacto : LiquidSpace.ecosistemaAlto
    }

    /// Dónde vive el hint «toca para unir» dentro del lienzo. Una sola fuente: el `offset` que
    /// lo dibuja y el alto que lo tiene que dejar entrar (antes eran dos números sueltos que se
    /// desincronizaron en cuanto uno de los dos se movió).
    static let hintUnirY: CGFloat = 226

    /// El radio que de verdad dibuja el plan para esta coreografía (FER-73 · M2).
    private var radioOrbeReal: CGFloat {
        if calibracion != nil { return Sim.Geometria.radioEmbrion }
        return coreo.radioOrbe
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
    /// Cuánto BAJA el lienzo al separar, para que la escena use el aire de abajo en vez de
    /// quedarse apretada arriba. Escala con el lienzo, como todo lo demás.
    private var descensoSeparado: CGFloat {
        esSeparadaEstable ? LiquidSpace.ecosistemaDescensoSeparado * escala : 0
    }

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
                // Publica el frame real del orbe (para la entrada sin costura). Sobre el
                // contenedor YA dispuesto: su .global es geometría de layout, correcta.
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeroOrbeFrameKey.self,
                        value: Self.orbeFrameGlobal(contenedor: geo.frame(in: .global), escala: escala,
                                                    radio: radioOrbeReal))
                })
                // Compacto (FER-28): sube el lienzo recortando su aire superior — el arte no
                // cambia, solo se presenta más apretado. El estado separado sigue librando.
                // FER-46: el offset se ANIMA con la separación — antes saltaba de golpe
                // (recorteCompacto → 0) mientras palabra/valores sí se fundían, y el orbe
                // daba un brinco seco al separar y al reunir. Al UNIR, además, ESPERA a
                // que las esferas viajen de vuelta (mismo retardo que la palabra): subir
                // el lienzo antes de tiempo les cortaba la cabeza a los vigías contra el
                // clipped() del contenedor.
                .offset(y: descensoSeparado - recorteCompacto)
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
        // FER-79 · D4 (dueño): el alto reservado se ANIMA con la separación. Al separar, el
        // bloque del veredicto se funde y la sección de abajo sube con él; al reunir, baja de
        // vuelta con el mismo gesto (la misma curva y el mismo retardo que el lienzo, para que
        // se lea como un solo movimiento y no como dos).
        // Sin animación: el alto ya no depende de la fase (ver `altoReservado`), así que no hay
        // nada que animar — y cualquier animación aquí volvería a mover la página al separar,
        // que es justo lo que el dueño pidió quitar.
        .frame(height: altoReservado * escala, alignment: .top)
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
        // SALIR de la app reúne el héroe; que una HOJA lo tape, no. `ambientPaused` mezcla dos
        // cosas —«no gastes batería dibujando» y «el usuario se fue»— y desde que las hojas
        // también lo activan, abrir cualquier métrica re-fundía el héroe detrás de la hoja y
        // movía 88 pt de layout con la hoja abierta: el usuario la cerraba y encontraba otra
        // pantalla (revisión adversarial). La fase la manda el ciclo de vida, no la batería.
        .onChange(of: scenePhase) { _, fase in
            // SOLO `.background`. `!= .active` era tan ancho como el `ambientPaused` que vino a
            // reemplazar: iOS pone `.inactive` al jalar el Centro de Control, al girar el
            // teléfono, al tomar una captura o cuando entra el banner de una llamada — y en
            // todos ellos el orbe se reunía solo mientras el usuario lo estaba leyendo
            // (tercera vuelta adversarial). Irse de la app sí lo reúne; asomarse a otra cosa no.
            if fase == .background { normalizarFase() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Text(verbatim: a11yCompuesta))
        .accessibilityHint(Text(verbatim: heroHint ?? ""))
        // FER-73 · INT-08: el hint promete «abre el detalle» — sin esto, el doble toque de
        // VoiceOver no hacía nada (solo existían acciones de rotor).
        .accessibilityAction { onTapVeredicto?() }
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
                    .offset(y: Self.hintUnirY)
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
        // Florecido sutil (FER-56, dueño): el dato no APARECE, se asienta — crece un
        // pelín (0.94→1) y sube 6 pt mientras funde, ya con el orbe quieto.
        // FER-73 · M10: bajo Reduce Motion la escala tampoco se anima (el offset ya lo hacía;
        // el crossfade animaba la escala igual y era movimiento no pedido).
        .scaleEffect(still || esSeparadaEstable ? 1 : 0.94)
        .offset(y: still ? 0 : (esSeparadaEstable ? 0 : 6))
        .allowsHitTesting(esSeparadaEstable)
        .animation(still ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                         : (esSeparadaEstable
                            // Espera el aterrizaje + que el rebote se calme, y florece
                            // suave y largo (antes: fade rápido a media separación).
                            ? LiquidEcosistemaMotion.revelarDatoAnim
                            // Al reunir, se va de inmediato (las motas se disuelven).
                            : LiquidMotion.glassOut(LiquidMotion.quick)),
                   value: esSeparadaEstable)
        // La palabra del veredicto (abajo, centrada) — se oculta en separado. En compacto
        // (FER-28) sube `acercaVeredicto` hacia el orbe (recorta el aire de abajo).
        palabra
            .frame(width: G.lienzo.width)
            // El subtítulo sube 34→64 pt sobre el fondo del lienzo (auditoría del dueño: la
            // puerta se veía «pegada» al subtítulo — hueco arriba chico, abajo grande). Con más
            // aire arriba, el botón respira y el ritmo vertical queda parejo; hay espacio de
            // sobra entre el orbe y el veredicto para subirlo.
            // Dueño 2026-08-15: el bloque del veredicto BAJA 20 pt (64→44, 26→6) para darle
            // más aire al orbe y sus satélites arriba; el lienzo reservado crece lo mismo
            // (ecosistemaAlto 300→320) y la zona de fade de los rótulos baja a la par.
            // Dueño 2026-08-15 (gate UX+UI): SIN pastilla bajo el subtítulo, el bloque baja
            // otros 24 pt (−44 → −20): el orbe gana ese aire; bajo el subtítulo quedan ~18 pt
            // como corte de sección. Con puerta-ACCIÓN (Connect Health) la pastilla es la
            // última fila del propio bloque (viaja con él).
            .frame(height: G.lienzo.height - (heroInfo ? 20 : 44)
                   - (compacto ? LiquidSpace.ecosistemaAcercaVeredicto : 0), alignment: .bottom)
            .opacity(esSeparadaEstable ? 0 : 1)
            // Deriva sutil (overlapping action, ojo del dueño): la palabra no aparece —
            // ATERRIZA. Al separar se hunde 10 pt (la misma dirección en la que el orbe
            // va a bajar); al unir viaja esos 10 pt de vuelta a su asiento mientras
            // funde. Reduce Motion: cero viaje, solo crossfade.
            .offset(y: still ? 0 : (esSeparadaEstable ? 10 : 0))
            // El hit-testing vive en los TEXT de adentro (allowsHitTesting(false) por
            // pieza): tocar el veredicto sigue separando (Grok #1); solo el ⓘ intercepta.
            .allowsHitTesting(!esSeparadaEstable)
            // Al SEPARAR se desvanece de inmediato (se hace a un lado, ambient suave);
            // al UNIR llega ~0.45 s DESPUÉS de que la subida arrancó — primero se mueve
            // el objeto, después habla el texto. Todo al unísono se sentía mecánico.
            .animation(still ? LiquidEcosistemaMotion.reduceCrossfadeAnim
                             : (esSeparadaEstable
                                ? LiquidMotion.ambient(LiquidEcosistemaMotion.palabraDur)
                                : LiquidMotion.ambient(0.75)
                                    .delay(LiquidEcosistemaMotion.fusionDur * 0.85 + 0.45)),
                       value: esSeparadaEstable)
        // La PUERTA como PASTILLA solo cuando es una ACCIÓN («Connect Health», ruta .salud):
        // un ⓘ ahí mentiría (HIG: el info button revela información, no ejecuta). Con puerta
        // informativa el ⓘ vive DENTRO del titular (ver `palabraVeredicto`) y la pastilla
        // desaparece — también en modo separado (D10 actualizado: el separado es una consulta
        // momentánea; la acción de rotor «How I got here» sigue viva en ambos modos).
        if let heroPuerta, !heroInfo {
            botonPuerta(heroPuerta)
                .frame(width: G.lienzo.width)
                .frame(height: G.lienzo.height - 6
                       - (compacto ? LiquidSpace.ecosistemaAcercaVeredicto : 0), alignment: .bottom)
        }
    }

    @ViewBuilder private var valoresSeparados: some View {
        let G = Sim.Geometria.self
        ForEach(Array(senales.prefix(2).enumerated()), id: \.element.id) { i, senal in
            let centro = i == 0 ? G.p1 : G.p2
            let etiqueta = i == 0 ? rotulos.reposo : rotulos.sueno
            // El rótulo toma el HUE de su orbe al separarse (revisión del dueño): REPOSO
            // rosa, SUEÑO indigo — el mismo color de su métrica en la Matriz de abajo. En
            // atención (votó fuera) cede al rojo semántico, como su número.
            let hueEtiqueta = i == 0 ? LiquidColor.rosa : LiquidColor.indigo
            VStack(spacing: LiquidSpace.s050) {
                Text(etiqueta)
                    .font(LiquidType.micro).tracking(LiquidType.microTracking)
                    .foregroundStyle(senal.state == .atencion
                                     ? LiquidColor.negativo : hueEtiqueta)
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
        // El rótulo toma el HUE de su vigía al separarse (revisión del dueño): TEMPERATURA
        // dorado, RESPIRACIÓN azul — su identidad en la Matriz. Fuera de rango cede al rojo.
        let hueRotulo = lado < 0 ? LiquidColor.doradoTemp : LiquidColor.azul
        Text(rotulo)
            .font(LiquidType.orbita).tracking(LiquidType.orbitaTracking)
            .fontWeight(.medium)
            .foregroundStyle(fuera ? LiquidColor.atencionTexto : hueRotulo)
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
                // FER-73 (dueño): el ⓘ se veía un pelín ALTO. `levante` lo subía 3 pt sobre la
                // base del texto; SF Symbols ya vienen alineados a la base tipográfica, así que
                // el cero es la alineación nativa — el glifo cae a la altura de la palabra.
                titularConInfo(palabraVeredicto(title: title, highlight: highlight, tone: tone),
                               tono: tone, fuente: LiquidType.infoGlifoTitular,
                               levante: 0)
                Text(subtitle)
                    .font(.system(size: subtituloPt)).lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
                if let confianza {
                    Text(confianza)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .allowsHitTesting(false)
                }
            case .demotado(let kicker, let title, let subtitle):
                if let kicker {
                    Text(kicker).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                        .allowsHitTesting(false)
                }
                // Los estados sin veredicto hablan bajito (displayS): un titular
                // demotado de 2 líneas en displayL se encimaba al orbe (revisión en
                // simulador con «Aún no conozco tu base»). Con puerta informativa llevan
                // su ⓘ en tinta neutra («sin veredicto, cero color»), talla callout.
                titularConInfo(
                    Text(title)
                        .font(LiquidType.displayS)
                        .tracking(LiquidType.displaySTracking)
                        .foregroundStyle(esCalibrando ? LiquidColor.tinta700 : LiquidColor.tinta900)
                        .multilineTextAlignment(.center),
                    tono: LiquidColor.tinta500, fuente: LiquidType.infoGlifoTitularS,
                    levante: 0)
                Text(subtitle)
                    .font(LiquidType.cuerpo).lineSpacing(LiquidType.cuerpoLineSpacing)
                    .foregroundStyle(LiquidColor.tinta700)
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
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

    /// El titular con su ⓘ (dueño 2026-08-15, gate UX+UI): el glifo va en la MISMA línea, a la
    /// última base (cubre titulares de 2 líneas), levantado un pelín, en el `tono` dado, y es
    /// el único blanco táctil del bloque (≥44 pt vía contentShape, SIN inflar la línea). Sin
    /// puerta informativa (acción «Connect Health», o sin puerta) el titular va solo.
    @ViewBuilder
    private func titularConInfo<T: View>(_ titular: T, tono: Color, fuente: Font,
                                         levante: CGFloat) -> some View {
        if heroInfo, let onTapVeredicto {
            HStack(alignment: .lastTextBaseline, spacing: LiquidSpace.s200) {
                titular.allowsHitTesting(false)
                Button(action: onTapVeredicto) {
                    Image(systemName: "info.circle")
                        .font(fuente)
                        .foregroundStyle(tono)
                        .alignmentGuide(.lastTextBaseline) { d in d[.lastTextBaseline] + levante }
                        // El «?» de la Matriz usa la misma receta (hit hacia afuera, la fila
                        // mide lo que mide el texto). FER-73 · INT-02: el blanco se COMPENSA
                        // por la escala del lienzo — toda la escena se dibuja con
                        // `scaleEffect(escala)` en iPhones ≤ 402 pt de ancho, así que un hit
                        // de 44 pt en el espacio del arte llegaba escalado (≈39 pt reales).
                        .contentShape(Rectangle().inset(by: -LiquidSpace.s300 / max(escala, 0.5)))
                }
                .buttonStyle(.liquidPress)
                .accessibilityLabel(Text(verbatim: heroPuerta ?? ""))
            }
        } else {
            titular.allowsHitTesting(false)
        }
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

    /// El tono del veredicto, cuando lo hay (nil en estados sin veredicto → puerta neutra).
    private var veredictoTono: Color? {
        if case .veredicto(_, _, let tone, _, _) = hero { return tone }
        return nil
    }

    @ViewBuilder private func botonPuerta(_ puerta: String) -> some View {
        // Opción A (revisión del dueño 2026-08): la puerta al acta TOMA EL TONO DEL VEREDICTO
        // — pastilla teñida (fill 12 % + borde 38 %) con el texto en su voz de lectura. Se ve,
        // se amarra al «por qué» de HOY, y con contención NO le gana a la palabra. Sin veredicto
        // queda neutra (regla «sin veredicto, cero color»). Antes era vidrio en tinta700, casi
        // invisible (FER-51).
        let tono = veredictoTono
        let textoTono = tono.map { LiquidSheetHeader.tonoTexto($0) } ?? LiquidColor.tinta700
        let etiqueta = HStack(spacing: LiquidSpace.s150) {
            Text(puerta)
                .font(LiquidType.captionLectura)
                .fontWeight(.medium)
                .foregroundStyle(textoTono)
            LiquidIcon(.chevron, size: 9, color: textoTono)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, LiquidSpace.s125)
        .background {
            if let tono {
                Capsule().fill(tono.opacity(0.12))
                Capsule().strokeBorder(tono.opacity(0.38), lineWidth: 1)
            } else {
                Capsule().fill(LiquidColor.vidrioPastilla)
                Capsule().strokeBorder(LiquidColor.vidrioBordePastilla, lineWidth: 0.5)
            }
        }
        if let onTapVeredicto {
            Button(action: onTapVeredicto) {
                etiqueta
                    // target real ≥44 pt (D10), COMPENSADO por la escala del lienzo (FER-73 ·
                    // INT-02): la escena entera se dibuja con `scaleEffect`, así que 44 pt de
                    // arte llegaban como ~39 pt de dedo en todo iPhone ≤ 402 pt de ancho.
                    .frame(minHeight: LiquidControl.hitTarget / max(escala, 0.5))
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
    private var tamanos: [String: CGSize] = [:]

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

    /// El tamaño dibujado de un rótulo, cacheado como su texto resuelto: se pide 60 veces por
    /// segundo para saber quién se encima con quién.
    func tamano(_ texto: String, en ctx: GraphicsContext) -> CGSize {
        if let hit = tamanos[texto] { return hit }
        let v = resuelta(texto, en: ctx)
            .measure(in: CGSize(width: 4000, height: 4000))
        tamanos[texto] = v
        return v
    }

    func vaciar() { resueltas.removeAll(); tamanos.removeAll() }
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

// MARK: - Los rótulos orbitales se ceden el paso (FER-117)

/// Geometría PURA de la cesión entre rótulos del héroe, fuera de la vista para poder probarla
/// sin Canvas ni simulador.
enum EcosistemaCesion {
    /// El aire que cada rótulo reclama a los lados: empiezan a cederse el paso ANTES de
    /// tocarse, porque dos versalitas a un pelo de distancia ya se leen como una sola palabra.
    static let aireRotulo: CGFloat = 5

    /// Cuánto cede cada rótulo, de 1 (nada) a 0 (invisible). **Pura**: la geometría se prueba
    /// sin Canvas ni simulador.
    ///
    /// Cede SIEMPRE el de menor alfa, que en esta escena es el que va más atrás en la órbita.
    /// La cesión es proporcional al solape horizontal —desvanecerse de golpe se leería como un
    /// parpadeo— y llega a cero cuando el traslape alcanza el 40 % del rótulo más angosto.
    static func cesionesRotulos(_ cajas: [(rect: CGRect, alfa: Double)]) -> [Double] {
        var k = [Double](repeating: 1, count: cajas.count)
        guard cajas.count > 1 else { return k }
        for i in cajas.indices {
            for j in cajas.indices where j != i {
                // Empate de alfa (mismo plano): cede el de la izquierda, para que la regla sea
                // determinista y no parpadeen los dos a la vez.
                let cedeYo = cajas[i].alfa < cajas[j].alfa
                    || (cajas[i].alfa == cajas[j].alfa && cajas[i].rect.minX < cajas[j].rect.minX)
                guard cedeYo else { continue }
                let solape = cajas[i].rect.intersection(cajas[j].rect)
                guard !solape.isNull, solape.width > 0, solape.height > 0 else { continue }
                let masAngosto = min(cajas[i].rect.width, cajas[j].rect.width)
                guard masAngosto > 0 else { continue }
                let fraccion = solape.width / masAngosto
                k[i] = min(k[i], max(0, 1 - fraccion / 0.4))
            }
        }
        return k
    }
}

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
        // El dorado de temperatura brincaba (dueño): más besado por el clima (k .55) para
        // que baje de intensidad y no lea como «lo más importante». La respiración (azul)
        // se queda como está.
        case .vigiaTemp: return Self.mezclada(LiquidColor.doradoTemp, hacia: tintaClima, k: 0.55)
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
        case .temperatura: return rotulos.temperatura
        case .respiracion: return rotulos.respiracion
        }
    }

    // MARK: Dibujo (recorre el PLAN — la coreografía vive en `EcosistemaSimulacion.plan`)

    private func dibujar(ctx: inout GraphicsContext, t: TimeInterval) {
        let plan = Sim.plan(t: t, escena: escena)
        // LOS RÓTULOS SE CEDEN EL PASO (FER-117). En español, «TEMPERATURA» y «FC EN REPOSO»
        // —versalitas espaciadas letra a letra, casi el doble de anchas que sus gemelas en
        // inglés— se montaban una sobre otra en parte de la órbita y quedaban ilegibles.
        //
        // De las tres salidas posibles se eligió la que no cobra el precio en otro lado:
        // acortar la palabra castiga al español y volvería a romperse con la siguiente palabra
        // larga; mover las órbitas rompe la coreografía que el dueño ya aprobó. Que el rótulo de
        // ATRÁS se desvanezca no cuesta ninguna de las dos: su alfa ya codifica la profundidad,
        // así que el de adelante gana solo, y como mide el texto REAL que va a dibujarse, sirve
        // en cualquier idioma y a cualquier tamaño de letra.
        let cede = cesiones(plan, ctx: ctx)
        var iRotulo = 0
        for trazo in plan {
            switch trazo {
            case .rotulo(let cual, let punto, let alfa):
                let k = iRotulo < cede.count ? cede[iRotulo] : 1
                iRotulo += 1
                guard alfa * k > 0.02 else { break }
                etiqueta(ctx: &ctx, texto: rotulo(cual), en: punto, alfa: alfa * k)
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

    /// Mide los rótulos del plan y pregunta cuánto cede cada uno.
    private func cesiones(_ plan: [Sim.Trazo], ctx: GraphicsContext) -> [Double] {
        var cajas: [(rect: CGRect, alfa: Double)] = []
        for trazo in plan {
            guard case .rotulo(let cual, let punto, let alfa) = trazo else { continue }
            let tam = etiquetas.tamano(rotulo(cual), en: ctx)
            cajas.append((CGRect(x: punto.x - tam.width / 2 - EcosistemaCesion.aireRotulo,
                                 y: punto.y - tam.height / 2,
                                 width: tam.width + EcosistemaCesion.aireRotulo * 2,
                                 height: tam.height), alfa))
        }
        return EcosistemaCesion.cesionesRotulos(cajas)
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
    /// Misma regla que el orbe: el subtítulo escala (FER-128 r10).
    @ScaledMetric(relativeTo: .footnote) private var subtituloPt: CGFloat = LiquidType.cuerpoLecturaBase
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
            Text(subtitle).font(.system(size: subtituloPt)).foregroundStyle(LiquidColor.tinta700)
            puerta
        case .demotado(let kicker, let title, let subtitle):
            if let kicker {
                Text(kicker).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            }
            Text(title)
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(subtitle).font(.system(size: subtituloPt)).foregroundStyle(LiquidColor.tinta700)
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
        // «62 lpm · fuera de tu rango», no «62 · lpm · fuera de tu rango»: la unidad va pegada
        // al número (como la a11y de la misma señal y como el módulo de abajo) — el punto medio
        // separa IDEAS, no número de unidad (dueño, captura a xxxLarge, FER-128).
        let contenido = fila(etiqueta,
                             valor: senal.badge.map { "\($0.valor) \($0.contexto)" }
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
