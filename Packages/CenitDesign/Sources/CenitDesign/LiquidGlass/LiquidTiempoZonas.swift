import SwiftUI

// MARK: - Liquid Glass · Tiempo en zonas de pulso (FER-99)
//
// «Tiempo en zonas · hoy»: cuánto del día viviste en cada zona de frecuencia cardiaca.
// Port del bloque que `MetricDetailScreen.hrZonesBlockContent` (FER-253) dibujaba A MANO —
// una barra apilada de 6 segmentos (alto 10, capsule) más una leyenda debajo— a tokens
// Liquid puros. El cálculo que lo alimenta (`computeZoneMinutesDetached`) sigue viviendo en
// la capa app y entrega SIEMPRE 6 valores: `[reposo, Z1, Z2, Z3, Z4, Z5]`, índice 0 = por
// debajo de Zona 1.
//
// El port ARREGLA el pecado del original: la leyenda de papel filtraba `mins[i] >= 1`, así
// que una zona sin minutos desaparecía de la pantalla y el día se leía como si esa zona no
// existiera. Aquí **las 6 zonas se dibujan siempre**: la que quedó en cero se ve como su
// riel VACÍO junto a su etiqueta, que es la única forma honesta de decir «ahí no estuviste».
//
// La proporción es sobre el TOTAL del día, no sobre la zona más alta: por eso el reposo
// suele comerse casi toda la barra, y eso es exactamente lo que hay que ver.
//
// El color es identidad de señal y vive SOLO en el dato (segmentos y rieles); el texto es
// tinta quieta. La rampa de zona la manda el CALLER (el DS no conoce zonas de pulso ni sabe
// que Z5 va más oscura que Z1) — misma regla que `LiquidStageBar` con las etapas del sueño.
//
// Contrato: strings YA localizados y formateados por el caller («Reposo», «Zona 3 · moderada»,
// «120–140 lpm»). El componente no trae marco propio: lo enmarca la sección que lo contiene,
// igual que hacía el `SeccionBloque` de la pantalla de papel.

public struct LiquidTiempoZonas: View {

    /// Una zona del día: su lugar en la rampa (`id` 0…5, 0 = reposo), su etiqueta ya
    /// localizada, los minutos que la proporción usa, su color y —opcional— un detalle
    /// ya formateado (el rango en lpm, «120–140 lpm»).
    public struct Zona: Identifiable, Sendable {
        public let id: Int
        public let etiqueta: String
        /// Minutos en la zona. **`nil` = el día no se midió**, que no es lo mismo que estar
        /// cero minutos en esa zona. Sin medición el riel queda vacío y la voz lo dice; con
        /// `0` la zona se dibuja presente en su base, porque «no estuviste aquí» es un dato.
        public let minutos: Double?
        public let color: Color
        public let detalle: String?

        public init(id: Int, etiqueta: String, minutos: Double?, color: Color,
                    detalle: String? = nil) {
            self.id = id
            self.etiqueta = etiqueta
            self.minutos = minutos
            self.color = color
            self.detalle = detalle
        }
    }

    /// Una zona con su parte del total del día (0…1). Es el ÚNICO reparto: la barra, la
    /// leyenda y VoiceOver leen de aquí, para que los tres cuenten exactamente lo mismo.
    struct Parte: Identifiable {
        let zona: Zona
        let fraccion: Double
        var id: Int { zona.id }
    }

    private let zonas: [Zona]
    private let etiquetaVoz: String
    private let valorVoz: String
    /// Lo que dicta VoiceOver cuando el día NO se midió. Llega del caller porque es copy.
    /// Sin este parámetro el estado «sin medir» dictaba una cadena vacía — el estado que la
    /// pieza existe para distinguir, mudo.
    private let vozSinMedicion: String

    /// La leyenda de 6 filas no cabe en tres columnas cuando el texto crece: en tamaños de
    /// accesibilidad cada fila se apila (nombre + detalle arriba, riel completo debajo).
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// Alto de la barra apilada — geometría interna: paridad EXACTA con el bloque de papel
    /// (`hrZonesBlockContent` traza `.frame(height: 10)`).
    private let altoBarra: CGFloat = 10

