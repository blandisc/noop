#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining

// MARK: - HojaCabecera — cabecera + título + CTA de «La Hoja» (FER-166)
//
// Mock `hoja-pantallas.html` P1/P2: `.headE` (kick + ✕) · `.titulo` (nombre editable + ✎) ·
// `.metaLn` (dot de familia + conteos) · `.ctaV` («Empezar»). Funciones estáticas (no un
// `View` propio): no llevan estado — leen/mutan el de `RoutineSheet` vía `sheet` (el `nonmutating
// set` de `@State` deja escribir sobre una copia por valor, mismo patrón que las closures de
// `body`).

enum HojaCabecera {

    /// Fila superior: ✕ (cierra) + Deshacer/Guardado.
    static func header(sheet: RoutineSheet) -> some View {
        HStack(spacing: LiquidSpace.s200) {
            BackButton(role: .close, theme: sheet.theme) { sheet.back() }
                .padding(.leading, -2)
            Spacer()
            // N4 (ronda 3): `undo()` ya corta bajo candado (R1) — el botón tampoco se ofrece, para
            // no dejar un control que toca y no hace nada.
            if sheet.dirty, !sheet.locked {
                Button { sheet.undo() } label: {
                    Text(String(localized: "Undo")).font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta900)
                        .frame(minHeight: LiquidControl.hitTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Undo")))
            } else if sheet.loaded {
                Text(String(localized: "Saved"))
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
        .padding(.horizontal, LiquidSpace.s600)
    }

    /// Overline por origen, el nombre EDITABLE (TextField, ✎ decorativo al lado) y la meta punteada.
    static func titleBlock(sheet: RoutineSheet) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            HStack(alignment: .firstTextBaseline) {
                Text(sheet.overline).liquidKicker().foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: LiquidSpace.s200)
                if sheet.isPlanDay { dayMenu(sheet: sheet) }
            }
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
                TextField("Routine name", text: Binding(
                    get: { sheet.routine?.name ?? "" },
                    set: { sheet.routine?.name = $0; sheet.dirty = true }
                ))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(sheet.items.isEmpty ? LiquidColor.tinta500 : LiquidColor.tinta900)
                .disabled(sheet.locked)
                // ✎ decorativo (mock «.lapiz»): el campo ya se edita tocándolo; el glifo solo lo anuncia.
                Text(verbatim: "✎").font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            if sheet.locked {
                Text("Session in progress · finish it to edit")
                    .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    .padding(.top, LiquidSpace.s050)
            }
            // R13 (QA D11, mapa A1): la meta calla con MENOS de 2 ejercicios — un solo ejercicio
            // recién agregado no tiene nada útil que resumir todavía («1 ejercicio · 3 series ·
            // ~2 min» no ayuda a nadie).
            if sheet.items.count >= 2 { metaLine(sheet: sheet) }
        }
    }

    /// El dot de familia + «{grupo} · N ejercicios · M series · ~T min · ~T,TTT kg» (R15: el
    /// tonelaje se omite cuando ningún ejercicio tiene peso — nunca un «~0 kg» inventado).
    private static func metaLine(sheet: RoutineSheet) -> some View {
        HStack(spacing: LiquidSpace.s250) {
            HStack(spacing: LiquidSpace.s150) {
                EntrenarFamilyDot(sheet.routineTint)
                Text(sheet.groupTitle).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            }
            Text(String(localized: "\(sheet.items.count) exercises")).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
            Text(String(localized: "\(sheet.totalSets) sets")).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                .numeroVivo(value: sheet.totalSets)
            Text(String(localized: "~\(sheet.estimatedMinutes) min")).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                .numeroVivo(value: sheet.estimatedMinutes)
            if let kg = sheet.estimatedTonnageKg {
                Text(String(localized: "~\(StrengthDisplay.weightNumber(kg, system: sheet.system)) \(StrengthDisplay.weightUnit(sheet.system).lowercased())"))
                    .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                    .numeroVivo(value: kg)
            }
        }
        .padding(.top, LiquidSpace.s050)
    }

    /// .planDay «···»: cambiar rutina / marcar descanso (A6/A7).
    private static func dayMenu(sheet: RoutineSheet) -> some View {
        Button { sheet.showDayMenu = true } label: {
            CenitIcon.more.image.font(LiquidType.infoGlifo.weight(.semibold))
                .foregroundStyle(LiquidColor.tinta500).frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Day options"))
        .disabled(sheet.locked)
        .liquidMenu(isPresented: Binding(get: { sheet.showDayMenu }, set: { sheet.showDayMenu = $0 }), items: [
            .init(String(localized: "Change routine"), systemImage: "arrow.left.arrow.right",
                  children: sheet.allRoutines.map { r in
                      LiquidMenuItem(r.name, systemImage: r.id == sheet.routine?.id ? "checkmark" : nil) { sheet.changeRoutine(to: r) }
                  }),
            .init(String(localized: "Mark as rest day"), systemImage: CenitIcon.sleep.systemName, isDestructive: true) { sheet.markRest() }
        ])
    }

    /// El CTA fijo — «Empezar»/«Resume», la ÚNICA puerta al ejercicio guiado (F2 lo sustituye).
    static func ctaBar(sheet: RoutineSheet) -> some View {
        LiquidGlassButton(sheet.ctaTitle, variant: .primary, expands: true) { sheet.start() }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s200)
            .padding(.bottom, LiquidSpace.s200)
            .entrenarHojaBarraFondo(tono: .indigo)
    }
}
#endif
