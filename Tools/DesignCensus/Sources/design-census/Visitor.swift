import Foundation
import SwiftSyntax
import SwiftParser

/// El único archivo que toca el AST. Todo lo demás (taxonomía, reporte, roles) trabaja sobre los
/// `Hit`/`ExemptHit` que este visitor produce.
///
/// Por qué AST y no regex (la razón de ser del censo, FER-261 principio 1): una llamada partida
/// en varias líneas —`.padding(\n    14\n)`— evade el regex de `check-design-drift.py` porque
/// ese linter opera línea por línea; el AST no distingue. Este visitor es, ante todo, el colador
/// de ESA clase de evasión — no reemplaza al linter (sigue siendo la verja rápida del hot path).
final class CensusVisitor: SyntaxVisitor {
    private(set) var hits: [Hit] = []
    private(set) var compositionCandidates: [CompositionCandidate] = []
    private(set) var iconNames: [String] = []          // SF Symbol names literales usados
    private(set) var symbolReferences: Set<String> = [] // identificadores tipo Liquid*/Instrumento* vistos

    private let file: String
    private let converter: SourceLocationConverter
    private let sourceText: String

    init(file: String, tree: SourceFileSyntax, converter: SourceLocationConverter, sourceText: String) {
        self.file = file
        self.converter = converter
        self.sourceText = sourceText
        super.init(viewMode: .sourceAccurate)
    }

