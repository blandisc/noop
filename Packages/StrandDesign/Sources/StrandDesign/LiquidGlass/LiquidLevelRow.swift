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
    private let tono: Color
    private let hoyEtiqueta: String?
    private let a11yHint: String?
    private let onTap: () -> Void

    /// La etiqueta escala con Dynamic Type como su rango y su conteo (`captionLectura`,
    /// relativo a `.caption2`). Con el `LiquidType.cuerpo` fijo de antes, a tamaños AX el
    /// nombre del carril terminaba MÁS CHICO que el número que lo acompaña.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = LiquidType.cuerpoLecturaBase

    public init(etiqueta: String, rango: String, conteo: String,
                esHoy: Bool, activa: Bool, tono: Color,
                hoyEtiqueta: String? = nil,
                a11yHint: String? = nil, onTap: @escaping () -> Void) {
        self.etiqueta = etiqueta
        self.rango = rango
        self.conteo = conteo
        self.esHoy = esHoy
        self.activa = activa
        self.tono = tono
        self.hoyEtiqueta = hoyEtiqueta
        self.a11yHint = a11yHint
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: LiquidSpace.s300) {
                punto
                // La etiqueta y el rótulo de HOY viajan juntos (gap chico): son una sola
                // idea, no dos columnas — el `Spacer` de abajo los separa del rango.
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
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
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: rango)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(activa ? LiquidColor.tinta900 : LiquidColor.tinta500)
                Text(verbatim: conteo)
                    .font(LiquidType.captionLectura)
                    .monospacedDigit()
                    .foregroundStyle(activa ? LiquidColor.tinta900 : LiquidColor.tinta500)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, LiquidSpace.s400)
            .padding(.vertical, LiquidSpace.s300)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            // I1 en la lista: la fila activa se ilumina con el tono (rango 10-16 % del épico).
            .background(activa ? tono.opacity(LiquidChart.filaActivaAlfa) : Color.clear)
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

    /// El marcador de índice de la fila: una BARRA VERTICAL, no un círculo. Paridad del mock
    /// canónico (`.lvl .tick`: barra 2×14, activa 2.5×17 del tono; auditoría Grok+DeepSeek
    /// 2026-08-03). Del tono cuando la fila es la activa o la de hoy; tenue (tinta10) si no.
    /// La barra se centra en una columna de 8 pt: el mismo ancho que ocupaba el círculo, para
    /// no correr el texto ni la sangría del separador de `LiquidLevelsList`.
    @ViewBuilder private var punto: some View {
        let esTono: Bool = activa || esHoy
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(esTono ? tono : LiquidColor.tinta10)
            .frame(width: activa ? 2.5 : 2, height: activa ? 17 : 14)
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
        public let hoyEtiqueta: String?
        public let a11yHint: String?
        public let onTap: () -> Void

        public init(etiqueta: String, rango: String, conteo: String,
                    esHoy: Bool = false, activa: Bool = false,
                    hoyEtiqueta: String? = nil, a11yHint: String? = nil,
                    onTap: @escaping () -> Void = {}) {
            self.etiqueta = etiqueta
            self.rango = rango
            self.conteo = conteo
            self.esHoy = esHoy
            self.activa = activa
            self.hoyEtiqueta = hoyEtiqueta
            self.a11yHint = a11yHint
            self.onTap = onTap
        }
    }

    private let filas: [Fila]
    private let tono: Color

    public init(filas: [Fila], tono: Color) {
        self.filas = filas
        self.tono = tono
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(filas.enumerated()), id: \.offset) { (i: Int, f: Fila) in
                LiquidLevelRow(etiqueta: f.etiqueta, rango: f.rango, conteo: f.conteo,
                               esHoy: f.esHoy, activa: f.activa, tono: tono,
                               hoyEtiqueta: f.hoyEtiqueta, a11yHint: f.a11yHint,
                               onTap: f.onTap)
                if i < filas.count - 1 {
                    // Sangría: margen de la fila + el punto + su gap, para que la línea
                    // arranque bajo el TEXTO y la columna de puntos se lea como un riel.
                    Rectangle()
                        .fill(LiquidColor.tinta10)
                        .frame(height: 1)
                        .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
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
