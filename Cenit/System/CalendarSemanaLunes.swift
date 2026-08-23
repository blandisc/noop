import Foundation

extension Calendar {
    /// La semana de Entrenar empieza en LUNES (como se dibuja la tira y como el Calendario 90 del
    /// Detalle de Sueño), gane o no el locale (es_MX/en_US empiezan en domingo). Una sola regla para
    /// la tira de Entrenar, el widget, el historial de fuerza y el detalle de ejercicio (FER-128 r15).
    static var semanaLunes: Calendar {
        var c = Calendar.current; c.firstWeekday = 2; return c
    }
}
