import SwiftUI

// MARK: - HojaTarjetaSuperserie — tarjeta única de superserie (FER-166)
//
// Estado EDICIÓN (mock `hoja-pantallas.html` P1 `.ss2` / `.ssL`). El vivo de sesión (P5) llega
// en F3. Cristal cian LOCAL — no depende de `EntrenarVidrio` / `EntrenarTono` (pueden no existir
// aún en la base `origin/iOS`).

/// Tarjeta de superserie en edición: cristal cian + nombre + pastilla + filas + pie.
public struct HojaTarjetaSuperserie<Filas: View>: View {

    // MARK: Cristal cian — constantes locales (mock `.ss2`)

    /// Radio de la tarjeta (`.ss2` / `.mod` `border-radius: 17px`).
    private static var radio: CGFloat { 17 }
    /// Fondo cian al 8 % (`.ss2{background:rgba(20,124,140,.08)}`).
    private static var fondoAlfa: Double { 0.08 }
    /// Highlight inset superior (`.ss2` `inset 0 1px 0 rgba(255,255,255,.75)`).
    private static var highlightAlfa: Double { 0.75 }
    /// Segundo aro inset blanco (`.ss2` `inset 0 0 0 1px rgba(255,255,255,.35)`).
    private static var aroAlfa: Double { 0.35 }
    /// Canto exterior cian al 30 % (`.ss2` `0 0 0 .5px rgba(20,124,140,.30)`).
    private static var cantoAlfa: Double { 0.30 }
    /// Sombra difusa cian (`.ss2` `0 10px 20px rgba(20,124,140,.10)`).
    private static var sombraRadio: CGFloat { 20 }
    private static var sombraY: CGFloat { 10 }
    private static var sombraAlfa: Double { 0.10 }
    /// Sombra cercana (`.ss2` `0 2px 3px rgba(34,29,22,.04)`).
    private static var sombraCercaRadio: CGFloat { 3 }
    private static var sombraCercaY: CGFloat { 2 }
    private static var sombraCercaAlfa: Double { 0.04 }

    /// Padding interior P1 (`style="padding:10px 14px"`).
    private static var padV: CGFloat { 10 }
    private static var padH: CGFloat { 14 }

    /// Nombre bold 13.5 (P1 header).
    private static var nombreSize: CGFloat { 13.5 }
    /// Pastilla `.ssL`: grotesk 8.5 / 700, tracking 1.
    private static var pastillaSize: CGFloat { 8.5 }
    private static var pastillaTracking: CGFloat { 1 }
    private static var pastillaPadH: CGFloat { 6 }
    private static var pastillaPadV: CGFloat { 2 }
    private static var pastillaGap: CGFloat { 6 } // `.ssL` margin-left: 6px
    /// Fondo pastilla (`.ssL` `background:rgba(20,124,140,.10)`).
    private static var pastillaFondoAlfa: Double { 0.10 }
    /// = EntrenarTono.cian rotulo — hex #136A78 del mock `.ssL` / `.ronda`.
    private static var cianRotulo: Color { Color(hex: "#136A78") }
    /// Menú ··· (`.menu` 14 px, tinta500).
    private static var menuSize: CGFloat { 14 }
    /// Pie: grotesk 10 / 600 tinta700.
    private static var pieSize: CGFloat { 10 }
    private static var pieTop: CGFloat { 8 } // padding-top del pie en P1

    private let nombre: String
    private let pie: String?
    private let onMenu: (() -> Void)?
    /// D0 (FER-170 · F5, épico FER-165): la puerta directa a Foco («⤢», mock `hoja-mapa.html` D0) —
    /// `nil` (default) la omite, para no aparecer en la Hoja fría/edición donde esta misma tarjeta
    /// también se monta y no hay sesión que enfocar.
    private let onEnfocar: (() -> Void)?
    private let filas: Filas

