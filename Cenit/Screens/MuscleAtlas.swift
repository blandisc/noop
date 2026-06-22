#if os(iOS)
import SwiftUI

// MARK: - MuscleAtlas — the front/back silhouette taxonomy (FER-350)
//
// The presentation half of the muscle map: it maps each of the catalog's 17 (lowercased,
// free-exercise-db) muscle names to a Spanish display name and a region on a front- or back-facing
// schematic silhouette. The LOAD math is muscle-agnostic and lives in `MuscleFatigueMap`
// (StrandAnalytics); the body geometry is a UI concern and lives here. Regions are normalized rects
// (0…1 in both axes) over a 100×220 figure box, scaled to whatever size the layout gives them.
//
// Front vs back is a single-side assignment per muscle (a muscle is colored on one figure, not both):
//   Front: chest, abdominals, shoulders, biceps, forearms, quadriceps, adductors, neck.
//   Back:  traps, lats, middle back, lower back, triceps, glutes, hamstrings, calves, abductors.

enum MuscleAtlas {

    enum Side { case front, back }

    struct Region: Identifiable {
        let id: String
        let muscle: String
        let side: Side
        let x, y, w, h: CGFloat
        let ellipse: Bool
        init(_ muscle: String, _ side: Side, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, ellipse: Bool = false) {
            self.id = "\(muscle)-\(side == .front ? "f" : "b")-\(x)-\(y)"
            self.muscle = muscle; self.side = side
            self.x = x; self.y = y; self.w = w; self.h = h; self.ellipse = ellipse
        }
    }

    static let regions: [Region] = [
        // Front
        .init("neck", .front, 0.45, 0.123, 0.10, 0.034),
        .init("shoulders", .front, 0.17, 0.168, 0.22, 0.082, ellipse: true),
        .init("shoulders", .front, 0.61, 0.168, 0.22, 0.082, ellipse: true),
        .init("chest", .front, 0.34, 0.227, 0.32, 0.118),
        .init("biceps", .front, 0.12, 0.227, 0.14, 0.127, ellipse: true),
        .init("biceps", .front, 0.74, 0.227, 0.14, 0.127, ellipse: true),
        .init("abdominals", .front, 0.39, 0.360, 0.22, 0.120),
        .init("forearms", .front, 0.10, 0.366, 0.12, 0.118, ellipse: true),
        .init("forearms", .front, 0.78, 0.366, 0.12, 0.118, ellipse: true),
        .init("adductors", .front, 0.47, 0.520, 0.06, 0.150),
        .init("quadriceps", .front, 0.37, 0.515, 0.09, 0.175),
        .init("quadriceps", .front, 0.54, 0.515, 0.09, 0.175),
        // Back
        .init("traps", .back, 0.36, 0.150, 0.28, 0.058),
        .init("middle back", .back, 0.41, 0.210, 0.18, 0.070),
        .init("triceps", .back, 0.12, 0.232, 0.14, 0.136, ellipse: true),
        .init("triceps", .back, 0.74, 0.232, 0.14, 0.136, ellipse: true),
        .init("lats", .back, 0.30, 0.282, 0.16, 0.110),
        .init("lats", .back, 0.54, 0.282, 0.16, 0.110),
        .init("lower back", .back, 0.40, 0.395, 0.20, 0.085),
        .init("abductors", .back, 0.31, 0.505, 0.06, 0.090),
        .init("abductors", .back, 0.63, 0.505, 0.06, 0.090),
        .init("glutes", .back, 0.39, 0.500, 0.22, 0.095),
        .init("hamstrings", .back, 0.38, 0.610, 0.09, 0.150),
        .init("hamstrings", .back, 0.53, 0.610, 0.09, 0.150),
        .init("calves", .back, 0.40, 0.795, 0.07, 0.115),
        .init("calves", .back, 0.53, 0.795, 0.07, 0.115),
    ]

    /// Spanish-by-catalog display name (English source key, es lives in Localizable.xcstrings).
    static func name(_ muscle: String) -> LocalizedStringKey {
        switch muscle {
        case "abdominals": return "Abs"
        case "abductors": return "Abductors"
        case "adductors": return "Adductors"
        case "biceps": return "Biceps"
        case "calves": return "Calves"
        case "chest": return "Chest"
        case "forearms": return "Forearms"
        case "glutes": return "Glutes"
        case "hamstrings": return "Hamstrings"
        case "lats": return "Lats"
        case "lower back": return "Lower back"
        case "middle back": return "Mid back"
        case "neck": return "Neck"
        case "quadriceps": return "Quads"
        case "shoulders": return "Shoulders"
        case "traps": return "Traps"
        case "triceps": return "Triceps"
        default: return LocalizedStringKey(muscle)
        }
    }
}

