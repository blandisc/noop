import SwiftUI

// MARK: - Liquid Glass · Hipnograma de la noche (épico hoja Liquid)
//
// La escalera de la noche: cada tramo de sueño es una CÁPSULA en el carril de su etapa
// (despierto arriba → profundo abajo), sobre cuatro guías tenues y bajo un eje de reloj.
// Es la firma visual del detalle de Sueño. Port de `Hypnogram.swift` (papel, §9.4) con su
// geometría EXACTA —22 pt de grosor, 4 carriles, eje de etapas de 60, franja de tiempo de
// 18, cinco marcas— y piel de tokens Liquid.
//
// Lo que NO se porta, a propósito:
// • El GLOW del REM (`.blur(6)` + `.blendMode(.plusLighter)`). El papel ya lo apagaba en
//   «Instrumento diurno» (`instrumentoFlat == true`, FER-131 · 03) y Liquid es un sistema
//   PLANO sobre papel cálido: el bloom solo ensucia el filo de la banda.
// • Los RISERS verticales entre bandas. Murieron en FER-610 (una reja de picas que competía
//   con el dato); Apple Health tampoco los dibuja. No vuelven.
//
// Contrato: los COLORES los manda el caller (`colores`) — la rampa de índigo vive en la capa
// app y este componente no conoce `LiquidColor.indigo`. Todos los strings llegan YA
// localizados (nombres de etapa, horas del eje, leyenda del vacío, VoiceOver). El ORDEN
// VERTICAL de los carriles, en cambio, lo fija el componente: es la gramática del
// hipnograma, no una decisión del caller.

public struct LiquidHipnograma: View {

    // MARK: - Vocabulario

    /// Las cuatro etapas de la noche. El carril de cada una es fijo (ver `ordenVertical`).
    public enum Etapa: Sendable, CaseIterable {
        case profundo, rem, ligero, despierto

        /// De ARRIBA a ABAJO: la gramática del hipnograma (paridad `SleepStage.bandRank`).
        /// Despierto arriba porque la noche se lee como una caída hacia lo profundo.
        static let ordenVertical: [Etapa] = [.despierto, .rem, .ligero, .profundo]

        /// Carril de la etapa: 0 = arriba (despierto) … 3 = abajo (profundo).
        var carril: Int {
            switch self {
            case .despierto: return 0
            case .rem:       return 1
            case .ligero:    return 2
            case .profundo:  return 3
            }
        }
    }

    /// Un tramo de la noche en una etapa. `fin <= inicio` = tramo de CERO minutos: no
    /// existe para esta gráfica (mismo criterio que `LiquidStageBar`, que filtra las etapas
    /// en 0 porque el fallback diario de Apple las fabrica).
    public struct Intervalo: Identifiable, Sendable {
        public let id = UUID()
        public let inicio: Date
        public let fin: Date
        public let etapa: Etapa

        public init(inicio: Date, fin: Date, etapa: Etapa) {
            self.inicio = inicio
            self.fin = fin
            self.etapa = etapa
        }

        /// Segundos MEDIDOS del tramo (nunca negativos).
        public var duracion: TimeInterval { Swift.max(0, fin.timeIntervalSince(inicio)) }
    }

    /// Una banda YA colocada: el rectángulo que ocupa en el lienzo + la etapa que la tiñe.
    /// Interna (no privada) a propósito: es lo que verifica el test en frío, sin montar la
    /// vista — el mismo patrón de `LiquidStageBar.visibles`.
    struct Banda: Identifiable {
        let id: UUID
        let etapa: Etapa
        let rect: CGRect
    }

    // MARK: - Entrada

    private let intervalos: [Intervalo]
    private let colores: [Etapa: Color]
    private let etiquetas: [Etapa: String]
    /// Las 5 horas del eje, YA formateadas. `nil` cae a rotular solo los extremos.
    private let horasEje: [String]?
    /// Qué decir del tramo bajo el dedo: («Profundo», «23:42–00:04 · 22 min»), YA formateado.
    /// Sin esto el scrub atenúa el 45 % de la noche y no dice nada a cambio — el papel sí
    /// mostraba etapa, rango horario y duración.
    private let textoTramo: ((Intervalo) -> (valor: String, detalle: String))?
    private let ejeInicio: String
    private let ejeFin: String
    private let vacio: String?
    private let alto: CGFloat
    private let a11yLabel: String
    private let a11yValue: String
    private let scrubFijo: Int?

