import SwiftUI

// MARK: - FER-51 · Cara Matriz (Lane B)
//
// Modelo tonto (`Sendable`, sin lógica) + vista que lo dibuja. La proyección de datos
// vive en `LiquidHoyBuilder.matriz` (capa app). Reusa MatrizChart / OrbeVivo /
// MedidorLunar / LiquidColor. Tinta sobre el suelo vivo de Hoy, sin tarjetas, filos 1 px.

// MARK: Model

/// Payload de gráfica ya derivado — el builder rellena; la vista solo pinta.
public enum MatrizChartPayload: Sendable, Equatable {
    case columnas(noches: [MatrizColumnas.Noche], referencia: Double,
                  referenciaTag: String, dominio: ClosedRange<Double>)
    case lineaRellena(puntos: [Double?], base: Double?, dominio: ClosedRange<Double>,
                      alfa: Double, alertaHoy: MedidorLunar.Alerta)
    /// FC (FER-55, diseño final): LA REGLA AL MARGEN — curva con relleno que muere a
    /// nada + regla a la derecha (capilar de dominio, tramo de tu rango ±1σ, lectura
    /// gemela de HOY). `banda` nil → la regla muestra solo el capilar.
    case regla(puntos: [Double?], banda: ClosedRange<Double>?,
               dominio: ClosedRange<Double>, alertaHoy: MedidorLunar.Alerta)
    case lineaSerena(puntos: [Double?], banda: ClosedRange<Double>?,
                     dominio: ClosedRange<Double>, alertaHoy: MedidorLunar.Alerta)
    case colina(p: Double?, zona: ClosedRange<Double>, estela: [Double],
                  alertaHoy: MedidorLunar.Alerta = .ninguna)
    /// `promedio`: si viene, se dibuja como línea punteada de referencia (Pasos: el promedio
    /// de la ventana — FER-125, el prototipo aprobado). Esfuerzo no lo pasa.
    case barrasMini(valores: [Double?], promedio: Double? = nil)
    case escalerita(niveles: [Int?])
    /// FER-80 · La costura del par del guardián: temp y resp espejadas, ya normalizadas.
    case costura(noches: [MatrizCostura.Noche])
}

/// Una sección de la Matriz (sello + título + valor + chart).
public struct MatrizSeccion: Sendable, Identifiable, Equatable {
    public let id: String
    public let hue: Color
    /// Guardián bicolor (dorado + azul). nil = orbe monocolor.
    public let huesPar: (Color, Color)?
    public let titulo: String
    public let valor: String
    /// Unidad del valor («ms», «bpm», «rpm») — se pinta chica, mismo hue (Grok-UI #7).
    public let unidad: String?
    /// Protagonista del veredicto (sueño / FC): numeral grande (`valorTileL`); el resto, medio
    /// (`valorTileM`) — dos tamaños, como el prototipo (FER-118).
    public let destacada: Bool
    public let sublabel: String?
    public let chartID: String
    public let chart: MatrizChartPayload
    /// Chip del guardián (solo esa sección); nil en el resto.
    public let chip: MatrizHoyModel.ChipGuardian?
    /// Renglones nombrados del guardián (Temp / Resp); nil en el resto.
    public let renglones: [MatrizRenglon]?
    /// Silueta del orbe-sello (FER-55): `.luna` para Sueño, `.esfera` para el resto.
    public let formaSello: OrbeVivo.Forma
    /// Glifo de gota (comparativa FER-55): si está presente, el sello es el
    /// `LiquidIconDrop` de las hojas de resumen en vez del orbe de partículas.
    public let glifoSello: LiquidIcon.Glyph?
    /// El sello dibujado de la métrica (la luna, el termómetro, el medidor…). Presente
    /// ⇒ manda sobre el orbe de partículas; el Guardián no lo lleva (su sello VIVE).
    public let sello: SelloMetrica?
    /// Scrub (FER-55): cada noche con su lectura ya formateada (valor + sublabel).
    /// El índice mapea 1:1 a las barras; el último = hoy. `nil` = celda sin scrub.
    public let scrubNoches: [ScrubNoche]?
    /// El valor DICHO para VoiceOver cuando el escrito es ambiguo (el par del guardián). nil =
    /// se lee `valor` tal cual.
    public let a11yValor: String?
    /// El sello del guardián VIVO (FER-56 · Ola 3): reacciona al estado del par (calma /
    /// vigila una / ambas ámbar / racha roja / sin datos) separando y tiñendo sus dos
    /// colores. Presente SOLO en la sección del guardián; nil ⇒ el sello normal (orbe/glifo).
    public let selloGuardian: SelloGuardianVivo.Estado?

    public init(id: String, hue: Color,
                huesPar: (Color, Color)? = nil, titulo: String, valor: String,
                unidad: String? = nil, destacada: Bool = false,
                sublabel: String? = nil, chartID: String, chart: MatrizChartPayload,
                chip: MatrizHoyModel.ChipGuardian? = nil,
                renglones: [MatrizRenglon]? = nil,
                formaSello: OrbeVivo.Forma = .esfera,
                glifoSello: LiquidIcon.Glyph? = nil,
                sello: SelloMetrica? = nil,
                scrubNoches: [ScrubNoche]? = nil,
                a11yValor: String? = nil,
                selloGuardian: SelloGuardianVivo.Estado? = nil) {
        self.id = id; self.hue = hue; self.huesPar = huesPar
        self.titulo = titulo; self.valor = valor
        self.unidad = unidad; self.destacada = destacada
        self.sublabel = sublabel
        self.chartID = chartID; self.chart = chart; self.chip = chip
        self.renglones = renglones
        self.formaSello = formaSello
        self.glifoSello = glifoSello
        self.sello = sello
        self.scrubNoches = scrubNoches
        self.a11yValor = a11yValor
        self.selloGuardian = selloGuardian
    }

    /// Una noche leída para el scrub: el valor grande y la frase del sublabel, ya
    /// formateados por el builder (la vista no sabe de fechas ni unidades).
    public struct ScrubNoche: Sendable, Equatable {
        public let valor: String
        public let sublabel: String
        public init(valor: String, sublabel: String) {
            self.valor = valor; self.sublabel = sublabel
        }
    }

    public static func == (lhs: MatrizSeccion, rhs: MatrizSeccion) -> Bool {
        lhs.id == rhs.id && lhs.titulo == rhs.titulo && lhs.valor == rhs.valor
            && lhs.sublabel == rhs.sublabel && lhs.chartID == rhs.chartID
            && lhs.chart == rhs.chart && lhs.chip == rhs.chip
            && lhs.renglones == rhs.renglones
            && lhs.hue == rhs.hue
            && lhs.huesPar?.0 == rhs.huesPar?.0 && lhs.huesPar?.1 == rhs.huesPar?.1
            && lhs.unidad == rhs.unidad && lhs.destacada == rhs.destacada
            && lhs.formaSello == rhs.formaSello && lhs.scrubNoches == rhs.scrubNoches
            && lhs.glifoSello == rhs.glifoSello
            && lhs.sello == rhs.sello
            && lhs.selloGuardian == rhs.selloGuardian
    }
}

