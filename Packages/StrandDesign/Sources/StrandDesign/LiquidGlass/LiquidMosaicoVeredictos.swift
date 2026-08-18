import SwiftUI

// MARK: - Liquid Glass · Mosaico de veredictos (FER-119, «Preparación»)
//
// Las últimas 30 mañanas de un veredicto CATEGÓRICO, en una retícula densa de calendario más
// el reparto de sus peldaños. Es el dominante de la pantalla de Preparación.
//
// POR QUÉ NO ES `LiquidCalendario90`: aquella pieza dimensiona la celda con `columnasFijas = 14`
// horneado en la fórmula (`:170`, `:211-216`) — con 30 días la retícula sale a un tercio del
// ancho. Y su dato es una `intensidad: Double?` continua: un veredicto de 4 estados tendría que
// disfrazarse de número para entrar. Comparten los DOS contratos de accesibilidad (abajo) y la
// receta visual; no comparten anatomía.
//
// POR QUÉ LOS CUATRO PELDAÑOS PESAN IGUAL: tipografía, tamaño, peso y padding son IDÉNTICOS en
// los cuatro renglones; lo único que los distingue es su pip. Darle a «todo en rango» color o
// tamaño propios reintroduciría por la puerta lateral la psicología que el requerimiento prohíbe
// (proteger el número verde).
//
// EL ORDEN NO ES UN RANKING, ES LA ESCALA DEL MOTOR: 0 ejes fuera → 1 → 2 o más → sin lectura.
// Es la misma variable ordinal que el motor calcula, en su orden natural, como la leyenda de
// cualquier escala. (Una revisión adversarial señaló con razón que este comentario antes decía
// que no había «primer lugar» cuando el verde siempre va primero: la afirmación era falsa. Lo
// que se sostiene es la equivalencia visual, y el orden se declara por lo que es.)
//
// LA REJILLA ES DENSA, LA SERIE ES DISPERSA: quien llama construye 30 claves de calendario y
// busca cada una en su diccionario (patrón `dayKeys`, `LiquidHoyBuilder+Matriz.swift:623-630`).
// Un día sin fila NO existe en la serie del motor: es una ausencia, no un `nil`. Por eso la
// pieza recibe SIEMPRE `[Dia?]` ya densa y su denominador es `dias.count`, nunca los que traen
// veredicto — «8 de 22» cuando la ventana son 30 es el defecto silencioso que esto evita.

/// Las últimas N mañanas de un veredicto categórico: retícula densa + reparto de peldaños.
public struct LiquidMosaicoVeredictos: View {

    /// Un peldaño del veredicto: su color, su etiqueta neutra y su pip en la retícula.
    public struct Peldano: Identifiable, Sendable, Equatable {
        public let id: String
        public let color: Color
        /// La etiqueta NEUTRA, en tercera persona, ya localizada. Nunca el consejo de hoy:
        /// «Hoy ve leve» sobre un día de hace tres semanas se contradice a sí mismo.
        public let etiqueta: String

        public init(id: String, color: Color, etiqueta: String) {
            self.id = id
            self.color = color
            self.etiqueta = etiqueta
        }
    }

    /// Un día de la ventana. `nil` en el arreglo denso = ese día no tuvo ni fila.
    public struct Dia: Identifiable, Sendable, Equatable {
        public let id: String
        public let fecha: Date
        /// El `id` de su peldaño. `nil` = hubo fila pero sin veredicto legible.
        public let peldano: String?
        /// Lo que se lee al tocarlo, ya localizado («Lun 4 · una señal fuera»).
        public let etiqueta: String

        public init(id: String, fecha: Date, peldano: String?, etiqueta: String) {
            self.id = id
            self.fecha = fecha
            self.peldano = peldano
            self.etiqueta = etiqueta
        }
    }

    private let dias: [Dia?]
    private let peldanos: [Peldano]
    private let conteos: [String: Int]
    private let unidadDias: (Int) -> String
    private let inicialesDia: [String]
    private let a11yLabel: String
    private let a11yConteo: (Int, Int) -> String
    private let pistaVacia: String?
    @Binding private var seleccion: String?

