import SwiftUI

// MARK: - Entrenar · tokens (FER-83 · E2 de «Entrenar, reconstruido»)
//
// La sección se reconstruye entera. Si cada pantalla dibuja sus propias filas, chips y bandas,
// terminamos con seis versiones de la misma tabla y ningún cambio se puede hacer una sola vez.
// Este archivo es la caja de piezas: los valores que aparecen dos veces en dos archivos distintos
// viven aquí, y las pantallas solo los ensamblan.
//
// El paquete NO importa StrandTraining (mismo precedente que `RoutineGlyph`): la familia de
// movimiento se declara del lado del diseño y la app mapea su `RoutineRegion` a esta.

/// La familia de movimiento de una rutina — la identidad de color que recorre toda la sección.
/// Espeja `RoutineGlyphKind` (y, del lado de la app, `RoutineRegion`).
public enum EntrenarFamily: String, Sendable, CaseIterable, Hashable {
    case push, pull, legs, fullBody

    /// El tinte de identidad: ámbar empuje · cian tirón · índigo pierna y completo. LA fuente, en
    /// singular: `RoutineRegion.tint` y `InstrumentoTheme.movementFamilyTint` delegan aquí.
    ///
    /// Hasta FER-88 había TRES definiciones de lo mismo y no coincidían: esta decía `dataSteps`
    /// (#4C8998) mientras las otras dos decían `dataHrv` (#147C8C), así que un mismo tirón salía de
    /// dos colores según quién lo dibujara. Gana el vivo — es lo que la gente ya tiene en pantalla,
    /// y además cumple AA (4.33:1) donde el otro se queda en 3.48:1.
    ///
    /// Hue saturado: solo para bolitas, barras, marcos y numerales ≥ 24 pt, nunca para texto chico
    /// (para eso está `reading`).
    public func tint(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .push:            return theme.dataStrain
        case .pull:            return theme.dataHrv
        case .legs, .fullBody: return theme.dataSleep
        }
    }

    /// El tono de LECTURA de esa misma identidad: el mismo hue oscurecido hasta cumplir contraste
    /// de texto (≥ 4.5:1) sobre el papel vivo. Es el par obligatorio del anterior — «hue de dato /
    /// tono de lectura» — para que un rótulo de familia nunca se pinte en el hue saturado.
    public func reading(_ theme: InstrumentoTheme) -> Color {
        OKLab.darkened(tint(theme), toContrast: 4.5, against: theme.paper)
    }

    /// Nombre visible de la familia (es-MX vía catálogo).
    public var label: LocalizedStringKey {
        switch self {
        case .push:     return "Push"
        case .pull:     return "Pull"
        case .legs:     return "Legs"
        case .fullBody: return "Full body"
        }
    }

    /// El glifo de línea que ya existe para esta familia, para no inventar dos vocabularios.
    public var glyph: RoutineGlyphKind {
        switch self {
        case .push:     return .push
        case .pull:     return .pull
        case .legs:     return .legs
        case .fullBody: return .fullBody
        }
    }
}