    /// - Parameters:
    ///   - intervalos: los tramos de la noche, en cualquier orden (se ordenan por inicio).
    ///   - colores: la rampa por etapa. Es del CALLER: la identidad cromática del sueño vive
    ///     en la capa app. Una etapa sin color cae a `tinta10` — un tramo gris es honesto,
    ///     no dibujarlo sería perder una medición.
    ///   - etiquetas: nombres YA localizados del eje de etapas. Vacío = SIN eje de etapas
    ///     (el caller ya nombra las etapas en su leyenda).
    ///   - ejeInicio: hora YA formateada del inicio de la noche («23:38»).
    ///   - ejeFin: hora YA formateada del despertar («7:04»).
    ///   - horasEje: las CINCO horas del eje, YA formateadas. El papel rotulaba las 5; con
    ///     solo los extremos no se puede ubicar una banda en el tiempo y el eje deja de serlo.
    ///   - textoTramo: qué decir del tramo bajo el dedo («Profundo» / «23:42–00:04 · 22 min»).
    ///     Sin él el scrub atenúa el 45 % de la noche y no entrega nada a cambio — el papel
    ///     sí mostraba etapa, rango horario y duración.
    ///   - vacio: la leyenda de «no hubo noche», ya localizada. Sin ella, el track queda
    ///     vacío y mudo — nunca se inventa una noche.
    ///   - alto: alto del área de datos. 176 = lo que monta la hoja de Sueño.
    ///   - a11yLabel: cómo se llama la gráfica para VoiceOver.
    ///   - a11yValue: el RESUMEN de la noche (minutos por etapa). Obligatorio: es una
    ///     gráfica, y sin valor VoiceOver solo anunciaría un nombre sin dato.
    ///   - scrubFijo: SOLO previews/arnés — asienta el resaltado en un tramo VISIBLE (índice
    ///     sobre la lista ya filtrada y ordenada). En uso real manda el dedo.
    public init(intervalos: [Intervalo],
                colores: [Etapa: Color],
                etiquetas: [Etapa: String] = [:],
                ejeInicio: String,
                ejeFin: String,
                horasEje: [String]? = nil,
                textoTramo: ((Intervalo) -> (valor: String, detalle: String))? = nil,
                vacio: String? = nil,
                alto: CGFloat = 176,
                a11yLabel: String,
                a11yValue: String,
                scrubFijo: Int? = nil) {
        self.intervalos = intervalos
        self.colores = colores
        self.etiquetas = etiquetas
        self.ejeInicio = ejeInicio
        self.ejeFin = ejeFin
        self.horasEje = horasEje
        self.textoTramo = textoTramo
        self.vacio = vacio
        self.alto = alto
        self.a11yLabel = a11yLabel
        self.a11yValue = a11yValue
        self.scrubFijo = scrubFijo
    }

    /// La x del dedo mientras dura el scrub; `nil` en reposo.
    @State private var dedoX: CGFloat? = nil

    /// En tallas de accesibilidad el eje de etapas CEDE: 60 pt no sostienen un nombre en
    /// AX5 sin recortarlo, y el contrato prohíbe texto cortado. Los nombres siguen vivos en
    /// la leyenda del caller y en `a11yValue` — que escala sin tope.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    /// El vacío escala con Dynamic Type (FER-128 r11).
    @ScaledMetric(relativeTo: .footnote) private var cuerpoPt: CGFloat = LiquidType.cuerpoLecturaBase

    // MARK: - Geometría interna (del papel, verificada contra `Hypnogram.swift`)