    /// Alto del riel de cada fila de la leyenda. Más delgado que la barra a propósito: la
    /// barra es el resumen del día, el riel es el detalle que la desglosa.
    private let altoRiel: CGFloat = 6

    /// Separación entre filas de la leyenda — paridad con el `VStack(spacing: 7)` del papel.
    /// No es un token de espacio: es la densidad del instrumento (mismo criterio que el
    /// `gap: 3` de `LiquidZoneMeter`).
    private let filaGap: CGFloat = 7

    /// Ancho mínimo del riel: con etiquetas largas («Zona 3 · moderada» + «120–140 lpm») el
    /// `HStack` le comía el ancho al riel hasta volverlo invisible, y el riel es el dato.
    private let rielMinimo: CGFloat = 56
    /// Ancho mínimo del relleno de una zona CON minutos. Mismo patrón que el par
    /// `altoHueco`/`altoMinimo` de `LiquidBarrasHora`: una lectura real nunca se vuelve
    /// invisible por ser pequeña.
    static let astillaMinima: CGFloat = 3
    /// Alfa de la marca de «cero medido»: presente, pero claramente por debajo de una lectura
    /// real. No compite con las astillas.
    private let marcaCeroAlfa: Double = 0.35

    public init(zonas: [Zona], a11yLabel: String, a11yValue: String,
                a11ySinMedicion: String = "") {
        self.vozSinMedicion = a11ySinMedicion
        self.zonas = zonas
        self.etiquetaVoz = a11yLabel
        self.valorVoz = a11yValue
    }

    /// El reparto sobre el TOTAL del día (no sobre la zona más alta), con la división
    /// blindada: un día sin minutos (total 0) devuelve todas las fracciones en 0 en vez de
    /// dividir entre cero. **Nunca filtra**: entran 6 zonas, salen 6 partes — es el contrato
    /// que impide que una zona en cero se borre de la pantalla.
    static func partes(_ zonas: [Zona]) -> [Parte] {
        let total = zonas.reduce(0.0) { $0 + max(0, $1.minutos ?? 0) }
        guard total > 0 else { return zonas.map { Parte(zona: $0, fraccion: 0) } }
        return zonas.map { z in
            // Sin medición la fracción es 0, pero el riel NO la dibuja: la diferencia entre
            // «no medido» y «cero minutos» la resuelve `anchoRiel`, no esta cuenta.
            Parte(zona: z, fraccion: max(0, z.minutos ?? 0) / total)
        }
    }

    /// ¿Se midió el día? Basta con que UNA zona traiga lectura.
    static func hayMedicion(_ zonas: [Zona]) -> Bool {
        zonas.contains { $0.minutos != nil }
    }

    /// Ancho del relleno del riel, o `nil` cuando esa zona no se midió.
    ///
    /// El piso es la parte que el papel no tenía y la revisión adversarial pidió: con los
    /// minutos reales de un día (742/260/180/96/34/8 sobre 1320), la zona 5 es el 0.6 % del
    /// total — 0.87 pt en un riel de 144. Sin piso, ocho minutos medidos se ven idénticos a
    /// cero minutos, y la zona más dura del día desaparece. El piso la vuelve una astilla
    /// visible sin mentir sobre su tamaño: cualquiera puede ver que es la más chica.
    static func anchoRiel(_ parte: Parte, ancho: CGFloat) -> CGFloat? {
        guard let minutos = parte.zona.minutos else { return nil }
        guard minutos > 0 else { return 0 }
        return max(astillaMinima, CGFloat(parte.fraccion) * ancho)
    }