    public init(
        nombre: String,
        pie: String?,
        onMenu: (() -> Void)? = nil,
        onEnfocar: (() -> Void)? = nil,
        @ViewBuilder filas: () -> Filas
    ) {
        self.nombre = nombre
        self.pie = pie
        self.onMenu = onMenu
        self.onEnfocar = onEnfocar
        self.filas = filas()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            filas
            if let pie {
                Text(verbatim: pie)
                    .font(InstrumentoType.grotesk(
                        Self.pieSize, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(LiquidColor.tinta700)
                    .padding(.top, Self.pieTop)
            }
        }
        .padding(.vertical, Self.padV)
        .padding(.horizontal, Self.padH)
        .background { cristal }
        .accessibilityElement(children: .contain)
        // N5 (ronda 3, menor): vía catálogo — reusa la MISMA clave que `SupersetTag`
        // (`RoutineSetEditing.swift`) en vez de hardcodear «Superserie» en español.
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Superset")), \(nombre)"))
        .accessibilityActionIfAvailable(onEnfocar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(verbatim: nombre)
                .font(InstrumentoType.grotesk(
                    Self.nombreSize, weight: .bold, relativeTo: .footnote))
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(2)
            Text(verbatim: "SUPERSERIE")
                .font(InstrumentoType.grotesk(
                    Self.pastillaSize, weight: .bold, relativeTo: .caption2))
                .tracking(Self.pastillaTracking)
                .foregroundStyle(Self.cianRotulo)
                .padding(.horizontal, Self.pastillaPadH)
                .padding(.vertical, Self.pastillaPadV)
                .background(
                    Capsule()
                        .fill(LiquidColor.cian.opacity(Self.pastillaFondoAlfa))
                        .overlay(
                            Capsule()
                                .strokeBorder(LiquidColor.cian.opacity(Self.cantoAlfa), lineWidth: 0.5)
                        )
                )
                .padding(.leading, Self.pastillaGap)
                .accessibilityHidden(true) // ya va en el label de la tarjeta
            Spacer(minLength: 8)
            // D0 (FER-170 · F5): «⤢» — la puerta directa a Foco (mock `hoja-mapa.html` D0), junto al
            // «···» que ya trae «Enfoque» como respaldo. La acción real vive en `.accessibilityAction`
            // del cuerpo (rotor) — este botón se oculta del árbol de accesibilidad para no duplicarla.
            if let onEnfocar {
                Button(action: onEnfocar) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(InstrumentoType.grotesk(Self.menuSize, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(minWidth: HojaMetrics.hitMin, minHeight: HojaMetrics.hitMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            if let onMenu {
                Button(action: onMenu) {
                    Text(verbatim: "···")
                        .font(InstrumentoType.grotesk(
                            Self.menuSize, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(LiquidColor.tinta500)
                        .frame(minWidth: HojaMetrics.hitMin, minHeight: HojaMetrics.hitMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // R10 (QA D6): vía catálogo, no español hardcodeado (`String(localized:)` en vez de
                // `Text(verbatim:)` — la clave "More options" ya existe y trae su es-MX).
                .accessibilityLabel(Text("More options"))
            }
        }
    }

    // MARK: - Cristal

    /// Aproxima el `box-shadow` inset + canto + sombra de `.ss2` (SwiftUI no tiene inset shadow).
    private var cristal: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radio, style: .continuous)
        return shape
            .fill(LiquidColor.cian.opacity(Self.fondoAlfa))
            .overlay {
                shape.strokeBorder(Color.white.opacity(Self.highlightAlfa), lineWidth: 1)
                    .blur(radius: 0.5)
                    .mask(shape)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(Self.aroAlfa), lineWidth: 1)
            }
            .overlay {
                shape.strokeBorder(LiquidColor.cian.opacity(Self.cantoAlfa), lineWidth: 0.5)
            }
            .shadow(
                color: LiquidColor.tinta900.opacity(Self.sombraCercaAlfa),
                radius: Self.sombraCercaRadio / 2,
                x: 0, y: Self.sombraCercaY)
            .shadow(
                color: LiquidColor.cian.opacity(Self.sombraAlfa),
                radius: Self.sombraRadio / 2,
                x: 0, y: Self.sombraY)
    }
}

/// D0 (FER-170 · F5): agrega la acción de VoiceOver «Foco» solo cuando el caller trae una — sin
/// esto, un `.accessibilityAction` incondicional expondría un botón «Foco» inerte en el rotor
/// cuando la tarjeta se monta SIN sesión que enfocar (Hoja fría/edición).
private extension View {
    @ViewBuilder
    func accessibilityActionIfAvailable(_ action: (() -> Void)?) -> some View {
        if let action {
            self.accessibilityAction(named: Text("Focus"), action)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("HojaTarjetaSuperserie · edición") {
    HojaTarjetaSuperserie(
        nombre: "Zancadas ＋ Curl femoral",
        pie: "3 rondas · descanso al cerrar cada ronda · 1:30",
        onMenu: {}
    ) {
        HojaFilaSerie(
            datos: .init(
                numero: "1", esCalentamiento: false,
                peso: "60", unidad: "kg", conSubida: false, reps: "10",
                arrastrable: true),
            contexto: .edicion, marca: .pendiente)
        HojaFilaSerie(
            datos: .init(
                numero: "2", esCalentamiento: false,
                peso: "70", unidad: "kg", conSubida: false, reps: "12",
                arrastrable: true),
            contexto: .edicion, marca: .pendiente)
    }
    .padding(16)
    .background(LiquidColor.fondoGradient)
}
#endif
