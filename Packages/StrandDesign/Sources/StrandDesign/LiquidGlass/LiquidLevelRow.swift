import SwiftUI

// MARK: - Liquid Glass · Fila de nivel (épico hoja de resumen, F3b)
//
// La fila TOCABLE de la lista de niveles del explorador (contrato
// docs/design-system/LIQUID-SHEET-CONTRACT.md §3 F3b): punto + etiqueta + rango + conteo,
// con la fila activa iluminada al 12 % del tono (I1, mismo rango 10-16 % que
// `LiquidBandsTable`) y el nivel de HOY marcado con anillo hueco mientras exploras otro
// (paridad `MetricLevelsExplorer:231-237`). Tocar dispara `onTap` — el caller alterna la
// selección y resalta la banda en la gráfica.
//
// Contrato D3: strings YA localizados/formateados («En tu base», «49–71», «12 días»,
// «· hoy»); el DS no conoce `MetricLevels` ni locales. `a11yHint` y `hoyEtiqueta` vienen
// del caller por la misma regla (el DS no puede acuñar copy).

// Pasada UI H2: rango y conteo NO van en `tono` — medido, falla AA (4.5) en 6 de
// los 7 tonos de dato sobre el wash de la fila activa. El color lo llevan el punto
// y el wash; el número se lee en tinta.
public struct LiquidLevelRow: View {
    private let etiqueta: String
    private let rango: String
    private let conteo: String
    private let esHoy: Bool
    private let activa: Bool
    /// Eco del scrub: la fila del nivel bajo el dedo recibe un wash tenue mientras arrastras
    /// sobre la gráfica (mock `.lvl.hit`, `filaResaltadaAlfa`). `activa` gana si ambas.
    private let resaltada: Bool
    private let tono: Color
    private let hoyEtiqueta: String?
    private let a11yHint: String?
    /// XC7-07 (FER-128 r7) · A tamaños de accesibilidad las tres columnas no caben y el texto
    /// partía PALABRAS («Athlet / e range», «0 night / s»): la fila se apila y cada texto tiene
    /// el ancho entero.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    private let onTap: () -> Void

    /// La etiqueta escala con Dynamic Type como su rango y su conteo (`captionLectura`,
    /// relativo a `.caption2`). Con el `LiquidType.cuerpo` fijo de antes, a tamaños AX el
    /// nombre del carril terminaba MÁS CHICO que el número que lo acompaña.
    // 14 base (mock `.lvl .nm {14px}`), 12.5→14 (auditoría 2026-08-03). Escala con Dynamic Type.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = 14

