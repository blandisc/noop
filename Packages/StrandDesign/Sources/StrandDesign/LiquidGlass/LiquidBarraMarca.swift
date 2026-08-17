import SwiftUI

// MARK: - Liquid Glass · Barra con marca de promedio («anoche vs tu típico»)
//
// La fila de «Anoche vs tu típico» del detalle de Sueño: un rótulo en caja alta, el dato de
// anoche a la derecha, un delta con signo, y debajo una barra donde el relleno mide la parte
// de anoche y un TICK de tinta marca dónde cae tu promedio.
//
// Port 1:1 de `stageVsTypicalRow` (papel «Instrumento», `SleepDetailScreen.swift`), que hasta
// hoy vivía dibujada a mano dentro de la pantalla: misma matemática de escala, mismos
// grosores, mismo trato del promedio. Aquí sale a pieza reutilizable con tokens Liquid.
//
// Las TRES reglas de honestidad que hereda del papel y que este archivo protege:
//
//   1. La marca es el PROMEDIO, no un objetivo. Va en tinta neutra (`tinta900`) y nunca se
//      tiñe de verde/rojo: pasarla no es «ganar» ni «perder», es una referencia.
//   2. Sin base todavía (`marca == nil`) se dibuja la barra SIN marca y la voz no menciona
//      promedio. Jamás se inventa una marca al 50 %.
//   3. El componente NO juzga. `masEsMejor` (el `higherIsBetter` del papel) SOLO decide el
//      COLOR DEL DELTA; el dibujo de la barra y la posición de la marca son idénticos en
//      ambos sentidos. La lectura («dormiste menos profundo que de costumbre») la pone el
//      caller en su texto, no la geometría.
//
// Contrato: `etiqueta`, `valorTexto` y los strings de accesibilidad llegan YA localizados y
// formateados por el caller. El componente solo calcula proporciones y el delta en puntos
// porcentuales (números y signos, sin idioma).

public struct LiquidBarraMarca: View {

    private let etiqueta: String
    private let fraccion: Double?
    private let marca: Double?
    private let tono: Color
    private let valorTexto: String
    private let masEsMejor: Bool
    private let indice: Int
    private let a11yLabel: String
    private let a11yValor: String

    /// La cabecera (rótulo · dato · delta) no cabe en una fila cuando el texto crece: en
    /// tamaños de accesibilidad se apila en vez de recortar.
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    // MARK: Geometría interna (del papel — no es escala del sistema, es esta pieza)

    /// Alto de la cápsula, 10 pt (papel: `.frame(height: 10)` en track y relleno). Más
    /// delgada que `LiquidStageBar` (12) porque aquí la barra es una FILA de una lista de
    /// cuatro, no el retrato de la noche.
    private let altoBarra: CGFloat = 10
    /// Alto del tick del promedio, 14 pt: 2 pt más que la cápsula ARRIBA y 2 pt ABAJO. Ese
    /// sobresalto es lo que lo hace leer como marca de regla y no como un trozo de la barra.
    private let altoMarca: CGFloat = 14
    /// Grosor del tick, 2 pt: la línea más fina que sigue siendo una marca a 1×.
    private let anchoMarca: CGFloat = 2

    /// 18 % de AIRE por encima de la señal más grande de la fila. Con él, la barra (o el
    /// tick) más alto llega siempre a ~84.7 % del ancho y nunca toca el borde: el ojo ve que
    /// la fila no está topada. Es la razón de que la escala sea POR FILA — ver `denominador`.
    private static let aire: Double = 1.18
    /// El delta se dice en PUNTOS PORCENTUALES, como el papel: las fracciones (0…1) se
    /// multiplican por 100 antes de redondear.
    private static let escala: Double = 100

