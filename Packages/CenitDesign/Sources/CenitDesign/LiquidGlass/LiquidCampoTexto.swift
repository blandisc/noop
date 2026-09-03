import SwiftUI
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

// MARK: - LiquidCampoTexto (FER-339)
//
// Campo de texto El Eje: padding + `.liquidGlass(.superficieSolida)` + `LiquidType.cuerpoLista`
// (receta de CreateExerciseSheet). Una pieza por rol «campo de texto»; no dejar TextField suelto.
//
// Cuándo SÍ: nombre, deporte, notas, números con teclado. Cuándo NO: búsqueda con lupa
// (usa `LiquidCampoBusqueda`); campo teñido de métrica (usa `LiquidCampoMetrica`).

/// Teclado del campo — espejo de `UIKeyboardType` sin arrastrar UIKit al signature en macOS.
public enum LiquidCampoTeclado: Sendable {
    case `default`
    case numberPad
    case decimalPad
    case emailAddress
    case phonePad
    case numbersAndPunctuation
    case URL
    case asciiCapable
    case namePhonePad
    case asciiCapableNumberPad
    case twitter
    case webSearch

    #if canImport(UIKit) && !os(watchOS)
    fileprivate var uiKit: UIKeyboardType {
        switch self {
        case .default: return .default
        case .numberPad: return .numberPad
        case .decimalPad: return .decimalPad
        case .emailAddress: return .emailAddress
        case .phonePad: return .phonePad
        case .numbersAndPunctuation: return .numbersAndPunctuation
        case .URL: return .URL
        case .asciiCapable: return .asciiCapable
        case .namePhonePad: return .namePhonePad
        case .asciiCapableNumberPad: return .asciiCapableNumberPad
        case .twitter: return .twitter
        case .webSearch: return .webSearch
        }
    }
    #endif
}

public struct LiquidCampoTexto: View {
    private let titulo: String?
    @Binding private var texto: String
    private let placeholder: String
    private let a11y: String
    private let teclado: LiquidCampoTeclado
    private let eje: Axis?
    private let limiteLineas: ClosedRange<Int>?
    private let sufijo: String?
    private let conSuperficie: Bool
    private let tipografia: Font
    private let tracking: CGFloat?
    private let onSubmit: (() -> Void)?