    public init(etiqueta: String, rango: String, conteo: String,
                esHoy: Bool, activa: Bool, resaltada: Bool = false, tono: Color,
                hoyEtiqueta: String? = nil,
                a11yHint: String? = nil, onTap: @escaping () -> Void) {
        self.etiqueta = etiqueta
        self.rango = rango
        self.conteo = conteo
        self.esHoy = esHoy
        self.activa = activa
        self.resaltada = resaltada
        self.tono = tono
        self.hoyEtiqueta = hoyEtiqueta
        self.a11yHint = a11yHint
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            let apilado = tamanoTexto >= .accessibility1
            let fila = apilado
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: LiquidSpace.s150))
                : AnyLayout(HStackLayout(spacing: LiquidSpace.s300))
            fila {
                if !apilado { punto }
                // La etiqueta y el rótulo de HOY viajan juntos (gap chico): son una sola
                // idea, no dos columnas — el `Spacer` de abajo los separa del rango.
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                    if apilado { punto }
                    Text(verbatim: etiqueta)
                        .font(.system(size: etiquetaPt))
                        .fontWeight(activa ? .bold : .regular)
                        .foregroundStyle(activa ? LiquidColor.tinta900 : LiquidColor.tinta700)
                    if esHoy, let hoyEtiqueta {
                        Text(verbatim: hoyEtiqueta)
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(tonoRotulo)
                    }
                }
                if !apilado { Spacer(minLength: LiquidSpace.s200) }
                // Rango 13/600 tinta700 y conteo 12 tinta500 — SIEMPRE, aunque la fila esté
                // activa (mock `.lvl .rng {13/600 tinta700}`, `.lvl .cnt {12 tinta500}`; la
                // fila activa se distingue por la etiqueta en bold+tinta900, el tick y el wash,
                // no por teñir sus números de tinta900). Auditoría Grok+DeepSeek 2026-08-03.
                Text(verbatim: rango)
                    .font(LiquidType.filaRango)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta700)
                Text(verbatim: conteo)
                    .font(LiquidType.filaConteo)
                    .monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta500)
                    .frame(minWidth: apilado ? nil : 52, alignment: .trailing)
            }
            .padding(.horizontal, LiquidSpace.s400)
            .padding(.vertical, LiquidSpace.s300)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            // I1 en la lista: la fila activa se ilumina con el tono (rango 10-16 % del épico);
            // la resaltada por scrub, con un wash más tenue (eco tabla↔gráfica); activa gana.
            // #inject · El resalte deja de ser un rectángulo a sangre y pasa a una PÍLDORA
            // inset y redondeada (r=control 12, mock `.lvl.on{border-radius:12}`): flota con
            // respiro a los lados y arriba/abajo, más refinada. La zona tocable sigue a sangre.
            .background(
                RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous)
                    .fill(washFila)
                    // #inject · Pedido del dueño: la píldora abarca más a la derecha (se
                    // cortaba muy cerca de «N nights»); margen izquierdo refinado, derecho
                    // más corto para que el resalte casi alcance el conteo.
                    .padding(.leading, LiquidSpace.s300)
                    .padding(.trailing, LiquidSpace.s100)
                    .padding(.vertical, LiquidSpace.s100)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        // `.combine` fusiona los cuatro textos de la fila, así que el rótulo de HOY entra
        // solo en el label de VoiceOver («Bajo, · hoy, < 49, 2 días») — sin componer copy.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(activa ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text(verbatim: a11yHint ?? ""))
    }

    /// El tono del rótulo de HOY, corregido para AA: el ámbar de dato (#C4631F, que llega
    /// como `tono` en piel/esfuerzo y en el clima de atención) ronda 3.5:1 sobre vidrio y
    /// esto es texto chico, así que usa su hermano oscurecido `atencionTexto` (misma regla
    /// que `LiquidSignalState.caption`). Los demás tonos de dato ya pasan.
    private var tonoRotulo: Color {
        (tono == LiquidColor.ambar || tono == LiquidColor.atencion)
            ? LiquidColor.atencionTexto : tono
    }

    /// El wash de la fila: `activa` manda (I1, wash fuerte); `resaltada && !activa` es el eco
    /// tenue del scrub; si nada, transparente. Mismo orden que `LiquidBandsTable`.
    private var washFila: Color {
        if activa { return tono.opacity(LiquidChart.filaActivaAlfa) }
        if resaltada { return tono.opacity(LiquidChart.filaResaltadaAlfa) }
        return .clear
    }

    /// El marcador de índice de la fila: una BARRA VERTICAL, no un círculo. Paridad del mock
    /// canónico (`.lvl .tick`: barra 2×14, activa 2.5×17 del tono; auditoría Grok+DeepSeek
    /// 2026-08-03). Del tono cuando la fila es la activa o la de hoy; tenue (tinta10) si no.
    /// La barra se centra en una columna de 8 pt: el mismo ancho que ocupaba el círculo, para
    /// no correr el texto ni la sangría del separador de `LiquidLevelsList`.
    @ViewBuilder private var punto: some View {
        // Tick del tono SOLO en la fila activa (mock `.lvl.on .tick`); el día se marca con el
        // rótulo «· hoy» aparte, no tiñendo su tick (auditoría 2026-08-03).
        let esTono: Bool = activa
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(esTono ? tono : LiquidColor.tinta10)
            // Apilado (AX): el tick se sienta en la baseline junto a la etiqueta, así que crece
            // con la letra — a 14 pt fijos quedaba como un guion bajo (FER-128 r8).
            .frame(width: activa ? 2.5 : 2,
                   height: tamanoTexto >= .accessibility1 ? etiquetaPt : (activa ? 17 : 14))
            .frame(width: 8)
    }
}

// MARK: - La LISTA de filas (el chrome que las vuelve una tabla)

/// Las filas de nivel dentro de su superficie: separadores de 1 px sangrados tras el punto,
/// esquinas del DS y vidrio `.superficie`.
///
/// Existe porque ese chrome estaba COPIADO en la hoja (`LiquidMetricSheetView.nivelesLista`),
/// en los previews y en el arnés de renders — y las copias se separaron: los PNG del arnés
/// enseñaban filas sueltas, con el wash de la fila activa saliéndose a sangre y esquinas
/// cuadradas, que es justo lo que la app NO dibuja. Un solo hogar, un solo dibujo.
///
/// Contrato D3 (igual que `LiquidLevelRow`): todo llega YA localizado y formateado.
public struct LiquidLevelsList: View {

