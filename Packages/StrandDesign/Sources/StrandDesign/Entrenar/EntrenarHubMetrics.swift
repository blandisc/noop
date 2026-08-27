import SwiftUI

// MARK: - Entrenar · métricas del mosaico del hub v18 (FER-171 · Parte B)
//
// La Parte A dejó la receta compartida de vidrio/mini-barras/cápsula-puerta (`EntrenarVidrio`,
// `EntrenarMiniBarras`, `EntrenarCapsulaPuerta`). Este archivo junta lo que le falta a cada módulo
// PROPIO del mosaico (semana, dosis, marcas, volumen, descanso, constancia, historial, héroe) —
// geometría y tipografía que no se repite en dos sitios, así que no le tocaba vivir en la Parte A.
// Cada valor cita su clase CSS exacta del mock `eje-hub-v18.html` — nada suelto en
// `Cenit/Screens/Entrenar/*.swift`.
public enum EntrenarHubMetrics {

    // MARK: SEMANA — la tesela de día (mock `.dia`)

    public static let teselaSize: CGFloat = 26
    public static let teselaRadius: CGFloat = 8
    /// Aro punteado de un día SIN plan (mock `.d-off{border:1.5px dashed var(--t10)}`).
    public static let teselaOffAlfa: Double = 0.10
    public static let teselaOffLineWidth: CGFloat = 1.5
    /// Aro de HOY, tinta llena (mock `.d-hoy{border:2px solid var(--t9)}`).
    public static let teselaHoyLineWidth: CGFloat = 2
    /// Gap de la fila de teselas — mock `.semRow{gap:8px}` (las 7 teselas quedan a ancho FIJO,
    /// nunca `.frame(maxWidth: .infinity)`; solo «EDITAR ›» se empuja al filo con un `Spacer`).
    public static let semRowGap: CGFloat = 8
    /// La inicial del día DENTRO de la tesela — grotesk 9.5/700 (mock `.dia{font-size:9.5px;
    /// font-weight:700}`). Ronda 2 · G11: vivía inline en `EntrenarHubSemana`, movido aquí (Grotesk
    /// sí acepta `relativeTo:` vía `.custom`, a diferencia de los tamaños SF de arriba).
    public static let teselaLabel = InstrumentoType.grotesk(9.5, weight: .bold, relativeTo: .caption2)
    /// El blanco táctil de una tesela — 44 pt (Ronda 2 · O3), el dibujo se queda en `teselaSize`
    /// (26) — mismo patrón que `EntrenarCapsulaPuerta` (dibujo chico, toque HIG).
    public static let teselaToque: CGFloat = 44

    // MARK: DOSIS — el riel de series por músculo (mock `.dtrack`/`.drow`)

    public static let dosisTrackHeight: CGFloat = 7
    public static let dosisTrackRadius: CGFloat = 4
    /// Fondo del riel — blanco al 60 % (mock `.dtrack{background:rgba(255,255,255,.6)}`).
    public static let dosisTrackFondoAlfa: Double = 0.60
    /// Los dos ticks MUDOS de referencia (50 % y 100 % del tope) — tinta al 30 %, sin texto (mock
    /// `.band`/`.dtrack::after`).
    public static let dosisTickAlfa: Double = 0.30
    public static let dosisTickWidth: CGFloat = 1.5
    /// Ancho fijo del rótulo de 3 letras (mock `.drow i{flex:0 0 30px}`).
    public static let dosisLabelWidth: CGFloat = 30
    /// Ancho fijo del numeral de series, para que la columna no baile fila a fila (mock
    /// `.drow b{flex:0 0 18px}`).
    public static let dosisNumeralWidth: CGFloat = 18
    /// Fill «bajo la banda» — cian al 65 % en vez del cian sólido (mock `.fill.low`).
    public static let dosisFillBajoAlfa: Double = 0.65
    /// Entre filas del riel (mock `.drow{margin-top:8px}`, salvo la primera).
    public static let dosisRowTop: CGFloat = 8
    /// Dentro de una fila: rótulo · riel · numeral (mock `.drow{gap:9px}`).
    public static let dosisRowGap: CGFloat = 9

