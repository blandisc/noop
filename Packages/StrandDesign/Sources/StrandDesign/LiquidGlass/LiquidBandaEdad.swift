import SwiftUI

// MARK: - Liquid Glass · Banda de edad corporal (port de `BodyAgeBand`, FER-145)
//
// La regla horizontal de la hoja de Edad corporal («Tu banda»): una escala plana donde se
// marcan DOS posiciones sobre el mismo eje —tu edad corporal y tu edad real— para que la
// lectura sea una COMPARACIÓN, no un número suelto. Port de la geometría de `BodyAgeBand`
// (inset 18, eje en y=28, regla de 3 pt, marca de 11 pt, referencia punteada 1.3 con dash
// 2/2 y alto 18, etiquetas en y=9 / y=48) con tokens Liquid puros.
//
// Quién lleva el color, y por qué en ese orden:
//   · la EDAD REAL es la referencia NEUTRA — marca punteada en tinta. No es un dato: es el
//     cero contra el que se lee todo lo demás.
//   · la EDAD CORPORAL es el DATO — el único punto teñido, con `tono`, y la única etiqueta
//     con color. Nunca al revés: teñir la referencia convertiría el ancla en una segunda
//     afirmación y la comparación perdería su punto de apoyo.
// `tono` lo manda el caller y se espera que siga la CONVENCIÓN DE SIGNO de la hoja, que
// está escrita completa en `LiquidBarrasContribucion`: verde (`positivo`) cuando la edad
// corporal RESTA años, ámbar (`atencion`) cuando los SUMA. Es contraintuitiva a propósito
// —menos edad corporal es buena noticia, así que el número negativo es el que se celebra—
// y por eso vive documentada en un solo lugar, no repartida en dos.
//
// La marca del dato viaja desde la edad real hasta la edad corporal al entrar: el recorrido
// ES el delta. Con Reduce Motion aparece colocada, sin viaje.
//
// Contrato: `etiquetaCorporal` / `etiquetaReal` llegan YA formateadas y localizadas
// («31 años»), igual que `a11yLabel` / `a11yValue` — el DS no conoce catálogo ni locales.

public struct LiquidBandaEdad: View {
    private let edadCorporal: Double
    private let edadReal: Double
    private let dominio: ClosedRange<Double>
    /// El ±N de la estimación. `VitalityEngine.bandYears` = 5. `nil` = el caller no puede
    /// afirmar una incertidumbre y la banda no se dibuja (ver el porqué en la cabecera).
    private let bandaAnos: Double?
    /// Los extremos de la banda, YA formateados por el caller («26», «36»).
    private let etiquetaBandaBaja: String?
    private let etiquetaBandaAlta: String?
    private let etiquetaCorporal: String
    private let etiquetaReal: String
    private let tono: Color
    private let a11y: String
    private let a11yVal: String

    /// A tallas de accesibilidad las etiquetas flotantes se salen de su carril y se pisan
    /// entre sí: ahí bajan a una leyenda APILADA bajo la regla (mismos textos, mismas
    /// marcas). Nada se recorta y nada se inventa.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @State private var trazada = false

    // MARK: Geometría portada de `BodyAgeBand`
    //
    // No son espaciados de layout: son la traza de la gráfica, y por eso viven aquí como
    // geometría interna del componente (mismo patrón que `altoBarra` en `LiquidStageBar`).

    /// Margen a cada lado de la regla (`inset: 18` del papel). Es la reserva para que una
    /// marca pegada a un extremo del dominio no toque el filo de la caja.
    private let margen: CGFloat = 18
    /// Eje de la regla dentro de la caja (y = 28 en el papel).
    private let ejeY: CGFloat = 28
    /// Alto de la caja con etiquetas flotantes: valor en y=9, referencia en y=48.
    private let altoConEtiquetas: CGFloat = 58
    /// Alto de la caja DESNUDA (tallas AX): sin etiquetas flotantes sobra su aire, y la
    /// referencia punteada (18 pt centrada en el eje) sigue cabiendo entera.
    private let altoDesnudo: CGFloat = 40
    /// Grosor de la regla quieta.
    private let grosorRegla: CGFloat = 3
    /// Diámetro de la marca del dato.
    private let diametroMarca: CGFloat = 11
    /// Trazo y alto de la referencia punteada de la edad real.
    private let grosorTick: CGFloat = 1.3
    private let altoTick: CGFloat = 18
    /// Grosor de la banda de incertidumbre. Del papel: una cápsula de 7 pt sobre la regla de
    /// 3 — más gruesa que el riel para que se lea como el dato y no como chrome.
    private let grosorBanda: CGFloat = 7
    /// Alturas de las dos etiquetas flotantes: el dato arriba de su marca, la referencia
    /// debajo de la suya — nunca en el mismo carril, así que no pueden encimarse.
    private let etiquetaDatoY: CGFloat = 9
    private let etiquetaReferenciaY: CGFloat = 48

