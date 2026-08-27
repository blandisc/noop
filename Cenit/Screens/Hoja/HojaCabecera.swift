#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaCabecera — cabecera + título + CTA de «La Hoja» (FER-166)
//
// Mock `hoja-pantallas.html` P1/P2: `.headE` (kick + ✕) · `.titulo` (nombre editable + ✎) ·
// `.metaLn` (dot de familia + conteos) · `.ctaV` («Empezar sesión»). Funciones estáticas (no un
// `View` propio): no llevan estado — leen/mutan el de `RoutineSheet` vía `sheet` (el `nonmutating
// set` de `@State` deja escribir sobre una copia por valor, mismo patrón que las closures de
// `body`).

enum HojaCabecera {

    /// Fila superior: ✕ (cierra) + Deshacer/Guardado.
    static func header(sheet: RoutineSheet) -> some View {
        HStack(spacing: 8) {
            BackButton(role: .close, theme: sheet.theme) { sheet.back() }
                .padding(.leading, -2)
            Spacer()
            if sheet.dirty {
                Button { sheet.undo() } label: {
                    Text(String(localized: "Undo")).font(StrandFont.body).foregroundStyle(sheet.theme.ink)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: "Undo")))
            } else if sheet.loaded {
                Text(String(localized: "Saved"))
                    .font(StrandFont.caption)
                    .foregroundStyle(sheet.theme.inkTertiary)
            }
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
    }

    /// Overline por origen, el nombre EDITABLE (TextField, ✎ decorativo al lado) y la meta punteada.
    static func titleBlock(sheet: RoutineSheet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(sheet.overline).groteskOverline().foregroundStyle(sheet.theme.inkTertiary)
                Spacer(minLength: 8)
                if sheet.isPlanDay { dayMenu(sheet: sheet) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Routine name", text: Binding(
                    get: { sheet.routine?.name ?? "" },
                    set: { sheet.routine?.name = $0; sheet.dirty = true }
                ))
                .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                .foregroundStyle(sheet.items.isEmpty ? sheet.theme.inkTertiary : sheet.theme.ink)
                .disabled(sheet.locked)
                // ✎ decorativo (mock «.lapiz»): el campo ya se edita tocándolo; el glifo solo lo anuncia.
                Text(verbatim: "✎").font(StrandFont.caption).foregroundStyle(sheet.theme.inkTertiary)
                    .accessibilityHidden(true)
            }
            if sheet.locked {
                Text("Session in progress · finish it to edit")
                    .font(StrandFont.caption).foregroundStyle(sheet.theme.inkTertiary)
                    .padding(.top, 2)
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
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                EntrenarFamilyDot(sheet.routineTint)
                Text(sheet.groupTitle).font(StrandFont.caption).foregroundStyle(sheet.theme.inkTertiary)
            }
            Text(String(localized: "\(sheet.items.count) exercises")).font(StrandFont.caption).foregroundStyle(sheet.theme.inkTertiary)
            Text(String(localized: "\(sheet.totalSets) sets")).font(StrandFont.caption).monospacedDigit().foregroundStyle(sheet.theme.inkTertiary)
            Text(String(localized: "~\(sheet.estimatedMinutes) min")).font(StrandFont.caption).monospacedDigit().foregroundStyle(sheet.theme.inkTertiary)
            if let kg = sheet.estimatedTonnageKg {
                Text(String(localized: "~\(StrengthDisplay.weightNumber(kg, system: sheet.system)) \(StrengthDisplay.weightUnit(sheet.system).lowercased())"))
                    .font(StrandFont.caption).monospacedDigit().foregroundStyle(sheet.theme.inkTertiary)
            }
        }
        .padding(.top, 2)
    }

    /// .planDay «···»: cambiar rutina / marcar descanso (A6/A7).
    private static func dayMenu(sheet: RoutineSheet) -> some View {
        Button { sheet.showDayMenu = true } label: {
            Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(sheet.theme.inkTertiary).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Day options"))
        .disabled(sheet.locked)
        .paperMenu(isPresented: Binding(get: { sheet.showDayMenu }, set: { sheet.showDayMenu = $0 }), items: [
            .init(String(localized: "Change routine"), systemImage: "arrow.left.arrow.right",
                  children: sheet.allRoutines.map { r in
                      PaperMenuItem(r.name, systemImage: r.id == sheet.routine?.id ? "checkmark" : nil) { sheet.changeRoutine(to: r) }
                  }),
            .init(String(localized: "Mark as rest day"), systemImage: "moon.zzz", isDestructive: true) { sheet.markRest() }
        ])
    }

    /// El CTA fijo — «Empezar sesión»/«Resume», la ÚNICA puerta al ejercicio guiado (F2 lo sustituye).
    static func ctaBar(sheet: RoutineSheet) -> some View {
        Button { sheet.start() } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))  // token-exempt: glifo del CTA
                Text(sheet.ctaTitle).font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
            }
            .foregroundStyle(sheet.theme.paper).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(sheet.theme.dataStrain, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(sheet.theme.paper)
    }
}
#endif
