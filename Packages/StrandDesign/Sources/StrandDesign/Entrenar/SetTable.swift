import SwiftUI

// MARK: - SetTable — la tabla de registro (FER-83 · E2, crecida FER-86)
//
// La pieza más usada de la sección: la tabla tipo Hevy que la sesión en vivo y «Rutina» comparten.
// Es la razón de ser de E2 — hoy cada pantalla dibuja su propia versión de estas columnas, y un
// cambio de altura o de estado hay que hacerlo dos veces.
//
// Cuatro tipos de ejercicio cambian la columna del dato, nunca la estructura: peso×reps, peso
// corporal, tiempo y distancia. Las filas hechas bajan a tinta secundaria, NO se aclaran hasta
// desaparecer. El calentamiento lleva «C» punteada en vez de número.
//
// Auditoría FER-81 (2026-08-17): esta pieza era más DELGADA que la tabla de `LiveStrengthSheet` que
// debe reemplazar. Este archivo es su crecimiento — todavía NO se adopta en la pantalla viva.
//
// Lo que creció, y por qué:
// 1. La columna PREV dedicada se RETIRA (no solo se apaga). FER-952 («modelo fantasma») mató esa
//    columna en la pantalla real: «la última vez» ya no vive aparte — vive DENTRO de la celda como
//    semilla tenue hasta que la tocas. Ningún consumidor (ni la sesión viva, ni el editor de rutina,
//    cuyo `numeralRing` tampoco tiñe por familia) quiere una columna aparte, así que cargarla como
//    API muerta violaba la regla de simplicidad. Ver `EntrenarCellState.ghost`.
// 2. El corazón de FER-952: cada celda de captura por teclado pasa por tres estados — `.ghost`
//    (semilla tenue sin tocar), `.touched` (valor propio) y `.editing` (teclado abierto: cursor +
//    subrayado grueso). `done` los apaga a todos (tinta asentada, sin cursor).
// 3. Columna RPE opcional (`showRPE`), solo con sentido en peso×reps/peso corporal — la enciende
//    quien la adopte; el editor de rutina puede dejarla apagada si no la usa.
// 4. El contrato de toque ya no es solo el id de la fila: `onTapCell(id, EntrenarCellKind)` dice
//    QUÉ celda —`.primary`, `.reps`, `.rpe` o `.pairedTime`— así el llamador enfoca el teclado
//    correcto en vez de adivinar.
// 5. `.bodyweight` gana su columna «+carga» real (antes era de una sola columna, mal etiquetada
//    «REPS» para el dato principal) y `.distance` gana su columna TIME pareada («400 m» sin su
//    «1:32» al lado no cuenta la serie completa).
// 6. Cardio en fila ACTIVA (cronómetro / rampa de FC / stepper de distancia) queda FUERA DE ALCANCE
//    a propósito: esa fila necesita estado vivo (un reloj que corre, una lectura de FC en tiempo
//    real) que una pieza de presentación, sin dependencias, del sistema de diseño no debe cargar.
//    `SetTable` dibuja tiempo/distancia como celdas «capturadas» (con `capturedCell`, igual que la
//    pantalla las dibuja fuera de la fila activa); la fila expandida sigue siendo de la pantalla.
// 7. Gesto de borrar: mantener pulsado arma la fila (se levanta ligeramente) y ofrece «Quitar
//    serie»; cualquier otro toque la desarma. Activado solo si se pasa `onDelete`.
// 8. El badge se ALINEA a la decisión cerrada del 2026-07-19 (ver `LiveStrengthSheet.badge`): aro
//    `dataStrain` (tenue en calentamiento) + subrayado de tinta bajo el numeral para «la serie en
//    curso» — nunca relleno por familia. Por eso `family` salió del init: sin este uso no le
//    quedaba ningún productor real, y cargarlo hubiera sido la MISMA API muerta que el Punto 12
//    retira de `isRaiseTarget`. La franja izquierda que antes teñía la fila actual por familia
//    también se retira — la pantalla ya decidió (r6) «sin resaltado de fila», solo el numeral.
// 9. El ✓ ahora lee `row.isCurrent`: registrada = verde de lectura; «la próxima» pendiente = ámbar
//    `dataStrain` (antes esta rama no existía — el ✓ solo sabía «hecha» o «no»); más
//    `symbolEffect(.bounce)` + `sensoryFeedback(.success)` al palomear.
// 10. Layout apilado (`reflow`) a partir de `.accessibility1`, espejo de `reflowRow` en la pantalla:
//     badge+check arriba, datos abajo.
// 11. `.accessibilityElement(children: .combine)` solo cuando la fila tiene UN dato + el check
//     (hoy, solo `.time`) — con reps, RPE o una columna pareada de por medio, combinar los vuelve
//     inalcanzables uno por uno; el resto usa `.contain` (como la pantalla real).
// 12. `isRaiseTarget` se RETIRA: sin productor en todo el repo (ni la pantalla, ni el catálogo salvo
//     su propio demo) — API muerta desde que se escribió.