    /// Lo que dicta VoiceOver como valor. El caller manda su frase (ahí es donde vive el
    /// total del día en minutos: la palabra «minutos» es copy y el DS no la inventa); si
    /// llega vacía, se deriva del mismo reparto que pinta la barra — cada zona con su parte
    /// del total, en por ciento, sin una sola palabra fabricada aquí.
    static func a11yValue(zonas: [Zona], explicito: String, sinMedicion: String) -> String {
        if !explicito.isEmpty { return explicito }
        // Un día sin una sola lectura NO puede narrarse como seis ceros medidos: eso afirma
        // que se midió y que todo salió en reposo. Sin frase del caller, se calla.
        guard hayMedicion(zonas) else { return sinMedicion }
        return partes(zonas)
            .map { "\($0.zona.etiqueta) \(Int(($0.fraccion * 100).rounded()))%" }
            .joined(separator: ", ")
    }

    public var body: some View {
        let repartos = Self.partes(zonas)
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            barra(repartos)
            VStack(alignment: .leading, spacing: filaGap) {
                ForEach(repartos) { fila($0) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: etiquetaVoz))
        .accessibilityValue(Text(verbatim: Self.a11yValue(zonas: zonas, explicito: valorVoz, sinMedicion: vozSinMedicion)))
    }

    /// La barra apilada: un segmento por zona, ancho ∝ su parte del total, sin gaps (el
    /// reposo y Z1 son vecinos del mismo día, no cuatro cosas distintas). Va sobre un riel
    /// de tinta/7 para que un día sin medir se lea como una barra VACÍA y no como un hueco.
    private func barra(_ repartos: [Parte]) -> some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(repartos) { parte in
                    // MISMA cuenta que los rieles (`anchoRiel`): el piso de astilla y la
                    // ausencia de medición valen aquí también. Antes esta barra —la pieza
                    // héroe del bloque— pintaba `fraccion` en crudo, así que los 8 minutos
                    // reales de Z5 medían 0.87 pt y una zona sin medir se veía idéntica a una
                    // medida en cero. La leyenda decía la verdad y la barra no.
                    if let ancho = Self.anchoRiel(parte, ancho: geo.size.width), ancho > 0 {
                        Rectangle()
                            .fill(parte.zona.color)
                            .frame(width: ancho)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: altoBarra)
        .background(LiquidColor.tinta7)
        .clipShape(Capsule())
    }

    /// Una fila de la leyenda: etiqueta · riel · detalle. En tamaños de accesibilidad deja
    /// de ser tres columnas y se apila (mismo criterio que la leyenda de `LiquidStageBar`).
    private func fila(_ p: Parte) -> some View {
        Group {
            if tamanoTexto.isAccessibilitySize {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    HStack(spacing: LiquidSpace.s200) {
                        etiqueta(p)
                        Spacer(minLength: LiquidSpace.s200)
                        detalle(p)
                    }
                    riel(p)
                }
            } else {
                HStack(spacing: LiquidSpace.s200) {
                    etiqueta(p)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    riel(p)
                    detalle(p)
                        .lineLimit(1)
                }
            }
        }
    }

    /// El riel de la fila. Tres estados distintos, y los tres se ven distinto:
    ///
    /// · **sin medir** (`minutos == nil`) — riel vacío, sin relleno. El día no se midió.
    /// · **cero minutos** — riel vacío pero con su base marcada: se midió y ahí no estuviste.
    /// · **con minutos** — relleno proporcional, nunca por debajo de `astillaMinima`, para
    ///   que ocho minutos reales en zona 5 no desaparezcan contra un riel de 144 pt.
    private func riel(_ p: Parte) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta7)
                if let ancho = Self.anchoRiel(p, ancho: geo.size.width) {
                    if ancho > 0 {
                        Capsule().fill(p.zona.color).frame(width: ancho)
                    } else {
                        // Cero MEDIDO: una marca de base en el tono, del ancho del propio
                        // grosor del riel. Sin ella, «no estuviste en esta zona» y «no
                        // sabemos» se dibujarían idénticos.
                        Capsule()
                            .fill(p.zona.color.opacity(marcaCeroAlfa))
                            .frame(width: altoRiel)
                    }
                }
            }
        }
        .frame(height: altoRiel)
        .frame(minWidth: rielMinimo, maxWidth: .infinity)
    }

    private func etiqueta(_ p: Parte) -> some View {
        Text(verbatim: p.zona.etiqueta)
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta700)
    }

    @ViewBuilder private func detalle(_ p: Parte) -> some View {
        if let texto = p.zona.detalle {
            Text(verbatim: texto)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
    }
}

