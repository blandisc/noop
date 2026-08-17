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

    /// El tinte de identidad: ámbar empuje · teal tirón · índigo pierna y completo. Fuente ÚNICA
    /// (antes vivía suelta en la app, FER-898). Hue saturado: solo para bolitas, barras, marcos y
    /// numerales ≥ 24 pt, nunca para texto chico.
    public func tint(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .push:            return theme.dataStrain
        case .pull:            return theme.dataSteps
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
    /// Grosor del filo izquierdo que marca la fila actual.
    public static let currentEdge: CGFloat = 2
    /// Alto de la barra de progreso de la sesión.
    public static let progressBar: CGFloat = 3
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
    /// La pastilla del hilo: fondo al 12 % y borde al 38 % del tono del veredicto. Son alfas de
    /// IDENTIDAD (así se dibuja la puerta de Hoy), por eso viven aquí y no sueltas en la vista.
    public static let pillFillAlpha: Double = 0.12
    public static let pillBorderAlpha: Double = 0.38
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

#if DEBUG
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
    }
    .padding(24)
    .background(t.paper)
}
#endif