/// El tipo de ejercicio, del lado del diseño: decide qué columnas se dibujan.
public enum EntrenarExerciseKind: String, Sendable, CaseIterable, Hashable {
    case weightReps, bodyweight, time, distance

    /// El rótulo de la columna del dato principal.
    var primaryColumn: LocalizedStringKey {
        switch self {
        case .weightReps: return "KG"
        case .bodyweight: return "+LOAD"
        case .time:       return "TIME"
        case .distance:   return "DIST"
        }
    }

    /// Si el tipo además captura repeticiones en su propia columna (Punto 5: peso corporal
    /// también las tiene — antes solo peso×reps las mostraba y «+carga» se perdía sin su columna).
    var hasRepsColumn: Bool { self == .weightReps || self == .bodyweight }

    /// La columna TIME pareada de `.distance` (Punto 5) — «400 m» sin su tiempo al lado no es la
    /// serie completa.
    var hasPairedTimeColumn: Bool { self == .distance }
}

/// El estado de una celda de captura por teclado ANTES de palomear (Punto 2 — el corazón de
/// FER-952). Nunca es solo «con valor / sin valor»: una celda sin tocar YA tiene un valor (la
/// semilla de «la última vez»), solo que en tinta tenue.
public enum EntrenarCellState: Sendable, Hashable {
    /// Sin tocar: el valor mostrado es la semilla del modelo fantasma — palomear así registra
    /// exactamente «lo de la vez pasada», sin que el usuario haya escrito nada.
    case ghost
    /// El usuario ya escribió (o confirmó) un valor propio: tinta normal.
    case touched
    /// El teclado propio está abierto sobre esta celda ahora mismo: cursor + subrayado grueso.
    case editing
}

/// Qué celda se tocó (Punto 4). Antes `onTapCell(rowId)` no distinguía peso de reps, así que el
/// llamador no podía enfocar el teclado correcto — ahora dice explícitamente cuál de las columnas
/// interactivas que la tabla puede dibujar fue la tocada.
public enum EntrenarCellKind: Sendable, Hashable {
    case primary     // KG / +LOAD / TIME / DIST
    case reps        // REPS (peso×reps, peso corporal)
    case rpe         // RPE (opcional, Punto 3)
    case pairedTime  // TIME pareado de `.distance` (Punto 5)
}

/// El estado visual final de una celda de captura, ya resuelto contra `done` (Punto 2). `done`
/// manda siempre: una serie registrada nunca vuelve a mostrar fantasma ni cursor.
public enum EntrenarCellVisualRole: Sendable, Hashable { case settled, ghost, normal, editing }

/// El rol de color del ✓ (Punto 9): registrada gana siempre; si no, «la próxima serie» (isCurrent)
/// se marca en el mismo ámbar que el badge — antes esta decisión ignoraba `isCurrent` del todo.
public enum EntrenarCheckRole: Sendable, Hashable { case done, active, idle }