    /// Grosor de cada banda. 22 fijo: la cápsula pesa igual toda la noche, así el ojo
    /// compara LARGOS (tiempo) y no áreas.
    private static let grosorBanda: CGFloat = 22
    /// Cuatro carriles, uno por etapa.
    private static let carriles: Int = 4
    /// Ancho MÍNIMO de una banda: por debajo de 2 pt un tramo real desaparecería del
    /// lienzo. Es el único punto donde el ancho deja de ser proporcional — y siempre a
    /// favor de que la medición se vea.
    private static let anchoMinimoBanda: CGFloat = 2
    /// Canaleta del eje de etapas.
    private let anchoEjeEtapas: CGFloat = 60
    /// Franja del eje de tiempo, BAJO el área de datos.
    private let altoEjeTiempo: CGFloat = 18
    /// Cinco marcas de reloj repartidas por el span (i/4).
    private let marcasEjeTiempo: Int = 5
    /// Alto y grosor de cada marca del eje.
    private let altoMarca: CGFloat = 4
    private let grosorMarca: CGFloat = 1
    /// Grosor de las guías de carril (1 pt, como el grid de `LiquidChartPlot`).
    private let grosorGuia: CGFloat = 1
    /// Caja fija de una etiqueta de reloj: se alinea hacia ADENTRO en los extremos para que
    /// ninguna hora se salga del lienzo.
    private let anchoCajaEtiqueta: CGFloat = 60
    /// Línea base de las etiquetas del eje (bajo las marcas).
    private let yEtiquetaEje: CGFloat = 12
    /// Opacidad de las bandas que NO están bajo el dedo. 0.45 es del papel: apaga lo demás
    /// sin borrarlo — la noche entera se sigue leyendo mientras exploras un tramo.
    /// (Sin token equivalente en `LiquidChart.*`; ver reporte FER-98.)
    private let alfaAtenuada: Double = 0.45