    /// - Parameters:
    ///   - titulo: rótulo kicker opcional encima del campo (`nil` = solo el campo).
    ///   - texto: binding del valor.
    ///   - placeholder: prompt ya localizado.
    ///   - teclado: tipo de teclado (mapea a `UIKeyboardType` bajo `#if canImport(UIKit)`).
    ///   - a11y: label de VoiceOver ya localizado.
    ///   - eje: `.vertical` para multilínea; `nil` = una línea.
    ///   - limiteLineas: rango de líneas cuando `eje == .vertical`.
    ///   - sufijo: unidad a la derecha (p. ej. «bpm», «kcal»); `nil` = sin sufijo.
    ///   - conSuperficie: `false` cuando el caller aplica otro cromo (p. ej. celda con subrayado).
    ///   - tipografia: override; default `LiquidType.cuerpoLista`.
    ///   - tracking: tracking tipográfico opcional (p. ej. `displaySTracking`).
    ///   - onSubmit: acción al enviar en el teclado.
    public init(
        _ titulo: String?,
        texto: Binding<String>,
        placeholder: String,
        teclado: LiquidCampoTeclado = .default,
        a11y: String,
        eje: Axis? = nil,
        limiteLineas: ClosedRange<Int>? = nil,
        sufijo: String? = nil,
        conSuperficie: Bool = true,
        tipografia: Font = LiquidType.cuerpoLista,
        tracking: CGFloat? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.titulo = titulo
        self._texto = texto
        self.placeholder = placeholder
        self.a11y = a11y
        self.teclado = teclado
        self.eje = eje
        self.limiteLineas = limiteLineas
        self.sufijo = sufijo
        self.conSuperficie = conSuperficie
        self.tipografia = tipografia
        self.tracking = tracking
        self.onSubmit = onSubmit
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Conveniencia que acepta `UIKeyboardType` directo (call-sites iOS).
    public init(
        _ titulo: String?,
        texto: Binding<String>,
        placeholder: String,
        teclado: UIKeyboardType,
        a11y: String,
        eje: Axis? = nil,
        limiteLineas: ClosedRange<Int>? = nil,
        sufijo: String? = nil,
        conSuperficie: Bool = true,
        tipografia: Font = LiquidType.cuerpoLista,
        tracking: CGFloat? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.init(
            titulo,
            texto: texto,
            placeholder: placeholder,
            teclado: LiquidCampoTeclado(uiKit: teclado),
            a11y: a11y,
            eje: eje,
            limiteLineas: limiteLineas,
            sufijo: sufijo,
            conSuperficie: conSuperficie,
            tipografia: tipografia,
            tracking: tracking,
            onSubmit: onSubmit)
    }
    #endif

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            if let titulo, !titulo.isEmpty {
                Text(verbatim: titulo)
                    .liquidKicker()
                    .foregroundStyle(LiquidColor.tinta500)
            }
            campo
        }
    }

    @ViewBuilder
    private var campo: some View {
        let core = HStack(spacing: LiquidSpace.s150) {
            fieldCore
            if let sufijo, !sufijo.isEmpty {
                Text(verbatim: sufijo)
                    .font(LiquidType.unidad)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .accessibilityElement(children: .combine)
        .modifier(CampoTextoA11y(a11y: a11y))

        if conSuperficie {
            core
                .padding(.horizontal, LiquidSpace.s300)
                .padding(.vertical, LiquidSpace.s250)
                .liquidGlass(.superficieSolida)
        } else {
            core
        }
    }

    @ViewBuilder
    private var fieldCore: some View {
        Group {
            if let eje, eje == .vertical {
                TextField(
                    "",
                    text: $texto,
                    prompt: Text(verbatim: placeholder).foregroundStyle(LiquidColor.tinta500),
                    axis: .vertical
                )
                .font(tipografia)
                .applyTracking(tracking)
                .foregroundStyle(LiquidColor.tinta900)
                .applyLineLimit(limiteLineas)
            } else {
                TextField(placeholder, text: $texto)
                    .textFieldStyle(.plain)
                    .font(tipografia)
                    .applyTracking(tracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }
        }
        #if canImport(UIKit) && !os(watchOS)
        .keyboardType(teclado.uiKit)
        #endif
        .applyOnSubmit(onSubmit)
    }
}

#if canImport(UIKit) && !os(watchOS)
private extension LiquidCampoTeclado {
    init(uiKit: UIKeyboardType) {
        switch uiKit {
        case .numberPad: self = .numberPad
        case .decimalPad: self = .decimalPad
        case .emailAddress: self = .emailAddress
        case .phonePad: self = .phonePad
        case .numbersAndPunctuation: self = .numbersAndPunctuation
        case .URL: self = .URL
        case .asciiCapable: self = .asciiCapable
        case .namePhonePad: self = .namePhonePad
        case .asciiCapableNumberPad: self = .asciiCapableNumberPad
        case .twitter: self = .twitter
        case .webSearch: self = .webSearch
        default: self = .default
        }
    }
}
#endif

private struct CampoTextoA11y: ViewModifier {
    let a11y: String
    func body(content: Content) -> some View {
        if a11y.isEmpty {
            content
        } else {
            content.accessibilityLabel(Text(verbatim: a11y))
        }
    }
}

private extension View {
    @ViewBuilder
    func applyLineLimit(_ range: ClosedRange<Int>?) -> some View {
        if let range {
            self.lineLimit(range)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyTracking(_ value: CGFloat?) -> some View {
        if let value {
            self.tracking(value)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyOnSubmit(_ action: (() -> Void)?) -> some View {
        if let action {
            self.onSubmit(of: .text) { action() }
        } else {
            self
        }
    }
}

#if DEBUG
#Preview("LiquidCampoTexto") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidCampoTexto("Name", texto: .constant(""),
                         placeholder: "e.g. Svend press",
                         a11y: "Name")
        LiquidCampoTexto(nil, texto: .constant("72"),
                         placeholder: "optional",
                         teclado: LiquidCampoTeclado.numberPad,
                         a11y: "Average heart rate",
                         sufijo: "bpm")
        LiquidCampoTexto("Notes", texto: .constant(""),
                         placeholder: "Add a note (optional)",
                         a11y: "Notes",
                         eje: .vertical,
                         limiteLineas: 1...5,
                         conSuperficie: false,
                         tipografia: .system(size: LiquidType.lecturaHojaBase))
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
}
#endif
