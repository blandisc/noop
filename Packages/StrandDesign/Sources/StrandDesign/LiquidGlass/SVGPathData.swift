import SwiftUI

// MARK: - Liquid Glass · Parser de path SVG
//
// La iconografía del handoff es 100 % SVG inline dibujado a mano (paths exactos en los
// archivos de componentes). Para que los glifos sean bit-fieles y diffeables contra el
// handoff, el catálogo (`LiquidIcon`) guarda los strings de path tal cual y este parser
// los convierte a `Path` de SwiftUI.
//
// Soporta el subconjunto que usa el corpus: M/m, L/l, H/h, V/v, C/c, S/s, Q/q, A/a, Z/z,
// con repetición implícita de comando y números pegados («.5-1.6.2»). Los arcos elípticos
// se convierten con la parametrización endpoint→centro del spec SVG (F.6.5) y se aproximan
// por tramos ≤ 90° con cúbicas (k = 4/3 · tan(Δθ/4)).

enum SVGPathData {

    /// Convierte un atributo `d` de SVG a un `Path` en coordenadas del viewBox.
    static func path(_ d: String) -> Path {
        var path = Path()
        var scanner = Tokenizer(d)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var command: Character = " "

        while let token = scanner.next() {
            switch token {
            case .command(let c):
                command = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    lastCubicControl = nil
                }
            case .number(let first):
                // Un número sin comando nuevo = repetición implícita del comando anterior
                // (M implícito se vuelve L, m se vuelve l — spec SVG).
                if command == "M" { command = "L" }
                if command == "m" { command = "l" }
                let relative = command.isLowercase
                let origin = relative ? current : .zero

                switch Character(command.uppercased()) {
                case "M":
                    let y = scanner.number()
                    current = CGPoint(x: origin.x + first, y: origin.y + y)
                    path.move(to: current)
                    subpathStart = current
                    lastCubicControl = nil
                    command = relative ? "l" : "L"
                case "L":
                    let y = scanner.number()
                    current = CGPoint(x: origin.x + first, y: origin.y + y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                case "H":
                    current = CGPoint(x: (relative ? current.x : 0) + first, y: current.y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                case "V":
                    current = CGPoint(x: current.x, y: (relative ? current.y : 0) + first)
                    path.addLine(to: current)
                    lastCubicControl = nil
                case "C":
                    let y1 = scanner.number()
                    let c1 = CGPoint(x: origin.x + first, y: origin.y + y1)
                    let c2 = CGPoint(x: origin.x + scanner.number(), y: origin.y + scanner.number())
                    current = CGPoint(x: origin.x + scanner.number(), y: origin.y + scanner.number())
                    path.addCurve(to: current, control1: c1, control2: c2)
                    lastCubicControl = c2
                case "S":
                    let y2 = scanner.number()
                    let c2 = CGPoint(x: origin.x + first, y: origin.y + y2)
                    let end = CGPoint(x: origin.x + scanner.number(), y: origin.y + scanner.number())
                    // El primer control es la reflexión del último control cúbico.
                    let c1: CGPoint
                    if let last = lastCubicControl {
                        c1 = CGPoint(x: 2 * current.x - last.x, y: 2 * current.y - last.y)
                    } else {
                        c1 = current
                    }
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end
                    lastCubicControl = c2
                case "Q":
                    let y1 = scanner.number()
                    let control = CGPoint(x: origin.x + first, y: origin.y + y1)
                    current = CGPoint(x: origin.x + scanner.number(), y: origin.y + scanner.number())
                    path.addQuadCurve(to: current, control: control)
                    lastCubicControl = nil
                case "A":
                    let rx = first
                    let ry = scanner.number()
                    let rotation = scanner.number()
                    let largeArc = scanner.number() != 0
                    let sweep = scanner.number() != 0
                    let end = CGPoint(x: origin.x + scanner.number(), y: origin.y + scanner.number())
                    addArc(to: &path, from: current, rx: rx, ry: ry, rotationDegrees: rotation,
                           largeArc: largeArc, sweep: sweep, end: end)
                    current = end
                    lastCubicControl = nil
                default:
                    assertionFailure("SVGPathData: comando no soportado «\(command)»")
                    return path
                }
            }
        }
        return path
    }

    // MARK: Arco elíptico → cúbicas (SVG spec F.6.5)

    private static func addArc(to path: inout Path, from p0: CGPoint, rx rxIn: CGFloat,
                               ry ryIn: CGFloat, rotationDegrees: CGFloat,
                               largeArc: Bool, sweep: Bool, end p1: CGPoint) {
        var rx = abs(rxIn), ry = abs(ryIn)
        guard rx > 0, ry > 0, p0 != p1 else {
            path.addLine(to: p1)
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Corrección de radios insuficientes.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let rxSq = rx * rx, rySq = ry * ry
        let x1pSq = x1p * x1p, y1pSq = y1p * y1p

        var numerator = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
        if numerator < 0 { numerator = 0 }
        let denominator = rxSq * y1pSq + rySq * x1pSq
        var coefficient = denominator == 0 ? 0 : sqrt(numerator / denominator)
        if largeArc == sweep { coefficient = -coefficient }

        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard len > 0 else { return 0 }
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                               (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep && deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let delta = deltaTheta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(delta / 4)

        func point(_ theta: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(theta) * cosPhi - ry * sin(theta) * sinPhi,
                    y: cy + rx * cos(theta) * sinPhi + ry * sin(theta) * cosPhi)
        }
        func derivative(_ theta: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(theta) * cosPhi - ry * cos(theta) * sinPhi,
                    y: -rx * sin(theta) * sinPhi + ry * cos(theta) * cosPhi)
        }

        var theta = theta1
        for _ in 0..<segments {
            let next = theta + delta
            let e1 = point(theta), e2 = point(next)
            let d1 = derivative(theta), d2 = derivative(next)
            path.addCurve(
                to: e2,
                control1: CGPoint(x: e1.x + k * d1.x, y: e1.y + k * d1.y),
                control2: CGPoint(x: e2.x - k * d2.x, y: e2.y - k * d2.y))
            theta = next
        }
    }

    // MARK: Tokenizer

    enum Token {
        case command(Character)
        case number(CGFloat)
    }

    struct Tokenizer {
        private let chars: [Character]
        private var index = 0

        init(_ d: String) {
            chars = Array(d)
        }

        mutating func next() -> Token? {
            skipSeparators()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter {
                index += 1
                return .command(c)
            }
            guard let n = scanNumber() else { return nil }
            return .number(n)
        }

        /// El siguiente número, cuando el comando actual exige más parámetros.
        mutating func number() -> CGFloat {
            skipSeparators()
            guard let n = scanNumber() else {
                assertionFailure("SVGPathData: parámetro numérico faltante")
                return 0
            }
            return n
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," ||
                chars[index] == "\n" || chars[index] == "\t" {
                index += 1
            }
        }

        private mutating func scanNumber() -> CGFloat? {
            var text = ""
            var seenDot = false
            var j = index
            while j < chars.count {
                let c = chars[j]
                if c == "+" || c == "-" {
                    // Un signo solo abre número al inicio o tras exponente.
                    guard j == index else { break }
                    text.append(c)
                } else if c == "." {
                    // Un segundo punto arranca el número siguiente («.5-1.6.2»).
                    guard !seenDot else { break }
                    seenDot = true
                    text.append(c)
                } else if c.isNumber {
                    text.append(c)
                } else {
                    break
                }
                j += 1
            }
            guard j > index, let value = Double(text) else { return nil }
            index = j
            return CGFloat(value)
        }
    }
}
