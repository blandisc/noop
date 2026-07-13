import SwiftUI
import StrandDesign
import StrandTraining

extension RoutineRegion {
    /// Color de identidad de la rutina por región. Fuente única (FER-898).
    func tint(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .push:            return theme.dataStrain
        case .pull:            return theme.dataHrv
        case .legs, .fullBody: return theme.dataSleep
        }
    }
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
    .background(t.paper)
}
#endif