/// Renglón nombrado del guardián (Temp piel / Resp) con su línea serena.
public struct MatrizRenglon: Sendable, Identifiable, Equatable {
    public let id: String
    public let titulo: String
    public let valor: String
    public let unidad: String?
    /// Estado en palabras bajo el renglón («dentro de tu banda», «típica tuya») — P2.
    public let sublabel: String?
    public let hue: Color
    public let chartID: String
    public let chart: MatrizChartPayload
    public let subrayado: MedidorLunar.Alerta
    /// El sello de la sub-señal (termómetro / onda). Antes estos renglones eran las dos
    /// únicas filas de Hoy sin nada a la izquierda: colgaban del margen mientras el resto
    /// de la pantalla arrancaba detrás de un sello.
    public let sello: SelloMetrica?
    /// Lecturas por-noche para el scrub del renglón (Skin temp/Breathing, dueño 2026-08-15).
    public let scrubNoches: [MatrizSeccion.ScrubNoche]?

    public init(id: String, titulo: String, valor: String, unidad: String? = nil,
                sublabel: String? = nil,
                hue: Color, chartID: String, chart: MatrizChartPayload,
                subrayado: MedidorLunar.Alerta = .ninguna,
                sello: SelloMetrica? = nil,
                scrubNoches: [MatrizSeccion.ScrubNoche]? = nil) {
        self.id = id; self.titulo = titulo; self.valor = valor; self.unidad = unidad
        self.sublabel = sublabel
        self.hue = hue
        self.chartID = chartID; self.chart = chart; self.subrayado = subrayado
        self.sello = sello
        self.scrubNoches = scrubNoches
    }

    public static func == (lhs: MatrizRenglon, rhs: MatrizRenglon) -> Bool {
        lhs.id == rhs.id && lhs.titulo == rhs.titulo && lhs.valor == rhs.valor
            && lhs.chartID == rhs.chartID && lhs.chart == rhs.chart
            && lhs.subrayado == rhs.subrayado && lhs.hue == rhs.hue
            && lhs.unidad == rhs.unidad && lhs.sublabel == rhs.sublabel
            && lhs.sello == rhs.sello
            && lhs.scrubNoches == rhs.scrubNoches
    }
}

/// Modelo tonto de la cara Matriz. Sin lógica: el builder proyecta todo.
public struct MatrizHoyModel: Sendable, Equatable {

    /// Chip del guardián — texto + tono ya resueltos por el builder (§8 / criterio 10).
    public struct ChipGuardian: Sendable, Equatable {
        public enum Tono: Sendable, Equatable {
            case calma       // verde
            case terciario   // vigilando una sola señal — sin cálidos
            case atencion    // ámbar — par 1.ª noche
            case alarma      // rojo — racha ≥ 2
        }
        public let texto: String
        public let tono: Tono
        public init(texto: String, tono: Tono) {
            self.texto = texto; self.tono = tono
        }
    }

    /// Banda visual §7: ancha completa o dividida (2 elementos a11y).
    /// Las divididas son MITADES EXACTAS — el filo parte la banda al centro
    /// (decisión de diseño; el ancho variable se retiró, hallazgo Grok #3).
    public enum Banda: Sendable, Equatable {
        case full(MatrizSeccion)
        case split(izq: MatrizSeccion, der: MatrizSeccion)
        /// Rótulo de NIVEL (Opción A del dueño): «Deciden tu día · Vigila · Contexto ·
        /// Bitácora» — el orden enseña el modelo sin manual. Con `manualID` la fila
        /// entera es tocable (FER-54): un «?» hueco discreto anuncia la hoja-manual
        /// que explica ese nivel; `nil` = decorativo como siempre.
        case nivel(String, manualID: String?)
    }

    /// Orden VISUAL de arriba a abajo (§7). Bandas divididas = 2 elementos a11y.
    public let bandas: [Banda]

    public init(bandas: [Banda]) {
        self.bandas = bandas
    }

    /// Orden de lectura VoiceOver = orden visual; bandas divididas expanden a 2 ids.
    public var ordenA11y: [String] {
        var ids: [String] = []
        for b in bandas {
            switch b {
            case .full(let s): ids.append(s.id)
            case .split(let izq, let der):
                ids.append(izq.id); ids.append(der.id)
            case .nivel:
                break   // decorativo: VoiceOver lee las secciones, no las capas.
            }
        }
        return ids
    }
}

// MARK: - Face view

/// La cara de «Hoy en atmósfera» (FER-118): tres estantes con su «?» y, dentro, módulos de
/// vidrio (`.superficieAtmosfera`) en cuadrícula de dos columnas sobre el polvo. El modelo NO
/// cambió: `.nivel` = cabecera de estante, `.split` = dos módulos gemelos, `.full` = un módulo
/// ancho (Pasos, horizontal; el guardián, vertical). Sin filos, sin chevron, sin sello «vota».
/// Breakpoint: Dynamic Type ≥ accessibility1 → columna única (y Pasos vuelve a vertical).
public struct MatrizHoyFace: View {
    private let model: MatrizHoyModel
    private let onTapSeccion: (String) -> Void
    /// El hint de barrido: una luz cruza la gráfica del guardián una vez, hasta que el host lo
    /// apague (3 apariciones o el primer scrub). La cara no lee `AppStorage`: recibe el bool y
    /// avisa cuando lo mostró y cuando el usuario ya barrió.
    private let mostrarHintScrub: Bool
    private let onHintMostrado: () -> Void
    private let onScrubCompletado: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    /// Acuse del sello: el orbe de la sección tocada late una vez (cariño §micro).
    @State private var latido: String?
    /// Scrub activo (FER-55): qué sección y qué noche está leyendo el dedo. `nil` =
    /// sin scrub → la celda muestra HOY (regresa sola al soltar).
    @State private var scrub: (id: String, idx: Int)?
    /// Pulso háptico: cambia al cruzar de barra durante el scrub (tick por noche).
    @State private var scrubTick: Int = 0
    /// El módulo cuyo encabezado está presionado: el vidrio ENTERO cede (`pressScale`), aunque el
    /// botón sea solo el encabezado — la gráfica lleva el gesto de scrub, separada (patrón #118).
    @State private var presionado: String?

    public init(model: MatrizHoyModel, onTapSeccion: @escaping (String) -> Void,
                mostrarHintScrub: Bool = false,
                onHintMostrado: @escaping () -> Void = {},
                onScrubCompletado: @escaping () -> Void = {}) {
        self.model = model
        self.onTapSeccion = onTapSeccion
        self.mostrarHintScrub = mostrarHintScrub
        self.onHintMostrado = onHintMostrado
        self.onScrubCompletado = onScrubCompletado
    }