/// El ritmo de la sección: las alturas y los blancos táctiles que se repiten en más de una pantalla.
/// Base 4, alineado al handoff. Lo que no está aquí vive en `CenitMetrics` (márgenes, radios, gaps).
public enum EntrenarMetrics {
    /// Fila mínima y blanco táctil (HIG). El dibujo puede ser menor; el toque nunca.
    public static let row: CGFloat = CenitMetrics.touchTarget      // 44
    /// Fila de la tabla de series: más alta que una fila de lista porque es un campo de captura.
    public static let tableRow: CGFloat = 48
    /// Badge del número de serie (dibujo 28, toque 44).
    public static let badge: CGFloat = 28
    /// Palomita de serie hecha (dibujo 24, celda entera tocable).
    public static let check: CGFloat = 24
    /// Botón primario del héroe.
    public static let primaryButton: CGFloat = 46
    /// Botón secundario / píldora de papel («Saltar», «+ Serie»).
    public static let secondaryButton: CGFloat = 36
    /// Aire dentro de una banda (descanso, franjas de sección).
    public static let bandGap: CGFloat = 12
    /// Canal entre columnas de la tabla.
    public static let columnGap: CGFloat = 12
    /// Grosor del subrayado de tinta que marca la serie en curso bajo el numeral del badge
    /// (`SetTable`, decisión 2026-07-19: aro `dataStrain` + subrayado, nunca relleno por familia).
    /// Antes de FER-86 este mismo valor marcaba el filo IZQUIERDO de la fila — se retiró (r6, la
    /// pantalla ya decidió «sin resaltado de fila»): el numeral subrayado es la única señal.
    public static let currentEdge: CGFloat = 2
    /// Alto de la barra de progreso de la sesión.
    public static let progressBar: CGFloat = 3
    /// Radio de esquina de la barra de progreso de la sesión (FER-133, handoff «Sesión en vivo» v4).
    public static let progressBarRadius: CGFloat = 2
    /// Margen horizontal de la cabecera compacta, la barra de progreso y el hilo de la sesión en vivo
    /// (FER-133, handoff «Sesión en vivo» v4: «padding 30 20 0» / «margen 12 20 0»). Distinto de
    /// `CenitMetrics.screenPadding` (24) que usa el resto de esta misma pantalla (resumen, listas) —
    /// esta cabecera compacta es una franja angosta de 36 pt, no el cuerpo de la hoja.
    public static let sessionHeaderMarginH: CGFloat = 20
    /// Aire sobre la cabecera compacta de la sesión en vivo, antes de la fila «‹»/título/reloj
    /// (FER-133, handoff «Sesión en vivo» v4: «padding 30 20 0»).
    public static let sessionHeaderPaddingTop: CGFloat = 30
    /// Aire bajo la cabecera compacta (FER-133, handoff «Sesión en vivo» v4: «padding 30 20 0» — el
    /// último número es el margen inferior). Cero: el bloque de abajo (barra, hilo o la primera fila
    /// de la lista) ya trae su propio aire superior, así que un segundo colchón aquí lo duplicaría.
    public static let sessionHeaderPaddingBottom: CGFloat = 0
    /// Ancho del subrayado de tinta bajo el numeral en curso (`SetTable.badge`).
    public static let badgeUnderline: CGFloat = 16
    /// Cuánto baja el subrayado de tinta respecto al numeral (`SetTable.badge`).
    public static let badgeUnderlineOffset: CGFloat = 5
    /// Ancho de la columna RPE — más angosta que KG/REPS/DIST/TIME (su contenido es «RPE» o «9,5»).
    public static let rpeColumn: CGFloat = 44
    /// Separación vertical del layout apilado de una fila en reflow (`SetTable`, Dynamic Type de
    /// accesibilidad): badge+check arriba, datos abajo.
    public static let reflowRowGap: CGFloat = 8
    /// Separación horizontal entre celdas de dato en el layout apilado de reflow.
    public static let reflowCellGap: CGFloat = 16
    /// Ancho y alto del cursor de una celda EN EDICIÓN (`SetTable`, corazón de FER-952).
    public static let caretWidth: CGFloat = 2
    public static let caretHeight: CGFloat = 18
    /// Grosor del subrayado de una celda de captura: fino en reposo, grueso mientras se edita.
    public static let cellUnderline: CGFloat = 1
    public static let cellUnderlineActive: CGFloat = 2
    /// Cuánto crece una fila armada para borrar (long-press) antes de que aparezca su pastilla.
    public static let armedLift: CGFloat = 1.03
    /// Geometría de la sombra transitoria de esa misma fila armada.
    public static let armedShadowRadius: CGFloat = 10
    public static let armedShadowY: CGFloat = 4
    /// Cuánto hay que sostener el toque para armar el borrado de una serie (`SetTable`).
    public static let deleteHoldDuration: Double = 0.4
    /// Relleno de la pastilla «Quitar serie» que aparece sobre la fila armada.
    public static let deletePillPaddingH: CGFloat = 9
    public static let deletePillPaddingV: CGFloat = 5
    /// Lado de una celda del calendario tipo contribuciones, en su tamaño chico y grande.
    public static let calendarCellMini: CGFloat = 9
    public static let calendarCell: CGFloat = 13
    /// Separación entre celdas del calendario.
    public static let calendarGap: CGFloat = 3
    /// Diámetro de un token de día de la semana.
    public static let weekToken: CGFloat = 22
    /// Riel de carga muscular.
    public static let loadRail: CGFloat = 6
    /// Esquina de una celda del calendario: la única esquina de la sección que no es un radio de
    /// control, porque la celda es un pixel de gráfico, no un contenedor.
    public static let calendarRadius: CGFloat = 3
    /// El radio del orbe del veredicto, por superficie (handoff v3). La pastilla teñida que
    /// vivía aquí se retiró con FER-85: el hue no llena fondos, y el handoff lo revierte explícito.
    public static let orbeLanding: CGFloat = 15.5
    public static let orbeSesion: CGFloat = 11
    public static let orbeHoja: CGFloat = 20
    /// El radio del orbe del hilo compacto en la cabecera de la SESIÓN EN VIVO del iPhone (FER-133,
    /// handoff «Sesión en vivo» v4: «EntrenarHilo(radio: EntrenarMetrics.orbeSesion = 32)»). Distinto
    /// de `orbeSesion` (11): ese token es el radio del hilo en la cara del Apple Watch
    /// (`WatchSessionRootView`, ~40 mm), una superficie mucho más chica que esta cabecera de iPhone —
    /// reusarlo aquí dejaba el orbe visiblemente chico junto al título de 16 pt y el resto de la
    /// cabecera de 36 pt.
    public static let orbeSesionCabecera: CGFloat = 32
    /// El aro punteado que ocupa el lugar del orbe cuando no hay lectura.
    public static let aroHueco: CGFloat = 22
    /// El punto de identidad de familia. UN tamaño, no dos: antes de FER-86 este punto estaba
    /// copiado seis veces en crudo por la app, la mitad a 8 pt y la mitad a 9.
    public static let familyDot: CGFloat = 9
    /// El punto de familia en la cabecera COMPACTA de la sesión en vivo (FER-133, handoff «Sesión
    /// en vivo» v4): más chico que el punto de fila (9) porque acompaña un título de 16 pt en una
    /// sola línea de 36 pt de alto, no una fila de lista.
    public static let familyDotCompact: CGFloat = 6
    /// El aro de papel que lo recorta cuando cae sobre un fondo ocupado (una miniatura, una tarjeta).
    public static let familyDotKnockout: CGFloat = 15
    /// Cuánto se indenta el subtítulo de una fila bajo un `EntrenarFamilyDot`, para que quede
    /// alineado con el NOMBRE (después del punto), no con el punto mismo — el diámetro del punto
    /// (9) más el aire que lo separa del texto en esa misma fila (7).
    public static let familyDotIndent: CGFloat = familyDot + 7

