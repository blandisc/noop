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

    public init(reposo: String, sueno: String, guardian: String, temperatura: String,
                respiracion: String, hintSeparar: String, hintUnir: String,
                accionSeparar: String, accionUnir: String,
                abrirReposo: String = "Abrir En reposo",
                abrirSueno: String = "Abrir Sueño",
                abrirGuardian: String = "Abrir Guardián",
                sinLecturaNoche: String = "Sin lectura anoche",
                sinLecturaHoy: String = "Sin lectura hoy",
                guardianSinLecturas: String = "Guardián: sin lecturas hoy",
                anuncioVeredicto: String = "Tu veredicto llegó: %@") {
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
    @State private var escala: CGFloat = 1
    /// ¿El héroe está a la vista? (FER-14 #3) — fuera del viewport el reloj de 60 Hz se
    /// apaga. Arranca en `true`: si el héroe no vive dentro de un ScrollView el modifier
    /// nunca dispara y el default honesto es «visible».
    @State private var visible = true
    private let faseForzada: Sim.Fase?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(senales: [LiquidHoyModel.Senal], hero: LiquidHoyModel.Hero,
                guardian: LiquidHoyModel.Guardian?, ambiente: LiquidAmbiente,
                calibracion: LiquidHoyModel.Calibracion?, rotulos: EcosistemaRotulos,
                heroPuerta: String? = nil, heroHint: String? = nil,
                mostrarHintSeparar: Bool = true, fusionInicial: Bool = false,
                onTapVeredicto: (() -> Void)? = nil, onTapSenal: ((String) -> Void)? = nil,
                onTapGuardian: (() -> Void)? = nil,
                onFusionArrancada: (() -> Void)? = nil, onSeparacion: (() -> Void)? = nil) {
        self.init(senales: senales, hero: hero, guardian: guardian, ambiente: ambiente,
                  calibracion: calibracion, rotulos: rotulos, heroPuerta: heroPuerta,
                  heroHint: heroHint, mostrarHintSeparar: mostrarHintSeparar,
                  fusionInicial: fusionInicial, faseForzada: nil,
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
         faseForzada: Sim.Fase?,
         onTapVeredicto: (() -> Void)? = nil, onTapSenal: ((String) -> Void)? = nil,
         onTapGuardian: (() -> Void)? = nil,
         onFusionArrancada: (() -> Void)? = nil, onSeparacion: (() -> Void)? = nil) {
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
        }
        .frame(height: LiquidSpace.ecosistemaAlto * escala)
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
            fase = still ? .viva(desde: t) : .formando(inicio: t)
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
                                senales: senales, guardianJuntas: guardian?.estado == .juntas,
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
            Text(esSeparadaEstable ? rotulos.hintUnir
                 : (mostrarHintSeparar ? rotulos.hintSeparar : ""))
                .font(LiquidType.microEstado).tracking(LiquidType.labelTracking)
                .foregroundStyle(LiquidColor.tinta500.opacity(0.6))
                .frame(width: G.lienzo.width)
                .offset(y: esSeparadaEstable ? 226 : 8)
                .animation(LiquidMotion.glassOut(LiquidMotion.quick), value: esSeparadaEstable)
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
        .opacity(esSeparadaEstable ? 1 : 0)
        .allowsHitTesting(esSeparadaEstable)
        .animation(still ? .easeInOut(duration: LiquidEcosistemaMotion.reduceMotionCrossfade)
                         : LiquidMotion.glassOut(LiquidMotion.gentle),
                   value: esSeparadaEstable)
        // La palabra del veredicto (abajo, centrada) — se oculta en separado.
        palabra
            .frame(width: G.lienzo.width)
            .frame(height: G.lienzo.height - 34, alignment: .bottom)
            .opacity(esSeparadaEstable ? 0 : 1)
            // La palabra es puro texto (la puerta vive aparte): NUNCA intercepta el tap
            // del lienzo — tocar el veredicto también separa (Grok #1).
            .allowsHitTesting(false)
            .animation(still ? .easeInOut(duration: LiquidEcosistemaMotion.reduceMotionCrossfade)
                             : LiquidMotion.glassOut(LiquidEcosistemaMotion.palabraDur),
                       value: esSeparadaEstable)
        // La PUERTA al acta («Cómo llegué a esto») vive en AMBOS modos (D10): el tap del
        // lienzo ya no navega, así que esta pastilla es la única entrada visible.
        if let heroPuerta {
            botonPuerta(heroPuerta)
                .frame(width: G.lienzo.width)
                .frame(height: G.lienzo.height, alignment: .bottom)
        }
    }

    @ViewBuilder private var valoresSeparados: some View {
        let G = Sim.Geometria.self
        ForEach(Array(senales.prefix(2).enumerated()), id: \.element.id) { i, senal in
            let centro = i == 0 ? G.p1 : G.p2
            let etiqueta = i == 0 ? rotulos.reposo : rotulos.sueno
            VStack(spacing: 2) {
                Text(etiqueta)
                    .font(LiquidType.micro).tracking(LiquidType.microTracking)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            .position(x: centro.x, y: 74)
            botonSenal(senal) {
                VStack(spacing: 1) {
                    Text(senal.badge?.valor ?? senal.valor ?? "—")
                        .font(LiquidType.valorL)
                        .foregroundStyle(senal.state == .atencion
                                         ? LiquidColor.negativo : LiquidColor.tinta900)
                    // Sin dato: la honestidad tiene voz («Sin lectura anoche/hoy»), no
                    // solo un guion (D8).
                    Text(senal.badge?.contexto
                         ?? (i == 1 ? rotulos.sinLecturaNoche : rotulos.sinLecturaHoy))
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta700)
                        .opacity(senal.badge != nil || senal.progress == nil ? 1 : 0)
                }
                .padding(LiquidSpace.s300)
                .background(respaldo)
                .frame(minWidth: 60, minHeight: 60)
            }
            .position(x: centro.x, y: centro.y)
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
        let contenido = HStack(spacing: 18) {
            miniGuardian(valor: guardian?.temp ?? "—", rotulo: rotulos.temperatura,
                         fuera: tempFuera)
                .frame(width: 100)   // «TEMPERATURA» a 8pt +2.2 tracking mide ~97 (R2)
            miniGuardian(valor: guardian?.resp ?? "—", rotulo: rotulos.respiracion,
                         fuera: respFuera)
                .frame(width: 100)
        }
        .frame(minHeight: 44)
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

    private func miniGuardian(valor: String, rotulo: String, fuera: Bool) -> some View {
        VStack(spacing: 1) {
            Text(valor)
                .font(LiquidType.datoMenor)
                .foregroundStyle(fuera ? LiquidColor.atencionTexto : LiquidColor.tinta900)
            Text(rotulo)
                .font(LiquidType.orbita).tracking(LiquidType.orbitaTracking)
                .foregroundStyle(fuera ? LiquidColor.atencionTexto : LiquidColor.tinta500)
        }
        .padding(.horizontal, LiquidSpace.s200)
        .padding(.vertical, LiquidSpace.s150)
        .background(respaldo)
    }

    /// El respaldo esmerilado que garantiza la legibilidad del dato sobre partículas.
    /// El respaldo esmerilado que garantiza la legibilidad del dato sobre partículas —
    /// más sólido tras la revisión en simulador (el dato flotaba sobre el moteado).
    private var respaldo: some View {
        RadialGradient(stops: [
            .init(color: Color.white.opacity(0.97), location: 0),
            .init(color: Color.white.opacity(0.9), location: 0.55),
            .init(color: Color.white.opacity(0.5), location: 0.8),
            .init(color: .clear, location: 1),
        ], center: .center, startRadius: 4, endRadius: 52)
    }

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
        .padding(.bottom, 2)
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
        HStack(spacing: 5) {
            ForEach(0..<max(1, total), id: \.self) { i in
                Circle()
                    .fill(i < noche ? LiquidColor.particulaNeutra : LiquidColor.tinta10)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)   // el caption ya dice «Noche n de m».
    }

    @ViewBuilder private func botonPuerta(_ puerta: String) -> some View {
        let etiqueta = HStack(spacing: LiquidSpace.s150) {
            Text(puerta)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
            LiquidIcon(.chevron, size: 9, color: LiquidColor.tinta500)
        }
        .padding(.horizontal, LiquidSpace.s300)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(LiquidColor.vidrioPastilla)
            Capsule().strokeBorder(LiquidColor.vidrioBordePastilla, lineWidth: 0.5)
        }
        if let onTapVeredicto {
            Button(action: onTapVeredicto) {
                etiqueta
                    .frame(minHeight: 44)      // target real ≥44 pt (D10)
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
            .foregroundColor(LiquidColor.tinta500))
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
    let senales: [LiquidHoyModel.Senal]
    let guardianJuntas: Bool
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
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
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
            eclipse: eclipseProgreso(t: t))
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
        case .enRango, .atencion: return LiquidColor.particulaVerde
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
        case .blanco: return .white
        }
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
                let filaGuardian = fila(rotulos.guardian,
                                        valor: "\(guardian.temp) · \(guardian.resp)",
                                        fuera: guardian.estado != .tranquilo)
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
        .padding(.vertical, 9)
        .padding(.horizontal, LiquidSpace.s400)
        .liquidGlass(.pastilla)
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
