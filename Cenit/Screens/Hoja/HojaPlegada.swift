#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaPlegada — la receta de una línea + «＋ Agregar ejercicio» (FER-166)
//
// Mock `hoja-pantallas.html` P1 `.mod.plegada` («Prensa inclinada» → «3 × 10 · 145 kg») y
// `.agregar` («＋ Agregar ejercicio», troquel punteado). Tocar una plegada la abre (single-open
// accordion, ver `RoutineSheet.openID`) y pliega la que estaba abierta. A3 (pirámide sin
// castigo): cuando las series de trabajo no son iguales, la receta se lee «N recetas ›» — el dato
// honesto (no finge una sola línea), sin el aviso inline de antes (esa acción se mudó a «···»,
// `RoutineSheetLogic.exerciseMenuItems`).

enum HojaPlegada {

    static func row(sheet: RoutineSheet, idx: Int) -> some View {
        let item = sheet.items[idx]
        let equal = sheet.setsAreEqual(idx)
        let receta = equal ? sheet.recetaSummary(idx) : String(localized: "\(sheet.recetaCount(idx)) recipes")
        return Button {
            // R7: cambiar de tarjeta abierta corta cualquier edición a medias en la anterior.
            sheet.activeCell = nil
            withAnimation(.snappy) { sheet.openID = item.id }
        } label: {
            EntrenarModulo(tono: .neutro) {
                HStack(spacing: LiquidSpace.s300) {
                    Text(StrengthDisplay.name(item.exercise))
                        .font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                        .lineLimit(1)
                    Spacer(minLength: LiquidSpace.s200)
                    HStack(spacing: LiquidSpace.s050) {
                        Text(receta)
                        if !equal { Text(verbatim: "›") }
                    }
                    // R11 (QA D7): `relativeTo` — cero fuentes fixedSize en texto de lectura.
                    .font(LiquidType.caption.weight(.bold))
                    .foregroundStyle(equal ? LiquidColor.tinta900 : LiquidColor.tinta700)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(StrengthDisplay.name(item.exercise)), \(receta)"))
        .accessibilityHint(Text("Opens the exercise"))
    }

    /// «＋ Agregar ejercicio» — troquel punteado centrado (mock `.agregar`). La Hoja es vidrio
    /// independiente (sin hilo/dot de riel de «recibo»), así que el control se arma a mano aquí.
    static func addExercise(sheet: RoutineSheet) -> some View {
        Button {
            sheet.replaceIndex = nil
            sheet.showLibrary = true
        } label: {
            HStack(spacing: LiquidSpace.s200) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))  // token-exempt: glifo del troquel
                Text("Add exercise").font(LiquidType.cuerpoBanner.weight(.semibold))
            }
            .foregroundStyle(LiquidColor.tinta700)
            .frame(maxWidth: .infinity, minHeight: HojaMetrics.hitMin)
            .contentShape(RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous)
                    .strokeBorder(LiquidColor.ambar.opacity(StrandOpacity.strokeSoft),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
        }
        .buttonStyle(.liquidPress)
        .accessibilityLabel(Text("Add exercise"))
    }
}
#endif
