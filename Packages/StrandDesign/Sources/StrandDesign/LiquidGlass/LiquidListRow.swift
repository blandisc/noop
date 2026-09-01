import SwiftUI

// MARK: - Liquid Glass · ListRow (handoff §5.7)
//
// Fila de lista (plan semanal, listados). Vive DENTRO de una tarjeta vidrio/superficie
// (`LiquidListCard`): punto de tono con glow · título + subtítulo · trailing · chevron
// en el tono. El divisor es borde inferior 0.5 tinta/10 (false en la última fila).
//
// MODO SELECCIÓN (FER-104 · TND-30): con `seleccionado` no-nil la fila deja de ser una fila de
// navegación y se vuelve un TOGGLE — el chevron se cambia por un ✓ en el tono cuando está
// elegida (hueco reservado cuando no, para que el layout no salte), y anuncia `.isSelected`.
// `deshabilitado` la apaga y la vuelve inerte (el tope de 4 en el picker de Comparar): sin
// glow, en tinta terciaria, sin acción. Con `a11yHint` la fila inerte DICE por qué no responde
// («máximo 4 métricas»), que si no VoiceOver leería una fila apagada sin razón (TND30-7). El
// `subtitle` es opcional — vacío no dibuja renglón.
//
// SLOT `accessory` (FER-280 · 1c, H1.4/clase 5): control a la derecha que NO es chevron/✓ —
// un `Picker`, un botón «Deshacer», un ícono de acción. Al proveerlo, REEMPLAZA la afordancia
// estándar (chevron/check) por completo: la fila deja de prometer navegación/selección y pasa
// el control al caller, exactamente lo que Ajustes necesita para `sexRow`/`recalibrateRow` sin
// clonar la geometría de la fila a mano.
//
// **Cuándo sí:** filas de lista Liquid con navegación (chevron), toggle (`seleccionado`) o un
// control de acción propio (`accessory`). **Cuándo no:** un grid de tiles (usa
// `LiquidMetricTile`); una fila fuera de una `LiquidListCard`/tarjeta de vidrio.

public struct LiquidListRow<Accessory: View>: View {
    private let title: String
    private let subtitle: String
    private let trailing: String?
    /// Tono de la fila — identidad de una métrica real (punto con glow + chevron en el tono).
    /// `nil` = fila "chrome" (sin métrica que colorear, FER-175): sin punto, chevron en tinta500.
    private let tone: Color?
    /// nil = fila de navegación (chevron). No-nil = toggle: ✓ cuando `true`.
    private let seleccionado: Bool?
    /// Fila apagada e inerte (tope de selección alcanzado).
    private let deshabilitado: Bool
    /// Pista de VoiceOver YA localizada — sobre todo para explicar por qué la fila está inerte.
    private let a11yHint: String?
    private let divider: Bool
    private let action: (() -> Void)?
    /// Control de la derecha que sustituye chevron/✓ cuando el caller lo provee (`EmptyView`
    /// por default = afordancia estándar sin cambios).
    private let accessory: Accessory

    public init(title: String, subtitle: String = "", trailing: String? = nil, tone: Color? = nil,
                seleccionado: Bool? = nil, deshabilitado: Bool = false, a11yHint: String? = nil,
                divider: Bool = true, action: (() -> Void)? = nil,
                @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.tone = tone
        self.seleccionado = seleccionado
        self.deshabilitado = deshabilitado
        self.a11yHint = a11yHint
        self.divider = divider
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        // Una fila apagada no es un botón: no responde y no debe leerse como accionable. La
        // pista (vacía = ninguna) explica el porqué de la fila inerte.
        if let action, !deshabilitado {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .accessibilityAddTraits(traits)
                .accessibilityHint(Text(verbatim: a11yHint ?? ""))
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(traits)
                .accessibilityHint(Text(verbatim: a11yHint ?? ""))
        }
    }

    private var traits: AccessibilityTraits {
        seleccionado == true ? .isSelected : []
    }

    private var tintaTitulo: Color {
        deshabilitado ? LiquidColor.tinta500 : LiquidColor.tinta900
    }

