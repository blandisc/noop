#if os(iOS)
import SwiftUI
import CenitDesign
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

    /// Las TRES claves que `HealthKitBridge.ingestNocturnalHRV()` escribe en la partición
    /// `apple-health-noop`: `apple_rmssd_night` (SOLO si la noche salió densa),
    /// `apple_rr_clean_night` (los latidos limpios de esa noche, densa o no) y
    /// `apple_rr_pairs_night` (los pares sucesivos de esa misma noche).
    static let claveRmssd = "apple_rmssd_night"
    static let claveLimpios = "apple_rr_clean_night"
    static let clavePares = "apple_rr_pairs_night"
    static let claves = [claveRmssd, claveLimpios, clavePares]

    /// Ventana de evidencia: los mismos 45 días que el bridge mantiene al día.
    static let ventanaDias = 45

    /// La lectura honesta de «ya llegan series de latidos»: existe una noche que el motor CONTÓ
    /// (`apple_rmssd_night`), o una noche que cumple LOS DOS pisos de densidad del motor la misma
    /// noche (`nClean ≥ 60` **y** `nPairs ≥ 30`, `NocturnalHRV.night`).
    ///
    /// Los latidos limpios solos NO bastan, y el propio `NocturnalHRV` documenta por qué: «a sparse
    /// wrist night can clear 60 clean beats while offering far fewer true successive pairs». Con el
    /// piso de pares fuera, una sola noche rala de esas silenciaba la sección PARA SIEMPRE justo a
    /// quien nunca va a recibir el co-voto — que es exactamente a quien la puerta le sirve.
    static func estado(filas: [MetricPoint]) -> Estado {
        // El veredicto de densidad del propio motor: si emitió RMSSD, la noche pasó los dos pisos.
        if filas.contains(where: { $0.key == claveRmssd }) { return .yaLleganSeries }
        var limpios: [String: Double] = [:]
        var pares: [String: Double] = [:]
        for fila in filas {
            switch fila.key {
            case claveLimpios: limpios[fila.day] = max(limpios[fila.day] ?? 0, fila.value)
            case clavePares:   pares[fila.day] = max(pares[fila.day] ?? 0, fila.value)
            default:           break
            }
        }
        // Los dos pisos, en LA MISMA noche: 60 latidos de una noche y 30 pares de otra no son una
        // noche densa, son dos noches ralas.
        let densa = limpios.contains { dia, n in
            n >= Double(NocturnalHRV.minCleanBeats)
                && (pares[dia] ?? 0) >= Double(NocturnalHRV.minSuccessivePairs)
        }
        return densa ? .yaLleganSeries : .noLleganSeries
    }
}

/// La sección de Ajustes. Se pinta solo cuando la evidencia dice que las series todavía no llegan.
struct HistorialFASection: View {
    @EnvironmentObject private var repo: Repository
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
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "Heart rhythm"))
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text(String(localized: "AFib History, in the Health app"))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)

                // Ronda 2 #6: el título prometía «en la app Salud» sin decir DÓNDE, y el botón de
                // abajo abre la app Salud en su inicio, no en Historial de FA directamente — Apple no
                // ofrece ese deep link. La ruta se dice aquí, en el cuerpo.
                Text(String(localized: "In Health: Browse → Heart → AFib History. Turning it on there makes your Apple Watch measure your heartbeat beat by beat far more often while you sleep. That density is what my nightly HRV reading needs. The morning verdict rides on your resting heart rate, with it or without it."))
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)

                // Las dos caras, MISMO componente (LiquidPatternBlock) y MISMO peso visual. Solo el
                // tono cambia: verde de dato para lo que afina, ámbar de cautela para lo que cuesta.
                LiquidPatternBlock(
                    overline: String(localized: "What it tunes"),
                    lineas: [String(localized: "HRV joins your resting heart rate as a second, lighter signal on the nights that come in dense: at least 60 clean beats and 30 successive pairs. It is a tuning, not a requirement, and it never speaks on its own.")],
                    tono: LiquidColor.verdePrimario)
                LiquidPatternBlock(
                    overline: String(localized: "What it costs"),
                    lineas: [String(localized: "To turn it on, Apple asks you to confirm that a doctor diagnosed you with atrial fibrillation. It is not intended for people under 22. And it switches off the real time irregular rhythm notifications: from then on your Apple Watch sends you a weekly summary instead.")],
                    tono: LiquidColor.atencion)

                enlaceSalud

                LiquidNotaLine(String(localized: "I am not recommending it and I am not talking you out of it: both sides are here so you can decide. Cénit does not diagnose anything, and none of this is medical advice."))
            }
            .liquidTarjetaSeccion()
        }
    }

    /// Enlace quieto a la app Salud (el ajuste vive allá, no aquí). A propósito NO es un CTA sólido
    /// de ancho completo: sería el empujón que esta sección no quiere dar.
    private var enlaceSalud: some View {
        Button {
            if let url = URL(string: "x-apple-health://") { openURL(url) }
        } label: {
            HStack(spacing: LiquidSpace.s200) {
                Image(systemName: "arrow.up.forward.app")
                    .font(LiquidType.iconSF(size: 13))
                Text(String(localized: "Open the Health app")).font(LiquidType.tituloFila)
                Spacer(minLength: 8)
            }
            .foregroundStyle(LiquidColor.tinta900)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)
        .accessibilityHint(Text(String(localized: "Opens Apple's Health app")))
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
            .padding(.horizontal, LiquidSpace.s550)
    }
    .background { LiquidSheetFondo().ignoresSafeArea() }
    .environmentObject(Repository(deviceId: "preview"))
}
#endif

#endif
