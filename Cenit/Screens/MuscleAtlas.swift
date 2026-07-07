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

// MARK: - Anatomical figure (FER-350 redesign · #7 · body FER-781)
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
    /// The figure's coordinate space (matches the owner-approved SVG viewBox, FER-781).
    static let viewBox = CGSize(width: 200, height: 430)

    /// The shared body silhouette contour (neck → torso → arms → legs), same on front and back, stroked
    /// in hairline behind the tinted muscle groups. The head is a separate ellipse drawn by
    /// `AnatomyBaseShape`. A single closed contour (owner-approved body, FER-781).
    static let baseBody: [String] = [
        """
        M91,48 C90,53 88,57 82,60 C68,64 58,70 52,80 C46,92 45,108 48,124 \
        L40,128 C33,148 30,176 30,200 C30,214 32,214 35,206 C39,186 43,168 48,152 \
        C49,168 49,186 50,206 C50,250 52,300 56,352 C58,384 62,410 68,420 \
        C72,426 80,426 82,418 C86,392 87,352 90,308 C92,282 96,270 100,270 \
        C104,270 108,282 110,308 C113,352 114,392 118,418 C120,426 128,426 132,420 \
        C138,410 142,384 144,352 C148,300 150,250 150,206 C151,186 151,168 152,152 \
        C157,168 161,186 165,206 C168,214 170,214 170,200 C170,176 167,148 160,128 \
        L152,124 C155,108 154,92 148,80 C142,70 132,64 118,60 C112,57 110,53 109,48 Z
        """,
    ]

    /// Front muscle groups. Obliques have no catalog muscle of their own, so they ride `abdominals`.
    static let front: [AnatomyPath] = build([
        ("neck", "M92,49 L108,49 C107,54 104,58 100,59 C96,58 93,54 92,49 Z"),
        ("shoulders", "M83,61 C71,64 62,71 57,81 C54,88 61,94 69,89 C76,84 80,73 84,63 Z"),
        ("shoulders", "M117,61 C129,64 138,71 143,81 C146,88 139,94 131,89 C124,84 120,73 116,63 Z"),
        ("chest", "M98,66 L98,104 C82,106 66,100 61,86 C58,74 66,64 82,63 C89,63 94,64 98,66 Z"),
        ("chest", "M102,66 L102,104 C118,106 134,100 139,86 C142,74 134,64 118,63 C111,63 106,64 102,66 Z"),
        ("biceps", "M48,90 C45,104 45,124 48,140 C51,150 66,150 68,138 C69,120 68,102 64,89 C59,84 52,84 48,90 Z"),
        ("biceps", "M152,90 C155,104 155,124 152,140 C149,150 134,150 132,138 C131,120 132,102 136,89 C141,84 148,84 152,90 Z"),
        ("forearms", "M44,146 C41,166 41,192 44,214 C46,224 60,224 61,212 C62,190 62,168 65,148 C58,142 49,142 44,146 Z"),
        ("forearms", "M156,146 C159,166 159,192 156,214 C154,224 140,224 139,212 C138,190 138,168 135,148 C142,142 151,142 156,146 Z"),
        ("abdominals", "M89,106 L111,106 L111,176 C111,182 89,182 89,176 Z"),
        ("abdominals", "M88,112 C79,116 73,132 74,152 C75,166 82,170 88,162 Z"),
        ("abdominals", "M112,112 C121,116 127,132 126,152 C125,166 118,170 112,162 Z"),
        ("quadriceps", "M84,190 C69,194 62,214 63,240 C64,272 71,300 84,312 C90,316 95,306 95,288 L95,204 C94,193 90,189 84,190 Z"),
        ("quadriceps", "M116,190 C131,194 138,214 137,240 C136,272 129,300 116,312 C110,316 105,306 105,288 L105,204 C106,193 110,189 116,190 Z"),
        ("adductors", "M97,194 L97,286 C89,282 84,262 84,238 C84,214 89,199 97,194 Z"),
        ("adductors", "M103,194 L103,286 C111,282 116,262 116,238 C116,214 111,199 103,194 Z"),
    ])

    /// Back muscle groups.
    static let back: [AnatomyPath] = build([
        ("traps", "M100,50 C86,52 74,58 66,66 C76,74 88,78 100,79 C112,78 124,74 134,66 C126,58 114,52 100,50 Z"),
        ("traps", "M100,80 C90,80 80,77 71,71 C77,90 88,104 100,110 C112,104 123,90 129,71 C120,77 110,80 100,80 Z"),
        ("shoulders", "M83,61 C71,64 62,71 57,81 C54,88 61,94 69,89 C76,84 80,73 84,63 Z"),
        ("shoulders", "M117,61 C129,64 138,71 143,81 C146,88 139,94 131,89 C124,84 120,73 116,63 Z"),
        ("triceps", "M48,90 C45,104 45,126 48,142 C51,152 66,152 68,140 C69,122 68,102 64,89 C59,84 52,84 48,90 Z"),
        ("triceps", "M152,90 C155,104 155,126 152,142 C149,152 134,152 132,140 C131,122 132,102 136,89 C141,84 148,84 152,90 Z"),
        ("forearms", "M44,148 C41,168 41,192 44,214 C46,224 60,224 61,212 C62,190 62,170 65,150 C58,144 49,144 44,148 Z"),
        ("forearms", "M156,148 C159,168 159,192 156,214 C154,224 140,224 139,212 C138,190 138,170 135,150 C142,144 151,144 156,148 Z"),
        ("lats", "M84,84 C71,92 65,112 68,138 C70,152 84,156 94,144 C99,134 98,108 94,90 C91,83 87,82 84,84 Z"),
        ("lats", "M116,84 C129,92 135,112 132,138 C130,152 116,156 106,144 C101,134 102,108 106,90 C109,83 113,82 116,84 Z"),
        ("middle back", "M96,112 L104,112 L104,150 C104,156 96,156 96,150 Z"),
        ("lower back", "M91,156 C87,166 85,182 88,198 C90,208 95,210 100,210 C105,210 110,208 112,198 C115,182 113,166 109,156 C104,162 96,162 91,156 Z"),
        ("glutes", "M98,206 C84,206 74,218 75,236 C76,254 88,262 98,256 Z"),
        ("glutes", "M102,206 C116,206 126,218 125,236 C124,254 112,262 102,256 Z"),
        ("abductors", "M76,212 C68,216 65,228 67,242 C69,252 78,252 80,242 C81,232 80,222 79,214 Z"),
        ("abductors", "M124,212 C132,216 135,228 133,242 C131,252 122,252 120,242 C119,232 120,222 121,214 Z"),
        ("hamstrings", "M84,258 C71,262 65,284 68,312 C70,332 79,340 89,328 C93,316 93,278 92,260 C90,256 87,256 84,258 Z"),
        ("hamstrings", "M116,258 C129,262 135,284 132,312 C130,332 121,340 111,328 C107,316 107,278 108,260 C110,256 113,256 116,258 Z"),
        ("calves", "M83,336 C74,341 71,362 74,384 C76,398 85,400 91,388 C95,372 93,348 89,338 C87,334 85,334 83,336 Z"),
        ("calves", "M117,336 C126,341 129,362 126,384 C124,398 115,400 109,388 C105,372 107,348 111,338 C113,334 115,334 117,336 Z"),
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
        // Head — ellipse cx 100, cy 26, rx 19, ry 23 (owner-approved body, FER-781).
        p.addEllipse(in: CGRect(x: rect.minX + (100 - 19) * sx, y: rect.minY + (26 - 23) * sy,
                                width: 38 * sx, height: 46 * sy))
        for d in MuscleAnatomy.baseBody {
            p.addPath(SVGPath(d).path(in: rect))
        }
        return p
    }
}
#endif
