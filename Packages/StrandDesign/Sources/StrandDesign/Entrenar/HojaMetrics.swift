import SwiftUI

// MARK: - HojaMetrics — tokens de La Hoja (FER-166)
//
// Medidas exactas del mock `hoja-pantallas.html` (clases `.trow`, `.trow.e`, `.sn`, `.val`,
// `.reps`, `.prev`, `.ok`, `.pend`, `.activa`, `.ant`). Cero números sueltos en las vistas:
// cada constante cita la clase CSS de origen.

/// Ritmo de la fila de serie y de la tarjeta de superserie de «La Hoja de Rutina».
public enum HojaMetrics {

    /// `.trow` padding vertical (`9px 4px`).
    public static let filaVPad: CGFloat = 9
    /// `.trow` padding horizontal (`9px 4px`).
    public static let filaHPad: CGFloat = 4

    /// `.trow` columna 1 — número de serie (`.sn`).
    public static let colNumero: CGFloat = 26
    /// `.trow` columna 2 — peso en sesión (`86px`).
    public static let colPesoSesion: CGFloat = 86
    /// `.trow.e` columna 2 — peso en edición (`76px`).
    public static let colPesoEdicion: CGFloat = 76
    /// `.trow.e` columna 3 — reps en edición (`52px`).
    public static let colRepsEdicion: CGFloat = 52
    /// Columna de marca ✓/pendiente en sesión (`.trow` col 4 = `24px`).
    public static let colMarca: CGFloat = 24
    /// Columna de agarre ≡ en edición (`.trow.e` col 5 = `22px`).
    public static let colMarcaEdicion: CGFloat = 22

    /// Diámetro de `.ok` / `.pend` (`22×22`).
    public static let marcaDiametro: CGFloat = 22
    /// Grosor del borde punteado de `.pend` (`border: 1.5px dashed`).
    public static let marcaBorde: CGFloat = 1.5
    /// Dash del borde de `.pend` (pares trazo/hueco en pt).
    public static let marcaDash: [CGFloat] = [3, 2]

    /// `.val` / `.reps` en sesión (`16px`).
    public static let valSize: CGFloat = 16
    /// `.val` / `.reps` en edición (`style="font-size:15px"`).
    public static let valSizeEdicion: CGFloat = 15
    /// `.val small` / `.reps small` — unidad y sufijo Q (`10px`).
    public static let unidadSize: CGFloat = 10
    /// `.sn` — número de serie (`11px`).
    public static let numeroSize: CGFloat = 11
    /// `.ant` / `.prev` — playhead ANT y columna ANTERIOR (`10.5px`).
    public static let antSize: CGFloat = 10.5
    /// `.val .up` — glifo ▲ de subida (`10px`).
    public static let subidaSize: CGFloat = 10
    /// `.agarra` — glifo ≡ de arrastre (`12px`).
    public static let agarreSize: CGFloat = 12
    /// Checkmark dentro de `.ok` (`font-size:11px`).
    public static let marcaGlifoSize: CGFloat = 11

    /// `.trow.activa` `border-radius: 10px`.
    public static let activaRadius: CGFloat = 10
    /// `.trow.activa` fondo `rgba(255,255,255,.45)`.
    public static let activaFondoAlfa: Double = 0.45
    /// `.ant` `margin-top: -3px` (acercar el playhead a la tríada).
    public static let antOffsetY: CGFloat = -3

    /// `.trow` `gap: 8px` entre columnas.
    public static let filaGap: CGFloat = 8
    /// Hairline superior entre filas (`.trow` `border-top: 1px solid var(--t07)`).
    public static let separadorGrosor: CGFloat = 1

    /// Blanco táctil mínimo de la fila completa (HIG; = `EntrenarMetrics.row` / `CenitMetrics.touchTarget`).
    public static let hitMin: CGFloat = 44
}
