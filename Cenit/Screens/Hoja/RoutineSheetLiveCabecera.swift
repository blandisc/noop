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
        HStack(spacing: CenitMetrics.space2) {
            Button {
                vivo.sheet.model.strengthSheetPresented = false   // B17: minimizar, nunca termina
            } label: {
                StrandIcon.back.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(vivo.sheet.theme.inkSecondary)
                    .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Minimize session"))

            EntrenarFamilyDot(vivo.familyTint, size: EntrenarMetrics.familyDotCompact)

            VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                Text(vivo.session.routineName).font(StrandFont.headline).foregroundStyle(vivo.sheet.theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(vivo.session.paused ? String(localized: "Paused") : vivo.serieSubtitle)
                    .instrumentoOverline().foregroundStyle(vivo.sheet.theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heartRate(vivo: vivo)

            TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                let elapsed = vivo.session.elapsedSeconds(now: ctx.date)
                let texto = SessionClock.format(elapsed)
                Text(texto)
                    .font(InstrumentoType.groteskNumber(15))
                    .foregroundStyle(vivo.sheet.theme.inkSecondary)
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
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(vivo.sheet.theme.inkSecondary)
                        .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Focus"))
            }

            if let alternar = vivo.alternarPausa {
                Button(action: alternar) {
                    Image(systemName: vivo.session.paused ? "play.fill" : "pause.fill")
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(vivo.sheet.theme.inkSecondary)
                        .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)   // 44 pt de toque
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(vivo.session.paused ? Text("Resume session") : Text("Pause session"))
            }
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, LiquidSpace.s150)
    }

    /// FER-250: píldora discreta «Terminar» en cabecera — mismo lenguaje que
    /// `LiveStrengthSheet.sessionHeaderPill` (papel + canto), no el CTA verde de sesión completa.
    private static func terminarSecundario(vivo: HojaSesionViva) -> some View {
        Button {
            vivo.confirmFinish = true
        } label: {
            Text("Finish")
                .entrenarSessionEndLabel()
                .foregroundStyle(vivo.sheet.theme.ink)
                .padding(.horizontal, CenitMetrics.receiptPadding)
                .frame(height: EntrenarMetrics.secondaryButton)
                .background(Capsule().fill(vivo.sheet.theme.paper))
                .overlay(Capsule().strokeBorder(vivo.sheet.theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(EntrenarPressStyle())
        .frame(minHeight: CenitMetrics.touchTarget)
        .contentShape(Capsule())
        .accessibilityLabel(Text("Finish"))
    }

    /// ♥ 118 — SOLO con FC viva (R14, paridad `LiveStrengthSheet.sessionHeaderHeartRate`). Sin punto
    /// animado a propósito: el numeral ya es la señal de vida.
    @ViewBuilder private static func heartRate(vivo: HojaSesionViva) -> some View {
        if let bpm = vivo.sheet.model.watchBpm {
            let tone = OKLab.darkened(vivo.sheet.theme.dataHeart, toContrast: 4.5, against: vivo.sheet.theme.paper)
            HStack(spacing: CenitMetrics.space1) {
                StrandIcon.heart.image.font(StrandFont.glyph(.chevron))
                Text("\(bpm)").font(StrandFont.subhead.weight(.semibold))
            }
            .foregroundStyle(tone)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Heart rate \(bpm) beats per minute"))
        }
    }

    /// El riel de avance (mock `.avance`): índigo, 3pt — MISMA fracción que la píldora/cabecera leen.
    static func avance(vivo: HojaSesionViva) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(vivo.sheet.theme.hairline)
                Capsule().fill(vivo.familyTint)
                    .frame(width: geo.size.width * vivo.fraccionAvance)
            }
        }
        .frame(height: EntrenarMetrics.progressBar)
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.rowVPad)
        .accessibilityLabel(Text(verbatim: vivo.serieSubtitle))
    }

    /// B16 — sesión llena: CTA prominente «Terminar y guardar», la ÚNICA acción que queda una vez
    /// que ya no hay ninguna fila activa que capturar (mapa B16).
    static func ctaTerminar(vivo: HojaSesionViva) -> some View {
        VStack(spacing: LiquidSpace.s150) {
            Button {
                vivo.confirmFinish = true
            } label: {
                Text("Finish and save")
                    .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3)
                    .foregroundStyle(vivo.sheet.theme.paper).frame(maxWidth: .infinity).padding(.vertical, LiquidSpace.s400)
                    .background(LiquidColor.verdePrimario, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Text("Your receipt is waiting on the other side")
                .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.top, CenitMetrics.space2)
        .padding(.bottom, CenitMetrics.space2)
        .entrenarHojaBarraFondo(tono: .indigo)
    }
}
#endif