    private func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }

    private func snippet(of node: some SyntaxProtocol) -> String {
        let s = node.trimmedDescription.replacingOccurrences(of: "\n", with: " ")
        return s.count > 120 ? String(s.prefix(117)) + "..." : s
    }

    private func record(_ dimension: Dimension, rule: String, node: some SyntaxProtocol, value: Double? = nil) {
        hits.append(Hit(file: file, line: line(of: node), dimension: dimension, rule: rule, snippet: snippet(of: node), value: value))
    }

    /// Literal numérico bare (incluye negativos: `-22`).
    private func literalValue(_ expr: ExprSyntax) -> Double? {
        if let lit = expr.as(IntegerLiteralExprSyntax.self) {
            return Double(lit.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let lit = expr.as(FloatLiteralExprSyntax.self) {
            return Double(lit.literal.text.replacingOccurrences(of: "_", with: ""))
        }
        if let pre = expr.as(PrefixOperatorExprSyntax.self), pre.operator.text == "-" {
            return literalValue(pre.expression).map { -$0 }
        }
        return nil
    }

    /// `token ± n`: un lado es literal, el otro NO lo es (referencia a un token/variable) — la
    /// evasión clásica de "ya lo saqué de CenitMetrics, nomás le sumo 2".
    private func tokenPlusNValue(_ expr: ExprSyntax) -> Bool {
        guard let bin = expr.as(InfixOperatorExprSyntax.self),
              let op = bin.operator.as(BinaryOperatorExprSyntax.self)?.operator.text,
              op == "+" || op == "-" else { return false }
        let leftLit = literalValue(bin.leftOperand) != nil
        let rightLit = literalValue(bin.rightOperand) != nil
        return leftLit != rightLit // exactamente uno de los dos es literal
    }

    override func visit(_ node: LabeledExprSyntax) -> SyntaxVisitorContinueKind {
        guard let label = node.label?.text else { return .visitChildren }
        let expr = node.expression
        switch label {
        case "cornerRadius", "radius":
            if let v = literalValue(expr) {
                record(.radiusElevation, rule: "literal-\(label)", node: node, value: v)
            } else if tokenPlusNValue(expr) {
                record(.radiusElevation, rule: "evasion:token±n", node: node)
            }
        case "lineWidth":
            if let v = literalValue(expr) {
                record(.radiusElevation, rule: "literal-lineWidth", node: node, value: v)
            }
        case "spacing":
            if let v = literalValue(expr) {
                record(.spacing, rule: "literal-spacing", node: node, value: v)
            } else if tokenPlusNValue(expr) {
                record(.spacing, rule: "evasion:token±n", node: node)
            }
        case "width", "height":
            if literalValue(expr) != nil {
                record(.spacing, rule: "evasion:.frame(\(label):)-decorativo", node: node)
            }
        case "size":
            // .font(.system(size: 13)) — el padre es el que da contexto; igual lo marcamos aquí
            // como candidato de tipografía si el literal es plausible (8...96pt).
            if let v = literalValue(expr), v > 0, v < 200 {
                record(.typography, rule: "literal-font-size", node: node, value: v)
            }
        default:
            break
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = node.calledExpression.trimmedDescription

        // .padding(14) / .padding(.top, 14) — el primer/segundo argumento posicional.
        if callee.hasSuffix(".padding") || callee == "padding" {
            let args = Array(node.arguments)
            for arg in args where arg.label == nil {
                if let v = literalValue(arg.expression) {
                    record(.spacing, rule: "literal-padding", node: node, value: v)
                } else if tokenPlusNValue(arg.expression) {
                    record(.spacing, rule: "evasion:token±n", node: node)
                }
            }
        }

        // .safeAreaPadding(14) — evasión directa del regex `no-spacing-literal` (no matchea
        // `.padding`, y el AST no le da ventaja al nombre distinto).
        if callee.hasSuffix(".safeAreaPadding") {
            for arg in node.arguments where literalValue(arg.expression) != nil {
                record(.spacing, rule: "evasion:.safeAreaPadding", node: node)
                _ = arg
            }
        }

        // .offset(x:y:) — desplazamiento manual fuera de token.
        if callee.hasSuffix(".offset") {
            record(.spacing, rule: "evasion:.offset", node: node)
        }

        // EdgeInsets(top:leading:bottom:trailing:) construido a mano con literales.
        if callee == "EdgeInsets" {
            let anyLiteral = node.arguments.contains { literalValue($0.expression) != nil }
            if anyLiteral {
                record(.spacing, rule: "evasion:EdgeInsets(literal)", node: node)
            }
        }

        // clipShape(RoundedRectangle(cornerRadius: n)) — mismo hueco que cornerRadius: directo,
        // pero envuelto para no matchear `RE_RADIUS` de la regex si esta cambiara de forma.
        if callee.hasSuffix(".clipShape"), node.trimmedDescription.contains("RoundedRectangle") {
            record(.radiusElevation, rule: "evasion:clipShape(RoundedRectangle)", node: node)
        }

        // .shadow(...) inline con radio/y literales.
        if callee.hasSuffix(".shadow") {
            record(.radiusElevation, rule: "literal-shadow", node: node)
        }

        // Color.white / Color.black / Color.gray — literal de sistema fuera de StrandPalette.
        if callee == "Color" {
            let text = node.arguments.map { $0.expression.trimmedDescription }.joined(separator: ",")
            if text.contains("red:") || text.contains("uiColor:") {
                record(.color, rule: "evasion:Color(red:g:b:/uiColor:)", node: node)
            }
        }

        // Image(systemName: "…") — vocabulario de iconografía y candidato a StrandIcon.
        if callee == "Image" {
            for arg in node.arguments where arg.label?.text == "systemName" {
                if let str = arg.expression.as(StringLiteralExprSyntax.self) {
                    let name = str.segments.description
                    iconNames.append(name)
                    record(.iconography, rule: "literal-systemName", node: node)
                }
            }
        }

        // .animation(...) / .transition(...) / .spring(...) literales — dimensión movimiento.
        if callee.hasSuffix(".animation") || callee.hasSuffix(".transition") {
            record(.movement, rule: "literal-\(callee.split(separator: ".").last.map(String.init) ?? callee)", node: node)
        }
        if callee.hasSuffix(".spring") || callee.hasSuffix(".easeInOut") || callee.hasSuffix(".easeIn") || callee.hasSuffix(".easeOut") {
            let hasLiteralDuration = node.arguments.contains { $0.label?.text == "duration" && literalValue($0.expression) != nil }
            if hasLiteralDuration {
                record(.movement, rule: "literal-curve-duration", node: node)
            }
        }

        // Háptica: generadores UIKit crudos fuera de un helper de StrandDesign (p.ej. EntrenarHaptics).
        if callee.contains("UIImpactFeedbackGenerator") || callee.contains("UINotificationFeedbackGenerator") || callee.contains("UISelectionFeedbackGenerator") {
            record(.interaction, rule: "evasion:UIFeedbackGenerator-crudo", node: node)
        }
        if callee.hasSuffix(".sensoryFeedback") {
            record(.interaction, rule: "uso-sensoryFeedback", node: node)
        }

        // Composición candidata: una cadena de modificadores que junta fondo + forma/radio
        // (+ sombra, si la trae) — el patrón "candidatos de composición" del issue §c. Solo
        // dispara en la llamada MÁS EXTERNA de la cadena (si esta llamada es la base de otra
        // `.algo(...)` que sigue, no es el final — se disparará ahí) para no reportar el mismo
        // candidato una vez por cada eslabón.
        let isOutermostOfChain = !((node.parent?.as(MemberAccessExprSyntax.self)?.parent?.is(FunctionCallExprSyntax.self)) ?? false)
        if isOutermostOfChain {
            let chainText = node.trimmedDescription
            let hasBackground = chainText.contains(".background(") || chainText.contains(".fill(") || chainText.contains(".overlay(")
            let hasShape = chainText.contains("cornerRadius") || chainText.contains("RoundedRectangle") || chainText.contains("Capsule") || chainText.contains(".clipShape(")
            if hasBackground && hasShape {
                compositionCandidates.append(CompositionCandidate(file: file, line: line(of: node), snippet: snippet(of: node)))
            }
        }

        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.declName.baseName.text
        // Color.white/.black/.gray — sistema, fuera de StrandPalette.
        if node.base?.trimmedDescription == "Color", ["white", "black", "gray", "clear"].contains(name) {
            record(.color, rule: "evasion:Color.\(name)", node: node)
        }
        // .foregroundStyle(.primary)/.secondary fuera de token — se detecta en la llamada padre,
        // aquí solo marcamos el símbolo para el conteo de vocabulario si hiciera falta a futuro.
        if name.hasPrefix("Liquid") || name.hasPrefix("Instrumento") {
            symbolReferences.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if name.hasPrefix("Liquid") || name.hasPrefix("Instrumento") {
            symbolReferences.insert(name)
        }
        return .visitChildren
    }

}

/// `.foregroundStyle(.primary)` fuera de tokens: se resuelve aparte porque el argumento es
/// posicional sin label — se busca por texto de la llamada completa (barato, y el AST ya
/// garantiza que no importan los saltos de línea).
extension CensusVisitor {
    static func scanForegroundStyleLiteral(file: String, tree: SourceFileSyntax, converter: SourceLocationConverter) -> [Hit] {
        final class V: SyntaxVisitor {
            var hits: [Hit] = []
            let file: String
            let converter: SourceLocationConverter
            init(file: String, converter: SourceLocationConverter) {
                self.file = file
                self.converter = converter
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                let callee = node.calledExpression.trimmedDescription
                if callee.hasSuffix(".foregroundStyle") || callee.hasSuffix(".foregroundColor") {
                    for arg in node.arguments where arg.label == nil {
                        let t = arg.expression.trimmedDescription
                        if t == ".primary" || t == ".secondary" || t == ".white" || t == ".black" {
                            let ln = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
                            hits.append(Hit(file: file, line: ln, dimension: .color, rule: "evasion:.foregroundStyle(\(t))-fuera-de-token", snippet: node.trimmedDescription.replacingOccurrences(of: "\n", with: " "), value: nil))
                        }
                    }
                }
                return .visitChildren
            }
        }
        let v = V(file: file, converter: converter)
        v.walk(tree)
        return v.hits
    }
}