    // MARK: VOLUMEN — las 8 barras semanales (mock `.vbars`/`.vb`)

    public static let vbarsHeight: CGFloat = 30
    public static let vbarsRadius: CGFloat = 3
    public static let vbarsGap: CGFloat = 4
    public static let vbarsEmptyAlfa: Double = 0.08
    public static let vbarsCantoAlfa: Double = 0.12

    // MARK: CONSTANCIA — la rejilla 13 semanas × 3 huecos (mock `.ghgrid`)

    public static let ghgridGap: CGFloat = 4
    public static let ghgridRadius: CGFloat = 3
    public static let ghgridEmptyAlfa: Double = 0.08
    public static let ghgridCantoAlfa: Double = 0.12
    public static let ghgridHoyStroke: CGFloat = 1.8

    // MARK: PAR DEL DÍA — el riel de «Descanso real» (mock `.tDes .rtrack`)

    public static let restTrackHeight: CGFloat = 6
    public static let restTrackRadius: CGFloat = 3
    public static let restFillAlfa: Double = 0.75
    public static let restPlanTickWidth: CGFloat = 1.5
    public static let restPlanTickAlfa: Double = 0.30

    // MARK: HÉROE — el CTA verde y la píldora «Otra forma» (mock `.ctaV`/`.otra`)

    public static let heroCTAMinWidth: CGFloat = 168
    public static let heroCTAShadowY: CGFloat = 6
    public static let heroCTAShadowRadius: CGFloat = 8
    public static let heroCTAShadowAlfa: Double = 0.28
    public static let otraFormaPaddingH: CGFloat = 18
    public static let otraFormaFondoAlfa: Double = 0.62
    public static let otraFormaHighlightAlfa: Double = 0.85
    public static let otraFormaCantoAlfa: Double = 0.10
    public static let otraFormaShadowY: CGFloat = 2
    public static let otraFormaShadowRadius: CGFloat = 3
    public static let otraFormaShadowAlfa: Double = 0.06

    // MARK: HÉROE — la píldora «Hoy subes» (mock `.subPill`)

    public static let subPillPaddingLeading: CGFloat = 9
    public static let subPillPaddingTrailing: CGFloat = 15
    public static let subPillPaddingV: CGFloat = 8
    public static let subPillFondoAlfa: Double = 0.10
    public static let subPillHighlightAlfa: Double = 0.80
    public static let subPillAroAlfa: Double = 0.40
    public static let subPillCantoAlfa: Double = 0.30
    public static let subPillShadowY: CGFloat = 2
    public static let subPillShadowRadius: CGFloat = 3
    public static let subPillShadowAlfa: Double = 0.10
    /// El disco blanco «↑» dentro de la píldora (mock `.subPill .up{width:18px;height:18px}`).
    public static let subPillBadge: CGFloat = 18
    /// El texto de la píldora — 12.5/400 BASE (mock `.subPill{font-size:12.5px}`, sin peso propio →
    /// regular). Ronda 2 · D2: es texto de LECTURA, así que debe escalar con Dynamic Type — pero
    /// `Font.system(size:)` es de tamaño fijo y SF no acepta `relativeTo:` (a diferencia de Grotesk,
    /// que sí vía `.custom(_:size:relativeTo:)`, ver `LiquidType`). El patrón del sistema para SF a
    /// tamaño propio es `@ScaledMetric(relativeTo:)` EN LA VISTA (un `enum` estático no tiene
    /// entorno) — este archivo solo publica la base; `EntrenarHubHeroe` la escala.
    public static let subPillTextoBase: CGFloat = 12.5
    /// El glifo «↑» dentro del disco — grotesk 10/700 (mock `.subPill .up{font-size:10px;font-weight:700}`).
    public static let subPillGlifo = InstrumentoType.grotesk(10, weight: .bold)

