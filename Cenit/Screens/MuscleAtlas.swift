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
#endif