    public var body: some View {
        // La cara NO trae fondo ni scroll propios: mide su contenido sobre la atmósfera y el
        // scroll es el de la pantalla (revisión del dueño en vivo, 2026-08-06; se conserva).
        let columnaUnica = dynamicTypeSize >= .accessibility1
        let bandas = model.bandas
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bandas.enumerated()), id: \.offset) { i, banda in
                bandaView(banda, columnaUnica: columnaUnica,
                          primera: i == 0,
                          sigueACabecera: i > 0 && Self.esNivel(bandas[i - 1]))
                    // Entrada en cascada: los índices siguen a los del héroe (0 y 1).
                    .liquidEntrada(index: 2 + i)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MatrizTokens.margenModulos)
        .padding(.bottom, LiquidSpace.s600)
        // FER-audit: solo en la transición «se puso» (tap), no también en la limpieza a nil
        // 320 ms después — que hacía vibrar DOS veces por un solo toque.
        .sensoryFeedback(.selection, trigger: latido) { _, nuevo in nuevo != nil }
        .sensoryFeedback(.selection, trigger: scrubTick)
        .accessibilityElement(children: .contain)
    }

    private static func esNivel(_ b: MatrizHoyModel.Banda) -> Bool {
        if case .nivel = b { return true }
        return false
    }

    /// Un módulo se compone horizontal SOLO si viene de una banda `.full` Y su gráfica es de
    /// barras (Pasos): `seccionView` no sabe de qué banda viene y Esfuerzo (`.split`, también
    /// barras) tiene que seguir vertical — por eso el contexto lo pasa `bandaView`.
    private static func esHorizontal(_ s: MatrizSeccion) -> Bool {
        if case .barrasMini = s.chart { return true }
        return false
    }

    /// Toca una sección: dispara su hoja + el latido del sello.
    private func tocar(_ id: String) {
        // El estilo del botón limpia `presionado` en `onChange(isPressed)`, pero la acción abre
        // una hoja en el mismo ciclo: si esa transición se pierde, el módulo se quedaría al 97 %
        // al volver. `tocar` corre al SOLTAR: aquí se limpia sin depender de nadie.
        presionado = nil
        if !reduceMotion {
            withAnimation(.spring(duration: 0.3)) { latido = id }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeOut(duration: 0.25)) { latido = nil }
            }
        }
        onTapSeccion(id)
    }

    // MARK: Estantes y filas

    @ViewBuilder
    private func bandaView(_ banda: MatrizHoyModel.Banda, columnaUnica: Bool,
                           primera: Bool, sigueACabecera: Bool) -> some View {
        switch banda {
        case .nivel(let rotulo, let manualID):
            cabeceraEstante(rotulo, manualID: manualID)
                .padding(.top, primera ? 0 : MatrizTokens.estanteGap)
                .padding(.bottom, MatrizTokens.estanteCabeceraPad)
        case .full(let s):
            // Un módulo ancho mide su contenido (sin estirarse: no hay gemela que igualar).
            modulo(s, horizontal: !columnaUnica && Self.esHorizontal(s), estirar: false)
                .padding(.top, primera || sigueACabecera ? 0 : MatrizTokens.moduloGap)
        case .split(let izq, let der):
            Group {
                if columnaUnica {
                    VStack(spacing: MatrizTokens.moduloGap) {
                        modulo(izq, horizontal: false, estirar: false)
                        modulo(der, horizontal: false, estirar: false)
                    }
                } else {
                    // Gemelas IGUAL de altas: la fila mide el módulo más alto y el otro se
                    // estira (el vidrio se aplica al módulo ya estirado).
                    HStack(alignment: .top, spacing: MatrizTokens.moduloGap) {
                        modulo(izq, horizontal: false, estirar: true)
                        modulo(der, horizontal: false, estirar: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, primera || sigueACabecera ? 0 : MatrizTokens.moduloGap)
        }
    }

    /// El texto de un rótulo de estante (compartido por el decorativo y el tocable).
    private func nivelTexto(_ rotulo: String) -> some View {
        Text(rotulo)
            .font(LiquidType.micro)
            .tracking(LiquidType.microTracking)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta700)
    }

    /// La cabecera de un estante: rótulo en versalitas + el mismo «?» de siempre (FER-54: la
    /// fila entera es el hit ≥ 44 pt, el glifo hueco anuncia la hoja-manual de ese nivel).
    @ViewBuilder
    private func cabeceraEstante(_ rotulo: String, manualID: String?) -> some View {
        if let manualID {
            Button { tocar(manualID) } label: {
                // firstTextBaseline: el «?» centrado ópticamente con las caps del rótulo.
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    nivelTexto(rotulo)
                    Image(systemName: "questionmark.circle")
                        .font(LiquidType.infoGlifoCompacto.weight(.medium))
                        .foregroundStyle(LiquidColor.tinta500)
                    Spacer(minLength: 0)
                }
                // Zona táctil ≥ 44 pt (HIG) SIN inflar el layout: el hit crece hacia afuera.
                .contentShape(Rectangle().inset(by: -LiquidSpace.s400))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(rotulo))
            .accessibilityHint(Text(String(localized: "matriz.nivel.manual.hint",
                                           defaultValue: "How this works",
                                           bundle: .main)))
        } else {
            // Cabecera decorativa (sin hoja): hoy NINGÚN emisor la usa —los tres estantes de la
            // app y de las fixtures llevan `manualID`— pero es un camino del componente
            // (`manualID: String?`), no un huérfano: se conserva y se declara.
            nivelTexto(rotulo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    // MARK: El módulo de vidrio

    /// El módulo: su contenido con el padding del prototipo, y encima la receta de vidrio sobre
    /// la atmósfera. `estirar` (gemelas): toma el alto de la fila; si no, mide su contenido.
    /// Cede entero al presionar su encabezado.
    private func modulo(_ s: MatrizSeccion, horizontal: Bool, estirar: Bool) -> some View {
        contenido(s, horizontal: horizontal)
            .padding(.horizontal, MatrizTokens.moduloPadH)
            .padding(.top, MatrizTokens.moduloPadTop)
            .padding(.bottom, MatrizTokens.moduloPadBottom)
            .frame(maxWidth: .infinity, maxHeight: estirar ? .infinity : nil, alignment: .topLeading)
            // Sin gemela, el módulo mide su CONTENIDO (el `Spacer` interior no se infla aunque el
            // contenedor proponga alto de sobra — p. ej. un render con marco fijo).
            .fixedSize(horizontal: false, vertical: !estirar)
            .liquidGlass(.superficieAtmosfera)
            .scaleEffect(presionado == s.id ? LiquidMotion.pressScale : 1)
            .animation(LiquidMotion.press, value: presionado == s.id)
    }

    @ViewBuilder
    private func contenido(_ s: MatrizSeccion, horizontal: Bool) -> some View {
        if let renglones = s.renglones {
            // Camino legado (guardián en dos filas; hoy sin emisor, con previews): SIN botón
            // contenedor — anidar botones rompe hit-testing y el foco de VoiceOver.
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                botonEncabezado(s) { textos(s) }
                ForEach(renglones) { r in
                    renglónView(r)
                }
            }
        } else if horizontal {
            // Pasos (ancho): fila de título + [número · subtítulo] a la izquierda y la gráfica
            // ocupando el resto, al pie. El encabezado (texto) es el botón; la gráfica, el gesto.
            // Con o sin scrub la anatomía es la MISMA (sin scrub el pan va apagado y el toque en
            // la gráfica abre la hoja igual).
            HStack(alignment: .bottom, spacing: LiquidSpace.s400) {
                botonEncabezado(s, expandir: false) { textos(s) }
                    // Ancho FIJO: la gráfica no puede cambiar de ancho bajo el dedo (el
                    // subtítulo del scrub es más largo que el de reposo).
                    .frame(width: MatrizTokens.moduloTextoAncho, alignment: .leading)
                grafica(s, noches: s.scrubNoches ?? [])
            }
        } else {
            // La anatomía vertical: título · número · subtítulo · (aire) · gráfica al pie. El
            // encabezado es su propio botón (abre la hoja) y la gráfica lleva el arrastre —
            // separados, para que un toque abra y un arrastre lea sin pelear (patrón #118).
            VStack(alignment: .leading, spacing: 0) {
                botonEncabezado(s) { textos(s) }
                Spacer(minLength: LiquidSpace.s300)
                grafica(s, noches: s.scrubNoches ?? [])
            }
        }
    }

    /// El botón del encabezado de un módulo (abre la hoja): su label son los textos. `expandir`
    /// = ocupa todo el ancho del módulo (vertical); en Pasos horizontal el texto hugs.
    private func botonEncabezado<L: View>(_ s: MatrizSeccion, expandir: Bool = true,
                                          @ViewBuilder label: () -> L) -> some View {
        Button { tocar(s.id) } label: {
            label()
                .frame(maxWidth: expandir ? .infinity : nil, alignment: .leading)
                // Hit ≥ 44 pt (HIG) hacia afuera, sin engordar el vidrio ni mover la gráfica.
                .contentShape(Rectangle().inset(by: -LiquidSpace.s125))
        }
        .buttonStyle(PresionaModulo(id: s.id, presionado: $presionado))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: a11yLabel(s)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("matriz-seccion-\(s.id)")
    }

    /// La gráfica de un módulo con su scrub y su control ajustable de VoiceOver.
    private func grafica(_ s: MatrizSeccion, noches: [MatrizSeccion.ScrubNoche]) -> some View {
        chartView(s.chart, hue: s.hue, chartID: s.chartID,
                  resaltado: scrub?.id == s.id ? scrub?.idx : nil)
            .frame(height: Self.chartAltura(s.chart))
            .modifier(ScrubGesto(id: s.id, noches: noches, chart: s.chart,
                                 scrub: $scrub, tick: $scrubTick, onTap: { tocar(s.id) },
                                 onCompletado: onScrubCompletado))
            // El hint de barrido: solo sobre la gráfica del par (la que estrena la figura), y
            // solo mientras el host lo pida; nunca bajo Reduce Motion ni en renders.
            .overlay {
                if case .costura = s.chart, mostrarHintScrub, !reduceMotion, !motionDisabled {
                    HintBarrido(onMostrado: onHintMostrado)
                }
            }
            // VoiceOver no arrastra: la gráfica es su propio control ajustable (solo si hay
            // lecturas que recorrer; sin scrub queda oculta y el botón del encabezado la representa).
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: scrubA11yLabel(s)))
            .accessibilityHidden(noches.count <= 1)
            .modifier(ScrubA11y(aplica: noches.count > 1, valor: scrubA11yValue(s),
                                hint: scrubA11yHint,
                                ajustar: { scrubAjustar(s, $0) }))
    }

    /// Los textos del módulo: fila de título (sello · título · estado) · número · subtítulo.
    private func textos(_ s: MatrizSeccion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            filaTitulo(s)
            numero(s)
                .padding(.top, LiquidSpace.s200)
            subtitulo(s)
                .padding(.top, LiquidSpace.s100)
        }
    }

    /// [sello · Título ····· estado]. El título va en caja normal (`tituloGemela` para todos):
    /// la jerarquía es estante = versalitas, módulo = título en caja normal (prototipo). El estado
    /// del guardián (chip) vive SIEMPRE aquí, a la derecha — y se calla mientras el dedo lee otra
    /// noche (adversarial C3: el chip dice el estado de HOY, no el de la noche leída).
    private func filaTitulo(_ s: MatrizSeccion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MatrizTokens.selloTexto) {
            sello(s)
                // El sello no es texto: ancla su centro óptico a la altura de la mayúscula
                // inicial del título (caja normal desde FER-118; verificado en captura: el 0.78
                // calibrado para versalitas sigue centrando con la inicial en mayúscula).
                .alignmentGuide(.firstTextBaseline) { d in d.height * 0.78 }
                // Acuse del tacto: el eco del héroe responde al dedo (§micro).
                .scaleEffect(latido == s.id ? 1.10 : 1)
            Text(s.titulo)
                .font(LiquidType.tituloGemela)
                .foregroundStyle(LiquidColor.tinta700)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: LiquidSpace.s200)
            if let chip = s.chip, scrub?.id != s.id {
                chipView(chip)
            }
        }
    }

    /// El sello del módulo: el guardián VIVO (FER-56 · Ola 3), el glifo del sistema
    /// (FER-117), el sello dibujado o el orbe de partículas — los mismos de siempre.
    @ViewBuilder
    private func sello(_ s: MatrizSeccion) -> some View {
        if let estado = s.selloGuardian {
            SelloGuardianVivo(radio: MatrizTokens.selloRadio,
                              hueTemp: s.huesPar?.0 ?? s.hue,
                              hueResp: s.huesPar?.1 ?? s.hue,
                              estado: estado)
        } else if let sello = s.sello {
            SelloMetricaVista(sello, lado: MatrizTokens.selloRadio * 2.5, tono: s.hue)
        } else if let glifo = s.glifoSello {
            LiquidIconDrop(glifo, tone: s.hue,
                           size: MatrizTokens.selloRadio * 2.5,
                           iconSize: MatrizTokens.selloRadio * 1.4)
        } else {
            OrbeVivo(radio: MatrizTokens.selloRadio, hue: s.huesPar?.0 ?? s.hue,
                     semillaID: "sello-\(s.id)", huePar: s.huesPar?.1, fps: 12,
                     forma: s.formaSello)
        }
    }

    /// El número grande del módulo (o nada si el valor viene vacío).
    @ViewBuilder
    private func numero(_ s: MatrizSeccion) -> some View {
        let valor = valorEfectivo(s)
        if !valor.isEmpty {
            valorCompuesto(s, valor: valor)
        }
    }

    /// El subtítulo: la frase de HOY o la de la noche leída. Sin subtítulo se reserva la línea
    /// (un espacio en la misma caption, invisible) para que las gemelas arranquen parejas.
    private func subtitulo(_ s: MatrizSeccion) -> some View {
        let sub = sublabelEfectivo(s)
        return Text(sub ?? " ")
            .font(LiquidType.caption)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(sub == nil ? 0 : 1)
            // El dato del scrub cambia con un cruce suave (es texto — numericText sólo aplica a
            // dígitos). Bajo Reduce Motion el valor salta sin cruce (FER-audit).
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: sub)
    }

    /// Valor a mostrar: la noche del scrub si esta sección la está leyendo, si no HOY.
    private func valorEfectivo(_ s: MatrizSeccion) -> String {
        if scrub?.id == s.id, let i = scrub?.idx, let n = s.scrubNoches, n.indices.contains(i) {
            return n[i].valor
        }
        return s.valor
    }

    /// Gemelos para RENGLONES (Skin temp/Breathing, dueño 2026-08-15): el arrastre cambia
    /// valor y fecha en el encabezado del renglón, igual que en las secciones.
    private func valorEfectivoRenglon(_ r: MatrizRenglon) -> String {
        if scrub?.id == r.id, let i = scrub?.idx, let n = r.scrubNoches, n.indices.contains(i) {
            return n[i].valor
        }
        return r.valor
    }

    private func sublabelEfectivoRenglon(_ r: MatrizRenglon) -> String? {
        if scrub?.id == r.id, let i = scrub?.idx, let n = r.scrubNoches, n.indices.contains(i) {
            return n[i].sublabel
        }
        return r.sublabel
    }

    /// Sublabel a mostrar: la frase de la noche del scrub si aplica, si no la de HOY.
    private func sublabelEfectivo(_ s: MatrizSeccion) -> String? {
        if scrub?.id == s.id, let i = scrub?.idx, let n = s.scrubNoches, n.indices.contains(i) {
            return n[i].sublabel
        }
        return s.sublabel
    }

    /// Numeral + unidad chica en el mismo hue. Dos tamaños (prototipo): las decisoras (Sueño ·
    /// FC) en `valorTileL`, el resto en `valorTileM`. El numeral RUEDA al refrescar
    /// (`numericText`) en vez de parpadear — también el par del guardián.
    private func valorCompuesto(_ s: MatrizSeccion, valor: String) -> some View {
        let fuente = s.destacada ? LiquidType.valorTileL : LiquidType.valorTileM
        return HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
            // FER-80 · El par del guardián se escribe con SUS DOS colores («+0.1°» dorado ·
            // «14.9» azul): son dos señales distintas, no un dato con dos partes. FER-118: tres
            // `Text` adyacentes (no una concatenación multicolor, cuyo rodado por dígito no está
            // documentado), cada uno con su propio `numericText`.
            if let par = s.huesPar, let corte = valor.range(of: " · ") {
                let temp = String(valor[..<corte.lowerBound]), resp = String(valor[corte.upperBound...])
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(temp).foregroundStyle(par.0)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .snappy, value: temp)
                    Text(verbatim: " · ").foregroundStyle(LiquidColor.tinta500)
                    Text(resp).foregroundStyle(par.1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .snappy, value: resp)
                }
                .font(fuente)
                .tracking(LiquidType.valorTileTracking)
                .monospacedDigit()
            } else {
                Text(valor)
                    .font(fuente)
                    .tracking(LiquidType.valorTileTracking)
                    .foregroundStyle(s.hue)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: valor)
            }
            if let u = s.unidad, valor != "—" {
                Text(u)
                    .font(LiquidType.caption)
                    .foregroundStyle(s.hue)
            }
        }
        // El numeral JAMÁS se parte («46» → «4/6»): una línea, encoge antes de envolver.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private func renglónView(_ r: MatrizRenglon) -> some View {
        if let noches = r.scrubNoches, noches.count > 1 {
            // CON scrub (Skin temp/Breathing, dueño 2026-08-15): el encabezado es su botón
            // (abre la hoja) y la gráfica lleva el arrastre — separados, como las secciones con
            // scrub, para que un toque abra y un arrastre lea sin pelear.
            VStack(alignment: .leading, spacing: MatrizTokens.renglonV) {
                Button { onTapSeccion(r.id) } label: {
                    encabezadoRenglon(r).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                chartView(r.chart, hue: r.hue, chartID: r.chartID,
                          resaltado: scrub?.id == r.id ? scrub?.idx : nil)
                    .frame(height: MatrizTokens.alturaRenglon)
                    .modifier(ScrubGesto(id: r.id, noches: noches, chart: r.chart,
                                         scrub: $scrub, tick: $scrubTick,
                                         onTap: { onTapSeccion(r.id) },
                                         onCompletado: onScrubCompletado))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(r.titulo), \(r.valor)"))
            .accessibilityIdentifier("matriz-renglon-\(r.id)")
        } else {
            Button { onTapSeccion(r.id) } label: {
                VStack(alignment: .leading, spacing: MatrizTokens.renglonV) {
                    encabezadoRenglon(r)
                    chartView(r.chart, hue: r.hue, chartID: r.chartID)
                        .frame(height: MatrizTokens.alturaRenglon)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(r.titulo), \(r.valor)"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("matriz-renglon-\(r.id)")
        }
    }

    /// El encabezado del renglón (título · valor · chevron + estado). Compartido por los dos
    /// caminos (con/sin scrub). VStack PROPIO — devolver la tupla suelta dejaba que el label
    /// del Button la acomodara HORIZONTAL y el sublabel se subía junto al título.
    private func encabezadoRenglon(_ r: MatrizRenglon) -> some View {
        // El valor/fecha EFECTIVOS: la noche del scrub si el dedo está leyendo este renglón.
        let valor = valorEfectivoRenglon(r)
        let sub = sublabelEfectivoRenglon(r)
        // Sentence-case a propósito: los renglones son SUB-señales del guardián (voz
        // subordinada); el ritmo/baseline sí es el mismo del encabezado.
        return VStack(alignment: .leading, spacing: MatrizTokens.renglonV) {
        HStack(alignment: .firstTextBaseline, spacing: MatrizTokens.selloTexto) {
            if let sello = r.sello {
                SelloMetricaVista(sello, lado: MatrizTokens.selloRadio * 2.5, tono: r.hue)
                    // Mismo anclaje óptico que el sello del encabezado: su centro a la
                    // altura de las versalitas, no a la caja del texto.
                    .alignmentGuide(.firstTextBaseline) { d in d.height * 0.78 }
            }
            Text(r.titulo)
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: MatrizTokens.selloTexto)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
                Text(valor)
                    .font(LiquidType.valorM)
                    .foregroundStyle(r.hue)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: valor)
                if let u = r.unidad {
                    Text(u)
                        .font(LiquidType.caption)
                        .foregroundStyle(r.hue)
                }
            }
            .underline(r.subrayado != .ninguna,
                       color: r.subrayado == .alarma
                       ? LiquidColor.negativo : LiquidColor.atencion)
            // Chevron gemelo del encabezado: el renglón también abre su hoja y sus numerales
            // alinean con los del header (Grok simetría R1).
            LiquidIcon(.chevron, size: 8, color: LiquidColor.tinta500)
                .alignmentGuide(.firstTextBaseline) { d in d.height * 0.85 }
        }
        if let sub {
            // P2: el estado en palabras — el número deja de asustar. Con el scrub, la
            // fecha cruza suave (es texto, no dígitos); bajo Reduce Motion salta.
            Text(sub)
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: sub)
        }
        }
    }

    /// El color del estado del guardián — una sola fuente para el chip y para la sublínea.
    static func tonoChip(_ tono: MatrizHoyModel.ChipGuardian.Tono) -> Color {
        switch tono {
        case .calma: return LiquidColor.verdePrimario
        case .terciario: return LiquidColor.tinta500
        case .atencion: return LiquidColor.atencion
        case .alarma: return LiquidColor.negativo
        }
    }

    private func chipView(_ chip: MatrizHoyModel.ChipGuardian) -> some View {
        let color: Color = Self.tonoChip(chip.tono)
        return Text(chip.texto)
            .font(LiquidType.caption)
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func chartView(_ payload: MatrizChartPayload, hue: Color,
                           chartID: String, resaltado: Int? = nil) -> some View {
        switch payload {
        case .columnas(let noches, let ref, let tag, let dom):
            MatrizColumnas(chartID: chartID, noches: noches, referencia: ref,
                           referenciaTag: tag, dominio: dom, hue: hue, resaltado: resaltado)
        case .lineaRellena(let pts, let base, let dom, let alfa, let alerta):
            MatrizLineaRellena(chartID: chartID, puntos: pts, base: base, dominio: dom,
                               hue: hue, alfa: alfa, alertaHoy: alerta, resaltado: resaltado)
        case .regla(let pts, let banda, let dom, let alerta):
            MatrizRegla(chartID: chartID, puntos: pts, banda: banda, dominio: dom,
                        hue: hue, alertaHoy: alerta, resaltado: resaltado)
        case .lineaSerena(let pts, let banda, let dom, let alerta):
            MatrizLineaSerena(chartID: chartID, puntos: pts, banda: banda, dominio: dom,
                              hue: hue, alertaHoy: alerta, resaltado: resaltado)
        case .colina(let p, let zona, let estela, let alertaHoy):
            MatrizColina(chartID: chartID, p: p, zona: zona, estela: estela, hue: hue,
                           alertaHoy: alertaHoy, resaltado: resaltado)
        case .barrasMini(let valores, let promedio):
            MatrizBarrasMini(chartID: chartID, valores: valores, hue: hue, promedio: promedio, resaltado: resaltado)
        case .escalerita(let niveles):
            MatrizEscalerita(chartID: chartID, niveles: niveles, hue: hue, resaltado: resaltado)
        case .costura(let noches):
            // FER-118: los dos hilos de puntos sustituyen a la costura; mismos datos.
            MatrizHilos(chartID: chartID, noches: noches, resaltado: resaltado)
        }
    }

    /// Revisión adversarial P-3 · El inset horizontal de cada gráfica, en UN solo lugar: lo usa
    /// el DIBUJO y lo usa el mapeo del DEDO. Vivían separados (el gesto asumía `chartInset` 4 y
    /// la línea serena dibujaba con 8.6 tras FER-73), así que cerca de los bordes el cursor
    /// caía en una noche y el readout anunciaba otra.
    static func chartInset(_ p: MatrizChartPayload) -> CGFloat {
        switch p {
        case .lineaSerena:
            return max(MatrizTokens.chartInset,
                       LiquidChart.puntoDatoRadio + LiquidChart.endpointBorde * 0.5 + MatrizTokens.aroGap2)
        case .costura:
            // FER-118: el anillo de HOY latiendo llega a 8 pt del centro (era 5, y se cortaba).
            return max(MatrizTokens.chartInset, MatrizTokens.hilosInset)
        default:
            return MatrizTokens.chartInset
        }
    }

    /// Alto del chart por tipo. `static internal` (no depende de `self`) para poder afirmar
    /// en un test la IGUALDAD de las gemelas (FER-59) sin depender de snapshots (que no son gate de CI).
    static func chartAltura(_ p: MatrizChartPayload) -> CGFloat {
        switch p {
        case .colina: return MatrizTokens.alturaRiel
        case .barrasMini: return MatrizTokens.alturaBarras
        case .escalerita: return MatrizTokens.alturaEscalera
        // FER-59: VFC (lineaRellena) es gemela de Estrés (escalerita) en Contexto → misma
        // altura, para que el borde inferior de la fila no quede dentado (antes 56 vs 40).
        case .lineaRellena: return MatrizTokens.alturaEscalera
        case .costura: return MatrizTokens.alturaHilos
        default: return MatrizTokens.alturaLinea
        }
    }

    private func a11yLabel(_ s: MatrizSeccion) -> String {
        // Revisión adversarial P-4: con la costura, `valor` es un PAR («+0.1° · 14.9») y leído
        // así no dice qué número es de qué señal. `a11yValor` lo desambigua cuando existe.
        var parts = [s.titulo, s.a11yValor ?? s.valor]
        if let sub = s.sublabel { parts.append(sub) }
        if let chip = s.chip { parts.append(chip.texto) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    // MARK: - Scrub accesible (FER-56)
    // El arrastre lee las 14/20 lecturas con el dedo; VoiceOver no puede arrastrar. Se
    // expone la gráfica como un control «ajustable»: deslizar ↑/↓ mueve el índice y el
    // valor a11y anuncia esa lectura — el equivalente accesible del scrub táctil.

    /// «FC Reposo, 20 lecturas» — nombre del control ajustable.
    private func scrubA11yLabel(_ s: MatrizSeccion) -> String {
        let n = s.scrubNoches?.count ?? 0
        return String(format: String(localized: "matriz.scrub.a11y.label",
                                     defaultValue: "%1$@, %2$d readings"), s.titulo, n)
    }

    /// Valor a11y: la lectura enfocada por el ajuste (o HOY mientras no se ha movido).
    private func scrubA11yValue(_ s: MatrizSeccion) -> String {
        guard let n = s.scrubNoches, !n.isEmpty else { return s.valor }
        let idx = (scrub?.id == s.id ? scrub?.idx : nil) ?? (n.count - 1)
        guard n.indices.contains(idx) else { return s.valor }
        return "\(n[idx].valor), \(n[idx].sublabel)"
    }

    private var scrubA11yHint: String {
        String(localized: "matriz.scrub.a11y.hint",
               defaultValue: "Swipe up or down to hear each reading")
    }

    /// El ajuste de VoiceOver mueve el índice (↑ acerca a HOY, ↓ al pasado).
    private func scrubAjustar(_ s: MatrizSeccion, _ dir: AccessibilityAdjustmentDirection) {
        guard let n = s.scrubNoches, !n.isEmpty else { return }
        let cur = (scrub?.id == s.id ? scrub?.idx : nil) ?? (n.count - 1)
        let nuevo: Int
        switch dir {
        case .increment: nuevo = min(n.count - 1, cur + 1)
        case .decrement: nuevo = max(0, cur - 1)
        @unknown default: return
        }
        scrub = (id: s.id, idx: nuevo)
        scrubTick += 1
    }
}

/// El estilo del botón de un módulo: NO escala su label (el label es solo el encabezado);
/// reporta el estado presionado a la cara, que escala el VIDRIO ENTERO con `pressScale` — la
/// única gramática de toque (`.liquidPress`), aplicada al objeto correcto. Un solo `presionado`
/// para toda la cara: dos dedos en dos módulos a la vez es un caso raro y el peor efecto es que
/// el primero deje de ceder antes de soltarlo (decisión registrada; sin estado colgado).
private struct PresionaModulo: ButtonStyle {
    let id: String
    @Binding var presionado: String?
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { presionado = id } else if presionado == id { presionado = nil }
            }
    }
}