// MARK: - Shapes

/// One muscle region (ellipse or rounded rect) drawn in its normalized slot of the figure box.
struct RegionShape: Shape {
    let region: MuscleAtlas.Region
    func path(in rect: CGRect) -> Path {
        let f = CGRect(x: rect.minX + region.x * rect.width,
                       y: rect.minY + region.y * rect.height,
                       width: region.w * rect.width,
                       height: region.h * rect.height)
        var p = Path()
        if region.ellipse {
            p.addEllipse(in: f)
        } else {
            p.addRoundedRect(in: f, cornerSize: CGSize(width: f.width * 0.4, height: f.width * 0.4))
        }
        return p
    }
}

/// A schematic humanoid outline (same front/back), stroked in hairline behind the muscle regions.
struct BodyOutlineShape: Shape {
    let side: MuscleAtlas.Side
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var p = Path()
        // Head
        p.addEllipse(in: CGRect(x: rect.minX + 0.39 * rect.width, y: rect.minY + 0.015 * rect.height,
                                width: 0.22 * rect.width, height: 0.12 * rect.height))
        // Body outline (clockwise from the left neck)
        let outline: [(CGFloat, CGFloat)] = [
            (0.42, 0.13), (0.20, 0.19), (0.13, 0.22), (0.10, 0.42), (0.09, 0.52), (0.16, 0.52),
            (0.30, 0.30), (0.33, 0.46), (0.30, 0.52), (0.34, 0.74), (0.36, 0.95), (0.46, 0.95),
            (0.50, 0.55), (0.54, 0.95), (0.64, 0.95), (0.66, 0.74), (0.70, 0.52), (0.67, 0.46),
            (0.70, 0.30), (0.84, 0.52), (0.91, 0.52), (0.90, 0.42), (0.87, 0.22), (0.80, 0.19),
            (0.58, 0.13),
        ]
        p.move(to: pt(outline[0].0, outline[0].1))
        for q in outline.dropFirst() { p.addLine(to: pt(q.0, q.1)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - Anatomical figure (FER-350 redesign · #7)
//
// The redesigned muscle map (`MuscleMapScreen`) draws DETAILED anatomical silhouettes instead of the
// schematic `RegionShape` ellipses/rects (which the exercise-detail figure still uses). The shapes are
// authored as SVG path data over a fixed 160×340 viewBox — front and back, plus a shared base body
// (torso / arms / legs / head) drawn in hairline behind the tinted muscle groups. Each muscle path keeps
// the catalog muscle key (`MuscleFatigueMap` / `MuscleAtlas.name`) so the same load tint and tap target
// apply. No math, no assets, no network — just `Shape`s derived from the atlas, like the rest of the map.

/// One tintable muscle group on the anatomical figure: its catalog muscle key + SVG path data.
struct AnatomyPath: Identifiable {
    let id: Int
    let muscle: String
    let d: String
}

enum MuscleAnatomy {
    /// The figure's coordinate space (matches the authored SVG viewBox).
    static let viewBox = CGSize(width: 160, height: 340)

    /// The shared body silhouette (neck, torso, arms, legs) — same on front and back. The head is a
    /// separate ellipse drawn by `AnatomyBaseShape`.
    static let baseBody: [String] = [
        "M72,42 L88,42 L89,55 L71,55 Z",
        "M62,52 C58,52 54,54 52,58 L46,62 C44,72 44,86 46,100 C48,120 50,135 52,150 L58,172 L102,172 L108,150 C110,135 112,120 114,100 C116,86 116,72 114,62 L108,58 C106,54 102,52 98,52 Z",
        "M48,60 C40,62 34,69 31,82 C28,98 26,116 26,136 C26,154 26,172 28,186 C29,192 33,193 35,188 C37,170 39,152 42,134 C44,114 46,94 47,80 C48,71 48,65 48,60 Z",
        "M112,60 C120,62 126,69 129,82 C132,98 134,116 134,136 C134,154 134,172 132,186 C131,192 127,193 125,188 C123,170 121,152 118,134 C116,114 114,94 113,80 C112,71 112,65 112,60 Z",
        "M58,170 C54,200 52,235 54,265 C55,290 58,315 62,328 C64,333 70,333 71,328 C73,300 73,265 74,235 L76,172 Z",
        "M102,170 C106,200 108,235 106,265 C105,290 102,315 98,328 C96,333 90,333 89,328 C87,300 87,265 86,235 L84,172 Z",
    ]

    /// Front muscle groups. Obliques have no catalog muscle of their own, so they ride `abdominals`.
    static let front: [AnatomyPath] = build([
        ("traps", "M70,52 C62,53 55,56 50,61 C56,62 64,60 70,57 Z"),
        ("traps", "M90,52 C98,53 105,56 110,61 C104,62 96,60 90,57 Z"),
        ("shoulders", "M50,60 C41,62 35,70 33,82 C32,89 38,92 44,88 C49,84 51,71 52,61 Z"),
        ("shoulders", "M110,60 C119,62 125,70 127,82 C128,89 122,92 116,88 C111,84 109,71 108,61 Z"),
        ("chest", "M78,58 L78,92 C68,93 58,89 54,79 C51,70 56,61 67,58 C71,57 75,57 78,58 Z"),
        ("chest", "M82,58 L82,92 C92,93 102,89 106,79 C109,70 104,61 93,58 C89,57 85,57 82,58 Z"),
        ("biceps", "M31,88 C29,98 29,112 31,122 C33,128 45,128 47,120 C48,108 47,96 45,87 C42,83 34,83 31,88 Z"),
        ("biceps", "M129,88 C131,98 131,112 129,122 C127,128 115,128 113,120 C112,108 113,96 115,87 C118,83 126,83 129,88 Z"),
        ("forearms", "M29,126 C27,140 27,160 29,180 C30,187 41,187 43,180 C44,160 44,142 45,128 C40,124 33,124 29,126 Z"),
        ("forearms", "M131,126 C133,140 133,160 131,180 C130,187 119,187 117,180 C116,160 116,142 115,128 C120,124 127,124 131,126 Z"),
        ("abdominals", "M71,92 C71,91 89,91 89,92 L89,142 C89,147 71,147 71,142 Z"),
        ("abdominals", "M70,96 C64,99 60,110 61,124 C62,134 67,138 70,132 Z"),
        ("abdominals", "M90,96 C96,99 100,110 99,124 C98,134 93,138 90,132 Z"),
        ("quadriceps", "M68,150 C58,153 53,166 54,184 C55,204 60,222 68,230 C72,232 75,226 75,214 L75,160 C74,152 72,149 68,150 Z"),
        ("quadriceps", "M92,150 C102,153 107,166 106,184 C105,204 100,222 92,230 C88,232 85,226 85,214 L85,160 C86,152 88,149 92,150 Z"),
        ("adductors", "M76,152 L76,210 C71,207 68,194 68,180 C68,166 71,156 76,152 Z"),
        ("adductors", "M84,152 L84,210 C89,207 92,194 92,180 C92,166 89,156 84,152 Z"),
    ])

    /// Back muscle groups.
    static let back: [AnatomyPath] = build([
        ("traps", "M80,50 C70,52 61,57 56,63 C63,69 71,72 80,73 C89,72 97,69 104,63 C99,57 90,52 80,50 Z"),
        ("traps", "M80,74 C73,74 66,72 60,68 C64,82 71,92 80,97 C89,92 96,82 100,68 C94,72 87,74 80,74 Z"),
        ("shoulders", "M50,60 C41,62 35,70 33,82 C32,89 38,92 44,88 C49,84 51,71 52,61 Z"),
        ("shoulders", "M110,60 C119,62 125,70 127,82 C128,89 122,92 116,88 C111,84 109,71 108,61 Z"),
        ("triceps", "M31,88 C29,98 29,114 31,124 C33,130 45,130 47,122 C48,109 47,96 45,87 C42,83 34,83 31,88 Z"),
        ("triceps", "M129,88 C131,98 131,114 129,124 C127,130 115,130 113,122 C112,109 113,96 115,87 C118,83 126,83 129,88 Z"),
        ("forearms", "M29,126 C27,140 27,160 29,180 C30,187 41,187 43,180 C44,160 44,142 45,128 C40,124 33,124 29,126 Z"),
        ("forearms", "M131,126 C133,140 133,160 131,180 C130,187 119,187 117,180 C116,160 116,142 115,128 C120,124 127,124 131,126 Z"),
        ("lats", "M56,66 C48,72 44,86 46,104 C47,114 56,116 64,108 C68,101 67,84 64,72 C62,67 59,64 56,66 Z"),
        ("lats", "M104,66 C112,72 116,86 114,104 C113,114 104,116 96,108 C92,101 93,84 96,72 C98,67 101,64 104,66 Z"),
        ("lower back", "M73,108 C70,116 69,130 71,144 C73,152 77,154 80,154 C83,154 87,152 89,144 C91,130 90,116 87,108 C84,113 76,113 73,108 Z"),
        ("glutes", "M79,150 C69,150 62,159 63,172 C64,185 72,190 79,187 Z"),
        ("glutes", "M81,150 C91,150 98,159 97,172 C96,185 88,190 81,187 Z"),
        ("hamstrings", "M68,190 C59,193 55,208 57,228 C58,242 64,248 71,240 C74,232 74,206 73,192 C72,189 70,189 68,190 Z"),
        ("hamstrings", "M92,190 C101,193 105,208 103,228 C102,242 96,248 89,240 C86,232 86,206 87,192 C88,189 90,189 92,190 Z"),
        ("calves", "M67,246 C61,250 59,266 61,282 C62,292 68,294 72,286 C75,274 74,256 71,248 C70,245 68,245 67,246 Z"),
        ("calves", "M93,246 C99,250 101,266 99,282 C98,292 92,294 88,286 C85,274 86,256 89,248 C90,245 92,245 93,246 Z"),
    ])

    static func paths(for side: MuscleAtlas.Side) -> [AnatomyPath] {
        side == .front ? front : back
    }

    private static func build(_ rows: [(String, String)]) -> [AnatomyPath] {
        rows.enumerated().map { AnatomyPath(id: $0.offset, muscle: $0.element.0, d: $0.element.1) }
    }
}

// MARK: - SVG path → Shape

/// A minimal absolute-only SVG path (`M`/`L`/`C`/`Z`) rendered into a rect, mapped from the
/// `MuscleAnatomy.viewBox` coordinate space. Enough to draw the authored anatomical figure — not a
/// general SVG engine.
struct SVGPath: Shape {
    private enum Seg { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close }
    private let segs: [Seg]
    private let viewBox: CGSize

    init(_ d: String, viewBox: CGSize = MuscleAnatomy.viewBox) {
        self.segs = SVGPath.parse(d)
        self.viewBox = viewBox
    }

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / viewBox.width, sy = rect.height / viewBox.height
        func m(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * sx, y: rect.minY + p.y * sy) }
        var path = Path()
        for s in segs {
            switch s {
            case .move(let p): path.move(to: m(p))
            case .line(let p): path.addLine(to: m(p))
            case .curve(let a, let b, let e): path.addCurve(to: m(e), control1: m(a), control2: m(b))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private static func parse(_ d: String) -> [Seg] {
        var segs: [Seg] = []
        let chars = Array(d)
        var idx = 0
        var cmd: Character = " "

        func readNumber() -> CGFloat? {
            while idx < chars.count, chars[idx] == " " || chars[idx] == "," || chars[idx] == "\n" || chars[idx] == "\t" {
                idx += 1
            }
            var s = ""
            while idx < chars.count {
                let c = chars[idx]
                if c.isNumber || c == "." {
                    s.append(c); idx += 1
                } else if c == "-" || c == "+" {
                    if s.isEmpty || s.last == "e" || s.last == "E" { s.append(c); idx += 1 } else { break }
                } else if c == "e" || c == "E" {
                    s.append(c); idx += 1
                } else { break }
            }
            return s.isEmpty ? nil : CGFloat(Double(s) ?? 0)
        }
        func point() -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return CGPoint(x: x, y: y)
        }

        while idx < chars.count {
            let c = chars[idx]
            if c.isLetter { cmd = c; idx += 1 }
            switch cmd {
            case "M":
                if let p = point() { segs.append(.move(p)); cmd = "L" } else { idx += 1 }
            case "L":
                if let p = point() { segs.append(.line(p)) } else { idx += 1 }
            case "C":
                if let a = point(), let b = point(), let e = point() { segs.append(.curve(a, b, e)) } else { idx += 1 }
            case "Z", "z":
                segs.append(.close)
            default:
                idx += 1
            }
        }
        return segs
    }
}

/// The shared base silhouette (head ellipse + `MuscleAnatomy.baseBody`), stroked/filled in hairline
/// behind the tinted muscle groups.
struct AnatomyBaseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let vb = MuscleAnatomy.viewBox
        let sx = rect.width / vb.width, sy = rect.height / vb.height
        var p = Path()
        // Head — ellipse cx 80, cy 28, rx 14, ry 17.
        p.addEllipse(in: CGRect(x: rect.minX + (80 - 14) * sx, y: rect.minY + (28 - 17) * sy,
                                width: 28 * sx, height: 34 * sy))
        for d in MuscleAnatomy.baseBody {
            p.addPath(SVGPath(d).path(in: rect))
        }
        return p
    }
}
#endif