    // MARK: - Ritmo de la landing («Ritmo 1b», FER-130)
    //
    // Los márgenes verticales literales del handoff, de arriba a abajo. Donde el número ya
    // coincidía con un token de `CenitMetrics` (4/8/12/16) la landing usa ESE, no uno nuevo —
    // los de aquí son los que no tenían casa: 6, 18, 20, 24, 28 y los dos que sí coinciden pero
    // el handoff los nombra aparte porque son parte del mismo ritmo nombrado, no un espaciado
    // genérico (se documenta la equivalencia en cada uno).

    /// El «HOY · día» del héroe, separado del hilo del veredicto de arriba.
    public static let heroKickerTop: CGFloat = 24
    /// El nombre de la rutina, separado de su kicker «HOY».
    public static let heroTitleTop: CGFloat = 6
    /// La línea de músculos, separada del título. (= `CenitMetrics.space2`.)
    public static let heroSubTop: CGFloat = CenitMetrics.space2
    /// Los tres numerales de la sesión («~50 min · 6 ejercicios · 18 series»), separados del subtítulo.
    public static let heroNumeralsTop: CGFloat = 20
    /// El canal entre los tres numerales, cuando se dibujan como bloques sueltos (handoff «canal 28»)
    /// — la landing hoy los lee como una sola frase con «·», así que este canal no tiene un sitio
    /// vivo todavía; se documenta para no perder el número del handoff.
    public static let heroNumeralsGap: CGFloat = 28
    /// La línea de progresión / subida del día, separada de los numerales. (= `CenitMetrics.gap`.)
    public static let heroProgressTop: CGFloat = CenitMetrics.gap
    /// La fila «Empezar + Otra forma», separada del bloque de arriba.
    public static let ctaRowTop: CGFloat = 20
    /// El primer nivel del hub («Tu plan»), separado de la fila CTA.
    public static let firstLevelTop: CGFloat = 18
    /// Cada nivel del hub que NO es el primero, separado del nivel anterior.
    /// Los niveles siguientes (el prototipo los separa con margin-top 10; el README da el rango 2-10 y
    /// el segundo nivel real de la landing usa 10). Con 2 el filo quedaba pegado a la fila de arriba.
    public static let levelTop: CGFloat = 10
    /// El aire entre el filo superior de un nivel y su fila de encabezado. (= `CenitMetrics.space1`.)
    public static let levelPadTop: CGFloat = CenitMetrics.space1

