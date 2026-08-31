import SwiftUI
import StrandDesign
import StrandTraining

extension RoutineRegion {
    /// La familia de diseño que corresponde a esta región. El paquete de diseño no puede importar
    /// StrandTraining, así que el puente vive aquí, del lado de la app.
    var family: EntrenarFamily {
        switch self {
        case .push:     return .push
        case .pull:     return .pull
        case .legs:     return .legs
        case .fullBody: return .fullBody
        }
    }

    /// Color de identidad de la rutina por región. DELEGA en `EntrenarFamily.tint` (FER-88): había
    /// tres tablas del mismo color y una ya se había ido por su lado. Una identidad, una fuente.
    func tint(_ theme: InstrumentoTheme) -> Color { family.tint(theme) }
}

extension Optional where Wrapped == RoutineRegion {
    /// nil (sin ejercicios clasificables) cae a dataStrain — preserva el render actual.
    func tint(_ theme: InstrumentoTheme) -> Color {
        self?.tint(theme) ?? theme.dataStrain
    }
}

#if DEBUG
#Preview("RoutineRegion tint") {
    let t = InstrumentoTheme.base
    HStack(spacing: 16) {
        VStack(spacing: 8) {
            Circle().fill(RoutineRegion.push.tint(t)).frame(width: 24, height: 24)
            Text("push").font(StrandFont.caption).foregroundStyle(t.inkTertiary)
        }
        VStack(spacing: 8) {
            Circle().fill(RoutineRegion.pull.tint(t)).frame(width: 24, height: 24)
            Text("pull").font(StrandFont.caption).foregroundStyle(t.inkTertiary)
        }
        VStack(spacing: 8) {
            Circle().fill(RoutineRegion.legs.tint(t)).frame(width: 24, height: 24)
            Text("legs").font(StrandFont.caption).foregroundStyle(t.inkTertiary)
        }
        VStack(spacing: 8) {
            Circle().fill(RoutineRegion.fullBody.tint(t)).frame(width: 24, height: 24)
            Text("fullBody").font(StrandFont.caption).foregroundStyle(t.inkTertiary)
        }
        VStack(spacing: 8) {
            Circle().fill((nil as RoutineRegion?).tint(t)).frame(width: 24, height: 24)
            Text("nil").font(StrandFont.caption).foregroundStyle(t.inkTertiary)
        }
    }
    .padding(20)
    .background(CenitColor.pantalla)
}
#endif
