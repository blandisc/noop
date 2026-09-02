import SwiftUI

// MARK: - LiquidRampas (FER-317)
//
// Rampas de DATO que las pantallas leían de `InstrumentoTheme.base`. Viven aquí para que
// `Cenit/` / `CenitApp/` no escriban el símbolo `InstrumentoTheme` (no-legacy-api). Dentro del
// paquete se delega a `.base` — misma geometría, cero cambio visual.

/// Rampas de dato (zonas HR, fatiga muscular, familia de movimiento) sin exponer `InstrumentoTheme`.
public enum LiquidRampas {

    /// Stop `index` (0…4) de la rampa cálida de zonas HR. Misma geometría que `InstrumentoTheme.base.hrZoneRamp`.
    public static func hrZone(_ index: Int) -> Color {
        InstrumentoTheme.base.hrZoneRamp[index]
    }

    /// Color 0…1 en la rampa fresh→loaded de fatiga muscular. Misma interpolación OKLab que `muscleLoadColor`.
    public static func muscleLoad(_ fraction: Double) -> Color {
        InstrumentoTheme.base.muscleLoadColor(fraction)
    }

    /// Tinte de familia de movimiento (empuje/jalón/pierna) a partir de músculos primarios.
    public static func movementFamilyTint(_ primaryMuscles: [String]) -> Color {
        InstrumentoTheme.base.movementFamilyTint(primaryMuscles: primaryMuscles)
    }
}

#if DEBUG
#Preview("LiquidRampas") {
    VStack(alignment: .leading, spacing: LiquidSpace.s300) {
        HStack(spacing: LiquidSpace.s100) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(LiquidRampas.hrZone(i)).frame(width: 28, height: 16)
            }
        }
        HStack(spacing: LiquidSpace.s100) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle().fill(LiquidRampas.muscleLoad(Double(i) / 4)).frame(width: 28, height: 16)
            }
        }
        HStack(spacing: LiquidSpace.s200) {
            Circle().fill(LiquidRampas.movementFamilyTint(["chest"])).frame(width: 18, height: 18)
            Circle().fill(LiquidRampas.movementFamilyTint(["lats"])).frame(width: 18, height: 18)
            Circle().fill(LiquidRampas.movementFamilyTint(["quadriceps"])).frame(width: 18, height: 18)
        }
    }
    .padding(LiquidSpace.tarjetaAmplia)
    .background(LiquidColor.fondoAlto)
}
#endif
