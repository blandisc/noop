import SwiftUI

// MARK: - HojaTarjetaSuperserie — tarjeta única de superserie (FER-166)
//
// Estado EDICIÓN (mock `hoja-pantallas.html` P1 `.ss2` / `.ssL`). El vivo de sesión (P5) llega
// en F3. Contenedor = módulo mosaico cian (FER-249); el rótulo cian reusa
// `LiquidTono.cian.rotulo`.

/// Tarjeta de superserie en edición: módulo cian + nombre + pastilla + filas + pie.
public struct HojaTarjetaSuperserie<Filas: View>: View {

    /// Canto exterior cian al 30 % de la pastilla SUPERSERIE (`.ssL`).
    private static var cantoAlfa: Double { 0.30 }

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
    /// Rótulo cian canónico del vidrio teñido (mock `.ssL` / `.ronda`).
    private static var cianRotulo: Color { LiquidTono.cian.rotulo }
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
        EntrenarModulo(tono: .cian, intensidad: LiquidTonoMetrics.intensidadDefault,
                       insets: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
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
        }
        .accessibilityElement(children: .contain)
        // N5 (ronda 3, menor): vía catálogo — reusa la MISMA clave que `SupersetTag`
        // (`RoutineSetEditing.swift`) en vez de hardcodear «Superserie» en español.
        .accessibilityLabel(Text(verbatim: "\(String(localized: "Superset")), \(nombre)"))
        .accessibilityActionIfAvailable(onEnfocar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            // FER-187: cromo sin celdas (nombre + pastilla). Con `onEnfocar` (sesión viva), un tap
            // entra a foco — las filas de ronda conservan sus TapZones. En edición `onEnfocar` es
            // nil y el cromo no responde.
            cromoNombre
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

    @ViewBuilder private var cromoNombre: some View {
        let bloque = HStack(alignment: .center, spacing: 0) {
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
        }
        .contentShape(Rectangle())
        if let onEnfocar {
            bloque.onTapGesture(perform: onEnfocar)
        } else {
            bloque
        }
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
    .padding(LiquidSpace.s400)
    .background(LiquidColor.papelGradient)
}
#endif