/// Una fila de la tabla. Todo llega ya formateado: el componente no sabe de unidades ni de sistemas
/// métricos, solo de jerarquía y estado.
public struct EntrenarSetRow: Identifiable, Sendable, Hashable {
    public let id: String
    /// Lo que se pinta en el badge: «1», «2»… o «C» para calentamiento.
    public let badge: String
    /// El dato principal ya formateado. En peso×reps/peso corporal NUNCA está vacío mientras no
    /// esté `done` — el modelo fantasma siempre pre-llena con la semilla; `primaryState` dice si esa
    /// semilla sigue sin tocar. En tiempo/distancia, `nil` = todavía sin capturar (ícono de "play").
    public let primary: String?
    /// El estado en captura de `primary` (Punto 2). Se ignora en tiempo/distancia.
    public let primaryState: EntrenarCellState
    /// Las repeticiones, solo si `EntrenarExerciseKind.hasRepsColumn`.
    public let reps: String?
    /// El estado en captura de `reps` (Punto 2).
    public let repsState: EntrenarCellState
    /// El RPE ya formateado («9,5»), o `nil` si no se ha capturado — dibuja el rótulo tenue «RPE».
    /// Solo se pinta si la tabla enciende `showRPE` (Punto 3).
    public let rpe: String?
    /// La columna TIME pareada de `.distance` (Punto 5). `nil` = todavía sin capturar.
    public let pairedTime: String?
    public let done: Bool
    public let isWarmup: Bool
    /// La serie en curso: aro `dataStrain` + subrayado de tinta bajo el numeral (Punto 8), y el ✓
    /// pendiente en ámbar (Punto 9). Por contrato, el llamador nunca manda `isCurrent && done`
    /// juntos — una serie registrada deja de ser «la próxima».
    public let isCurrent: Bool

    public init(id: String, badge: String,
                primary: String? = nil, primaryState: EntrenarCellState = .touched,
                reps: String? = nil, repsState: EntrenarCellState = .touched,
                rpe: String? = nil, pairedTime: String? = nil,
                done: Bool = false, isWarmup: Bool = false, isCurrent: Bool = false) {
        self.id = id; self.badge = badge
        self.primary = primary; self.primaryState = primaryState
        self.reps = reps; self.repsState = repsState
        self.rpe = rpe; self.pairedTime = pairedTime
        self.done = done; self.isWarmup = isWarmup; self.isCurrent = isCurrent
    }
}

public struct SetTable: View {
    private let kind: EntrenarExerciseKind
    private let rows: [EntrenarSetRow]
    private let showRPE: Bool
    private let onToggle: ((String) -> Void)?
    private let onTapCell: ((String, EntrenarCellKind) -> Void)?
    private let onDelete: ((String) -> Void)?

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// La fila armada para borrar (long-press, Punto 7) — brinca en su lugar y ofrece «Quitar
    /// serie»; cualquier otro toque la desarma. `nil` = ninguna.
    @State private var armedRowId: String?

    public init(kind: EntrenarExerciseKind, rows: [EntrenarSetRow], showRPE: Bool = false,
                onToggle: ((String) -> Void)? = nil,
                onTapCell: ((String, EntrenarCellKind) -> Void)? = nil,
                onDelete: ((String) -> Void)? = nil) {
        self.kind = kind; self.rows = rows; self.showRPE = showRPE
        self.onToggle = onToggle; self.onTapCell = onTapCell; self.onDelete = onDelete
    }