    // MARK: SEMANA / CONSTANCIA — el valor a la derecha de la regla (mock `.semVal`)

    /// «2 DE 3» / «10 ESTE MES» — el numeral de la regla del nivel, alineado a la derecha. Grotesk
    /// 15/700, tracking −0.3, tabular (mock `.semVal{font-size:15px;font-weight:700;letter-spacing:-.3px}`).
    public static let semValNumeral = InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline)
    public static let semValTracking: CGFloat = -0.3
    /// El calificativo pequeño junto al numeral («DE 3» / «ESTE MES») — 8.5/600, tracking 1 (mock
    /// `.semVal small{font-size:8.5px;color:var(--t5);letter-spacing:1px;font-weight:600}`).
    public static let semValCalificativo = InstrumentoType.grotesk(8.5, weight: .semibold, relativeTo: .caption2)
    public static let semValCalificativoTracking: CGFloat = 1

    // MARK: HÉROE — ritmo vertical propio (mock `.hero`/`h1`/`.meta`/`.nombres`/`.subPill`/`.ctaRow`)

    /// Padding propio del héroe — v16/h18 (mock `.hero{padding:16px 18px}`), distinto del default de
    /// `EntrenarModulo` (v11/h18): el único módulo que pasa su propio `insets` (Parte A, doc de
    /// `EntrenarModulo.init`).
    public static let heroInsets = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// Intensidad del vidrio índigo del héroe — 0.11, no el 0.10 por defecto (mock `.hero{background:
    /// rgba(93,90,158,.11)}`; Parte A ya documenta el override en `EntrenarVidrioMetrics`).
    public static let heroIntensidad: Double = 0.11
    /// Kicker → nombre de la rutina (mock `.hero h1{margin:5px 0 3px}`, mitad superior).
    public static let heroKickerToTituloTop: CGFloat = 5
    /// Nombre de la rutina → meta (misma regla, mitad inferior).
    public static let heroTituloToMetaTop: CGFloat = 3
    /// Meta — 12.5/500, tabular (mock `.meta{font-size:12.5px;font-weight:500;font-variant-numeric:
    /// tabular-nums}`).
    public static let heroMeta = InstrumentoType.grotesk(12.5, weight: .medium, relativeTo: .footnote)
    /// Meta → nombres de ejercicios (mock `.nombres{margin-top:11px}`).
    public static let heroMetaToNombresTop: CGFloat = 11
    /// Nombres de ejercicios — 12/400 BASE, line-height 1.6, ancho máximo 300 (mock `.nombres{
    /// font-size:12px;line-height:1.6;max-width:300px}`). Ronda 2 · D2: base para `@ScaledMetric`
    /// en la vista (ver `subPillTextoBase`).
    public static let heroNombresBase: CGFloat = 12
    public static let heroNombresLineSpacing: CGFloat = 7.2   // 12 × (1.6 − 1) ≈ 7.2
    public static let heroNombresMaxWidth: CGFloat = 300
    /// Nombres → píldora «Hoy subes» (mock `.subPill{margin-top:13px}`).
    public static let heroNombresToSubPillTop: CGFloat = 13
    /// Píldora «Hoy subes» → fila CTA (mock `.ctaRow{margin-top:12px}`).
    public static let heroSubPillToCtaTop: CGFloat = 12
    public static let heroCtaGap: CGFloat = 14
    /// «Empezar» — grotesk 14/600 (mock `.ctaV{font-size:14px;font-weight:600}`).
    public static let heroCTATexto = InstrumentoType.grotesk(14, weight: .semibold)
    /// «Otra forma ⌄» — grotesk 13/600 (mock `.otra{font-size:13px;font-weight:600}`).
    public static let heroOtraFormaTexto = InstrumentoType.grotesk(13, weight: .semibold)

    // MARK: HÉROE / PAR / MARCAS·VOLUMEN — el numeral grande + su fila (mock `.numRow`)

    /// El numeral de 26 pt de un tile → lo que le sigue (mock `.numRow{margin-top:7px}`, compartido
    /// por Subidas listas, Descanso real, Marcas y Volumen).
    public static let numRowTop: CGFloat = 7
    public static let numRowGap: CGFloat = 4

    // MARK: PAR — «Subidas listas» (mock `.subLs`) y «Descanso real» (mock `.sub2`)

    public static let subLsTop: CGFloat = 8
    public static let subLsGap: CGFloat = 4
    /// Una fila de «Subidas listas» — 11/400 BASE color t7 (mock `.subLs div`). Ronda 2 · D2: base
    /// para `@ScaledMetric` en la vista.
    public static let subLsFilaBase: CGFloat = 11
    /// El delta en negritas — grotesk 10.5/700, tabular (mock `.subLs b`).
    public static let subLsDelta = InstrumentoType.groteskNumber(10.5, weight: .bold, relativeTo: .caption)
    /// El «▲» que antecede al delta — 8 pt (mock `.subLs b i{font-size:8px}`).
    public static let subLsGlifo = Font.system(size: 8)
    /// La cláusula de «Descanso real» — 11/400 BASE, line-height 1.55, tabular (mock `.tDes .sub2`).
    /// Ronda 2 · D2: base para `@ScaledMetric` en la vista.
    public static let restClausulaBase: CGFloat = 11
    public static let restClausulaLineSpacing: CGFloat = 6   // 11 × (1.55 − 1) ≈ 6
    public static let restTrackTop: CGFloat = 10

    // MARK: MARCAS · VOLUMEN — el pie de cada tile (mock `.tMar .ult`/`.prev`, `.tVol .delta`)

    public static let marcasUltTop: CGFloat = 8
    /// «Sentadilla · peso máx» — 11/400 BASE color t7 (mock `.tMar .ult`). Ronda 2 · D2: base para
    /// `@ScaledMetric` en la vista.
    public static let marcasUltBase: CGFloat = 11
    /// «antes 100.0 · hace 2 días» — 11/400 BASE color t5, tabular (mock `.tMar .prev`). Ronda 2 ·
    /// D2: base para `@ScaledMetric` en la vista.
    public static let marcasPrevBase: CGFloat = 11
    /// «↗ +9 %» — grotesk 10.5/700 (mock `.delta`).
    public static let volumenDelta = InstrumentoType.grotesk(10.5, weight: .bold, relativeTo: .caption)

    // MARK: CUERPO — la fila del pictograma (mock `.cuerpo`)

    public static let cuerpoGap: CGFloat = 10
    /// «Espalda baja cargada · el resto, fresco» — 11.5/400 BASE color t7 (mock `.cuerpo{font-size:
    /// 11.5px}`). Ronda 2 · D2: base para `@ScaledMetric` en la vista.
    public static let cuerpoLineaBase: CGFloat = 11.5
    public static let cuerpoPictogramSize = CGSize(width: 15, height: 23)

    // MARK: HISTORIAL (mock `.hist`/`.fila`/`.hueco`/`.prom`)

    public static let historialFilaGap: CGFloat = 10
    public static let historialFilaPaddingV: CGFloat = 8
    /// El título de una fila — 13.5/600 BASE (mock `.fila .tit`). Ronda 2 · D2: base para
    /// `@ScaledMetric` en la vista (el peso `.semibold` lo aplica el caller).
    public static let historialTituloBase: CGFloat = 13.5
    /// El subtítulo de una fila — 11/400 BASE color t5, tabular (mock `.fila .subt`). Ronda 2 · D2:
    /// base para `@ScaledMetric` en la vista.
    public static let historialSubtituloBase: CGFloat = 11
    /// El indentado de «· · N días sin registrar», a plomo con el NOMBRE tras el bead (mock `.hueco{
    /// padding-left:19px}` = el bead de 9 pt + el gap de fila de 10 pt).
    public static let historialHuecoIndent: CGFloat = 19
    public static let historialPromTop: CGFloat = 6
    public static let historialPromPaddingTop: CGFloat = 9
    public static let historialPromPaddingBottom: CGFloat = 4
    public static let historialPromGap: CGFloat = 14
    /// El calificativo junto al numeral del pie («min»/«kcal»/«t») — 9/600 color t5, tracking nulo
    /// aquí (va pegado, no en mayúsculas de regla) (mock `.prom .pv small{font-size:9px;font-weight:
    /// 600;margin-left:2px}`).
    public static let historialPromUnidad = InstrumentoType.grotesk(9, weight: .semibold, relativeTo: .caption2)

    // MARK: Tipografía propia del mosaico (no cubierta por `LiquidType`)

    /// El rótulo de 9/600/tracking 2 que se repite en cuatro sitios del mosaico (mock `.drow i`,
    /// `.hueco`, `.prom .pl`, `.ghlabs i`) — el MISMO tamaño en los cuatro, un peldaño bajo
    /// `LiquidType.regla` (10/600/tracking 2.2). Un solo nombre para las cuatro apariciones.
    public static let microLabel9 = InstrumentoType.grotesk(9, weight: .semibold, relativeTo: .caption2)
    public static let microLabel9Tracking: CGFloat = 2
    /// El numeral del pie «Promedio · 7 días» (mock `.prom .pv{font-size:12px;font-weight:700}`).
    public static let promedioNumeral = InstrumentoType.groteskNumber(12, weight: .bold, relativeTo: .caption)
}