    /// El título del héroe de Descanso («Descanso»), FER-132: el prototipo lo dibuja a 40 pt / 700 /
    /// tracking -1 — un escalón MÁS GRANDE que el título de un día con rutina (Grotesk 32), porque
    /// «Descanso» es una sola palabra corta y el handoff le da más peso para llenar el mismo espacio
    /// vertical. No existía un token para 40 antes de este estado.
    public static let restHeroTitle: CGFloat = 40

    /// El canal entre «Empezar»/«Movilidad»/«Continuar» y el enlace quiet que lo acompaña en la MISMA
    /// fila del héroe (handoff «Ritmo 1b»/FER-132 ronda 2): antes un `16` suelto se repetía en los
    /// tres héroes (rutina, descanso, sesión viva) sin nombre.
    public static let ctaRowGap: CGFloat = 16

    // MARK: - «QUEDABAN» (RIR) del teclado propio (FER-134, handoff «Sesión en vivo»)

    /// El botón del segmento 0 · 1 · 2 · 3 · 4+ (`SessionKeypad.rirRow`): más chico que
    /// `CenitMetrics.touchTarget` (44) a propósito — son cinco botones apretados en una sola
    /// píldora dentro de la fila del teclado, no un blanco táctil aislado; la fila entera (padding +
    /// alto) supera el mínimo de toque.
    public static let rirButton: CGFloat = 30
    /// El separador vertical entre botones del segmento RIR.
    public static let rirDivider: CGFloat = 18
    /// El grosor del divisor entre botones y del borde de la píldora del segmento RIR (revisión ronda
    /// 4, hallazgo menor): antes tomaba prestado `cellUnderline`, cuyo contrato documentado es el
    /// subrayado de una celda de la tabla, no un hairline genérico de borde/divisor.
    public static let rirHairline: CGFloat = 1

    /// El aire vertical del contenedor exterior de la banda de descanso (`RestBand`), FER-134 ronda 2:
    /// antes un `10` suelto (heredado de la banda vieja) se reemplazó por `4` sin nombre — la banda
    /// nueva es más compacta, así que el respiro exterior también se achica.
    public static let restBandOuterInset: CGFloat = 4

    /// El thumb del ejercicio HECHO, colapsado en el acordeón (handoff «Sesión en vivo» §1): más
    /// chico que el thumb activo porque la fila entera ya está atenuada (`StrandOpacity.dim`).
    public static let doneRowThumb: CGFloat = 28
    /// El thumb de un ejercicio PRÓXIMO en el acordeón (handoff «Sesión en vivo» §7).
    public static let comingRowThumb: CGFloat = 34

    // MARK: - Rejilla 4×4 del teclado propio (FER-134 ítem 8, handoff «Sesión en vivo» bloque teclado)