    private var reflow: Bool { Self.reflows(at: typeSize) }
    /// RPE solo tiene sentido donde hay reps que calificar (peso×reps, peso corporal) — Punto 3.
    private var showsRPE: Bool { showRPE && kind.hasRepsColumn }
    private var isSingleDatumRow: Bool { Self.combinesAccessibilityChildren(kind: kind, showRPE: showRPE) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(rows) { row in
                Divider().overlay(theme.hairline)
                line(row)
            }
        }
    }

    // MARK: Header

    /// El rótulo quieto del encabezado. Oculto para VoiceOver: la fila ya se lee completa.
    private var header: some View {
        HStack(spacing: EntrenarMetrics.columnGap) {
            Text("SET").instrumentoOverline().frame(width: EntrenarMetrics.badge, alignment: .leading)
            // Modelo fantasma (FER-952, Punto 1): sin columna PREV dedicada, el hueco flexible
            // mantiene las columnas pegadas a la derecha.
            Spacer(minLength: 0)
            Text(kind.primaryColumn).instrumentoOverline().frame(maxWidth: .infinity, alignment: .trailing)
            if kind.hasRepsColumn {
                Text("REPS").instrumentoOverline().frame(maxWidth: .infinity, alignment: .trailing)
            }
            if kind.hasPairedTimeColumn {
                Text("TIME").instrumentoOverline().frame(maxWidth: .infinity, alignment: .trailing)
            }
            if showsRPE {
                Text("RPE").instrumentoOverline().frame(width: EntrenarMetrics.rpeColumn, alignment: .trailing)
            }
            Color.clear.frame(width: EntrenarMetrics.row, height: 1)
        }
        .foregroundStyle(theme.inkTertiary)
        .padding(.bottom, CenitMetrics.space1)
        .accessibilityHidden(true)
    }

    // MARK: Row assembly — layout, borrado, accesibilidad

    /// Punto 10: layout normal (una línea) o apilado (`reflow`, Dynamic Type de accesibilidad).
    private func baseRow(_ row: EntrenarSetRow) -> some View {
        Group {
            if reflow { reflowLine(row) } else { gridLine(row) }
        }
        .padding(.vertical, reflow ? EntrenarMetrics.reflowRowGap : 0)
        .frame(minHeight: EntrenarMetrics.tableRow)
    }

    /// Punto 11: combinar en UN elemento de VoiceOver solo cuando dato + check son los ÚNICOS
    /// controles de la fila (hoy, solo `.time`); si hay reps, RPE o una columna pareada de por
    /// medio, cada control se deja ALCANZABLE (`.contain`), igual que la pantalla real.
    @ViewBuilder
    private func accessibleRow(_ row: EntrenarSetRow) -> some View {
        if isSingleDatumRow {
            baseRow(row)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowLabel(row))
        } else {
            baseRow(row)
                .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private func line(_ row: EntrenarSetRow) -> some View {
        if let onDelete {
            deletableRow(row, onDelete: onDelete)
        } else {
            accessibleRow(row)
        }
    }

    /// Punto 7: mantener pulsado arma la fila (brinca en su lugar) y ofrece «Quitar serie»;
    /// cualquier otro toque la desarma. El mismo lenguaje que el borrado de la sesión viva
    /// (`LiveStrengthSheet.armedSetRow`), ahora dentro de la pieza compartida.
    private func deletableRow(_ row: EntrenarSetRow, onDelete: @escaping (String) -> Void) -> some View {
        let armed = armedRowId == row.id
        return accessibleRow(row)
            .scaleEffect(armed ? EntrenarMetrics.armedLift : 1)
            .shadow(color: .black.opacity(armed ? 0.10 : 0),  // token-exempt: sombra transitoria de lift, no superficie
                    radius: EntrenarMetrics.armedShadowRadius, y: EntrenarMetrics.armedShadowY)
            .overlay(alignment: .trailing) {
                if armed { deletePill { onDelete(row.id); armedRowId = nil } }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: EntrenarMetrics.deleteHoldDuration).onEnded { _ in
                withAnimation(StrandMotion.gentle) { armedRowId = row.id }
            })
            .simultaneousGesture(TapGesture().onEnded {
                if armedRowId != nil { withAnimation(StrandMotion.gentle) { armedRowId = nil } }
            })
            .accessibilityAction(named: Text("Delete set")) { onDelete(row.id) }
    }

    private func gridLine(_ row: EntrenarSetRow) -> some View {
        HStack(spacing: EntrenarMetrics.columnGap) {
            badge(row)
            Spacer(minLength: 0)
            dataCells(row)
            check(row)
        }
    }

    /// Punto 10: badge + check arriba, datos abajo — espejo de `LiveStrengthSheet.reflowRow`.
    private func reflowLine(_ row: EntrenarSetRow) -> some View {
        VStack(alignment: .leading, spacing: EntrenarMetrics.reflowRowGap) {
            HStack {
                badge(row)
                Spacer()
                check(row)
            }
            HStack(spacing: EntrenarMetrics.reflowCellGap) { dataCells(row) }
        }
    }

    /// Las celdas de dato, por tipo de ejercicio (Punto 5): peso×reps y peso corporal ganan RPE
    /// opcional; peso corporal antepone «+» a su carga; distancia gana su columna TIME pareada.
    @ViewBuilder
    private func dataCells(_ row: EntrenarSetRow) -> some View {
        switch kind {
        case .weightReps:
            numericCell(row.primary, state: row.primaryState, done: row.done, cellKind: .primary, row: row)
            numericCell(row.reps, state: row.repsState, done: row.done, cellKind: .reps, row: row)
            if showsRPE { rpeCell(row) }
        case .bodyweight:
            HStack(spacing: CenitMetrics.space1) {
                Text(verbatim: "+").font(StrandFont.body)
                    .foregroundStyle(row.done ? theme.inkSecondary : theme.inkTertiary)
                numericCell(row.primary, state: row.primaryState, done: row.done, cellKind: .primary, row: row)
            }
            numericCell(row.reps, state: row.repsState, done: row.done, cellKind: .reps, row: row)
            if showsRPE { rpeCell(row) }
        case .time:
            capturedCell(row.primary, cellKind: .primary, row: row)
        case .distance:
            capturedCell(row.primary, cellKind: .primary, row: row)
            capturedCell(row.pairedTime, cellKind: .pairedTime, row: row)
        }
    }

    // MARK: Badge

    /// El numeral de serie. Punto 8: aro `dataStrain` (tenue en calentamiento) + subrayado de tinta
    /// bajo el numeral para «la serie en curso» — la decisión cerrada del 2026-07-19, la MISMA que
    /// `LiveStrengthSheet.badge` ya dibuja. Ya NO rellena el badge por familia (ver nota de cabecera,
    /// Punto 8): sin ese uso, `family` no tenía más productor y salió del init.
    private func badge(_ row: EntrenarSetRow) -> some View {
        let ring = row.isWarmup ? theme.dataStrain.opacity(StrandOpacity.dim) : theme.dataStrain
        return Text(verbatim: row.badge)
            .font(InstrumentoType.groteskNumber(12, weight: .bold, relativeTo: .caption))
            .foregroundStyle(ring)
            .frame(width: EntrenarMetrics.badge, height: EntrenarMetrics.badge)
            .background {
                if row.isWarmup {
                    Circle().strokeBorder(ring, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    Circle().strokeBorder(ring, lineWidth: 1)
                }
            }
            .overlay(alignment: .bottom) {
                if row.isCurrent && !row.isWarmup {
                    Rectangle().fill(theme.ink)
                        .frame(width: EntrenarMetrics.badgeUnderline, height: EntrenarMetrics.currentEdge)
                        .offset(y: EntrenarMetrics.badgeUnderlineOffset)
                }
            }
            .accessibilityLabel(row.isWarmup ? Text("Warm-up set") : Text("Set \(row.badge)"))
    }

    // MARK: Celdas de captura por teclado (peso, +carga, reps) — Punto 2

    /// Una celda de captura por teclado: fantasma / tocada / en edición (Punto 2, el corazón de
    /// FER-952). El texto YA llega formateado — mientras se edita, el llamador manda el buffer crudo
    /// tal cual (esta pieza no sabe de comas ni de unidades). El subrayado engruesa y el cursor
    /// aparece SOLO en edición.
    private func numericCell(_ text: String?, state: EntrenarCellState, done: Bool,
                             cellKind: EntrenarCellKind, row: EntrenarSetRow) -> some View {
        let role = Self.visualRole(state: state, done: done)
        let shown = text ?? "—"
        let ink: Color
        switch role {
        case .settled: ink = theme.inkSecondary
        case .ghost:   ink = theme.inkDim
        case .normal, .editing: ink = theme.ink
        }
        let content = HStack(spacing: CenitMetrics.space1) {
            Text(verbatim: shown)
                .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(ink)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            if role == .editing {
                Rectangle().fill(theme.ink)
                    .frame(width: EntrenarMetrics.caretWidth, height: EntrenarMetrics.caretHeight)
                    .opacity(0.9)  // token-exempt: opacidad de cursor >0.70 (mismo criterio que la pantalla)
            }
        }
        .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .trailing)
        .overlay(alignment: .bottom) {
            Rectangle().fill(role == .editing ? theme.ink : theme.hairlineStrong)
                .frame(height: role == .editing ? EntrenarMetrics.cellUnderlineActive : EntrenarMetrics.cellUnderline)
        }
        return Group {
            if let onTapCell {
                Button { onTapCell(row.id, cellKind) } label: {
                    // El blanco táctil es la CELDA, no el texto: un «82.5» mide poco, y esta celda es
                    // un campo de captura que se toca todo el tiempo.
                    content.contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
            } else {
                content
            }
        }
        .accessibilityLabel(cellAccessibilityLabel(cellKind, row: row))
        .accessibilityValue(Text(verbatim: shown))
    }

    // MARK: RPE (Punto 3) — abre un mecanismo externo (hoja de RPE), no el teclado propio.

    private func rpeCell(_ row: EntrenarSetRow) -> some View {
        let content = Group {
            if let rpe = row.rpe {
                Text(verbatim: rpe)
                    .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(theme.dataEffort)
            } else {
                Text("RPE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(width: EntrenarMetrics.rpeColumn, alignment: .trailing)
        .frame(minHeight: EntrenarMetrics.row)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.hairline).frame(height: EntrenarMetrics.cellUnderline)
        }
        return Group {
            if let onTapCell {
                Button { onTapCell(row.id, .rpe) } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(EntrenarPressStyle())
            } else {
                content
            }
        }
        .accessibilityLabel(cellAccessibilityLabel(.rpe, row: row))
        .accessibilityValue(Text(row.rpe ?? String(localized: "Not recorded")))
    }

    // MARK: Celdas «capturadas» (tiempo / distancia) — Punto 5/6, sin estado fantasma/edición.

    /// Una celda de tiempo/distancia: texto si ya se capturó, ícono de "play" si no (la captura de
    /// verdad —cronómetro, rampa de FC— vive en la fila ACTIVA de la pantalla, fuera de alcance
    /// aquí, Punto 6). Tocar solo AVISA al llamador qué celda fue — no hay teclado propio.
    private func capturedCell(_ text: String?, cellKind: EntrenarCellKind, row: EntrenarSetRow) -> some View {
        let content = Group {
            if let text {
                Text(verbatim: text)
                    .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(row.done ? theme.inkSecondary : theme.ink)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            } else {
                Image(systemName: "play.circle")
                    .font(StrandFont.glyph(.lead))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .trailing)
        return Group {
            if let onTapCell {
                Button { onTapCell(row.id, cellKind) } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(EntrenarPressStyle())
            } else {
                content
            }
        }
        .accessibilityLabel(cellAccessibilityLabel(cellKind, row: row))
        .accessibilityValue(Text(verbatim: text ?? String(localized: "Not recorded")))
    }

    // MARK: Check — Punto 9

    /// El toggle de serie hecha (44pt tocable entero). `row.isCurrent` decide el ámbar de «la
    /// próxima» (antes esta rama no existía). Símbolo + confirmación háptica al palomear
    /// (ReduceMotion omite el bounce solo, vía el sistema).
    private func check(_ row: EntrenarSetRow) -> some View {
        let role = Self.checkRole(done: row.done, isCurrent: row.isCurrent)
        return Button { onToggle?(row.id) } label: {
            Image(systemName: row.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: EntrenarMetrics.check))
                .foregroundStyle(role == .done ? theme.positiveText : (role == .active ? theme.dataStrain : theme.inkTertiary))
                .symbolEffect(.bounce, value: row.done)
                .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(onToggle == nil)
        .sensoryFeedback(.success, trigger: row.done)
        .accessibilityLabel(row.done ? Text("Done") : Text("Mark set done"))
    }

    // MARK: Borrar serie — Punto 7

    /// La pastilla de confirmación que aparece sobre la fila armada — el mismo lenguaje que
    /// `DeleteSetPill` en la app (contorno crítico, sin relleno saturado), ahora dentro de la pieza.
    private func deletePill(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CenitMetrics.space1) {
                Image(systemName: "trash").font(StrandFont.glyph(.chevron))
                Text("Delete set").font(StrandFont.caption)
            }
            .foregroundStyle(theme.critical)
            .padding(.horizontal, EntrenarMetrics.deletePillPaddingH)
            .padding(.vertical, EntrenarMetrics.deletePillPaddingV)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.critical.opacity(StrandOpacity.dim), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel(Text("Delete set"))
    }

    // MARK: Accesibilidad — Punto 11

    /// Solo se usa cuando la fila combina sus hijos (`.time`, dato + check nada más).
    private func rowLabel(_ row: EntrenarSetRow) -> Text {
        var t = row.isWarmup ? Text("Warm-up set") : Text("Set \(row.badge)")
        if let primary = row.primary { t = t + Text(verbatim: ", ") + Text(verbatim: primary) }
        if row.done { t = t + Text(verbatim: ", ") + Text("done") }
        return t
    }

    /// El rótulo de una celda individual cuando la fila NO combina (Punto 11): «KG, set 2» en vez
    /// de dejar la celda muda dentro de un contenedor sin nombre.
    private func cellAccessibilityLabel(_ cellKind: EntrenarCellKind, row: EntrenarSetRow) -> Text {
        let column: Text
        switch cellKind {
        case .primary:    column = Text(kind.primaryColumn)
        case .reps:       column = Text("REPS")
        case .rpe:        column = Text("RPE")
        case .pairedTime: column = Text("TIME")
        }
        let subject = row.isWarmup ? Text("warm-up set") : Text("set \(row.badge)")
        return column + Text(verbatim: ", ") + subject
    }
}

// MARK: - Lógica pura (probada en `SetTableTests`)

extension SetTable {
    /// El estado visual final de una celda de captura: `done` manda siempre — una serie registrada
    /// nunca vuelve a mostrar fantasma ni cursor, sin importar en qué `EntrenarCellState` haya
    /// quedado (Punto 2 / corazón de FER-952).
    public static func visualRole(state: EntrenarCellState, done: Bool) -> EntrenarCellVisualRole {
        guard !done else { return .settled }
        switch state {
        case .ghost:   return .ghost
        case .touched: return .normal
        case .editing: return .editing
        }
    }

    /// El rol de color del ✓ (Punto 9): registrada gana siempre; si no, «la próxima» (`isCurrent`)
    /// se marca en el mismo ámbar del badge — antes esta decisión ignoraba `isCurrent` del todo.
    public static func checkRole(done: Bool, isCurrent: Bool) -> EntrenarCheckRole {
        done ? .done : (isCurrent ? .active : .idle)
    }

    /// ¿Reflowa esta tabla a layout apilado en este tamaño de Dynamic Type? (Punto 10 — espejo de
    /// `LiveStrengthSheet.reflow`: arranca en `.accessibility1`.)
    public static func reflows(at size: DynamicTypeSize) -> Bool { size >= .accessibility1 }

    /// Las celdas interactivas que expone una tabla de este tipo, en el orden en que se dibujan
    /// (Puntos 3/4/5) — el contrato que `onTapCell` usa para decir QUÉ celda se tocó.
    public static func interactiveCells(kind: EntrenarExerciseKind, showRPE: Bool) -> [EntrenarCellKind] {
        var cells: [EntrenarCellKind] = [.primary]
        if kind.hasRepsColumn { cells.append(.reps) }
        if kind.hasPairedTimeColumn { cells.append(.pairedTime) }
        if showRPE && kind.hasRepsColumn { cells.append(.rpe) }
        return cells
    }

    /// ¿La fila combina sus hijos en un solo elemento de VoiceOver, o los deja alcanzables uno por
    /// uno? Combinar solo cuando dato + check son los ÚNICOS controles (Punto 11) — con reps, RPE o
    /// una columna pareada de por medio, combinarlos los vuelve inalcanzables.
    public static func combinesAccessibilityChildren(kind: EntrenarExerciseKind, showRPE: Bool) -> Bool {
        interactiveCells(kind: kind, showRPE: showRPE).count <= 1
    }
}

#if DEBUG
private let demoRows: [EntrenarSetRow] = [
    .init(id: "w", badge: "C", primary: "40", primaryState: .ghost, reps: "10", repsState: .ghost,
          isWarmup: true),
    .init(id: "1", badge: "1", primary: "82,5", reps: "8", rpe: "8", done: true),
    .init(id: "2", badge: "2", primary: "82,5", primaryState: .editing, reps: "8", repsState: .ghost,
          isCurrent: true),
    .init(id: "3", badge: "3", primary: "80", primaryState: .ghost, reps: "8", repsState: .ghost),
]

#Preview("SetTable · peso × reps, con RPE") {
    SetTable(kind: .weightReps, rows: demoRows, showRPE: true,
             onToggle: { _ in }, onTapCell: { _, _ in }, onDelete: { _ in })
        .padding(24)
        .background(InstrumentoTheme.base.paper)
        .instrumentoTheme(.base)
}

