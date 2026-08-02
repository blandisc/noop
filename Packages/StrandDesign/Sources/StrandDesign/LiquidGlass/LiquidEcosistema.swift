import SwiftUI

// MARK: - «El Ecosistema» (FER-10) — el héroe de Hoy
//
// Esferas de PARTÍCULAS (cada punto representa una medición) que se funden en el orbe del
// veredicto: las dos decisoras (EN REPOSO · SUEÑO) quedan orbitándolo como lunas con su
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

    // MARK: Body

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // AX1+: el héroe abandona la física — variante lista con TODOS los datos.
            EcosistemaListado(senales: senales, hero: hero, guardian: guardian,
                              calibracion: calibracion, rotulos: rotulos,
                              heroPuerta: heroPuerta,
                              onTapVeredicto: onTapVeredicto, onTapSenal: onTapSenal)
        } else {
            lienzo
        }
    }

    private var lienzo: some View {
        GeometryReader { geo in
            let escala = min(1, geo.size.width / Sim.Geometria.lienzo.width)
            ZStack(alignment: .topLeading) {
                escena
                    .frame(width: Sim.Geometria.lienzo.width,
                           height: Sim.Geometria.lienzo.height)
                    .scaleEffect(escala, anchor: .top)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: LiquidSpace.ecosistemaAlto)
        .onAppear {
            guard fase == nil else { return }
            let ahora = Date().timeIntervalSinceReferenceDate
            if fusionInicial && coreo.conFusion {
                // El ritual del día corre (con Reduce Motion aparece asentado, pero el
                // día SÍ se consume: recibió su veredicto).
                fase = still ? .viva(desde: ahora) : .formando(inicio: ahora)
                onFusionArrancada?()
            } else {
                // SIN veredicto aún («Leyendo…», calibrando): el día NO se marca — el
                // ritual espera a que el veredicto se estrene (D1 del gate de QA).
                fase = .viva(desde: ahora)
            }
        }
        // El veredicto se estrena con la pantalla abierta (sync matutino): AHÍ corre el
        // ritual pendiente + el announcement de VoiceOver.
        .onChange(of: coreo.conFusion) { antes, ahora in
            guard ahora, !antes, fusionInicial else { return }
            let t = Date().timeIntervalSinceReferenceDate
            fase = still ? .viva(desde: t) : .formando(inicio: t)
            onFusionArrancada?()
            anunciarVeredicto()
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
            EcosistemaCanvas(coreo: coreo, fase: fase ?? .viva(desde: 0),
                             senales: senales, guardianJuntas: guardian?.estado == .juntas,
                             guardianHueco: guardian == nil
                                 || (guardian?.temp == "—" && guardian?.resp == "—"),
                             rotulos: rotulos, still: still, paused: still || ambientPaused)
                .contentShape(Rectangle())
                .onTapGesture { alternar() }
            overlays
        }
    }

    private func alternar() {
        guard coreo.separable, let actual = fase else { return }
        let ahora = Date().timeIntervalSinceReferenceDate
        switch actual {
        case .formando(let inicio):
            // Tap durante la fusión = saltar al estado FUNDIDO final (HIG: nunca atrapar
            // al usuario en una animación). No cuenta como separación.
            if Sim.cuadro(t: ahora, fase: .formando(inicio: inicio)).fundida {
                fase = still ? .separada : .separando(desde: ahora)
                onSeparacion?()
            } else {
                fase = .viva(desde: ahora)
            }
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
        // Hint (arriba, centrado).
        if coreo.separable {
            Text(esSeparadaEstable ? rotulos.hintUnir
                 : (mostrarHintSeparar ? rotulos.hintSeparar : ""))
                .font(LiquidType.microEstado).tracking(LiquidType.labelTracking)
                .foregroundStyle(LiquidColor.tinta500.opacity(0.6))
                .frame(width: G.lienzo.width)
                .offset(y: 8)
                .animation(LiquidMotion.glassOut(LiquidMotion.quick), value: esSeparadaEstable)
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
            .allowsHitTesting(!esSeparadaEstable)
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
                        .foregroundStyle(LiquidColor.tinta500)
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
        let contenido = HStack(spacing: 26) {
            miniGuardian(valor: guardian?.temp ?? "—", rotulo: rotulos.temperatura,
                         fuera: tempFuera)
                .frame(width: 92)
            miniGuardian(valor: guardian?.resp ?? "—", rotulo: rotulos.respiracion,
                         fuera: respFuera)
                .frame(width: 92)
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
    private var respaldo: some View {
        RadialGradient(colors: [LiquidColor.vidrioEspecular,
                                LiquidColor.vidrioStreak.opacity(0.6), .clear],
                       center: .center, startRadius: 4, endRadius: 44)
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
                Text(title)
                    .font(esCalibrando ? LiquidType.displayS : LiquidType.displayL)
                    .tracking(esCalibrando ? LiquidType.displaySTracking
                                           : LiquidType.displayLTracking)
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

    func body(content: Content) -> some View {
        content
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
            .accessibilityAction(named: Text(verbatim: separada ? rotulos.accionUnir
                                                                : rotulos.accionSeparar)) {
                if separable { onToggle() }
            }
    }
}

// MARK: - El canvas de partículas (decorativo: la a11y vive en el elemento compuesto)

private struct EcosistemaCanvas: View {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria
    typealias M = LiquidEcosistemaMotion

    let coreo: Sim.Coreografia
    let fase: Sim.Fase
    let senales: [LiquidHoyModel.Senal]
    let guardianJuntas: Bool
    let guardianHueco: Bool
    let rotulos: EcosistemaRotulos
    let still: Bool
    let paused: Bool

    /// Esferas fibonacci precomputadas (una vez por proceso).
    private static let dEsfera = Sim.fibonacci(G.nEsfera)
    private static let dLuna = Sim.fibonacci(G.nLuna)
    private static let dGuardian = Sim.fibonacci(G.nGuardian)
    /// Variantes RALAS para lo «hueco» (sin dato: no se fabrica materia densa).
    private static let dLunaHueca = Sim.fibonacci(G.nLuna).enumerated()
        .filter { $0.offset % 3 == 0 }.map(\.element)
    private static let dGuardianHueco = Sim.fibonacci(G.nGuardian).enumerated()
        .filter { $0.offset % 2 == 0 }.map(\.element)

    /// Ancla del eclipse (el guardián viaja al asomarse; con `still` aparece colocado).
    @State private var eclipseDesde: TimeInterval?

    /// La materia de una luna: su órbita, identidad y estado honesto.
    struct LunaSpec {
        let orb: Sim.Orbital
        let nombre: String
        let rotK: Double
        let hueca: Bool
        let fuera: Bool
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, _ in
                dibujar(ctx: &ctx, t: t)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            if case .atencion(eclipse: true) = coreo, eclipseDesde == nil {
                eclipseDesde = Date().timeIntervalSinceReferenceDate
            }
        }
        .onChange(of: guardianJuntas) { _, juntas in
            eclipseDesde = juntas ? Date().timeIntervalSinceReferenceDate : nil
        }
    }

    // MARK: Colores por clase (todo de tokens — cero hex aquí)

    private var tintaClima: Color {
        switch coreo {
        case .enRango, .atencion: return LiquidColor.particulaVerde
        case .desgaste: return LiquidColor.particulaRoja
        case .neutra, .calibrando: return LiquidColor.particulaNeutra
        }
    }

    private func color(_ clase: Sim.ClaseParticula) -> Color {
        switch clase {
        case .base, .menisco, .vapor: return tintaClima
        case .capAmbar: return LiquidColor.atencion
        case .liquidoBajo: return LiquidColor.negativo
        }
    }

    // MARK: Dibujo

    private func dibujar(ctx: inout GraphicsContext, t: TimeInterval) {
        if case .calibrando(let noche, let total) = coreo {
            dibujarAcrecion(ctx: &ctx, t: t, noche: noche, total: total)
            return
        }
        let cuadro = Sim.cuadro(t: t, fase: still ? faseEstable : fase)
        let eclipse = eclipseProgreso(t: t)
        let flicker = coreo == .desgaste && !still
            ? 0.9 + 0.1 * sin(t * M.flickerDesgaste) : 1.0

        // 1 · El guardián atrás (órbita con z<0, o el eclipse asomándose). En separado el
        // orbital NO se dibuja: el guardián «se partió» en sus dos mini-orbes (D4).
        let orbGuardian = Sim.guardian(t: t, eclipse: eclipse)
        let sepTemprano = Sim.cuadro(t: t, fase: still ? faseEstable : fase).separada
        if !sepTemprano, orbGuardian.z < 0 || eclipse > 0.5 {
            dibujarGuardian(ctx: &ctx, t: t, orb: orbGuardian, eclipse: eclipse)
        }

        // 2 · Lunas detrás del orbe: una por señal — HUECA si su eje no tiene dato (no
        // se fabrica materia), con CASQUETE ámbar si su eje está fuera (la luna causante).
        var lunas: [LunaSpec] = []
        if cuadro.fundida {
            for (i, senal) in senales.prefix(2).enumerated() {
                let orb = Sim.luna(i + 1, t: t, desgaste: coreo == .desgaste)
                lunas.append(LunaSpec(
                    orb: orb,
                    nombre: i == 0 ? rotulos.reposo : rotulos.sueno,
                    rotK: i == 0 ? M.rotacionLuna1 : M.rotacionLuna2,
                    hueca: senal.progress == nil,
                    fuera: senal.state == .atencion))
            }
            for luna in lunas where luna.orb.z < 0 {
                dibujarLuna(ctx: &ctx, t: t, luna: luna)
            }
        }

        // 3 · Las esferas decisoras (separadas / viajando / fundidas).
        let capAmbar = eclipse > 0.5 && cuadro.fundida
        let radio = (Sim.lerp(Double(G.radioSeparada), Double(coreo.radioOrbe), min(1, cuadro.u))
                     * (1 + 0.02 * sin(t * M.respiracionEsfera) * cuadro.u)
                     + cuadro.settle) * (1 + min(0, cuadro.stretch))
        let c1 = puntoLerp(G.p1, G.centro, cuadro.u)
        let c2 = puntoLerp(G.p2, G.centro, cuadro.u)
        let jitter = still ? 0 : coreo.jitter
        let sep = cuadro.separada
        dibujarEsfera(ctx: &ctx, dirs: Self.dEsfera, centro: c1, radio: CGFloat(radio),
                      rot: t * M.rotacionEsfera, jitter: jitter, t: t, alfaK: flicker,
                      stretch: max(0, cuadro.stretch),
                      nivel: sep ? nivelSenal(0) : nil,
                      nivelBajo: sep && senalFuera(0) && coreo == .desgaste,
                      capAmbar: capAmbar)
        dibujarEsfera(ctx: &ctx, dirs: Self.dEsfera, centro: c2, radio: CGFloat(radio),
                      rot: -t * 0.5, jitter: jitter, t: t, alfaK: flicker,
                      stretch: max(0, cuadro.stretch),
                      nivel: sep ? nivelSenal(1) : nil,
                      nivelBajo: sep && senalFuera(1) && coreo == .desgaste,
                      capAmbar: capAmbar)

        // 4 · Destello + chispas del contacto.
        if cuadro.bump > 0.25, !still {
            dibujarDestello(ctx: &ctx, t: t, bump: cuadro.bump, radio: CGFloat(radio))
        }

        // 5 · Especular del orbe fundido.
        if cuadro.fundida {
            let r = CGFloat(radio)
            let rect = CGRect(x: G.centro.x - r * 1.05, y: G.centro.y - r * 1.05,
                              width: r * 2.1, height: r * 2.1)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0)]),
                center: CGPoint(x: G.centro.x - r * 0.3, y: G.centro.y - r * 0.36),
                startRadius: 3, endRadius: r * 1.05))
        }

        // 6 · Lunas al frente + guardián al frente (órbita con z≥0, sin eclipse).
        for luna in lunas where luna.orb.z >= 0 {
            dibujarLuna(ctx: &ctx, t: t, luna: luna)
        }
        if orbGuardian.z >= 0, eclipse <= 0.5, cuadro.fundida, !cuadro.separada {
            dibujarGuardian(ctx: &ctx, t: t, orb: orbGuardian, eclipse: eclipse)
        }
        // 7 · Mini-esferas del guardián en el estado separado (fondo de los badges).
        if sep {
            let tono = guardianJuntas ? LiquidColor.atencion : LiquidColor.particulaNeutra
            dibujarNube(ctx: &ctx, dirs: Self.dGuardian, centro: G.guardianSeparado1,
                        radio: G.radioGuardianSeparado, rot: t * 0.9, t: t, alfaK: 0.9,
                        tono: tono)
            dibujarNube(ctx: &ctx, dirs: Self.dGuardian, centro: G.guardianSeparado2,
                        radio: G.radioGuardianSeparado, rot: -t * 0.8, t: t, alfaK: 0.9,
                        tono: tono)
        }
    }

    /// Con Reduce Motion la fase se lee en su estado FINAL (sin viajes).
    private var faseEstable: Sim.Fase {
        switch fase {
        case .formando, .uniendo, .viva: return .viva(desde: 0)
        case .separando, .separada: return .separada
        }
    }

    private func eclipseProgreso(t: TimeInterval) -> Double {
        guard case .atencion(eclipse: true) = coreo else { return 0 }
        if still { return 1 }
        guard let desde = eclipseDesde else { return 1 }
        return min(1, max(0, (t - desde) / M.eclipseDur))
    }

    private func nivelSenal(_ i: Int) -> Double? {
        senales.indices.contains(i) ? senales[i].progress : nil
    }

    private func senalFuera(_ i: Int) -> Bool {
        senales.indices.contains(i) && senales[i].state == .atencion
    }

    private func puntoLerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(u), y: a.y + (b.y - a.y) * CGFloat(u))
    }

    // MARK: Primitivas de dibujo (bucketing: un Path por clase×alfa, ≤40 fills/frame)

    private func dibujarEsfera(ctx: inout GraphicsContext, dirs: [SIMD3<Double>],
                               centro: CGPoint, radio: CGFloat, rot: Double,
                               jitter: Double, t: TimeInterval, alfaK: Double,
                               stretch: Double, nivel: Double?, nivelBajo: Bool,
                               capAmbar: Bool) {
        var buckets: [Int: Path] = [:]
        var clases: [Int: Sim.ClaseParticula] = [:]
        for (i, dir) in dirs.enumerated() {
            let p = Sim.particula(dir: dir, indice: i, centro: centro, radio: radio,
                                  rotacion: rot, jitterAmp: jitter, t: t, alfaK: alfaK,
                                  stretch: stretch, nivel: nivel, nivelBajo: nivelBajo,
                                  capAmbar: capAmbar)
            let alfaIdx = min(11, max(0, Int(p.alfa * 12)))
            let clave = claseIndice(p.clase) * 16 + alfaIdx
            buckets[clave, default: Path()].addEllipse(in: CGRect(
                x: p.pos.x - p.tamano, y: p.pos.y - p.tamano,
                width: p.tamano * 2, height: p.tamano * 2))
            clases[clave] = p.clase
        }
        for (clave, path) in buckets {
            let alfa = (Double(clave % 16) + 0.5) / 12
            ctx.fill(path, with: .color(color(clases[clave] ?? .base).opacity(min(1, alfa))))
        }
    }

    /// Nube simple (lunas, guardián): sin gauge ni cap — el camino rápido.
    private func dibujarNube(ctx: inout GraphicsContext, dirs: [SIMD3<Double>],
                             centro: CGPoint, radio: CGFloat, rot: Double,
                             t: TimeInterval, alfaK: Double, tono: Color) {
        var buckets: [Int: Path] = [:]
        for (i, dir) in dirs.enumerated() {
            let p = Sim.particula(dir: dir, indice: i, centro: centro, radio: radio,
                                  rotacion: rot, jitterAmp: 0.4, t: t, alfaK: alfaK)
            let alfaIdx = min(11, max(0, Int(p.alfa * 12)))
            buckets[alfaIdx, default: Path()].addEllipse(in: CGRect(
                x: p.pos.x - p.tamano, y: p.pos.y - p.tamano,
                width: p.tamano * 2, height: p.tamano * 2))
        }
        for (alfaIdx, path) in buckets {
            let alfa = (Double(alfaIdx) + 0.5) / 12
            ctx.fill(path, with: .color(tono.opacity(min(1, alfa))))
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

    private func dibujarLuna(ctx: inout GraphicsContext, t: TimeInterval, luna: LunaSpec) {
        let orb = luna.orb
        let dep = (orb.z + 1) / 2
        // Hueca = materia rala y tenue (el eje no tiene dato); fuera = casquete ámbar.
        dibujarEsfera(ctx: &ctx, dirs: luna.hueca ? Self.dLunaHueca : Self.dLuna,
                      centro: orb.centro, radio: orb.radio, rot: t * luna.rotK,
                      jitter: 0.4, t: t,
                      alfaK: (0.5 + 0.5 * dep) * (luna.hueca ? 0.45 : 1),
                      stretch: 0, nivel: nil, nivelBajo: false, capAmbar: luna.fuera)
        etiqueta(ctx: &ctx, texto: luna.nombre,
                 en: CGPoint(x: orb.centro.x, y: orb.centro.y + orb.radio + 13),
                 alfa: 0.35 + 0.5 * dep)
    }

    private func dibujarGuardian(ctx: inout GraphicsContext, t: TimeInterval,
                                 orb: Sim.Orbital, eclipse: Double) {
        let dep = (orb.z + 1) / 2
        let tono = eclipse > 0 ? LiquidColor.atencion : LiquidColor.particulaNeutra
        let alfaK = (eclipse > 0 ? 0.85 * max(0.4, eclipse)
                                 : (0.4 + 0.6 * dep) * 0.75)
                    * (guardianHueco ? 0.55 : 1)
        dibujarNube(ctx: &ctx, dirs: guardianHueco ? Self.dGuardianHueco : Self.dGuardian,
                    centro: orb.centro, radio: orb.radio,
                    rot: t * M.rotacionGuardian, t: t, alfaK: alfaK, tono: tono)
        if eclipse < 0.5 {
            etiqueta(ctx: &ctx, texto: rotulos.guardian,
                     en: CGPoint(x: orb.centro.x, y: orb.centro.y + orb.radio + 13),
                     alfa: dep * 0.8)
        }
    }

    private func dibujarDestello(ctx: inout GraphicsContext, t: TimeInterval,
                                 bump: Double, radio: CGFloat) {
        let r = radio + 6 + CGFloat(bump) * 10
        let anillo = CGRect(x: G.centro.x - r, y: G.centro.y - r, width: r * 2, height: r * 2)
        ctx.stroke(Path(ellipseIn: anillo),
                   with: .color(Color.white.opacity(bump * 0.8)), lineWidth: 1.5)
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi + t
            let sr = Double(radio) + 10 + bump * 22
            let p = CGPoint(x: G.centro.x + CGFloat(cos(a) * sr),
                            y: G.centro.y + CGFloat(sin(a) * sr * 0.9))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.3, y: p.y - 1.3,
                                            width: 2.6, height: 2.6)),
                     with: .color(Color.white.opacity(bump * 0.75)))
        }
    }

    private func dibujarAcrecion(ctx: inout GraphicsContext, t: TimeInterval,
                                 noche: Int, total: Int) {
        for i in 0..<G.nEspirales {
            let m = Sim.espiral(i, t: t)
            ctx.fill(Path(ellipseIn: CGRect(x: m.pos.x - m.tamano, y: m.pos.y - m.tamano,
                                            width: m.tamano * 2, height: m.tamano * 2)),
                     with: .color(tintaClima.opacity(m.alfa)))
        }
        // El embrión: solo sus franjas de abajo pobladas (noche/total), respirando apenas.
        let radio = G.radioEmbrion + CGFloat(still ? 0 : 1.6 * sin(t * 0.8))
        let nivel = total > 0 ? Double(noche) / Double(total) : 0
        dibujarEsfera(ctx: &ctx, dirs: Self.dEsfera, centro: G.centro, radio: radio,
                      rot: t * 0.35, jitter: still ? 0 : 0.5, t: t, alfaK: 0.9,
                      stretch: 0, nivel: nivel, nivelBajo: false, capAmbar: false)
    }

    private func etiqueta(ctx: inout GraphicsContext, texto: String, en punto: CGPoint,
                          alfa: Double) {
        let resuelto = ctx.resolve(
            Text(texto.map(String.init).joined(separator: " "))
                .font(LiquidType.orbita)
                .foregroundColor(LiquidColor.tinta500.opacity(alfa)))
        ctx.draw(resuelto, at: punto, anchor: .center)
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

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            encabezado
            ForEach(Array(senales.prefix(2).enumerated()), id: \.element.id) { i, senal in
                filaSenal(senal, etiqueta: i == 0 ? rotulos.reposo : rotulos.sueno)
            }
            if let guardian {
                fila(rotulos.guardian, valor: "\(guardian.temp) · \(guardian.resp)",
                     fuera: guardian.estado != .tranquilo)
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