    /// - Parameters:
    ///   - edadCorporal: la edad corporal estimada, en años. Es el DATO (lleva el tono).
    ///   - edadReal: la edad cronológica. Es la REFERENCIA (va en tinta, nunca teñida).
    ///   - dominio: la escala visible. La manda el caller para que la regla no cambie de
    ///     largo entre sesiones; los valores fuera de ella se CLAMPEAN al extremo (la marca
    ///     siempre se ve).
    ///   - etiquetaCorporal: «31 años», YA formateada y localizada.
    ///   - etiquetaReal: «34 años», YA formateada y localizada.
    ///   - tono: el tinte del dato (ver la convención de signo, arriba).
    ///   - bandaAnos: el ±N años de incertidumbre del modelo. **Es la lectura honesta**: el
    ///     original de papel dice de sí mismo «the band, not the point, is the honest read».
    ///     `nil` deja la banda sin dibujar, para el caller que no puede afirmar un intervalo.
    ///   - etiquetaBandaBaja/Alta: los extremos YA formateados («26» / «36»).
    ///   - a11yLabel: qué es esto, para VoiceOver.
    ///   - a11yValue: qué dice hoy — obligatorio: esto es una gráfica.
    public init(edadCorporal: Double,
                edadReal: Double,
                dominio: ClosedRange<Double>,
                etiquetaCorporal: String,
                etiquetaReal: String,
                tono: Color,
                bandaAnos: Double? = nil,
                etiquetaBandaBaja: String? = nil,
                etiquetaBandaAlta: String? = nil,
                a11yLabel: String,
                a11yValue: String) {
        self.bandaAnos = bandaAnos
        self.etiquetaBandaBaja = etiquetaBandaBaja
        self.etiquetaBandaAlta = etiquetaBandaAlta
        self.edadCorporal = edadCorporal
        self.edadReal = edadReal
        self.dominio = dominio
        self.etiquetaCorporal = etiquetaCorporal
        self.etiquetaReal = etiquetaReal
        self.tono = tono
        self.a11y = a11yLabel
        self.a11yVal = a11yValue
    }

    // MARK: Mapeo

    /// Fracción 0…1 de `valor` dentro de `dominio`, SIEMPRE clampeada.
    ///
    /// El papel ensanchaba su escala hasta contener la edad cronológica para que la marca
    /// nunca se saliera de la regla. Aquí el dominio lo manda el caller (escala estable),
    /// así que el clamp es la única garantía equivalente: una edad fuera de la escala se
    /// pega al extremo en vez de dibujarse fuera de la caja. Con dominio degenerado
    /// (`lower == upper`) todo cae al centro — no hay escala que interpolar.
    static func posicion(_ valor: Double, en dominio: ClosedRange<Double>) -> Double {
        let tramo = dominio.upperBound - dominio.lowerBound
        guard tramo > 0 else { return 0.5 }
        return min(1, max(0, (valor - dominio.lowerBound) / tramo))
    }

    private func x(_ fraccion: Double, ancho w: CGFloat) -> CGFloat {
        margen + CGFloat(fraccion) * max(0, w - 2 * margen)
    }

    private var apilado: Bool { tamanoTexto.isAccessibilitySize }

