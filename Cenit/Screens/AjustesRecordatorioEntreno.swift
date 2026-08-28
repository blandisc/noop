#if os(iOS)
import SwiftUI
import UIKit       // UIApplication.openSettingsURLString (abrir Ajustes de iOS cuando lo negaron ahí)
import UserNotifications
import StrandDesign
import CenitStore
import StrandTraining

// MARK: - Recordatorio del día que toca entrenar (FER-95 · E14) — Liquid Glass (FER-178)
//
// Migración de piel de `RecordatorioEntrenoSection` al lenguaje Liquid Glass (FER-175/176:
// mismas reglas que la raíz de Ajustes ya migrada). Es un pase de PIEL, no de hilo: el permiso
// del sistema, el estado del plan semanal, el switch, la hora y el mensaje de negado en iOS se
// conservan verbatim. Lo que cambia es la superficie — overline `franja`, el grupo
// toggle+hora en `liquidTarjetaSeccion`, `LiquidCapilar` como separador, `LiquidNotaLine` para
// la glosa y los avisos.
//
// Mismo patrón que `AvisoMatutinoSection` (FER-114): su propio archivo, su propio permiso del
// sistema, su propio estado. La diferencia real es la fuente del plan — el aviso matutino lee
// `repo.todayPreparedness` (algo que `AppModel` ya publica); este lee el split semanal DIRECTO
// del store, porque esta pantalla no es parte del árbol de Entrenar que `AppModel` alimenta.
//
// Las mismas cuatro verdades que `AvisoMatutinoSection` sostiene a la vista:
//   1. El permiso se pide AL ENCENDER el switch, nunca antes.
//   2. Sin el permiso concedido, el switch NO finge estar encendido — y negado en Ajustes de iOS,
//      queda deshabilitado (el diálogo del sistema ya no vuelve).
//   3. El permiso se relee al volver al primer plano, no solo al entrar.
//   4. Sin plan semanal (ningún día con rutina asignada), se dice también: el recordatorio callará
//      hasta que haya un plan, y es mejor decirlo aquí que dejar al dueño esperando un aviso que no
//      va a llegar.
struct RecordatorioEntrenoSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var repo: Repository

    @AppStorage(TrainingDayReminder.enabledKey) private var quiereAviso = false
    @AppStorage(TrainingDayReminder.hourKey) private var hora = TrainingDayReminder.horaPorDefecto
    @AppStorage(TrainingDayReminder.minuteKey) private var minuto = 0

    /// `nil` = todavía no se ha leído el permiso real (la consulta es asíncrona).
    @State private var permiso: UNAuthorizationStatus?
    @State private var pidiendoPermiso = false
    /// El split + los nombres de rutina, leídos directo del store — esta sección no vive del
    /// dashboard de `AppModel`.
    @State private var split: [Int: String] = [:]
    @State private var routineNames: [String: String] = [:]

    private var encendido: Bool {
        guard quiereAviso else { return false }
        guard let permiso else { return true }
        return permiso == .authorized
    }
    private var negadoEnIOS: Bool {
        guard quiereAviso, let permiso else { return false }
        return permiso == .denied
    }
    /// «Lo pediste, iOS deja, pero hoy no tienes ningún día con rutina asignada.»
    private var sinPlan: Bool { encendido && split.isEmpty }

    private var capilar: some View { LiquidCapilar(eje: .horizontal) }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text("Training reminder")
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Toggle(isOn: Binding(get: { encendido }, set: { encender($0) })) {
                    Text("Remind me on training days")
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                }
                .tint(LiquidColor.verdePrimario)
                .frame(minHeight: 44)
                // Con el permiso NEGADO en Ajustes de iOS el switch no hace nada (el diálogo del
                // sistema ya no vuelve a aparecer): tocable e inerte era peor que deshabilitado. El
                // camino real es el botón de abajo. Para APAGAR la preferencia no hace falta el switch:
                // sin permiso ya no suena nada.
                .disabled(pidiendoPermiso || negadoEnIOS)

                if encendido {
                    capilar
                    HStack(alignment: .center, spacing: LiquidSpace.s400) {
                        Text("At what time")
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        DatePicker("", selection: horaBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .accessibilityLabel(Text("At what time"))
                    }
                    .frame(minHeight: 44)
                }

                // Glosa y estados DENTRO de la tarjeta, igual que «Aviso matutino» (secciones hermanas).
                LiquidNotaLine(String(localized: "One reminder on each day your plan assigns a routine, at the time you pick. I freeze it when I schedule it: I name the routine, never how you'll be feeling that day."))

                if sinPlan {
                    LiquidNotaLine(String(localized: "You haven't assigned any training days yet, so I have nothing to remind you of."))
                }

                if negadoEnIOS {
                    // Ronda 2 #21: la misma clave que «Aviso matutino» (`AvisoMatutinoSection`) para
                    // el mismo permiso — dos frases distintas para «negado en Ajustes de iOS» era el
                    // mismo hecho contado dos veces, con dos voces.
                    LiquidNotaLine(String(localized: "aviso.matutino.denegado",
                                defaultValue: "Notices are off in iOS Settings, so I cannot reach you."),
                                   tono: LiquidColor.atencionTexto)
                    settingsButton
                }
            }
            .liquidTarjetaSeccion()
        }
        .task { await sincronizar() }
        // Volver de Ajustes de iOS (o de editar el plan semanal en Entrenar) es exactamente cuando el
        // permiso o el split pudieron cambiar.
        .onChange(of: scenePhase) { _, fase in
            guard fase == .active else { return }
            Task { await sincronizar() }
        }
        .onChange(of: hora) { _, _ in reprogramar() }
        .onChange(of: minuto) { _, _ in reprogramar() }
    }

    private var settingsButton: some View {
        Button { abrirAjustesDeIOS() } label: {
            Text("Open Settings")
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
        }
        .buttonStyle(.liquidPress)
        .frame(minHeight: 32)
    }

    // MARK: - Estado

    @MainActor
    private func sincronizar() async {
        permiso = await TrainingDayReminder.authorizationStatus()
        await cargarPlan()
        guard quiereAviso else { return }
        await TrainingDayReminder.reschedule(split: split, routineNames: routineNames)
    }

    @MainActor
    private func cargarPlan() async {
        guard let store = await repo.storeHandle() else { return }
        let sched = (try? await store.routineSchedule()) ?? []
        split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let routines = (try? await store.routines()) ?? []
        routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    /// El permiso se pide AQUÍ, en el instante en que se enciende el switch.
    private func encender(_ on: Bool) {
        guard on else {
            quiereAviso = false
            Task { await TrainingDayReminder.reschedule(split: split, routineNames: routineNames) }
            return
        }
        pidiendoPermiso = true
        Task {
            var estado = await TrainingDayReminder.authorizationStatus()
            if estado == .notDetermined {
                _ = await TrainingDayReminder.requestAuthorization()
                estado = await TrainingDayReminder.authorizationStatus()
            }
            permiso = estado
            quiereAviso = true
            pidiendoPermiso = false
            if estado == .authorized {
                await cargarPlan()
                await TrainingDayReminder.reschedule(split: split, routineNames: routineNames)
            }
        }
    }

    private func reprogramar() {
        guard quiereAviso else { return }
        Task { await TrainingDayReminder.reschedule(split: split, routineNames: routineNames) }
    }

    private var horaBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hora, minute: minuto, second: 0, of: Date()) ?? Date()
            },
            set: { nueva in
                let c = Calendar.current.dateComponents([.hour, .minute], from: nueva)
                hora = c.hour ?? TrainingDayReminder.horaPorDefecto
                minuto = c.minute ?? 0
            })
    }

    private func abrirAjustesDeIOS() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
#endif
