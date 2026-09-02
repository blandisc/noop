#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Entrenar · CUERPO del hub v18 (FER-171 · Parte B)
//
// «Tu cuerpo»: un pictograma humano sencillo (tinta 700) con un punto ámbar en la zona aproximada
// del músculo más cargado, la frase «{músculo} · carga alta · el resto, fresco» y la puerta «MAPA ›»
// hacia el mapa muscular completo (que se mudó de Tendencias). Sustituye a `muscleSection`/
// `muscleSectionModulo`: MISMOS datos (`MuscleFatigueMap.loads` vía `muscleEvents`), nueva piel.
//
// Copy sin género (regla del repo): el mock dice «cargada», flexionado al femenino de «espalda» —
// no concuerda con «pecho», «hombros» (masculinos). En vez de una tabla de género por músculo, la
// frase evita el adjetivo flexionado, mismo criterio que ya usa `EntrenarLanding.muscleLine`.

struct EntrenarHubCuerpo: View {
    let topMuscleName: Text
    /// La zona aproximada del músculo más cargado, para posicionar el punto (catalog muscle key).
    let topMuscleKey: String
    let onOpenMap: () -> Void

    /// Ronda 2 · D2: `cuerpoLinea` era `Font.system(size:)` fijo — texto de LECTURA sin escalar.
    @ScaledMetric(relativeTo: .caption2) private var cuerpoLineaSize = EntrenarHubMetrics.cuerpoLineaBase

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            HStack(spacing: EntrenarHubMetrics.cuerpoGap) {
                pictogram
                (topMuscleName.fontWeight(.semibold).foregroundStyle(LiquidColor.tinta900)
                 + Text(verbatim: " ")
                 + Text("high load").foregroundStyle(LiquidColor.tinta700)
                 + Text(verbatim: " · ").foregroundStyle(LiquidColor.tinta700)
                 + Text("the rest, fresh").foregroundStyle(LiquidColor.tinta700))
                    .font(.system(size: cuerpoLineaSize))
                    .lineLimit(2)
                Spacer(minLength: LiquidSpace.s100)
                EntrenarCapsulaPuerta(String(localized: "Body map").uppercased(), action: onOpenMap)
            }
        }
        .liquidEntrada(index: 4)
    }

    private var pictogram: some View {
        let size = EntrenarHubMetrics.cuerpoPictogramSize
        return Canvas { context, _ in
            let ink = GraphicsContext.Shading.color(LiquidColor.tinta700)
            // Cabeza.
            context.fill(Path(ellipseIn: CGRect(x: 5.2, y: 0.3, width: 4.6, height: 4.6)), with: ink)
            // Torso.
            let torso = Path(roundedRect: CGRect(x: 5.1, y: 5.6, width: 4.8, height: 7.7), cornerRadius: 2.4) // token-exempt: geometría del pictograma (mock SVG 15×23), no un radio del sistema
            context.fill(torso, with: ink)
            // Brazos + piernas.
            var limbs = Path()
            limbs.move(to: CGPoint(x: 4.6, y: 7.2)); limbs.addLine(to: CGPoint(x: 2.3, y: 12.1))
            limbs.move(to: CGPoint(x: 10.4, y: 7.2)); limbs.addLine(to: CGPoint(x: 12.7, y: 12.1))
            limbs.move(to: CGPoint(x: 6.1, y: 13.8)); limbs.addLine(to: CGPoint(x: 4.9, y: 20.5))
            limbs.move(to: CGPoint(x: 8.9, y: 13.8)); limbs.addLine(to: CGPoint(x: 10.1, y: 20.5))
            context.stroke(limbs, with: ink, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
            // El punto de carga, en la zona del músculo más cargado.
            let dot = Self.zonePoint(for: topMuscleKey)
            let dotRect = CGRect(x: dot.x - 2.2, y: dot.y - 2.2, width: 4.4, height: 4.4)
            context.fill(Path(ellipseIn: dotRect), with: .color(LiquidColor.ambar))
            context.stroke(Path(ellipseIn: dotRect), with: .color(LiquidColor.fondoAlto), lineWidth: 1.1)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// Mapa zona→punto aproximado sobre el pictograma 15×23 (hombros/pecho arriba, espalda media,
    /// espalda baja/core centro, pierna abajo) — geometría de dato, no un token reusable en otro
    /// sitio. token-exempt: coordenadas de un dibujo hecho a mano, no una medida del sistema.
    private static func zonePoint(for muscle: String) -> CGPoint {
        switch muscle {
        case "shoulders", "chest", "neck", "traps":
            return CGPoint(x: 7.5, y: 6.2)
        case "lats", "middle back", "biceps", "triceps", "forearms":
            return CGPoint(x: 7.5, y: 9)
        case "abdominals", "lower back":
            return CGPoint(x: 7.5, y: 12)
        default:   // quadriceps, hamstrings, calves, glutes, adductors, abductors
            return CGPoint(x: 7.5, y: 17)
        }
    }
}
#endif