    /// El cursor del scrub —regla y anillo— habla con UNA sola tinta, para que se lean como
    /// una pieza y no como dos adornos.
    private var tintaCursor: Color {
        LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa)
    }

    // MARK: - Cuerpo

    public var body: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            if muestraEjeEtapas { ejeEtapas }
            VStack(spacing: LiquidSpace.s150) {
                lienzo
                ejeTiempo
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11yValue))
    }

    private var visibles: [Intervalo] { Self.visibles(intervalos) }

    private var muestraEjeEtapas: Bool {
        // A xxxLarge (el tope real de la app, FER-394) los rótulos salían «Despi…/Profu…»:
        // el eje se retira desde `.xxLarge`; la leyenda y VoiceOver siguen nombrando las etapas (r10).
        !etiquetas.isEmpty && tamanoTexto < .xxLarge
    }

    private var lienzo: some View {
        GeometryReader { geo in
            let bandas = Self.bandas(intervalos, en: geo.size)
            let activa = indiceActivo(en: geo.size)
            ZStack(alignment: .topLeading) {
                guias(geo.size)
                ForEach(Array(bandas.enumerated()), id: \.element.id) { i, banda in
                    let atenuada = activa != nil && activa != i
                    RoundedRectangle(cornerRadius: banda.rect.height / 2)
                        .fill(color(banda.etapa))
                        .frame(width: banda.rect.width, height: banda.rect.height)
                        .opacity(atenuada ? alfaAtenuada : 1)
                        .position(x: banda.rect.midX, y: banda.rect.midY)
                }
                if let i = activa, bandas.indices.contains(i) {
                    overlayScrub(bandas[i], alto: geo.size.height,
                                 ancho: geo.size.width, tramo: tramoVisible(i))
                }
                if bandas.isEmpty, let vacio {
                    Text(verbatim: vacio)
                        .font(.system(size: cuerpoPt))
                        .foregroundStyle(LiquidColor.tinta500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LiquidSpace.s400)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .contentShape(Rectangle())
            // `liquidScrubPan`, NO `scrubGesture`. Los dos existen y NO son intercambiables:
            // `scrubGesture` (`TrendChart.swift`) es un `highPriorityGesture(DragGesture(
            // minimumDistance: 0))` que le gana el toque al ScrollView y CONGELA el scroll de
            // la hoja mientras el dedo esté encima — exactamente el bug que FER-73 arregló.
            // `liquidScrubPan` no arranca si el dedo va vertical, así que se puede seguir
            // scrolleando la hoja pasando por encima del hipnograma.
            //
            // `LiquidBarrasDeuda` vive en la MISMA hoja de Sueño y usa este mismo gesto. Con
            // el otro, la página se congelaría sobre una banda de 176 pt y no sobre la de al
            // lado: la incoherencia se sentiría como un fallo, no como un modo.
            .liquidScrubPan(
                enabled: bandas.count > 1,
                onChange: { p in dedoX = p.x },
                onEnd: { dedoX = nil })
            // Háptica solo al CAER en un tramo nuevo, jamás al soltar (paridad `LiquidChartPlot`).
            .onChange(of: activa) { _, nuevo in if nuevo != nil { ChartHaptics.datumChanged() } }
        }
        .frame(height: alto)
    }

    /// Cuatro guías tenues, una por carril: un ancla quieta, no una retícula de reglas.
    /// `tinta10` ES `tinta900` al 10 % — el mismo peso que `LiquidChart.gridAlfa`.
    private func guias(_ size: CGSize) -> some View {
        ForEach(0..<Self.carriles, id: \.self) { carril in
            let y = Self.rowY(carril, alto: size.height)
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(LiquidColor.tinta10, lineWidth: grosorGuia)
        }
    }

    /// I2 · el scrub es una REGLA VERTICAL punteada que corta el lienzo + un anillo sobre la
    /// banda leída. El anillo va con `strokeBorder` (queda DENTRO de su caja, como los
    /// anillos de `LiquidChartPlot`); el papel trazaba la línea media.
    @ViewBuilder private func overlayScrub(_ banda: Banda, alto: CGFloat,
                                           ancho: CGFloat, tramo: Intervalo?) -> some View {
        let inflado = LiquidSpace.s150   // 6 pt de aire alrededor de la cápsula
        CrosshairRule(x: banda.rect.midX, height: alto, color: tintaCursor)
        RoundedRectangle(cornerRadius: (banda.rect.height + inflado) / 2)
            .strokeBorder(tintaCursor, lineWidth: LiquidChart.scrubAnilloBorde)
            .frame(width: banda.rect.width + inflado, height: banda.rect.height + inflado)
            .position(x: banda.rect.midX, y: banda.rect.midY)
            .allowsHitTesting(false)
        // Qué es el tramo que estás tocando. Sin esto el scrub atenúa el 45 % de la noche y
        // no entrega nada a cambio: el papel sí decía etapa, rango horario y duración, y su
        // vecina de hoja (`LiquidBarrasDeuda`) lo dice también. Misma pieza de la familia.
        if let textoTramo, let tramo {
            let t = textoTramo(tramo)
            let tam: CGSize = popupMedido == .zero ? CGSize(width: 96, height: 34) : popupMedido
            let p = ChartTooltipPlacement.positionBeside(
                anchor: CGPoint(x: banda.rect.midX, y: LiquidSpace.s200),
                tooltipSize: tam,
                in: CGSize(width: ancho, height: alto),
                gap: LiquidSpace.s200)
            LiquidScrubPopup(valor: t.valor, fecha: t.detalle, color: color(banda.etapa))
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { popupMedido = g.size }
                            .onChange(of: g.size) { _, nuevo in popupMedido = nuevo }
                    }
                }
                .position(x: p.x, y: p.y)
                .allowsHitTesting(false)
        }
    }

    /// El intervalo detrás de la banda `i` (las bandas salen de la lista YA filtrada y
    /// ordenada, así que el índice es el mismo).
    private func tramoVisible(_ i: Int) -> Intervalo? {
        let visibles = Self.visibles(intervalos)
        return visibles.indices.contains(i) ? visibles[i] : nil
    }

    /// Medida del popup, para colocarlo sin que se salga del lienzo (patrón `LiquidBarrasDeuda`).
    @State private var popupMedido: CGSize = .zero

    /// Los nombres de las etapas, uno por carril, pegados al lienzo. Cada uno ocupa un cuarto
    /// del alto, así que su línea base cae en el centro de su guía.
    private var ejeEtapas: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(Etapa.ordenVertical, id: \.self) { etapa in
                Text(verbatim: etiquetas[etapa] ?? "")
                    .font(LiquidType.microEstado)
                    // Un paso MÁS oscuro que las horas: el nombre del carril manda sobre el
                    // reloj (misma jerarquía de dos pasos del papel).
                    .foregroundStyle(LiquidColor.tinta700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(width: anchoEjeEtapas, height: alto)
    }

    /// Cinco marcas repartidas por el span. SOLO los extremos llevan hora: el caller manda
    /// «23:38» y «7:04» ya formateadas, y el sistema de diseño no inventa las horas
    /// intermedias (no conoce el locale ni el reloj de 12/24 h del producto). Las tres
    /// marcas de en medio son la regla que hace legible el reparto del tiempo.
    ///
    /// La franja se reserva SIEMPRE, aunque no haya noche: si apareciera solo con datos, la
    /// hoja brincaría 24 pt al cargar.
    private var ejeTiempo: some View {
        GeometryReader { geo in
            if !visibles.isEmpty {
                ForEach(0..<marcasEjeTiempo, id: \.self) { i in
                    let x = CGFloat(i) / CGFloat(marcasEjeTiempo - 1) * geo.size.width
                    Rectangle()
                        .fill(LiquidColor.tinta500)
                        .frame(width: grosorMarca, height: altoMarca)
                        .position(x: x, y: altoMarca / 2)
                    if let hora = horaDeMarca(i) {
                        let primera = i == 0
                        Text(verbatim: hora)
                            .font(LiquidType.unidadCompacta)
                            .monospacedDigit()
                            .foregroundStyle(LiquidColor.tinta500)
                            .lineLimit(1)
                            // Caja fija alineada hacia ADENTRO: la hora se lee desde el
                            // borde del lienzo en vez de recortarse contra él.
                            .frame(width: anchoCajaEtiqueta, alignment: primera ? .leading : .trailing)
                            .position(x: primera ? x + anchoCajaEtiqueta / 2 : x - anchoCajaEtiqueta / 2,
                                      y: yEtiquetaEje)
                    }
                }
            }
        }
        .frame(height: altoEjeTiempo)
    }

    /// El rótulo de la marca `i`. Si el caller mandó las 5 horas (como el papel), se usan;
    /// si solo mandó inicio y fin, se rotulan los extremos. El papel dibujaba las 5 y sin
    /// ellas no se puede ubicar una banda en el tiempo: el eje deja de ser eje.
    private func horaDeMarca(_ i: Int) -> String? {
        if let horas = horasEje, horas.indices.contains(i) { return horas[i] }
        if i == 0 { return ejeInicio }
        if i == marcasEjeTiempo - 1 { return ejeFin }
        return nil
    }

    /// Una etapa sin color declarado se pinta en tinta quieta: perder la banda sería perder
    /// una medición.
    private func color(_ etapa: Etapa) -> Color {
        colores[etapa] ?? LiquidColor.tinta10
    }

    /// El tramo bajo el dedo; en reposo, el que fijó el arnés (o ninguno).
    private func indiceActivo(en size: CGSize) -> Int? {
        if let dedoX { return Self.indice(atX: dedoX, en: size, intervalos: intervalos) }
        guard let fijo = scrubFijo, visibles.indices.contains(fijo) else { return nil }
        return fijo
    }

    // MARK: - Geometría pura (lo que verifican los tests, sin montar la vista)

    /// Los tramos que EXISTEN, ordenados por inicio. Un tramo de 0 minutos no se dibuja: el
    /// fallback diario de Apple fabrica etapas en 0 y dibujarlas insinuaría una medición que
    /// nunca ocurrió. El filtro es UNO solo para bandas, scrub y conteos.
    /// Las CINCO horas del eje, repartidas por el span REAL de la noche.
    ///
    /// Vive aquí y no en el caller porque usa `visibles` + `ventana`, que son internos: la
    /// pantalla las estaba reimplementando («el MISMO criterio… que es interno al paquete»,
    /// decía su propio comentario), y si las dos versiones divergían el eje rotulaba horas
    /// que la gráfica no dibuja. El caller solo dice CÓMO se escribe una hora.
    public static func horasDelEje(_ intervalos: [Intervalo],
                                   formato: (Date) -> String) -> [String]? {
        let vis = visibles(intervalos)
        guard let v = ventana(vis) else { return nil }
        return (0..<5).map { i in
            formato(v.origen.addingTimeInterval(v.span * Double(i) / 4))
        }
    }

    static func visibles(_ intervalos: [Intervalo]) -> [Intervalo] {
        intervalos.filter { $0.duracion > 0 }.sorted { $0.inicio < $1.inicio }
    }

    /// Origen y span de la noche (`nil` si no hubo noche). El span se piso-guarda en 1 s
    /// para no dividir entre cero.
    static func ventana(_ visibles: [Intervalo]) -> (origen: Date, span: TimeInterval)? {
        guard let primero = visibles.first else { return nil }
        let ultimo = visibles.map(\.fin).max() ?? primero.fin
        return (primero.inicio, Swift.max(1, ultimo.timeIntervalSince(primero.inicio)))
    }

    /// Centro vertical del carril `rank`: cuartos del alto (12.5 / 37.5 / 62.5 / 87.5 %).
    static func rowY(_ carril: Int, alto: CGFloat) -> CGFloat {
        (alto / CGFloat(carriles)) * (CGFloat(carril) + 0.5)
    }

    /// Las bandas colocadas sobre un lienzo: x ∝ tiempo, y = carril de la etapa, alto fijo.
    /// Filtra internamente, así que bandas, scrub y test cuentan exactamente lo mismo.
    static func bandas(_ intervalos: [Intervalo], en size: CGSize) -> [Banda] {
        let tramos = visibles(intervalos)
        guard let (origen, span) = ventana(tramos) else { return [] }
        return tramos.map { tramo in
            let x0 = CGFloat(tramo.inicio.timeIntervalSince(origen) / span) * size.width
            let x1 = CGFloat(tramo.fin.timeIntervalSince(origen) / span) * size.width
            let y = rowY(tramo.etapa.carril, alto: size.height)
            return Banda(id: tramo.id,
                         etapa: tramo.etapa,
                         rect: CGRect(x: x0,
                                      y: y - grosorBanda / 2,
                                      width: Swift.max(anchoMinimoBanda, x1 - x0),
                                      height: grosorBanda))
        }
    }

    /// El tramo que toca una x local: primero por CONTENCIÓN exacta (el dedo cayó dentro de
    /// sus minutos) y, si el dedo cayó en un hueco de la noche, por cercanía al centro
    /// temporal del tramo. El índice es sobre la lista YA filtrada y ordenada.
    static func indice(atX x: CGFloat, en size: CGSize, intervalos: [Intervalo]) -> Int? {
        let tramos = visibles(intervalos)
        guard !tramos.isEmpty, size.width > 0,
              let (origen, span) = ventana(tramos) else { return nil }
        let t = origen.addingTimeInterval(Double(x / size.width) * span)
        if let i = tramos.firstIndex(where: { $0.inicio <= t && t <= $0.fin }) { return i }
        return tramos.indices.min { a, b in
            abs(centro(tramos[a]).timeIntervalSince(t)) < abs(centro(tramos[b]).timeIntervalSince(t))
        }
    }

    private static func centro(_ tramo: Intervalo) -> Date {
        tramo.inicio.addingTimeInterval(tramo.duracion / 2)
    }
}