    /// - Parameters:
    ///   - etiqueta: «Profundo» — YA localizada; se pinta en caja alta.
    ///   - fraccion: 0…1, la parte de anoche. Fuera de rango se clampea (no rompe el layout).
    ///     **`nil` = esa etapa NO se midió anoche**, que no es lo mismo que medirse en cero:
    ///     sin medición no hay relleno, no hay delta y la voz lo dice. Con `0` sí hay dato y
    ///     la cápsula se dibuja vacía pero presente. Colapsarlos haría que una noche sin
    ///     etapas (el fallback diario de Apple) se leyera como una noche de cero profundo.
    ///   - marca: 0…1, el promedio típico. `nil` = todavía no hay base → no se dibuja marca.
    ///     `0` = base MEDIDA en cero: el tick no se pinta (caería sobre el borde izquierdo)
    ///     pero el delta sí se dice, igual que en el papel.
    ///   - tono: el color de la etapa; tiñe SOLO el relleno.
    ///   - valorTexto: «1:31 · 22 %» — YA formateado por el caller (el separador decimal y el
    ///     espacio antes del % son de idioma, no del componente).
    ///   - masEsMejor: el `higherIsBetter` del papel. SOLO tiñe el delta (verde/ámbar); no
    ///     cambia ni un pixel del dibujo.
    ///   - indice: posición de la fila entre sus hermanas — da el stagger de la entrada.
    ///   - a11yLabel: normalmente la etiqueta.
    ///   - a11yValue: ármalo con `LiquidBarraMarca.a11yValue(anoche:tipico:)` para que, sin
    ///     base, la voz NO mencione promedio (regla 2).
    public init(etiqueta: String,
                fraccion: Double?,
                marca: Double?,
                tono: Color,
                valorTexto: String,
                masEsMejor: Bool = true,
                indice: Int = 0,
                a11yLabel: String,
                a11yValue: String) {
        self.etiqueta = etiqueta
        self.fraccion = fraccion
        self.marca = marca
        self.tono = tono
        self.valorTexto = valorTexto
        self.masEsMejor = masEsMejor
        self.indice = indice
        self.a11yLabel = a11yLabel
        self.a11yValor = a11yValue
    }

    // MARK: - Matemática (pura y estática: el test la comprueba en frío, sin render)