/// El hint de barrido (FER-118): una luz tenue de tinta cruza la gráfica una vez, 0.9 s después
/// de que la gráfica ENTRA A LA VISTA, para enseñar que se arrastra. Decorativo: sin hit, sin
/// VoiceOver. Cuenta como «mostrado» solo si de verdad se vio: el `ScrollView` de Hoy no es
/// lazy y monta la Matriz entera al abrir, así que un `onAppear` a secas quemaba el contador de
/// 3 en tres lanzamientos sin que nadie hubiera bajado hasta el guardián (revisión adversarial).
/// En iOS 18+ lo decide `onScrollVisibilityChange`; antes, el `onAppear` de siempre.
private struct HintBarrido: View {
    let onMostrado: () -> Void
    @State private var cruzo = false
    @State private var disparado = false
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [LiquidColor.tinta900.opacity(0), LiquidColor.tinta7,
                                    LiquidColor.tinta900.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: MatrizTokens.hintAncho)
                .offset(x: cruzo ? geo.size.width + MatrizTokens.hintAncho
                                 : -MatrizTokens.hintAncho * 1.2)
        }
        .modifier(HintVisibilidad { visible in
            guard visible, !disparado else { return }
            disparado = true
            // Se cuenta cuando el cruce TERMINÓ, no cuando arranca: si el contador subiera aquí,
            // en la tercera vez el host apagaría `mostrarHintScrub` en el mismo ciclo y el hint se
            // desmontaría antes de moverse — se verían dos, contados tres (revisión final).
            withAnimation(.easeInOut(duration: MatrizTokens.hintDuracion)
                            .delay(MatrizTokens.hintEspera)) { cruzo = true } completion: { onMostrado() }
        })
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// «¿La gráfica está a la vista?» — iOS 18+ lo sabe (`onScrollVisibilityChange`, ≥ 60 % dentro
/// del viewport); antes se asume visible al aparecer (el estado seguro de siempre).
private struct HintVisibilidad: ViewModifier {
    let cambio: (Bool) -> Void
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, *) {
            content.onScrollVisibilityChange(threshold: 0.6) { cambio($0) }
        } else {
            content.onAppear { cambio(true) }
        }
    }
}