#if DEBUG
/// La rampa del caller: índigo graduado por opacidad para las tres etapas dormidas y tinta
/// quieta para despierto (paridad `LiquidStageBar`). El componente no la conoce.
private func coloresDemo() -> [LiquidHipnograma.Etapa: Color] {
    [.profundo: LiquidColor.indigo,
     .rem: LiquidColor.indigo.opacity(0.78),    // token-exempt: rampa graduada de etapas
     .ligero: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
     .despierto: LiquidColor.tinta10]
}

private func etiquetasDemo() -> [LiquidHipnograma.Etapa: String] {
    [.despierto: "Despierto", .rem: "REM", .ligero: "Ligero", .profundo: "Profundo"]
}

/// Arma una noche a partir de (etapa, minutos), arrancando a las 23:18.
private func nocheDemo(_ tramos: [(LiquidHipnograma.Etapa, Double)]) -> [LiquidHipnograma.Intervalo] {
    var t = Calendar.current.date(bySettingHour: 23, minute: 18, second: 0, of: Date()) ?? Date()
    var salida: [LiquidHipnograma.Intervalo] = []
    for (etapa, minutos) in tramos {
        let fin = t.addingTimeInterval(minutos * 60)
        salida.append(.init(inicio: t, fin: fin, etapa: etapa))
        t = fin
    }
    return salida
}