    public struct Fila {
        public let etiqueta: String
        public let rango: String
        public let conteo: String
        public let esHoy: Bool
        public let activa: Bool
        public let resaltada: Bool
        public let hoyEtiqueta: String?
        public let a11yHint: String?
        public let onTap: () -> Void

        public init(etiqueta: String, rango: String, conteo: String,
                    esHoy: Bool = false, activa: Bool = false, resaltada: Bool = false,
                    hoyEtiqueta: String? = nil, a11yHint: String? = nil,
                    onTap: @escaping () -> Void = {}) {
            self.etiqueta = etiqueta
            self.rango = rango
            self.conteo = conteo
            self.esHoy = esHoy
            self.activa = activa
            self.resaltada = resaltada
            self.hoyEtiqueta = hoyEtiqueta
            self.a11yHint = a11yHint
            self.onTap = onTap
        }
    }

    private let filas: [Fila]
    private let tono: Color
    /// La sangría del separador sigue al texto también cuando la fila se apila (r8).
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public init(filas: [Fila], tono: Color) {
        self.filas = filas
        self.tono = tono
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { (i: Int, f: Fila) in
                LiquidLevelRow(etiqueta: f.etiqueta, rango: f.rango, conteo: f.conteo,
                               esHoy: f.esHoy, activa: f.activa, resaltada: f.resaltada,
                               tono: tono,
                               hoyEtiqueta: f.hoyEtiqueta, a11yHint: f.a11yHint,
                               onTap: f.onTap)
                // #inject · El separador NO se dibuja pegado a la fila activa (mock
                // `.lvl.on + .lvl{border-top-color:transparent}`): la píldora del resalte
                // flota limpia, sin una línea rozándole el filo arriba o abajo.
                if i < filas.count - 1, !filas[i].activa, !filas[i + 1].activa {
                    // Sangría: margen de la fila + el punto + su gap, para que la línea
                    // arranque bajo el TEXTO y la columna de puntos se lea como un riel.
                    Rectangle()
                        .fill(LiquidColor.tinta10)
                        .frame(height: 1)
                        .padding(.leading, LiquidSpace.s400 + 8
                                 + (tamanoTexto >= .accessibility1 ? LiquidSpace.s150 : LiquidSpace.s300))
                }
            }
        }
        // El clip va ANTES del vidrio (igual que `LiquidBandsTable`): el wash de la fila
        // activa respeta las esquinas también en el camino nativo.
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
    }
}

#if DEBUG
#Preview("Liquid · LevelRow") {
    LiquidLevelsList(
        filas: [
            .init(etiqueta: "Alto", rango: "≥ 71", conteo: "4 días"),
            // Activa (la que exploras): wash del tono + texto en tinta/900.
            .init(etiqueta: "En tu base", rango: "49–71", conteo: "12 días", activa: true),
            // Hoy, mientras exploras otro nivel: anillo hueco + rótulo «· hoy».
            .init(etiqueta: "Bajo", rango: "< 49", conteo: "2 días",
                  esHoy: true, hoyEtiqueta: "· hoy"),
        ],
        tono: LiquidColor.cian)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · LevelRow · ámbar (AA)") {
    // El tono ámbar del dato falla AA en texto chico: el rótulo de HOY se pinta en
    // `atencionTexto`, no en el ámbar crudo.
    LiquidLevelsList(
        filas: [
            .init(etiqueta: "Sobre tu base", rango: "≥ +0.4 °C", conteo: "3 noches",
                  esHoy: true, hoyEtiqueta: "· hoy"),
            .init(etiqueta: "En tu base", rango: "−0.3–+0.4 °C", conteo: "9 noches",
                  activa: true),
        ],
        tono: LiquidColor.ambar)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.ambar))
        .environment(\.liquidMotionDisabled, true)
}
#endif

/// XC7-07 · a tamaños AX la fila se apila (punto + etiqueta / rango / conteo) y nada parte palabras.
#Preview("Liquid · LevelRow AX") {
    LiquidLevelsList(
        filas: [
            .init(etiqueta: "Rango de atleta", rango: "≥ 71", conteo: "0 noches"),
            .init(etiqueta: "Alto", rango: "60–70", conteo: "4 noches", esHoy: true, activa: true),
            .init(etiqueta: "Bajo", rango: "< 45", conteo: "1 noche"),
        ],
        tono: LiquidColor.cian)
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.dynamicTypeSize, .accessibility3)
}