/// Expone el historial del scrub a VoiceOver como control «ajustable» (FER-56): sin esto,
/// las 14/20 lecturas sólo existían para el dedo. `aplica == false` → no-op (secciones
/// sin scrub no deben volverse ajustables).
private struct ScrubA11y: ViewModifier {
    let aplica: Bool
    let valor: String
    let hint: String
    let ajustar: (AccessibilityAdjustmentDirection) -> Void
    func body(content: Content) -> some View {
        if aplica {
            content
                .accessibilityValue(Text(verbatim: valor))
                .accessibilityHint(Text(verbatim: hint))
                .accessibilityAdjustableAction { ajustar($0) }
        } else {
            content
        }
    }
}

// MARK: - Scrub (FER-55)

/// Arrastrar sobre la gráfica lee cada lectura (fecha + valor) en el sublabel, como
/// las gráficas de adentro. Se monta en toda sección con `scrubNoches` (Sueño, FC —
/// panel B baja #7); al soltar
/// —o si el gesto se CANCELA— la celda regresa sola a HOY. Detalles de robustez, todos
/// hallazgos del panel adversarial Grok/DeepSeek/Sonnet:
/// - El gesto vive en un `overlay` transparente que TOMA el tamaño del contenido ya
///   dimensionado, así el `.frame(height:)` del chart se preserva (un `GeometryReader`
///   envolvente reportaba alto ideal ~0 y colapsaba la celda).
/// - `highPriorityGesture` para ganarle al pan vertical del `ScrollView` de Hoy (#118).
/// - `@GestureState` → al cancelarse el gesto, SwiftUI resetea el estado y limpiamos
///   `scrub` en `onChange`, no solo en `onEnded` (que no corre en cancelación).
/// - El índice descuenta el `chartInset` real de las barras y sólo se compromete cuando
///   el arrastre es predominantemente HORIZONTAL (no secuestra el scroll vertical).
/// El mapeo dedo→índice del scrub, PURO y testeable (FER-62). Vivía inline en el gesto y
/// escondía un bug: trataba TODA forma que no fuera `.columnas` como serie, pero las
/// `.barrasMini` son BINS igual que las columnas — al darles scrub (Esfuerzo/Pasos) el
/// índice se desfasaba hasta un día (~23% del arrastre). Nunca se ejerció porque barrasMini
/// no tenía scrub… hasta ahora. Extraído a estáticas puras con test de contrato.
enum ScrubMapeo {
    /// ¿La forma ancla sus puntos como SERIE (i/(n−1), redondeo al vecino) o como BINS
    /// (columnas y barras: floor sobre n)? Las series de contexto (curva/escalera) redondean;
    /// las de bins parten el ancho en `n` cajones iguales.
    static func esSerie(_ chart: MatrizChartPayload) -> Bool {
        switch chart {
        case .columnas, .barrasMini: return false   // bins de ancho igual
        default: return true                         // series: lineaRellena, escalerita, regla…
        }
    }