    // MARK: Cuerpo

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            regla
            if apilado { leyendaApilada }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityValue(Text(verbatim: a11yVal))
    }

    private var regla: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // El dato viaja desde la referencia: el recorrido es el delta.
            let origen = trazada ? edadCorporal : edadReal
            let xDato = x(Self.posicion(origen, en: dominio), ancho: w)
            let xReferencia = x(Self.posicion(edadReal, en: dominio), ancho: w)
            ZStack(alignment: .topLeading) {
                // La regla: track quieto de tinta, jamás teñido.
                Capsule().fill(LiquidColor.tinta7)
                    .frame(width: max(0, w - 2 * margen), height: grosorRegla)
                    .position(x: w / 2, y: ejeY)
                // LA BANDA · el ±N años del modelo, en tinta (no teñida: es incertidumbre,
                // no dato). Va sobre el riel y bajo la marca. Sin ella, un punto pelado
                // afirmaría una precisión que el motor no tiene.
                if let bandaAnos {
                    let xBaja = x(Self.posicion(edadCorporal - bandaAnos, en: dominio), ancho: w)
                    let xAlta = x(Self.posicion(edadCorporal + bandaAnos, en: dominio), ancho: w)
                    Capsule().fill(LiquidColor.tinta10)
                        .frame(width: max(0, xAlta - xBaja), height: grosorBanda)
                        .position(x: (xBaja + xAlta) / 2, y: ejeY)
                }
                // REFERENCIA · la edad real, punteada y en tinta (el cero de la lectura).
                LiquidTickPunteado()
                    .stroke(LiquidColor.tinta500,
                            style: StrokeStyle(lineWidth: grosorTick,
                                               dash: [LiquidSpace.s050, LiquidSpace.s050]))
                    .frame(width: grosorTick, height: altoTick)
                    .position(x: xReferencia, y: ejeY)
                // DATO · la edad corporal, la única marca con color.
                Circle().fill(tono)
                    .frame(width: diametroMarca, height: diametroMarca)
                    .position(x: xDato, y: ejeY)

                if !apilado {
                    Text(verbatim: etiquetaCorporal)
                        .font(LiquidType.datoMenor)
                        .foregroundStyle(tono)
                        .fixedSize()
                        .position(x: xDato, y: etiquetaDatoY)
                    Text(verbatim: etiquetaReal)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .fixedSize()
                        .position(x: xReferencia, y: etiquetaReferenciaY)
                    if let bandaAnos {
                        if let baja = etiquetaBandaBaja {
                            Text(verbatim: baja)
                                .font(LiquidType.captionLectura)
                                .foregroundStyle(LiquidColor.tinta500)
                                .fixedSize()
                                .position(x: x(Self.posicion(edadCorporal - bandaAnos, en: dominio),
                                               ancho: w),
                                          y: etiquetaReferenciaY)
                        }
                        if let alta = etiquetaBandaAlta {
                            Text(verbatim: alta)
                                .font(LiquidType.captionLectura)
                                .foregroundStyle(LiquidColor.tinta500)
                                .fixedSize()
                                .position(x: x(Self.posicion(edadCorporal + bandaAnos, en: dominio),
                                               ancho: w),
                                          y: etiquetaReferenciaY)
                        }
                    }
                }
            }
        }
        .frame(height: apilado ? altoDesnudo : altoConEtiquetas)
        .onAppear {
            guard !trazada else { return }
            if motionDisabled || reduceMotion {
                trazada = true
            } else {
                withAnimation(LiquidMotion.ringProgress) { trazada = true }
            }
        }
    }

    /// Tallas AX: las dos etiquetas bajan a una leyenda apilada, cada una con la MISMA
    /// marca que lleva en la regla (punto teñido / trazo punteado en tinta) — el vínculo se
    /// mantiene sin una sola palabra nueva.
    private var leyendaApilada: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s150) {
                Circle().fill(tono)
                    .frame(width: diametroMarca, height: diametroMarca)
                Text(verbatim: etiquetaCorporal)
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(tono)
            }
            HStack(spacing: LiquidSpace.s150) {
                LiquidTickPunteado()
                    .stroke(LiquidColor.tinta500,
                            style: StrokeStyle(lineWidth: grosorTick,
                                               dash: [LiquidSpace.s050, LiquidSpace.s050]))
                    .frame(width: grosorTick, height: diametroMarca)
                    .frame(width: diametroMarca)   // misma columna que el punto
                Text(verbatim: etiquetaReal)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Una línea vertical centrada en su caja — la referencia punteada de la edad real.
private struct LiquidTickPunteado: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

#if DEBUG
#Preview("Liquid · Banda de edad (con datos)") {
    LiquidBandaEdad(
        edadCorporal: 31, edadReal: 34, dominio: 26...42,
        etiquetaCorporal: "31 años", etiquetaReal: "34 años",
        tono: LiquidColor.positivo,
        a11yLabel: "Edad corporal",
        a11yValue: "31 años, tres menos que tu edad real de 34")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.positivo))
}

/// Caso extremo: la edad corporal cae MUY por debajo y MUY por encima del dominio. La
/// posición se clampea al extremo — la marca nunca se sale de la regla, y la etiqueta
/// sigue diciendo el valor real.
#Preview("Liquid · Banda de edad (extremos)") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        LiquidBandaEdad(
            edadCorporal: 21, edadReal: 34, dominio: 26...42,
            etiquetaCorporal: "21 años", etiquetaReal: "34 años",
            tono: LiquidColor.positivo,
            a11yLabel: "Edad corporal",
            a11yValue: "21 años, trece menos que tu edad real de 34")
        LiquidBandaEdad(
            edadCorporal: 48, edadReal: 34, dominio: 26...42,
            etiquetaCorporal: "48 años", etiquetaReal: "34 años",
            tono: LiquidColor.atencion,
            a11yLabel: "Edad corporal",
            a11yValue: "48 años, catorce más que tu edad real de 34")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
}

/// Sin diferencia: la marca del dato se para encima de la referencia. Las dos etiquetas
/// viven en carriles distintos (arriba / abajo), así que se leen sin pisarse.
#Preview("Liquid · Banda de edad (en tu edad)") {
    LiquidBandaEdad(
        edadCorporal: 34, edadReal: 34, dominio: 26...42,
        etiquetaCorporal: "34 años", etiquetaReal: "34 años",
        tono: LiquidColor.tinta900,
        a11yLabel: "Edad corporal",
        a11yValue: "34 años, igual que tu edad real")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo())
}

#Preview("Liquid · Banda de edad (AX)") {
    LiquidBandaEdad(
        edadCorporal: 31, edadReal: 34, dominio: 26...42,
        etiquetaCorporal: "31 años", etiquetaReal: "34 años",
        tono: LiquidColor.positivo,
        a11yLabel: "Edad corporal",
        a11yValue: "31 años, tres menos que tu edad real de 34")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.positivo))
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