#if DEBUG
/// La rampa de zona que arma el CALLER (aquí, la de `MetricDetailSupport.zoneFill`: reposo en
/// tinta quieta y las cinco zonas graduando el tono de la métrica, más oscuro = más duro).
/// Vive en las previews porque el DS no conoce zonas de pulso.
private func rampaZona(_ i: Int, tono: Color) -> Color {
    switch i {
    case 0:  return LiquidColor.tinta10
    case 1:  return tono.opacity(0.35) // token-exempt: rampa de intensidad de zona (geometría de dato)
    case 2:  return tono.opacity(0.5)  // token-exempt: rampa de intensidad de zona (geometría de dato)
    case 3:  return tono.opacity(0.65) // token-exempt: rampa de intensidad de zona (geometría de dato)
    case 4:  return tono.opacity(0.82) // token-exempt: rampa de intensidad de zona (geometría de dato)
    default: return tono
    }
}

private func zonasDemo(_ minutos: [Double]) -> [LiquidTiempoZonas.Zona] {
    let etiquetas = ["Reposo", "Z1 · muy ligera", "Z2 · ligera", "Z3 · moderada",
                     "Z4 · dura", "Z5 · máxima"]
    let rangos = ["< 98 lpm", "98–117 lpm", "118–137 lpm", "138–156 lpm",
                  "157–176 lpm", "> 176 lpm"]
    return (0..<6).map { i in
        LiquidTiempoZonas.Zona(id: i, etiqueta: etiquetas[i], minutos: minutos[i],
                               color: rampaZona(i, tono: LiquidColor.rosa),
                               detalle: rangos[i])
    }
}

#Preview("Zonas · día activo") {
    // Un día con entrenamiento: el reposo sigue mandando (es el total del DÍA, no de la
    // sesión) y Z4/Z5 son las astillas honestas que se ganaron.
    LiquidTiempoZonas(
        zonas: zonasDemo([742, 260, 180, 96, 34, 8]),
        a11yLabel: "Tiempo en zonas de hoy",
        a11yValue: "138 minutos en zona 3 o más alta, de 1320 minutos medidos")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
}

#Preview("Zonas · día en reposo") {
    // Todo el día en la zona 0: las cinco zonas de entrenamiento quedan como rieles VACÍOS
    // con su etiqueta. Antes desaparecían y el día se leía como si no tuvieran zona.
    LiquidTiempoZonas(
        zonas: zonasDemo([1320, 0, 0, 0, 0, 0]),
        a11yLabel: "Tiempo en zonas de hoy",
        a11yValue: "Sin minutos elevados: todo el día en reposo")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
}

#Preview("Zonas · sin datos") {
    // Total 0 (no hubo curva que repartir): la barra queda hueca y los seis rieles vacíos.
    // No se divide entre cero y no se inventa un reparto que nadie midió.
    LiquidTiempoZonas(
        zonas: zonasDemo([0, 0, 0, 0, 0, 0]),
        a11yLabel: "Tiempo en zonas de hoy",
        a11yValue: "")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
}

#Preview("Zonas · AX") {
    // Tamaño de accesibilidad: cada fila deja de ser tres columnas y se apila —el riel se
    // va al renglón de abajo, a todo lo ancho— en vez de recortar la etiqueta.
    LiquidTiempoZonas(
        zonas: zonasDemo([742, 260, 180, 96, 34, 8]),
        a11yLabel: "Tiempo en zonas de hoy",
        a11yValue: "138 minutos en zona 3 o más alta, de 1320 minutos medidos")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