    /// La lectura y la leyenda se APILAN en tallas de accesibilidad en vez de recortarse
    /// (la retícula es chrome geométrico y no escala — mismo contrato que `LiquidCalendario90`).
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchoMedido: CGFloat = 0

    /// - Parameters:
    ///   - dias: la ventana YA DENSA, un hueco por día de calendario, del más viejo al más nuevo.
    ///   - peldanos: los estados a decodificar, en el orden en que se pintan.
    ///   - conteos: días por `peldano.id`. Los que faltan cuentan 0.
    ///   - unidadDias: compone «5 días» / «1 día», ya localizado.
    ///   - a11yConteo: compone «24 de 30» para VoiceOver.
    public init(dias: [Dia?],
                peldanos: [Peldano],
                conteos: [String: Int],
                seleccion: Binding<String?>,
                unidadDias: @escaping (Int) -> String,
                a11yLabel: String,
                a11yConteo: @escaping (Int, Int) -> String,
                inicialesDia: [String] = LiquidCalendario90.inicialesPorLocale(),
                pistaVacia: String? = nil) {
        self.dias = dias
        self.peldanos = peldanos
        self.conteos = conteos
        self._seleccion = seleccion
        self.unidadDias = unidadDias
        self.a11yLabel = a11yLabel
        self.a11yConteo = a11yConteo
        self.inicialesDia = inicialesDia
        self.pistaVacia = pistaVacia
    }

    // MARK: - Geometría

    /// Columnas fijas: una semana. A diferencia de `LiquidCalendario90` (14, por su ventana de
    /// 90), aquí 7 columnas × ~5 filas llenan el ancho con celdas que se pueden tocar.
    private static let columnas: Int = 7
    private static let gap: CGFloat = LiquidSpace.s100
    private static let celdaSemilla: CGFloat = 28
    /// Radio de la celda — 5, el mismo que `LiquidCalendario90.radioCelda` y por la misma razón:
    /// no es `LiquidRadius.control` (12), que a este tamaño convertiría la celda en un círculo.
    private static let radioCelda: CGFloat = 5
    /// Radio del pip del reparto — 3: es un cuadro pequeño, no una pastilla.
    private static let radioPip: CGFloat = 3

    /// Sin viaje con Reduce Motion; si no, la misma curva de salida que la pieza hermana.
    private var animacion: Animation? {
        reduceMotion ? nil : LiquidMotion.glassOut(LiquidMotion.quick)
    }

    /// El lado que hace que 7 columnas llenen `ancho` (misma fórmula que la pieza hermana).
    private var celda: CGFloat {
        guard anchoMedido > 0 else { return Self.celdaSemilla }
        let cols = CGFloat(Self.columnas)
        return max(12, (anchoMedido - Self.gap * (cols - 1)) / cols)
    }

    // MARK: - Contratos puros (los mismos que leen la vista, VoiceOver y las pruebas)

    /// Cuántos días traen veredicto, de cuántos hay en la ventana. El denominador es la
    /// VENTANA — un día sin fila cuenta en el total, o el mosaico miente sobre su cobertura.
    public static func conteo(_ dias: [Dia?]) -> (conDato: Int, total: Int) {
        (dias.reduce(0) { $0 + ($1?.peldano == nil ? 0 : 1) }, dias.count)
    }

    /// Lo que dicta VoiceOver: el conteo y, si hay un día tocado, su etiqueta.
    public static func a11yValor(dias: [Dia?], seleccion: String?,
                                 conteo formato: (Int, Int) -> String) -> String {
        let c = conteo(dias)
        let base = formato(c.conDato, c.total)
        guard let id = seleccion,
              let dia = dias.compactMap({ $0 }).first(where: { $0.id == id }) else { return base }
        return base + ", " + dia.etiqueta
    }

    /// Tocar un día lo selecciona; re-tocarlo lo suelta.
    public static func alterna(seleccion actual: String?, toca id: String) -> String? {
        actual == id ? nil : id
    }