public extension View {
    /// El rótulo compartido de 9/600/tracking 2 — ver `EntrenarHubMetrics.microLabel9`. El color lo
    /// pone el caller (casi siempre `LiquidColor.tinta500`).
    func entrenarHub9Label() -> some View {
        self.font(EntrenarHubMetrics.microLabel9)
            .tracking(EntrenarHubMetrics.microLabel9Tracking)
            .textCase(.uppercase)
    }
}

#if DEBUG
#Preview("EntrenarHubMetrics · muestras") {
    VStack(alignment: .leading, spacing: 20) {
        Text(verbatim: "PEC").entrenarHub9Label().foregroundStyle(LiquidColor.tinta500)
        RoundedRectangle(cornerRadius: EntrenarHubMetrics.teselaRadius, style: .continuous)
            .fill(LiquidColor.cian)
            .frame(width: EntrenarHubMetrics.teselaSize, height: EntrenarHubMetrics.teselaSize)
            .overlay {
                Text(verbatim: "J").font(EntrenarHubMetrics.teselaLabel).foregroundStyle(.white)
            }
        HStack(spacing: EntrenarHubMetrics.vbarsGap) {
            ForEach(0..<8, id: \.self) { i in
                RoundedRectangle(cornerRadius: EntrenarHubMetrics.vbarsRadius, style: .continuous)
                    .fill(i == 7 ? AnyShapeStyle(LiquidColor.ambar)
                                 : AnyShapeStyle(LiquidColor.tinta900.opacity(EntrenarHubMetrics.vbarsEmptyAlfa)))
                    .frame(width: 20, height: EntrenarHubMetrics.vbarsHeight * (0.4 + Double(i) * 0.07))
            }
        }
        .frame(height: EntrenarHubMetrics.vbarsHeight, alignment: .bottom)
        Text(verbatim: "42").font(EntrenarHubMetrics.promedioNumeral).foregroundStyle(LiquidColor.tinta700)
    }
    .padding(24)
    .background(LiquidColor.fondoGradient)
}
#endif