    /// Punto con glow — solo existe si la fila tiene un tono real. `tone == nil` (fila "chrome",
    /// FER-175) no dibuja NADA aquí, ni un punto en tinta: sin métrica que colorear, sin punto.
    @ViewBuilder private var punto: some View {
        if let tone {
            Circle()
                .fill(deshabilitado ? LiquidColor.tinta500 : tone)
                .frame(width: 8, height: 8)
                // Glow del punto como geometría (regla del sistema: nada de .shadow a mano).
                // Apagada: sin glow, para que la fila inerte no compita con las elegibles.
                .liquidShadow(deshabilitado
                              ? []
                              : [.init(color: tone.opacity(0.35), radius: 4, y: 0)],
                              silhouette: Circle())
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            punto
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LiquidType.tituloFila).foregroundStyle(tintaTitulo)
                if !subtitle.isEmpty {
                    Text(subtitle).font(LiquidType.unidadCompacta)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing).font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
            }
            trailingSlot
        }
        .padding(.vertical, 11)
        .padding(.horizontal, LiquidSpace.s100)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
    }

    /// `accessory` (no-`EmptyView`) reemplaza por completo la afordancia estándar — la fila
    /// deja de prometer chevron/✓ y pasa el control al caller.
    @ViewBuilder private var trailingSlot: some View {
        if Accessory.self == EmptyView.self {
            afordanciaTrailing
        } else {
            accessory
        }
    }

    @ViewBuilder private var afordanciaTrailing: some View {
        if let seleccionado {
            // Modo toggle: ✓ en el tono cuando está elegida. El hueco se reserva SIEMPRE
            // (opacidad 0 cuando no) para que activar/desactivar no mueva el layout.
            // `tone` debería venir siempre en modo selección; el fallback a tinta500 es solo
            // para no crashear si algún día no fuera así.
            Image(systemName: "checkmark")
                .font(LiquidType.iconSF(size: 12))
                .foregroundStyle(tone ?? LiquidColor.tinta500)
                .opacity(seleccionado ? 1 : 0)
                .frame(width: 14, alignment: .trailing)
                .accessibilityHidden(true)
        } else {
            // Fila "chrome" (tone nil): chevron en tinta500, sin inventar un color de métrica.
            LiquidIcon(.chevron, size: 12, color: tone ?? LiquidColor.tinta500)
        }
    }
}

/// La tarjeta contenedora de filas: vidrio/superficie con el padding 2/14 del handoff.
public struct LiquidListCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.vertical, LiquidSpace.s050)
            .padding(.horizontal, 14)
            .liquidGlass(.superficie) // token-exempt: fila de lista de pantalla, no de hoja
    }
}

#if DEBUG
#Preview("Liquid · ListRow") {
    LiquidListCard {
        LiquidListRow(title: "Empuje", subtitle: "L · Pecho · Hombros · Tríceps",
                      tone: LiquidColor.ambar, action: {})
        LiquidListRow(title: "Jalón", subtitle: "M · Dorsales · Espalda baja · Espalda media",
                      tone: LiquidColor.cian, action: {})
        LiquidListRow(title: "Pierna", subtitle: "X · Cuádriceps · Glúteo · Isquios",
                      tone: LiquidColor.indigo, divider: false, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}

/// Modo selección (picker de Comparar): ✓ en el tono cuando está elegida, apagada al tope.
#Preview("Liquid · ListRow selección") {
    VStack(spacing: 0) {
        LiquidListRow(title: "VFC", tone: LiquidColor.cian, seleccionado: true, action: {})
        LiquidListRow(title: "Esfuerzo", tone: LiquidColor.ambar, seleccionado: true, action: {})
        LiquidListRow(title: "Sueño", tone: LiquidColor.indigo, seleccionado: false, action: {})
        LiquidListRow(title: "FC en reposo", tone: LiquidColor.rosa,
                      seleccionado: false, deshabilitado: true,
                      a11yHint: "Máximo 4 métricas.", divider: false, action: {})
    }
    .liquidTarjetaSeccion()
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}

/// FER-175: `tone: nil` para filas de "chrome" (sin métrica que colorear) — sin punto, chevron
/// en tinta500 — junto a una fila con tono real para comparar ambos modos lado a lado.
#Preview("Liquid · ListRow tono opcional") {
    VStack(spacing: LiquidSpace.s300) {
        LiquidListCard {
            LiquidListRow(title: "Exportar datos", tone: nil, action: {})
            LiquidListRow(title: "Cerrar sesión", tone: nil, divider: false, action: {})
        }
        LiquidListCard {
            LiquidListRow(title: "Frecuencia cardiaca", subtitle: "Apple Watch",
                          tone: LiquidColor.rosa, divider: false, action: {})
        }
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}

/// FER-280 · 1c (H1.4/clase 5): slot `accessory` — un control propio (aquí, un botón) en vez
/// del chevron/✓ estándar, para que Ajustes deje de clonar la geometría de la fila a mano
/// (`sexRow`/`recalibrateRow`).
#Preview("Liquid · ListRow accessory") {
    LiquidListCard {
        LiquidListRow(title: "Recalibrar recuperación", subtitle: "Recalibrado el 10 jul 2026",
                      divider: false) {
            Button("Deshacer") {}
                .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.negativo)
                .buttonStyle(.plain)
        }
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