    /// El lado de cada tecla de la rejilla (numéricas y las 4 de acción) — el mismo mínimo de toque
    /// que `CenitMetrics.touchTarget`, nombrado aquí porque la rejilla lo fija por diseño (handoff),
    /// no por regla de accesibilidad genérica.
    public static let keyCap: CGFloat = 44
    /// El radio de esquina de cada tecla.
    public static let keyRadius: CGFloat = 12
    /// El aire horizontal y vertical entre teclas de la rejilla.
    public static let keyGap: CGFloat = 6
}

/// El estado de una celda del calendario de entrenamiento. Es un token porque lo consumen dos
/// tamaños del mismo componente y dos pantallas (landing y historial).
public enum EntrenarCalendarState: Sendable, Hashable {
    /// Sin sesión ese día (ya pasó y no entrenaste).
    case empty
    /// Todavía no llega: un día futuro de la rejilla. No es un hueco tuyo, así que se dibuja más
    /// tenue que un día vacío en vez de acusarte de no haber entrenado mañana.
    case future
    /// Sesión hecha, teñida por la familia que se entrenó.
    case done(EntrenarFamily)
    /// Hoy, sin sesión todavía: aro de tinta, nunca el color del veredicto.
    case today
    /// Día planeado por la semana, aún no entrenado.
    case planned(EntrenarFamily)

    public func fill(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .empty, .today: return theme.hairline
        case .future:        return theme.paper
        case .done(let f):   return f.tint(theme)
        case .planned:       return theme.paper
        }
    }

    public func stroke(_ theme: InstrumentoTheme) -> Color? {
        switch self {
        case .empty:          return nil
        case .future:         return theme.hairline
        case .today:          return theme.ink
        case .done:           return nil
        case .planned(let f): return f.tint(theme)
        }
    }

    /// Lectura para VoiceOver: el calendario es una rejilla densa y sin esto es ruido.
    public var voiceOver: LocalizedStringKey {
        switch self {
        case .empty:          return "no session"
        case .future:         return "not yet"
        case .done:           return "session done"
        case .today:          return "today"
        case .planned:        return "planned"
        }
    }
}

