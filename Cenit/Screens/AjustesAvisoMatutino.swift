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
// Cuatro verdades que la sección tiene que sostener a la vista:
//   1. El permiso se pide AL ENCENDER el switch, nunca antes.
//   2. Si el permiso no está concedido, el switch NO finge estar encendido: se ve apagado y la
//      sección dice por qué, con el atajo para abrirlo. Negado en Ajustes de iOS, además, el switch
//      queda DESHABILITADO — ahí no hace nada (el diálogo del sistema ya no vuelve).
//   3. El permiso se relee al volver al primer plano, no solo al entrar: conceder en Ajustes de iOS
//      y regresar es justo el momento en que esta sección se quedaba congelada en su verdad vieja.
//   4. Si el motor todavía no tiene una lectura que dar, se dice también: el aviso callará hasta
//      tenerla, y es mejor decirlo aquí que dejar al dueño esperando un aviso que no va a llegar.

struct AvisoMatutinoSection: View {
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var repo: Repository

    /// La preferencia del dueño (lo que PIDIÓ), separada del permiso del sistema (lo que iOS permite).
    @AppStorage(MorningReadingScheduler.enabledKey) private var quiereAviso = false
    @AppStorage(MorningReadingScheduler.hourKey) private var hora = MorningReadingScheduler.horaPorDefecto
    @AppStorage(MorningReadingScheduler.minuteKey) private var minuto = 0

    /// `nil` = todavía no se ha leído el permiso real (la consulta es asíncrona). No es lo mismo que
    /// `.notDetermined`, que ya es una respuesta del sistema.
    @State private var permiso: UNAuthorizationStatus?
    @State private var pidiendoPermiso = false

    /// El switch solo se ve encendido cuando de verdad PUEDE sonar. Con cualquier estado que no sea
    /// `.authorized` se ve apagado: `reschedule` no programa nada sin ese permiso, así que un switch
    /// prendido sería la app prometiendo algo que ya sabe que no va a hacer. El caso que se colaba:
    /// si `requestAuthorization()` lanzaba, el estado se quedaba en `.notDetermined` —ni concedido ni
    /// negado— y el switch se veía prendido mientras no se programaba nada.
    /// Mientras el permiso todavía no se ha leído se respeta la preferencia guardada, para no
    /// parpadear en apagado un switch que el dueño dejó prendido.
    private var encendido: Bool {
        guard quiereAviso else { return false }
        guard let permiso else { return true }
        return permiso == .authorized
    }
    private var negadoEnIOS: Bool {
        guard quiereAviso, let permiso else { return false }
        return permiso == .denied
    }
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
            // Con el permiso NEGADO en Ajustes de iOS el switch no hace nada (el diálogo del
            // sistema ya no vuelve a aparecer): tocable e inerte era peor que deshabilitado. El
            // camino real es el botón de abajo. Para APAGAR la preferencia no hace falta el switch:
            // sin permiso ya no suena nada.
            .disabled(pidiendoPermiso || negadoEnIOS)

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
        // Volver de Ajustes de iOS es EXACTAMENTE cuando el permiso pudo cambiar: sin esto, quien
        // tocaba «Abrir Ajustes», concedía y regresaba encontraba la sección diciendo todavía que
        // los avisos están apagados, y el aviso seguía sin programarse hasta la siguiente visita.
        .onChange(of: scenePhase) { _, fase in
            guard fase == .active else { return }
            Task { await sincronizar() }
        }
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
            // Por `reschedule` (y no `cancelAll` a secas) para que el borrado entre EN LA COLA:
            // con el switch apagado el plan sale vacío y cancela, pero sin pisarse con una
            // reprogramación en vuelo.
            Task { await MorningReadingScheduler.reschedule(prep: repo.todayPreparedness) }
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

    /// Cambiar la hora es la ÚNICA reprogramación que cancela aunque el plan salga vacío
    /// (`cancelaSinPlan`): dejar lo pendiente ahí haría sonar el aviso a la hora anterior.
    private func reprogramar() {
        guard quiereAviso else { return }
        Task {
            await MorningReadingScheduler.reschedule(prep: repo.todayPreparedness,
                                                     cancelaSinPlan: true)
        }
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