private func nocheCompleta() -> [LiquidHipnograma.Intervalo] {
    nocheDemo([
        (.despierto, 6), (.ligero, 22), (.profundo, 38), (.ligero, 18), (.rem, 24),
        (.ligero, 14), (.profundo, 30), (.rem, 28), (.ligero, 20), (.despierto, 4),
        (.rem, 32), (.ligero, 26), (.despierto, 8),
    ])
}

#Preview("Hipnograma · noche completa") {
    LiquidHipnograma(intervalos: nocheCompleta(),
                     colores: coloresDemo(),
                     etiquetas: etiquetasDemo(),
                     ejeInicio: "23:18",
                     ejeFin: "7:08",
                     a11yLabel: "Anoche, por etapas",
                     a11yValue: "Profundo 1:08, REM 1:24, Ligero 1:40, Despierto 0:18")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

/// Noche rota: muchos despertares cortos. Es el caso que prueba el ancho mínimo de banda —
/// un tramo de 2 minutos sigue viéndose en vez de desaparecer.
#Preview("Hipnograma · noche fragmentada") {
    LiquidHipnograma(intervalos: nocheDemo([
        (.despierto, 12), (.ligero, 18), (.despierto, 4), (.ligero, 9), (.despierto, 6),
        (.rem, 11), (.despierto, 3), (.ligero, 14), (.profundo, 12), (.despierto, 7),
        (.ligero, 8), (.rem, 6), (.despierto, 2), (.ligero, 16), (.despierto, 9),
        (.rem, 13), (.despierto, 5), (.ligero, 21), (.despierto, 11),
    ]),
                     colores: coloresDemo(),
                     etiquetas: etiquetasDemo(),
                     ejeInicio: "0:41",
                     ejeFin: "3:58",
                     a11yLabel: "Anoche, por etapas",
                     a11yValue: "Profundo 0:12, REM 0:30, Ligero 1:26, Despierto 0:59")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