    /// Clampea a 0…1 y mata NaN/infinito: un ancho negativo o no-finito rompe el layout de
    /// SwiftUI, y ninguna fracción de la noche vive fuera de 0…1.
    static func enRango(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(0, v))
    }

    /// El denominador de la fila: la señal más grande (anoche o su promedio) más el `aire`.
    ///
    /// La escala es POR FILA — cada barra tiene su propio denominador y NO hay escala
    /// compartida entre filas. Es deliberado: cada etapa se compara consigo misma, no con la
    /// de al lado, así que 22 % de profundo y 6 % de despierto pueden llenar lo mismo. La
    /// consecuencia visible es que el elemento más grande de cada fila llega siempre a
    /// ~84.7 % del ancho (1 / 1.18), nunca al 100 %.
    static func denominador(fraccion: Double?, marca: Double?) -> Double {
        let tope = max(enRango(fraccion ?? 0), enRango(marca ?? 0)) * aire
        return tope > 0 ? tope : 1
    }

    /// Ancho del relleno como fracción del ancho disponible (0…1), o `nil` cuando la etapa no
    /// se midió: sin medición no se dibuja cápsula de color, ni siquiera de ancho cero. La
    /// diferencia se ve — un cero medido deja una cápsula presente en su base; un hueco deja
    /// solo el riel.
    static func anchoRelleno(fraccion: Double?, marca: Double?) -> Double? {
        guard let fraccion else { return nil }
        return min(1, enRango(fraccion) / denominador(fraccion: fraccion, marca: marca))
    }

    /// Posición del CENTRO del tick como fracción del ancho (0…1), o `nil` si no hay marca
    /// que dibujar (regla 2: sin base no se inventa nada; con base en 0 el tick caería sobre
    /// el borde, y el papel tampoco lo pinta).
    static func posicionMarca(fraccion: Double?, marca: Double?) -> Double? {
        guard let marca, enRango(marca) > 0 else { return nil }
        return min(1, enRango(marca) / denominador(fraccion: fraccion, marca: marca))
    }

    /// El delta en puntos porcentuales: «~0» cuando redondea a cero, «+4» arriba, «−4»
    /// abajo (signo menos U+2212, no un guion). `nil` sin base — no hay contra qué comparar.
    static func deltaTexto(fraccion: Double?, marca: Double?) -> String? {
        // Sin medición no hay delta que decir: un «−18» sobre una noche que nadie midió es
        // una afirmación inventada, y es justo la mentira que esta familia existe para evitar.
        guard let fraccion, let marca else { return nil }
        let diff = Int(((enRango(fraccion) - enRango(marca)) * escala).rounded())
        if diff == 0 { return "~0" }
        return diff > 0 ? "+\(abs(diff))" : "−\(abs(diff))"
    }

    /// Si el delta va en positivo o en atención. ÚNICO lugar donde `masEsMejor` cambia algo
    /// (regla 3). Sin base no hay juicio: se calla en verde.
    static func mejora(fraccion: Double?, marca: Double?, masEsMejor: Bool) -> Bool {
        guard let fraccion, let marca else { return true }
        let diff = enRango(fraccion) - enRango(marca)
        return masEsMejor ? diff >= 0 : diff <= 0
    }

    /// Arma el valor de VoiceOver con las piezas YA localizadas por el caller. Con
    /// `tipico == nil` la voz no menciona promedio: la barra sin base tampoco lo dibuja.
    public static func a11yValue(anoche: String, tipico: String?) -> String {
        ([anoche] + [tipico].compactMap { $0 }).joined(separator: ", ")
    }

    // MARK: - Cuerpo

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            cabecera
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(LiquidColor.tinta7)
                        .frame(height: altoBarra)
                    if let ancho = Self.anchoRelleno(fraccion: fraccion, marca: marca) {
                        Capsule(style: .continuous)
                            .fill(tono)
                            .frame(width: w * CGFloat(ancho), height: altoBarra)
                    }
                    if let pos = Self.posicionMarca(fraccion: fraccion, marca: marca) {
                        // Tinta NEUTRA y posicionada por su CENTRO (regla 1): el promedio no
                        // opina, solo señala. Sobresale 2 pt por arriba y por abajo.
                        Rectangle()
                            .fill(LiquidColor.tinta900)
                            .frame(width: anchoMarca, height: altoMarca)
                            .position(x: w * CGFloat(pos), y: altoBarra / 2)
                    }
                }
            }
            .frame(height: altoBarra)
        }
        // La entrada del sistema (fade + rise 8 pt, stagger 60 ms por índice) en lugar del
        // `recGrow` del papel: ya respeta Reduce Motion —la fila aparece colocada— y el
        // congelado de los renders. La barra deja de «crecer», pero el escalonado de la lista
        // se conserva, que es lo que el papel comunicaba.
        .liquidEntrada(index: indice)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11yValor))
    }

    /// Rótulo · dato · delta. En tallas AX el rótulo se va a su propio renglón: en una sola
    /// fila, «PROFUNDO» inflado exprimía al dato hasta recortarlo.
    @ViewBuilder private var cabecera: some View {
        if tamanoTexto.isAccessibilitySize {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                rotulo
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    valor
                    delta
                }
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                rotulo
                Spacer(minLength: LiquidSpace.s200)
                valor
                delta
            }
        }
    }

    /// Papel: 10/600 +1.1 MAYÚSCULAS en tinta terciaria → `regla` (10/600, el ÚNICO token de
    /// la escala chica que mide exactamente 10) con su tracking del sistema (+2.2). El
    /// tracking cede al token a propósito: la escala chica se unificó justo para que estos
    /// rótulos no lleven siete trackings casi iguales.
    private var rotulo: some View {
        Text(verbatim: etiqueta)
            .liquidRegla()
            .foregroundStyle(LiquidColor.tinta500)
    }

    /// Papel: 12/500 tabular en tinta plena → `valorS` (14 tabular, numeral terciario), el
    /// numeral más chico del sistema. Sube 2 pt respecto del papel; el orden de la fila
    /// (dato > delta > rótulo) se conserva y el dato manda un poco más, como pide el ADN.
    private var valor: some View {
        Text(verbatim: valorTexto)
            .font(LiquidType.valorS)
            .foregroundStyle(LiquidColor.tinta900)
    }

    /// Papel: 11/600 tabular en verde/ámbar → `microEstado` (10.5/600, el chip de estado),
    /// mismo peso y medio punto menos. Tabular a mano porque `microEstado` es texto, no
    /// numeral: sin eso, «+4» y «−4» bailan al re-medir.
    @ViewBuilder private var delta: some View {
        if let texto = Self.deltaTexto(fraccion: fraccion, marca: marca) {
            Text(verbatim: texto)
                .font(LiquidType.microEstado)
                .monospacedDigit()
                .foregroundStyle(Self.mejora(fraccion: fraccion, marca: marca,
                                             masEsMejor: masEsMejor)
                                 ? LiquidColor.positivo : LiquidColor.atencion)
        }
    }
}