    /// Índice de la noche bajo el dedo. `x` local; `ancho` ya descuenta los insets; `inset`
    /// es el margen izquierdo. Bins → floor; serie → redondeo al vecino. Clampa a [0, n-1].
    static func indice(x: CGFloat, inset: CGFloat, ancho: CGFloat, count: Int, esSerie: Bool) -> Int {
        guard ancho > 0, count > 1 else { return max(count - 1, 0) }
        let rel = min(max((x - inset) / ancho, 0), 0.9999)
        return esSerie ? Int((rel * CGFloat(count - 1)).rounded())
                       : min(Int(rel * CGFloat(count)), count - 1)
    }
}

private struct ScrubGesto: ViewModifier {
    // Trabaja con secciones Y renglones (guardián): recibe las piezas, no un `MatrizSeccion`.
    let id: String
    let noches: [MatrizSeccion.ScrubNoche]
    let chart: MatrizChartPayload
    @Binding var scrub: (id: String, idx: Int)?
    @Binding var tick: Int
    var onTap: () -> Void = {}
    /// FER-118: avisa cuando un arrastre terminó (para apagar el hint de barrido).
    var onCompletado: () -> Void = {}
    /// La regla reserva su zona a la derecha: el mapeo del dedo debe usar el MISMO
    /// ancho útil que usa la curva, o el índice se corre cerca del margen.
    private var insetDerecho: CGFloat {
        if case .regla = chart { return MatrizTokens.reglaZona }
        return MatrizHoyFace.chartInset(chart)
    }
    /// El inset IZQUIERDO del mapeo: el mismo con el que dibuja esta gráfica (P-3).
    private var insetIzquierdo: CGFloat { MatrizHoyFace.chartInset(chart) }
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    // Un toque limpio sobre la gráfica abre la hoja, como en las celdas
                    // sin scrub (panel B, DeepSeek BAJA: quedaba zona muerta).
                    .onTapGesture { onTap() }
                    // FER-73 · H-S: el gesto NO EMPIEZA si el dedo va vertical (regla en
                    // `gestureRecognizerShouldBegin`), así el scroll de Hoy sigue vivo aunque
                    // el dedo arranque sobre la gráfica. Antes el `DragGesture` reconocía y en
                    // iOS 18+ el pan del ScrollView cedía: la página no se movía.
                    .liquidScrubPan(
                        enabled: noches.count > 1,
                        onChange: { p in
                            let inset = insetIzquierdo
                            let w = geo.size.width - inset - insetDerecho
                            guard w > 0, noches.count > 1 else { return }
                            let i = ScrubMapeo.indice(
                                x: p.x, inset: inset, ancho: w,
                                count: noches.count,
                                esSerie: ScrubMapeo.esSerie(chart))
                            if scrub?.id != id || scrub?.idx != i {
                                scrub = (id, i)
                                tick &+= 1   // pulso háptico por noche cruzada
                            }
                        },
                        onEnd: {
                            if scrub?.id == id { scrub = nil; onCompletado() }
                        })
            }
        )
    }
}