/// El estado HONESTO: los carriles vacíos y la leyenda del caller. Ni una banda inventada,
/// ni horas en el eje que nadie pueda respaldar — pero la franja del eje sigue reservada,
/// así que la hoja no brinca cuando por fin haya noche.
#Preview("Hipnograma · sin datos") {
    LiquidHipnograma(intervalos: [],
                     colores: coloresDemo(),
                     etiquetas: etiquetasDemo(),
                     ejeInicio: "",
                     ejeFin: "",
                     vacio: "Anoche no se midió el sueño.",
                     a11yLabel: "Anoche, por etapas",
                     a11yValue: "Sin datos")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

/// El estado LEÍDO (lo que ves con el dedo encima): regla punteada, anillo sobre la banda y
/// el resto de la noche atenuada al 45 %.
#Preview("Hipnograma · scrub") {
    LiquidHipnograma(intervalos: nocheCompleta(),
                     colores: coloresDemo(),
                     etiquetas: etiquetasDemo(),
                     ejeInicio: "23:18",
                     ejeFin: "7:08",
                     a11yLabel: "Anoche, por etapas",
                     a11yValue: "Profundo 1:08, REM 1:24, Ligero 1:40, Despierto 0:18",
                     scrubFijo: 6)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

/// Talla de accesibilidad: el eje de etapas CEDE (60 pt no sostienen «Despierto» en AX3 sin
/// recortarlo) y el lienzo se queda con todo el ancho. Los nombres siguen en la leyenda del
/// caller y en `accessibilityValue`.
#Preview("Hipnograma · AX") {
    LiquidHipnograma(intervalos: nocheCompleta(),
                     colores: coloresDemo(),
                     etiquetas: etiquetasDemo(),
                     ejeInicio: "23:18",
                     ejeFin: "7:08",
                     a11yLabel: "Anoche, por etapas",
                     a11yValue: "Profundo 1:08, REM 1:24, Ligero 1:40, Despierto 0:18")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
