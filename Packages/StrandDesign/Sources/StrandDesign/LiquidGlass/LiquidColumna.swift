import SwiftUI

// MARK: - Liquid Glass · Columna de dato (FER-28 «El Tablero»)
//
// Dentro de un módulo, cada dato es una COLUMNA desnuda y tocable: rótulo arriba, valor
// teñido 1:1 en medio, detalle/delta abajo. Área de toque ≥ 44 pt, press que hunde SOLO la
// columna (`.liquidPress`) + un haptic suave, y contrato de VoiceOver como botón
// «{dato}, {valor}, {delta}» + hint «Abre el detalle».
//
// Dos piezas: `LiquidColumnaShell` (el envoltorio reutilizable: rótulo + contenido libre +
// botón/press/haptic/a11y) para las columnas ricas (carga con bullet-graph, «VIGILANDO» con
// par teñido, sueño con su dos-puntos tenue), y `LiquidColumna` (el caso simple
// valor+unidad+detalle), que cubre 7 de las 10 columnas de Hoy.

/// El envoltorio de una columna: rótulo `dato` + contenido libre, hecho botón con el press y
/// el haptic del sistema, con su etiqueta de VoiceOver. Alinea a la izquierda o a la derecha
/// (las columnas `.der` del mockup).
public struct LiquidColumnaShell<Content: View>: View {
    private let label: String
    private let alignment: HorizontalAlignment
    private let a11yLabel: String
    private let a11yHint: String
    private let action: () -> Void
    private let content: Content

    @State private var taps = 0

    public init(label: String, alignment: HorizontalAlignment = .leading,
                a11yLabel: String, a11yHint: String = "Opens the detail",
                action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.label = label
        self.alignment = alignment
        self.a11yLabel = a11yLabel
        self.a11yHint = a11yHint
        self.action = action
        self.content = content()
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .trailing: return .trailing
        case .center: return .center
        default: return .leading
        }
    }

    public var body: some View {
        Button {
            taps &+= 1
            action()
        } label: {
            VStack(alignment: alignment, spacing: LiquidSpace.s025) {
                Text(label).liquidDato().foregroundStyle(LiquidColor.tinta500)
                content
            }
            // Hit target del sistema (eje 8 de tokenización: 44 pt, HIG). El desperdicio que
            // se veía antes NO era este piso sino el capilar greedy (arreglado con
            // `.fixedSize(vertical:)` en la fila); con eso resuelto, 44 pt es el estándar sano.
            .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget, alignment: frameAlignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityHint(Text(verbatim: a11yHint))
        .accessibilityAddTraits(.isButton)
        .liquidSoftHaptic(trigger: taps)
    }
}

/// El caso simple de columna: valor teñido 1:1 + unidad tinta/500 + una línea de detalle
/// (tinta/500, o verde si mejora). Para sueño/carga/«VIGILANDO» usa `LiquidColumnaShell`.
public struct LiquidColumna: View {
    private let label: String
    private let value: String
    private let unit: String
    private let detail: String
    private let detailImproves: Bool
    private let tone: Color
    private let alignment: HorizontalAlignment
    private let a11yValencia: String?
    /// VoiceOver YA compuesto por el caller (con valencia, origen, etc.). Si es `nil` se deriva
    /// de label/valor/detalle/valencia — pero el caller que tiene el label completo debe pasarlo
    /// para no PERDER la valencia audible ni el origen (el color no habla).
    private let a11yLabelOverride: String?
    private let a11yHint: String
    private let action: () -> Void

    public init(label: String, value: String, unit: String = "", detail: String = "",
                detailImproves: Bool = false, tone: Color,
                alignment: HorizontalAlignment = .leading, a11yValencia: String? = nil,
                a11yLabel: String? = nil, a11yHint: String = "Opens the detail",
                action: @escaping () -> Void) {
        self.label = label
        self.value = value
        self.unit = unit
        self.detail = detail
        self.detailImproves = detailImproves
        self.tone = tone
        self.alignment = alignment
        self.a11yValencia = a11yValencia
        self.a11yLabelOverride = a11yLabel
        self.a11yHint = a11yHint
        self.action = action
    }

    private var a11yLabel: String {
        if let a11yLabelOverride { return a11yLabelOverride }
        let valor = unit.isEmpty ? value : "\(value) \(unit)"
        var parts = ["\(label), \(valor)"]
        if !detail.isEmpty { parts.append(detail) }
        if let v = a11yValencia { parts.append(v) }
        return parts.joined(separator: ", ")
    }

    public var body: some View {
        LiquidColumnaShell(label: label, alignment: alignment, a11yLabel: a11yLabel,
                           a11yHint: a11yHint, action: action) {
            VStack(alignment: alignment, spacing: LiquidSpace.s025) {
                HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s050) {
                    Text(value).font(LiquidType.valorL).foregroundStyle(tone)
                    if !unit.isEmpty {
                        Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail).font(LiquidType.captionLectura)
                        .foregroundStyle(detailImproves ? LiquidColor.verdeProfundo
                                                         : LiquidColor.tinta500)
                }
            }
        }
    }
}

// MARK: - Haptic suave del sistema

public extension View {
    /// Un toque háptico ligero cuando `trigger` cambia (el press de una columna). Sólo iOS 17+;
    /// en el resto es inerte. La gramática de toque del sistema: visual `.liquidPress` + esto.
    @ViewBuilder
    func liquidSoftHaptic<T: Equatable>(trigger: T) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            self.sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: trigger)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
#Preview("Liquid · Columna") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        HStack(alignment: .top, spacing: 0) {
            LiquidColumna(label: "SUEÑO", value: "7:20", unit: "h", detail: "20:00 → 4:00",
                          tone: LiquidColor.indigo) {}
            LiquidCapilar()
            LiquidColumna(label: "FC REPOSO", value: "52", unit: "lpm", detail: "en tu rango",
                          tone: LiquidColor.rosa, alignment: .trailing) {}
        }
        .padding(LiquidSpace.s600)
    }
}
#endif