// MARK: - Previews

#if DEBUG
private enum MatrizHoyFacePreviewData {
    static var t1Bueno: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            .init(valor: 420 + Double(i % 4) * 12, alerta: .ninguna)
        }
        let fc: [Double?] = (0..<20).map { i in 58 + Double(i % 5) }
        let vfc: [Double?] = (0..<20).map { i in 40 + Double(i % 7) }
        let estela: [Double] = [0.9, 1.0, 1.05, 0.95, 1.1]
        let strain: [Double?] = (0..<14).map { Double(10 + $0) }
        let steps: [Double?] = (0..<14).map { Double(6000 + $0 * 200) }
        let stress: [Int?] = [0, 1, 0, 1, 1, 0, 1]
        let temp: [Double?] = (0..<20).map { _ in 0.1 }
        let resp: [Double?] = (0..<20).map { _ in 14.0 }

        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "7:12",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: noches, referencia: 420,
                                     referenciaTag: "7 h", dominio: 240...600))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "52",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: fc, banda: 53...59, dominio: 45...75,
                                      alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "68 ms",
                        sublabel: "Does not vote",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vfc, base: 45, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .ninguna),
                    chip: .init(texto: "At ease", tono: .calma),
                    renglones: [
                        MatrizRenglon(id: "skintemp", titulo: "Skin temp",
                                      valor: "+0.1°", hue: LiquidColor.doradoTemp,
                                      chartID: "matriz-guardian-temp",
                                      chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                                          dominio: -1...1, alertaHoy: .ninguna)),
                        MatrizRenglon(id: "resp", titulo: "Breathing",
                                      valor: "14.0", hue: LiquidColor.azul,
                                      chartID: "matriz-guardian-resp",
                                      chart: .lineaSerena(puntos: resp, banda: 12...16,
                                                          dominio: 8...22, alertaHoy: .ninguna)),
                    ])),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.12",
                        sublabel: "Steady",
                        chartID: "matriz-carga",
                        chart: .colina(p: 1.12, zona: 0.8...1.3, estela: estela)),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "12.4",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: strain))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta500,
                        titulo: "Stress", valor: "Low",
                        sublabel: "last 7 days",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: stress)),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "8 432",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: steps))),
            ])
    }

    static var t2Calibrando: MatrizHoyModel {
        let vacioNoches = [MatrizColumnas.Noche](repeating: .init(valor: nil), count: 14)
        let vacio20 = [Double?](repeating: nil, count: 20)
        let vacio14 = [Double?](repeating: nil, count: 14)
        let vacio7 = [Int?](repeating: nil, count: 7)
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "—",
                    sublabel: "Getting to know you",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: vacioNoches, referencia: 420,
                                     referenciaTag: "7 h", dominio: 240...600))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "—",
                        sublabel: "Getting to know you",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: vacio20, banda: nil, dominio: 45...75,
                                      alertaHoy: .ninguna)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "—",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(puntos: vacio20, base: nil, dominio: 20...80,
                                             alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "—",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: vacio20, banda: nil, dominio: -1...1,
                                        alertaHoy: .ninguna))),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "—",
                        sublabel: "Calibrating",
                        chartID: "matriz-carga",
                        chart: .colina(p: nil, zona: 0.8...1.3, estela: [])),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "—",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: vacio14))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta500,
                        titulo: "Stress", valor: "—",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: vacio7)),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "—",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: vacio14))),
            ])
    }

    static var t3Alerta: MatrizHoyModel {
        let noches: [MatrizColumnas.Noche] = (0..<14).map { i in
            .init(valor: i == 13 ? 5.0 : 7.0,
                  alerta: (i == 13 || i == 5) ? .atencion : .ninguna)
        }
        let fc: [Double?] = (0..<20).map { i in i == 19 ? 72.0 : 58.0 }
        let temp: [Double?] = (0..<20).map { i in i >= 17 ? 0.9 : 0.1 }
        let resp: [Double?] = (0..<20).map { i in i >= 17 ? 17.0 : 14.0 }
        let estela: [Double] = [1.0, 1.1, 1.2, 1.3, 1.4]
        return MatrizHoyModel(
            bandas: [
                .full(MatrizSeccion(
                    id: "sleep", hue: LiquidColor.indigo,
                    titulo: "Sleep", valor: "5:00",
                    chartID: "matriz-sleep",
                    chart: .columnas(noches: noches, referencia: 7,
                                     referenciaTag: "7 h", dominio: 4...10))),
                .split(
                    izq: MatrizSeccion(
                        id: "rhr", hue: LiquidColor.rosa,
                        titulo: "Resting HR", valor: "72",
                        chartID: "matriz-rhr",
                        chart: .regla(puntos: fc, banda: 53...59, dominio: 45...80,
                                      alertaHoy: .atencion)),
                    der: MatrizSeccion(
                        id: "hrv", hue: LiquidColor.cian,
                        titulo: "HRV", valor: "38 ms",
                        chartID: "matriz-hrv",
                        chart: .lineaRellena(
                            puntos: (0..<20).map { _ in 38.0 as Double? },
                            base: 45, dominio: 20...80, alfa: 0.6, alertaHoy: .ninguna))),
                .full(MatrizSeccion(
                    id: "guardian", hue: LiquidColor.doradoTemp,
                    huesPar: (LiquidColor.doradoTemp, LiquidColor.azul),
                    titulo: "Guardian", valor: "",
                    chartID: "matriz-guardian",
                    chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                        dominio: -1...1, alertaHoy: .alarma),
                    chip: .init(texto: "Temperature and breathing off · 3rd night",
                                tono: .alarma),
                    renglones: [
                        MatrizRenglon(id: "skintemp", titulo: "Skin temp",
                                      valor: "+0.9°", hue: LiquidColor.doradoTemp,
                                      chartID: "matriz-guardian-temp",
                                      chart: .lineaSerena(puntos: temp, banda: -0.4...0.4,
                                                          dominio: -1...1, alertaHoy: .alarma),
                                      subrayado: .alarma),
                        MatrizRenglon(id: "resp", titulo: "Breathing",
                                      valor: "17.0", hue: LiquidColor.azul,
                                      chartID: "matriz-guardian-resp",
                                      chart: .lineaSerena(puntos: resp, banda: 12...16,
                                                          dominio: 8...22, alertaHoy: .alarma),
                                      subrayado: .alarma),
                    ])),
                .split(
                    izq: MatrizSeccion(
                        id: "carga", hue: LiquidColor.verdePrimario,
                        titulo: "Load", valor: "1.48", sublabel: "Building",
                        chartID: "matriz-carga",
                        chart: .colina(p: 1.48, zona: 0.8...1.3, estela: estela)),
                    der: MatrizSeccion(
                        id: "strain", hue: LiquidColor.teal,
                        titulo: "Effort", valor: "14.0",
                        chartID: "matriz-strain",
                        chart: .barrasMini(valores: (0..<14).map { Double(10 + $0) }))),
                .split(
                    izq: MatrizSeccion(
                        id: "stress", hue: LiquidColor.tinta500,
                        titulo: "Stress", valor: "High",
                        chartID: "matriz-stress",
                        chart: .escalerita(niveles: [0, 1, 1, 2, 2, 1, 2])),
                    der: MatrizSeccion(
                        id: "steps", hue: LiquidColor.tinta700,
                        titulo: "Steps", valor: "3 200",
                        chartID: "matriz-steps",
                        chart: .barrasMini(valores: (0..<14).map { Double(3000 + $0 * 50) }))),
            ])
    }
}

#Preview("Matriz · T1 bueno") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t1Bueno, onTapSeccion: { _ in })
}

#Preview("Matriz · T2 calibrando") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t2Calibrando, onTapSeccion: { _ in })
}

#Preview("Matriz · T3 alerta") {
    MatrizHoyFace(model: MatrizHoyFacePreviewData.t3Alerta, onTapSeccion: { _ in })
}
#endif