/// El kicker compartido de Entrenar (handoff «Ritmo 1b», tokens.json): 11.5 pt / 600 / tracking 1.5,
/// mayúsculas — el color es lo único que cambia por rol (tinta700 en la cabecera de pantalla,
/// tinta500 en el overline del héroe y en `EntrenarNivel`). El handoff dibuja los tres con el mismo
/// inline style, así que los tres usan esta misma receta en vez de tres kickers distintos.
///
/// Distinto, a propósito, del kicker de fecha de `TodayView` (`shortDate`, 11 pt / 600 /
/// tracking 2 — ver `TodayView.headerBlock`): esa receta es la fecha SOLA, sin acompañante, con el
/// tracking más abierto que da aire a un renglón vacío. Aquí el kicker comparte fila con el botón
/// «?» (handoff «Prototipo Entrenar.dc.html» línea 52, literal 11.5/600/1.5) — no es un descuido de
/// no mirar a Hoy, es que la pareja fecha+acción pide una medida distinta a la fecha sola. Si un
/// tercer lugar necesita este mismo patrón (fecha + acompañante), promuévelo a un token compartido
/// en vez de copiar el número.
public extension View {
    func entrenarCabeceraKicker() -> some View {
        self.font(InstrumentoType.grotesk(11.5, weight: .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
    }
}

/// El chip de «marca» de la Bitácora (handoff «Niveles», tokens.json «9.5+1.2 chips»): 9.5 pt / 600 /
/// tracking 1.2 — el mismo escalón de tipografía que las columnas del calendario, un paso más chico
/// que el kicker de cabecera. El color (verdeProfundo sobre su propio tinte al 10 %) lo pone quien
/// arma el chip, no este modificador.
///
/// `relativeTo: .caption2` (quisquilloso ronda 2): a diferencia de `entrenarCabeceraKicker` —un
/// rótulo fijo, «chrome»— esta es una PALABRA leída («marca»/«marcas»), así que sí debe crecer con
/// Dynamic Type.
public extension View {
    func entrenarMarcaChip() -> some View {
        self.font(InstrumentoType.grotesk(9.5, weight: .semibold, relativeTo: .caption2))
            .tracking(1.2)
    }
}

/// La inicial del día bajo cada token de `WeekTokens` (handoff «Niveles», prototipo línea 55):
/// 10.5 pt / 600 / tracking 1.4 — un escalón entre el chip de marca (9.5) y el kicker de cabecera
/// (11.5), porque siete letras solas necesitan más aire que un número de chip para no verse
/// apachurradas contra su vecino.
///
/// `relativeTo: .caption2` (quisquilloso ronda 2): es contenido leído (la inicial del día), no
/// chrome fijo, así que escala con Dynamic Type como el resto del texto de la tira.
public extension View {
    func entrenarWeekDayLabel() -> some View {
        self.font(InstrumentoType.grotesk(10.5, weight: .semibold, relativeTo: .caption2))
            .tracking(1.4)
    }
}

/// El kicker «QUEDABAN» de la fila RIR del teclado propio (FER-134, handoff «Sesión en vivo» §8,
/// prototipo `sesion.txt`): 10.5 pt / 600 / tracking 1.2 — mismo escalón de tamaño que
/// `entrenarWeekDayLabel` pero con SU PROPIO tracking, porque el prototipo lo pide distinto (1.2,
/// no 1.4) y ese modifier ya tiene nombre y doc propios de la inicial del día en `WeekTokens`
/// (revisión ronda 3, hallazgo menor: no pedir prestado un token con nombre y contrato de otra
/// sección).
public extension View {
    func entrenarKeypadKicker() -> some View {
        self.font(InstrumentoType.grotesk(10.5, weight: .semibold, relativeTo: .caption2))
            .tracking(1.2)
    }
}

/// El título de la cabecera COMPACTA de la sesión en vivo (FER-133, handoff «Sesión en vivo» v4):
/// 16 pt / 700, tracking −0.3 — un escalón bajo `groteskScreenTitle` (25 pt), porque esta cabecera
/// ahora comparte fila con el disco de minimizar, el reloj y «Terminar» en vez de ocupar su propia
/// línea.
public extension View {
    func entrenarSessionHeaderTitle() -> some View {
        self.font(InstrumentoType.grotesk(16, weight: .bold, relativeTo: .callout))
            .tracking(-0.3)
    }
}

/// La etiqueta de «Terminar» en la cabecera compacta de la sesión en vivo (FER-133): 12 pt / 600,
/// sin tracking — es una palabra LEÍDA («Terminar»), no un rótulo en mayúsculas, así que no lleva
/// el tracking abierto de `entrenarCabeceraKicker`.
public extension View {
    func entrenarSessionEndLabel() -> some View {
        self.font(InstrumentoType.grotesk(12, weight: .semibold, relativeTo: .caption))
    }
}

#if DEBUG
#Preview("Entrenar · cabecera kicker") {
    Text(verbatim: "Entrenar · Sáb 15 ago")
        .entrenarCabeceraKicker()
        .foregroundStyle(InstrumentoTheme.base.inkSecondary)
        .padding(24)
        .background(InstrumentoTheme.base.paper)
        .instrumentoTheme(.base)
}

#Preview("Entrenar · tokens") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 20) {
        Text("FAMILIA · HUE Y TONO DE LECTURA").instrumentoOverline().foregroundStyle(t.inkTertiary)
        ForEach(EntrenarFamily.allCases, id: \.self) { f in
            HStack(spacing: 12) {
                Circle().fill(f.tint(t)).frame(width: 24, height: 24)
                Text(f.label).font(StrandFont.subhead).foregroundStyle(f.reading(t))
                Spacer()
                RoutineRegionGlyph(f.glyph, tint: f.tint(t)).frame(width: 24, height: 24)
            }
        }
        Text("CALENDARIO · ESTADOS").instrumentoOverline().foregroundStyle(t.inkTertiary)
        HStack(spacing: EntrenarMetrics.calendarGap) {
            ForEach(Array([EntrenarCalendarState.empty, .done(.push), .done(.pull), .done(.legs),
                           .today, .planned(.push)].enumerated()), id: \.offset) { _, s in
                RoundedRectangle(cornerRadius: EntrenarMetrics.calendarRadius, style: .continuous)
                    .fill(s.fill(t))
                    .frame(width: EntrenarMetrics.calendarCell, height: EntrenarMetrics.calendarCell)
                    .overlay {
                        if let stroke = s.stroke(t) {
                            RoundedRectangle(cornerRadius: EntrenarMetrics.calendarRadius, style: .continuous)
                                .strokeBorder(stroke, lineWidth: 1.5)
                        }
                    }
            }
        }
        Text("NIVELES · CHIP DE MARCA Y ETIQUETA DE DÍA").instrumentoOverline().foregroundStyle(t.inkTertiary)
        HStack(spacing: 12) {
            Text("1 mark").entrenarMarcaChip().foregroundStyle(t.positiveText)
                .padding(.horizontal, CenitMetrics.space2).padding(.vertical, CenitMetrics.space1)
                .background(t.tint(t.positiveText), in: Capsule())
            Text(verbatim: "L").entrenarWeekDayLabel().foregroundStyle(t.inkTertiary)
        }
    }
    .padding(24)
    .background(t.paper)
}
#endif