    /// El vecino CON veredicto en la dirección dada — el gesto de ajuste no se detiene en huecos.
    public static func vecino(dias: [Dia?], desde: String?, paso: Int) -> String? {
        let legibles = dias.compactMap { $0 }.filter { $0.peldano != nil }
        guard !legibles.isEmpty else { return nil }
        guard let actual = desde, let i = legibles.firstIndex(where: { $0.id == actual }) else {
            return paso > 0 ? legibles.first?.id : legibles.last?.id
        }
        let j = min(max(i + paso, 0), legibles.count - 1)
        return legibles[j].id
    }

    private func color(_ peldanoID: String?) -> Color {
        guard let peldanoID, let p = peldanos.first(where: { $0.id == peldanoID }) else {
            return LiquidColor.celdaVacia
        }
        return p.color
    }

    // MARK: - Cuerpo

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            reticula
            lectura
            reparto
        }
    }

    private var reticula: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: Self.gap) {
                ForEach(Array(inicialesDia.enumerated()), id: \.offset) { _, inicial in
                    Text(inicial)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(width: celda)
                }
            }
            .accessibilityHidden(true)

            let filas = stride(from: 0, to: dias.count, by: Self.columnas).map { inicio in
                Array(dias[inicio..<min(inicio + Self.columnas, dias.count)])
            }
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(Array(filas.enumerated()), id: \.offset) { _, fila in
                    HStack(spacing: Self.gap) {
                        ForEach(Array(fila.enumerated()), id: \.offset) { _, dia in
                            celdaVista(dia)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // La medición cuelga de la caja que ocupa TODO el ancho, no de la retícula ya
        // dimensionada — si midiera la retícula, la celda se realimentaría a sí misma.
        .background(GeometryReader { g in
            Color.clear.preference(key: LiquidMosaicoAnchoKey.self, value: g.size.width)
        })
        .onPreferenceChange(LiquidMosaicoAnchoKey.self) { anchoMedido = $0 }
        // 30 celdas son 30 paradas de VoiceOver: se colapsan en UNA, con el conteo honesto
        // como valor y el gesto de ajuste caminando los días que sí tienen veredicto.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: Self.a11yValor(dias: dias, seleccion: seleccion,
                                                          conteo: a11yConteo)))
        .accessibilityAdjustableAction { direccion in
            switch direccion {
            case .increment: seleccion = Self.vecino(dias: dias, desde: seleccion, paso: 1)
            case .decrement: seleccion = Self.vecino(dias: dias, desde: seleccion, paso: -1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func celdaVista(_ dia: Dia?) -> some View {
        let tocado = dia != nil && dia?.id == seleccion
        RoundedRectangle(cornerRadius: Self.radioCelda)
            .fill(color(dia?.peldano))
            .frame(width: celda, height: celda)
            .overlay {
                if tocado {
                    RoundedRectangle(cornerRadius: Self.radioCelda)
                        .strokeBorder(LiquidColor.tinta900, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard let dia, dia.peldano != nil else { return }
                let nueva = Self.alterna(seleccion: seleccion, toca: dia.id)
                withAnimation(animacion) { seleccion = nueva }
            }
    }

    /// La lectura del día tocado, o la pista que invita a tocar.
    @ViewBuilder
    private var lectura: some View {
        if let id = seleccion,
           let dia = dias.compactMap({ $0 }).first(where: { $0.id == id }) {
            Text(dia.etiqueta)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta900)
                .accessibilityHidden(true)
        } else if let pistaVacia {
            Text(pistaVacia)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityHidden(true)
        }
    }

    /// El reparto: los cuatro peldaños, TODOS con el mismo peso visual.
    private var reparto: some View {
        VStack(spacing: 0) {
            ForEach(Array(peldanos.enumerated()), id: \.element.id) { i, p in
                if i > 0 { LiquidCapilar(eje: .horizontal) }
                renglon(p)
            }
        }
    }

    @ViewBuilder
    private func renglon(_ p: Peldano) -> some View {
        let n = conteos[p.id] ?? 0
        // A tallas de accesibilidad la etiqueta y su conteo se apilan en vez de truncarse.
        let apilado = tamanoTexto.isAccessibilitySize
        let pip = RoundedRectangle(cornerRadius: Self.radioPip)
            .fill(p.color)
            .frame(width: LiquidSpace.s250, height: LiquidSpace.s250)
        Group {
            if apilado {
                VStack(alignment: .leading, spacing: LiquidSpace.s075) {
                    HStack(spacing: LiquidSpace.s250) {
                        pip
                        Text(p.etiqueta).font(LiquidType.cuerpo)
                            .foregroundStyle(LiquidColor.tinta900)
                    }
                    Text(unidadDias(n)).font(LiquidType.valorM)
                        .foregroundStyle(LiquidColor.tinta900)
                }
            } else {
                HStack(spacing: LiquidSpace.s250) {
                    pip
                    Text(p.etiqueta).font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta900)
                    Spacer(minLength: LiquidSpace.s250)
                    Text(unidadDias(n)).font(LiquidType.valorM)
                        .foregroundStyle(LiquidColor.tinta900)
                }
            }
        }
        .padding(.vertical, LiquidSpace.s225)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// El ancho medido de la retícula. Propio de esta pieza: el de `LiquidCalendario90` es privado
/// de aquel archivo, y compartir la llave haría que dos retículas en la misma pantalla se
/// pisaran la medición.
private struct LiquidMosaicoAnchoKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
private func mosaicoDemo() -> [LiquidMosaicoVeredictos.Dia?] {
    let cal = Calendar(identifier: .gregorian)
    let hoy = Date(timeIntervalSince1970: 1_755_000_000)
    let patron: [String?] = [nil, nil, "full", "full", "caution", "full", "full",
                            "full", nil, "full", "caution", "easy", "easy", "caution",
                            "full", "full", "full", nil, nil, "full", "full",
                            "caution", "full", "full", "full", nil, "caution", "full",
                            "full", "full"]
    return patron.enumerated().map { i, p in
        let f = cal.date(byAdding: .day, value: i - 29, to: hoy) ?? hoy
        guard let p else { return nil }
        return .init(id: "d\(i)", fecha: f, peldano: p, etiqueta: "Día \(i + 1) · \(p)")
    }
}

private let mosaicoPeldanos: [LiquidMosaicoVeredictos.Peldano] = [
    .init(id: "full", color: LiquidColor.verdePrimario, etiqueta: "Todo en rango"),
    .init(id: "caution", color: LiquidColor.atencion, etiqueta: "Una señal fuera"),
    .init(id: "easy", color: LiquidColor.negativo, etiqueta: "Dos o más fuera"),
    .init(id: "none", color: LiquidColor.celdaVaciaPip, etiqueta: "Sin lectura"),
]

private struct MosaicoDemo: View {
    @State private var sel: String?
    var body: some View {
        ScrollView {
            LiquidMosaicoVeredictos(
                dias: mosaicoDemo(),
                peldanos: mosaicoPeldanos,
                conteos: ["full": 15, "caution": 5, "easy": 2, "none": 8],
                seleccion: $sel,
                unidadDias: { "\($0) días" },
                a11yLabel: "Tus 30 mañanas",
                a11yConteo: { "\($0) de \($1)" },
                pistaVacia: "Toca un día para ver su lectura.")
            .liquidSeccion()
        }
        .background(LiquidColor.fondoGradient)
    }
}

#Preview("Liquid · Mosaico de veredictos") { MosaicoDemo() }

/// El segundo contrato del archivo: a tallas de accesibilidad la lectura y el reparto se
/// APILAN en vez de recortarse; la retícula es chrome geométrico y no escala.
#Preview("Liquid · Mosaico · accessibility3") {
    MosaicoDemo().environment(\.dynamicTypeSize, .accessibility3)
}
#endif
