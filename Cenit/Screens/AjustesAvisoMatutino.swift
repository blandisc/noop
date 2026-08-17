#if os(iOS)
import SwiftUI
import UIKit       // UIApplication.openSettingsURLString (abrir Ajustes de iOS cuando lo negaron ahí)
import UserNotifications
import StrandDesign
import StrandAnalytics

// MARK: - Aviso matutino (FER-114) — la sección de Ajustes
//
// El onboarding promete «te aviso cuando esté»; esta sección es donde esa promesa se enciende. Vive en
// su propio archivo (y no dentro de `AjustesView`) porque es una feature con su propio permiso del
// sistema, su propio estado y su propio texto honesto; `AjustesLanding` solo la invoca.
//
// Tres verdades que la sección tiene que sostener a la vista:
//   1. El permiso se pide AL ENCENDER el switch, nunca antes.
//   2. Si el permiso se negó en Ajustes de iOS, el switch NO finge estar encendido: se ve apagado y
//      la sección dice por qué, con el atajo para abrirlo.
//   3. Si el motor todavía no tiene una lectura que dar, se dice también: el aviso callará hasta
//      tenerla, y es mejor decirlo aquí que dejar al dueño esperando un aviso que no va a llegar.

struct AvisoMatutinoSection: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository

    /// La preferencia del dueño (lo que PIDIÓ), separada del permiso del sistema (lo que iOS permite).
    @AppStorage(MorningReadingScheduler.enabledKey) private var quiereAviso = false
    @AppStorage(MorningReadingScheduler.hourKey) private var hora = MorningReadingScheduler.horaPorDefecto
    @AppStorage(MorningReadingScheduler.minuteKey) private var minuto = 0

    @State private var permiso: UNAuthorizationStatus = .notDetermined
    @State private var pidiendoPermiso = false

    /// El switch solo se ve encendido cuando de verdad puede sonar.
    private var encendido: Bool { quiereAviso && permiso != .denied }
    private var negadoEnIOS: Bool { quiereAviso && permiso == .denied }
    /// «Lo pediste, iOS deja, pero hoy no tengo nada que decirte.»
    private var sinLecturaQueDar: Bool {
        encendido && !MorningReadingScheduler.hayLectura(repo.todayPreparedness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "aviso.matutino.overline", defaultValue: "Morning notice"))
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: Binding(get: { encendido }, set: { encender($0) })) {
                Text(String(localized: "aviso.matutino.toggle",
                            defaultValue: "Tell me when my reading is ready"))
                    .font(StrandFont.body).foregroundStyle(theme.ink)
            }
            .toggleStyle(.instrumento)
            .frame(minHeight: 44)
            .disabled(pidiendoPermiso)

            if encendido {
                Divider().overlay(theme.hairline)
                HStack(alignment: .center, spacing: 16) {
                    Text(String(localized: "aviso.matutino.hora", defaultValue: "At what time"))
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DatePicker("", selection: horaBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel(String(localized: "aviso.matutino.hora",
                                                   defaultValue: "At what time"))
                }
                .frame(minHeight: 44)
            }

            Text(String(localized: "aviso.matutino.glosa",
                        defaultValue: "One notice a day, on your iPhone, at the time you pick. If that day I have no reading to give you, I stay quiet."))
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if sinLecturaQueDar {
                Text(String(localized: "aviso.matutino.sinlectura",
                            defaultValue: "I have no reading to give you yet, so I will stay quiet until I do."))
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if negadoEnIOS {
                Text(String(localized: "aviso.matutino.denegado",
                            defaultValue: "Notices are off in iOS Settings, so I cannot reach you."))
                    .font(StrandFont.caption).foregroundStyle(theme.critical)
                    .fixedSize(horizontal: false, vertical: true)
                Button { abrirAjustesDeIOS() } label: {
                    Text("Open Settings").font(StrandFont.subhead).foregroundStyle(theme.dataRecovery)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 32)
            }
        }
        .task { await sincronizar() }
        // Cambiar la hora cancela lo pendiente y reprograma (lo hace `reschedule` entero).
        .onChange(of: hora) { _, _ in reprogramar() }
        .onChange(of: minuto) { _, _ in reprogramar() }
    }

    // MARK: - Estado

    /// Refleja el permiso REAL al entrar (pudo cambiar en Ajustes de iOS desde la última vez) y deja
    /// el horario armado con la lectura de este momento.
    @MainActor
    private func sincronizar() async {
        permiso = await MorningReadingScheduler.authorizationStatus()
        guard quiereAviso else { return }
        await MorningReadingScheduler.reschedule(prep: repo.todayPreparedness)
    }

    /// El permiso se pide AQUÍ, en el instante en que se enciende el switch.
    private func encender(_ on: Bool) {
        guard on else {
            quiereAviso = false
            Task { await MorningReadingScheduler.cancelAll() }
            return
        }
        pidiendoPermiso = true
        Task {
            var estado = await MorningReadingScheduler.authorizationStatus()
            // El diálogo del sistema solo existe una vez: con `.denied` ya no aparece, y el único
            // camino real es Ajustes de iOS (el botón de abajo).
            if estado == .notDetermined {
                _ = await MorningReadingScheduler.requestAuthorization()
                estado = await MorningReadingScheduler.authorizationStatus()
            }
            permiso = estado
            // La preferencia guarda lo que PIDIÓ el dueño, aunque iOS lo niegue: así la sección
            // puede decirlo en voz alta en vez de rebotar el switch en silencio, y el día que lo
            // conceda en Ajustes de iOS el aviso se arma solo al volver aquí.
            quiereAviso = true
            pidiendoPermiso = false
            if estado == .authorized {
                await MorningReadingScheduler.reschedule(prep: repo.todayPreparedness)
            }
        }
    }

    private func reprogramar() {
        guard quiereAviso else { return }
        Task { await MorningReadingScheduler.reschedule(prep: repo.todayPreparedness) }
    }

    /// La hora guardada (hora + minuto) vista como la `Date` que pide `DatePicker`. Solo se escriben
    /// los dos números; la fecha del día no significa nada.
    private var horaBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hora, minute: minuto, second: 0, of: Date())
                    ?? Date()
            },
            set: { nueva in
                let c = Calendar.current.dateComponents([.hour, .minute], from: nueva)
                hora = c.hour ?? MorningReadingScheduler.horaPorDefecto
                minuto = c.minute ?? 0
            })
    }

    private func abrirAjustesDeIOS() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
#endif