// MARK: - EntrenarFamilyDot — el punto de identidad de familia (FER-86)
//
// La marca más pequeña de la sección, y la que más se había copiado: seis `Circle().fill(...)` en
// crudo repartidos entre el hub, la sesión viva y el editor de rutina, con dos tamaños distintos
// mezclados (8 y 9) y dos formas que nadie había nombrado — el punto pelón y el punto recortado
// con un aro de papel para que se lea sobre un fondo ocupado.
//
// Aquí viven las dos, con un solo tamaño. El tinte lo pasa quien la usa: el paquete de diseño no
// conoce `RoutineRegion` (eso es de la app), así que recibe el estilo ya resuelto.
public struct EntrenarFamilyDot: View {

    private let estilo: AnyShapeStyle
    private let sobreFondo: Bool
    private let size: CGFloat

    @Environment(\.instrumentoTheme) private var theme

    /// - Parameters:
    ///   - estilo: el tinte ya resuelto. `AnyShapeStyle` y no `Color` porque «cuerpo completo» se
    ///     pinta con un degradado que cruza dos familias.
    ///   - sobreFondo: `true` añade el aro de papel que lo recorta sobre un fondo ocupado.
    ///   - size: el diámetro del punto. Por omisión `EntrenarMetrics.familyDot` (9) — el tamaño de
    ///     fila; la cabecera compacta de la sesión en vivo pasa `EntrenarMetrics.familyDotCompact`.
    public init(_ estilo: AnyShapeStyle, sobreFondo: Bool = false, size: CGFloat = EntrenarMetrics.familyDot) {
        self.estilo = estilo
        self.sobreFondo = sobreFondo
        self.size = size
    }

    /// Atajo para el caso normal: un color plano.
    public init(_ color: Color, sobreFondo: Bool = false, size: CGFloat = EntrenarMetrics.familyDot) {
        self.init(AnyShapeStyle(color), sobreFondo: sobreFondo, size: size)
    }

    public var body: some View {
        Circle()
            .fill(estilo)
            .frame(width: size, height: size)
            .background {
                if sobreFondo {
                    Circle().fill(theme.paper)
                        .frame(width: EntrenarMetrics.familyDotKnockout,
                               height: EntrenarMetrics.familyDotKnockout)
                }
            }
            // El color no porta significado por sí solo: la familia siempre viene escrita al lado.
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("EntrenarFamilyDot · las cuatro familias, con y sin aro") {
    let t = InstrumentoTheme.base
    return VStack(alignment: .leading, spacing: 18) {
        ForEach(EntrenarFamily.allCases, id: \.self) { f in
            HStack(spacing: 14) {
                EntrenarFamilyDot(f.tint(t))
                EntrenarFamilyDot(f.tint(t), sobreFondo: true)
                Text(f.label).font(StrandFont.caption).foregroundStyle(t.inkSecondary)
            }
        }
    }
    .padding(28)
    .background(t.paper)
    .instrumentoTheme(.base)
}
#endif
