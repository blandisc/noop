#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaCabeceraSesion — cabecera + avance + CTA de «La Hoja viva» (FER-167 · F2, ronda 2)
//
// Mock `hoja-pantallas.html` P3/P4/P7: `.headS` (‹ · dot · nombre · «Serie N de M» · ♥ · reloj ·
// ⤢ · ‖) · `.avance` (riel 3pt) · P7 el mismo `.headS` con «N de N · completa» + CTA `.ctaV`
// «Terminar y guardar». «Serie N de M» es la unidad ÚNICA de avance (cabecera + píldora + riel) —
// mismo cálculo que `HojaSesionViva.serieSubtitle`, nunca dos fuentes que puedan divergir (R20: la
// píldora flotante lo comparte, ver `RootTabView`/`AppMap`).

@MainActor
enum HojaCabeceraSesion {

    /// Fila de cabecera: ‹ minimiza · dot de familia + nombre + «Serie N de M» · ♥ (R14, solo con
    /// FC viva) · reloj · ⤢ Foco (R2a) · ‖.
    static func header(vivo: HojaSesionViva) -> some View {
        HStack(spacing: LiquidSpace.s200) {
            Button {
                vivo.sheet.model.strengthSheetPresented = false   // B17: minimizar, nunca termina
            } label: {
                StrandIcon.back.image
                    .font(LiquidType.infoGlifoCompacto.weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta700)
                    .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Minimize session"))

            EntrenarFamilyDot(vivo.familyTint, size: EntrenarMetrics.familyDotCompact)

            VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                Text(vivo.session.routineName).font(LiquidType.tituloHoja).foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(vivo.session.paused ? String(localized: "Paused") : vivo.serieSubtitle)
                    .liquidKicker().foregroundStyle(LiquidColor.tinta700)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heartRate(vivo: vivo)

            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                let elapsed = vivo.session.elapsedSeconds(now: ctx.date)
                let texto = SessionClock.format(elapsed)
                Text(texto)
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.tinta700)
                    .numeroVivo(value: texto)
                    // Misma clave que LiveStrengthSheet (reloj vivo): «Elapsed %@» / «Paused at %@».
                    .accessibilityLabel(Text(vivo.session.paused ? "Paused at \(texto)" : "Elapsed \(texto)"))
                    .accessibilityAddTraits(.updatesFrequently)
            }

            // FER-250: «Terminar» secundario SIEMPRE visible a media sesión (criterio 1: con 0 series
            // el confirm ya es honesto — «Aún no registras ninguna serie.» + Seguir/Descartar). El CTA
            // prominente `ctaTerminar` se reserva para sesión completa — no se mueve.
            if !vivo.session.isComplete {
                terminarSecundario(vivo: vivo)
            }

            // R2(a): ⤢ — la misma puerta a Foco que `SessionStatsBar.onFocus` ofrecía en la barra vieja.
            if vivo.puedeEnfocar {
                Button { vivo.enterFoco() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(LiquidType.infoGlifo.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta700)
                        .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Focus"))
            }

            if let alternar = vivo.alternarPausa {
                Button(action: alternar) {
                    Image(systemName: vivo.session.paused ? "play.fill" : "pause.fill")
                        .font(LiquidType.infoGlifo.weight(.semibold))
                        .foregroundStyle(LiquidColor.tinta700)
                        .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vivo.session.paused ? Text("Resume session") : Text("Pause session"))
            }
        }
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.top, LiquidSpace.s150)
    }

    /// FER-250: píldora discreta «Terminar» en cabecera — mismo lenguaje que
    /// `LiveStrengthSheet.sessionHeaderPill` (papel + canto), no el CTA verde de sesión completa.
    private static func terminarSecundario(vivo: HojaSesionViva) -> some View {
        OutlineCapsule(theme: vivo.sheet.theme, size: .lg, estilo: .papel,
                       action: { vivo.confirmFinish = true }) {
            Text("Finish")
                .entrenarSessionEndLabel()
                .foregroundStyle(LiquidColor.tinta900)
        }
        .accessibilityLabel(Text("Finish"))
    }

    /// ♥ 118 — SOLO con FC viva (R14, paridad `LiveStrengthSheet.sessionHeaderHeartRate`). Sin punto
    /// animado a propósito: el numeral ya es la señal de vida.
    @ViewBuilder private static func heartRate(vivo: HojaSesionViva) -> some View {
        if let bpm = vivo.sheet.model.watchBpm {
            HStack(spacing: LiquidSpace.s100) {
                StrandIcon.heart.image.font(LiquidType.infoGlifoCompacto)
                Text("\(bpm)").font(LiquidType.cuerpoBanner.weight(.semibold))
            }
            .foregroundStyle(LiquidTono.rosa.rotulo)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Heart rate \(bpm) beats per minute"))
        }
    }

    /// El riel de avance (mock `.avance`): índigo, 3pt — MISMA fracción que la píldora/cabecera leen.
    static func avance(vivo: HojaSesionViva) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta10)
                Capsule().fill(vivo.familyTint)
                    .frame(width: geo.size.width * vivo.fraccionAvance)
            }
        }
        .frame(height: EntrenarMetrics.progressBar)
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.top, CenitMetrics.rowVPad)
        .accessibilityLabel(Text(verbatim: vivo.serieSubtitle))
    }

    /// B16 — sesión llena: CTA prominente «Terminar y guardar», la ÚNICA acción que queda una vez
    /// que ya no hay ninguna fila activa que capturar (mapa B16).
    static func ctaTerminar(vivo: HojaSesionViva) -> some View {
        VStack(spacing: LiquidSpace.s150) {
            LiquidGlassButton("Finish and save", variant: .primary, expands: true) {
                vivo.confirmFinish = true
            }
            Text("Your receipt is waiting on the other side")
                .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
        }
        .padding(.horizontal, LiquidSpace.s600)
        .padding(.top, LiquidSpace.s200)
        .padding(.bottom, LiquidSpace.s200)
        .entrenarHojaBarraFondo(tono: .indigo)
    }
}
#endif