#Preview("SetTable · fantasma, tocada, en edición") {
    // El corazón de FER-952 (Punto 2): la MISMA celda «82,5», en sus tres estados de captura.
    VStack(alignment: .leading, spacing: 4) {
        Text("FANTASMA · TOCADA · EDITANDO").instrumentoOverline()
        SetTable(kind: .weightReps, rows: [
            .init(id: "g", badge: "1", primary: "82,5", primaryState: .ghost, reps: "8", repsState: .ghost, isCurrent: true),
            .init(id: "t", badge: "2", primary: "82,5", primaryState: .touched, reps: "8", repsState: .touched),
            .init(id: "e", badge: "3", primary: "82,5", primaryState: .editing, reps: "8", repsState: .touched),
        ], onToggle: { _ in }, onTapCell: { _, _ in })
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("SetTable · peso corporal (+carga), tiempo, distancia pareada") {
    VStack(alignment: .leading, spacing: 28) {
        SetTable(kind: .bodyweight, rows: [
            .init(id: "1", badge: "1", primary: "0", reps: "12", done: true),
            .init(id: "2", badge: "2", primary: "5", primaryState: .ghost, reps: "12", repsState: .ghost, isCurrent: true),
        ], showRPE: true, onToggle: { _ in }, onTapCell: { _, _ in })
        SetTable(kind: .time, rows: [
            .init(id: "1", badge: "1", primary: "1:00", isCurrent: true),
            .init(id: "2", badge: "2"),   // sin capturar: ícono de "play"
        ], onToggle: { _ in }, onTapCell: { _, _ in })
        SetTable(kind: .distance, rows: [
            .init(id: "1", badge: "1", primary: "0.40 km", pairedTime: "1:32", isCurrent: true),
            .init(id: "2", badge: "2"),   // sin capturar: ambas columnas muestran "play"
        ], onToggle: { _ in }, onTapCell: { _, _ in })
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}

#Preview("SetTable · vacía y xxxLarge (reflow)") {
    VStack(alignment: .leading, spacing: 28) {
        SetTable(kind: .weightReps, rows: [])
        SetTable(kind: .weightReps, rows: Array(demoRows.prefix(3)), showRPE: true,
                 onToggle: { _ in }, onTapCell: { _, _ in })
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
