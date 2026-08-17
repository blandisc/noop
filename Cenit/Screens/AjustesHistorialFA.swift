#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore

// MARK: - «Historial de FA»: la puerta INFORMADA, en Ajustes (FER-115)
//
// Encender el «Historial de FA» (AFib History) en la app Salud densifica el muestreo latido a latido
// del Apple Watch durante la noche, que es EXACTAMENTE lo que `NocturnalHRV.night` necesita para
// emitir un `apple_rmssd_night` (≥ 60 latidos limpios y ≥ 30 pares sucesivos). Con eso, el RMSSD
// nocturno entra como CO-VOTO de 0.5 en `Preparedness.Config`, junto a la frecuencia cardiaca en
// reposo, que es la señal de peso 1.0 y la que de verdad sostiene el veredicto.
//
// Por eso esto es AFINACIÓN, no requisito, y por eso vive en Ajustes y NO en el onboarding: Apple
// gatea el ajuste detrás de confirmar un diagnóstico médico y apaga los avisos de ritmo irregular en
// tiempo real. Un costo así no se pide en un empujón; se informa y se deja decidir. La sección dice
// las dos caras con el MISMO peso visual (mismo contenedor, misma tipografía; solo cambia el hue de
// identidad de cada bloque) y no afirma que Cénit lo recomiende.

/// El estado de la puerta: si las series de latidos YA llegan, no hay nada que ofrecer.
enum HistorialFAPuerta {
    enum Estado: Equatable {
        /// Todavía no se leyó la evidencia (no se pinta nada: evita el parpadeo de una sección
        /// que aparece y desaparece).
        case sinResolver
        /// El Apple Watch ya entrega latido a latido con densidad usable → la sección se calla.
        case yaLleganSeries
        /// No hay evidencia de series densas → tiene sentido informar de la puerta.
        case noLleganSeries
    }

    /// Las dos claves que `HealthKitBridge.ingestNocturnalHRV()` escribe en la partición
    /// `apple-health-noop`: `apple_rmssd_night` (SOLO si la noche salió densa) y
    /// `apple_rr_clean_night` (los latidos limpios de esa noche, densa o no).
    static let claves = ["apple_rmssd_night", "apple_rr_clean_night"]

    /// Ventana de evidencia: los mismos 45 días que el bridge mantiene al día.
    static let ventanaDias = 45

    /// La lectura honesta de «ya llegan series de latidos»: existe una noche que el motor CONTÓ
    /// (`apple_rmssd_night`), o una noche cuyos latidos limpios llegaron al piso de densidad del
    /// propio motor (`NocturnalHRV.minCleanBeats`). Un goteo de tres latidos no es «ya llegan».
    static func estado(filas: [MetricPoint]) -> Estado {
        let llegan = filas.contains { fila in
            fila.key == "apple_rmssd_night"
                || (fila.key == "apple_rr_clean_night" && fila.value >= Double(NocturnalHRV.minCleanBeats))
        }
        return llegan ? .yaLleganSeries : .noLleganSeries
    }
}

/// La sección de Ajustes. Se pinta solo cuando la evidencia dice que las series todavía no llegan.
struct HistorialFASection: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var puerta: HistorialFAPuerta.Estado = .sinResolver

    var body: some View {
        Group {
            if puerta == .noLleganSeries { contenido }
        }
        .task { await resolverPuerta() }
    }

    // MARK: Contenido

    private var contenido: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Heart rhythm").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("AFib History, in the Health app")
                    .font(StrandFont.body).foregroundStyle(theme.ink)

                Text("If you turn it on there, your Apple Watch measures your heartbeat beat by beat far more often while you sleep. That density is what my nightly HRV reading needs. The morning verdict rides on your resting heart rate, with it or without it.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Las dos caras, mismo contenedor y misma tipografía. Solo el hue cambia: verde de
                // dato para lo que afina, ámbar de cautela para lo que cuesta.
                cara(title: "What it tunes",
                     texto: "HRV joins your resting heart rate as a second, lighter signal on the nights that come in dense: at least 60 clean beats and 30 successive pairs. It is a tuning, not a requirement, and it never speaks on its own.",
                     bar: theme.dataRecovery)
                cara(title: "What it costs",
                     texto: "To turn it on, Apple asks you to confirm that a doctor diagnosed you with atrial fibrillation. It is not intended for people under 22. And it switches off the real time irregular rhythm notifications: from then on your Apple Watch sends you a weekly summary instead.",
                     bar: theme.warning)

                enlaceSalud

                Text("I am not recommending it and I am not talking you out of it: both sides are here so you can decide. Cénit does not diagnose anything, and none of this is medical advice.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Una cara de la decisión. Las dos se construyen con esta MISMA función: el peso visual no
    /// puede desbalancearse sin que se note en un solo lugar.
    private func cara(title: LocalizedStringKey, texto: LocalizedStringKey, bar: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkSecondary)
            Text(texto)
                .font(StrandFont.caption).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.rowVPad)
        .patternBlock(theme, bar: bar)
    }

    /// Enlace quieto a la app Salud (el ajuste vive allá, no aquí). A propósito NO es un CTA sólido
    /// de ancho completo: sería el empujón que esta sección no quiere dar.
    private var enlaceSalud: some View {
        Button {
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app")
                    .font(StrandFont.glyph(.inline, weight: .semibold))
                Text("Open the Health app").font(StrandFont.subhead)
                Spacer(minLength: 8)
            }
            .foregroundStyle(theme.ink)
            .frame(minHeight: CenitMetrics.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Apple's Health app")
    }

    // MARK: Evidencia

    /// Lee la partición propia del RMSSD nocturno y decide si hay algo que ofrecer. Una sola lectura
    /// indexada por (deviceId, key, day); si el store no abre, la puerta queda sin resolver y la
    /// sección simplemente no se pinta.
    @MainActor private func resolverPuerta() async {
        guard puerta == .sinResolver, let store = await repo.storeHandle() else { return }
        let hoy = Date()
        let desde = Calendar.current.date(byAdding: .day, value: -HistorialFAPuerta.ventanaDias, to: hoy) ?? hoy
        let filas = (try? await store.metricSeries(deviceId: Repository.appleComputedDeviceId,
                                                   keys: HistorialFAPuerta.claves,
                                                   from: Repository.localDayKey(desde),
                                                   to: Repository.localDayKey(hoy))) ?? []
        puerta = HistorialFAPuerta.estado(filas: filas)
    }
}

#if DEBUG
#Preview("Historial de FA · puerta") {
    ScrollView {
        HistorialFASection()
            .padding(.horizontal, CenitMetrics.screenPadding)
    }
    .background(InstrumentoTheme.base.paper.ignoresSafeArea())
    .instrumentoTheme(.base)
    .environmentObject(Repository(deviceId: "preview"))
}
#endif

#endif