#if DEBUG
/// Las cuatro filas del bloque real («anoche vs tu típico» del detalle de Sueño), para que el
/// preview enseñe lo que el componente hace en lista: escala POR FILA (cada barra topa a
/// ~84.7 % con su propio máximo) y entrada escalonada.
private struct BarraMarcaDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s400) {
            LiquidBarraMarca(etiqueta: "Profundo", fraccion: 0.22, marca: 0.18,
                             tono: LiquidColor.indigo, valorTexto: "1:31 · 22 %",
                             indice: 0,
                             a11yLabel: "Profundo",
                             a11yValue: LiquidBarraMarca.a11yValue(anoche: "22 % anoche",
                                                                   tipico: "típico 18 %"))
            LiquidBarraMarca(etiqueta: "REM", fraccion: 0.25, marca: 0.24,
                             tono: LiquidColor.indigo.opacity(0.78),  // token-exempt: rampa graduada de etapas
                             valorTexto: "1:44 · 25 %", indice: 1,
                             a11yLabel: "REM",
                             a11yValue: LiquidBarraMarca.a11yValue(anoche: "25 % anoche",
                                                                   tipico: "típico 24 %"))
            LiquidBarraMarca(etiqueta: "Ligero", fraccion: 0.46, marca: 0.52,
                             tono: LiquidColor.indigo.opacity(0.52),  // token-exempt: rampa graduada de etapas
                             valorTexto: "3:10 · 46 %", indice: 2,
                             a11yLabel: "Ligero",
                             a11yValue: LiquidBarraMarca.a11yValue(anoche: "46 % anoche",
                                                                   tipico: "típico 52 %"))
            // Despierto: aquí MENOS es mejor, así que el mismo «+7» se dice en ámbar. La
            // barra y la marca se dibujan igual que arriba — el sentido solo tiñe el delta.
            LiquidBarraMarca(etiqueta: "Despierto", fraccion: 0.13, marca: 0.06,
                             tono: LiquidColor.oro, valorTexto: "0:47 · 13 %",
                             masEsMejor: false, indice: 3,
                             a11yLabel: "Despierto",
                             a11yValue: LiquidBarraMarca.a11yValue(anoche: "13 % anoche",
                                                                   tipico: "típico 6 %"))
        }
    }
}

#Preview("Barra · encima del promedio") {
    // Anoche 22 % contra un típico de 18 %: el relleno pasa el tick y el delta va en verde.
    LiquidBarraMarca(etiqueta: "Profundo", fraccion: 0.22, marca: 0.18,
                     tono: LiquidColor.indigo, valorTexto: "1:31 · 22 %",
                     a11yLabel: "Profundo",
                     a11yValue: LiquidBarraMarca.a11yValue(anoche: "22 % anoche",
                                                           tipico: "típico 18 %"))
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Barra · debajo") {
    // 46 % contra 52 %: el tick queda a la DERECHA del relleno (y topa a ~84.7 %, porque
    // ahora el máximo de la fila es el promedio). Delta en ámbar.
    LiquidBarraMarca(etiqueta: "Ligero", fraccion: 0.46, marca: 0.52,
                     tono: LiquidColor.indigo.opacity(0.52),  // token-exempt: rampa graduada de etapas
                     valorTexto: "3:10 · 46 %",
                     a11yLabel: "Ligero",
                     a11yValue: LiquidBarraMarca.a11yValue(anoche: "46 % anoche",
                                                           tipico: "típico 52 %"))
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Barra · sin base") {
    // Todavía no hay promedio: barra sin tick, sin delta, y la voz NO dice «típico».
    LiquidBarraMarca(etiqueta: "Profundo", fraccion: 0.22, marca: nil,
                     tono: LiquidColor.indigo, valorTexto: "1:31 · 22 %",
                     a11yLabel: "Profundo",
                     a11yValue: LiquidBarraMarca.a11yValue(anoche: "22 % anoche", tipico: nil))
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Barra · cero medido vs sin medir") {
    // Los DOS estados que no pueden verse igual, uno encima del otro:
    // arriba se midió y dio cero (cápsula presente en su base, delta real contra el promedio);
    // abajo NO se midió (solo el riel, sin delta, sin juicio).
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidBarraMarca(etiqueta: "Despierto", fraccion: 0, marca: 0.06,
                         tono: LiquidColor.oro, valorTexto: "0:00 · 0 %",
                         masEsMejor: false,
                         a11yLabel: "Despierto",
                         a11yValue: LiquidBarraMarca.a11yValue(anoche: "0 % anoche",
                                                               tipico: "típico 6 %"))
        // Etapa NO medida: sin relleno y sin delta, aunque exista promedio. Un «−6» aquí
        // afirmaría algo sobre una noche que nadie midió.
        LiquidBarraMarca(etiqueta: "Profundo", fraccion: nil, marca: 0.22,
                         tono: LiquidColor.indigo, valorTexto: "—", indice: 1,
                         a11yLabel: "Profundo",
                         a11yValue: LiquidBarraMarca.a11yValue(anoche: "sin medir anoche",
                                                               tipico: "típico 22 %"))
        // Sin dato y sin base: hueca y muda, sin inventar una marca a media barra.
        LiquidBarraMarca(etiqueta: "REM", fraccion: nil, marca: nil,
                         tono: LiquidColor.cian, valorTexto: "—", indice: 2,
                         a11yLabel: "REM",
                         a11yValue: LiquidBarraMarca.a11yValue(anoche: "sin medir anoche", tipico: nil))
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Barra · las cuatro etapas") {
    BarraMarcaDemo()
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}

#Preview("Barra · AX") {
    // Talla de accesibilidad: el rótulo se va a su propio renglón y el dato deja de exprimirse.
    BarraMarcaDemo()
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
