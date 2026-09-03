#if os(iOS)
import SwiftUI
import UIKit             // UIApplication.openSettingsURLString (abrir Ajustes de iOS cuando negó un permiso)
import UserNotifications // UNAuthorizationStatus, para releer el permiso real de enfermedad/descanso
import CenitDesign
import StrandAnalytics
import CenitStore

// MARK: - Ajustes (the Settings tab root) — FER-337, reskinned to Liquid Glass (FER-176)
//
// The «Ajustes» tab root in the Liquid Glass language (glass surfaces, color as identity,
// hierarchy by space) — same information architecture and row names as before, only the skin
// changes. It replaced TWO stacked surfaces from the old shell: the interim «Más» drawer (a junk
// list of orphan screens) AND the SettingsView it pointed at. The tab opens DIRECTLY here — no
// list → "Settings" indirection.
//
// Structure (unchanged): Profile is surfaced inline on the root; everything else is a quiet row
// grouped under an overline that opens a focused sheet. Navigation is by SHEET, not a nested
// NavigationStack: the focused sub-screens (Units & format, the profile wheels, Max heart rate)
// ride Liquid sheets that build their own `LiquidSheetFondo` (the theme doesn't cross `.sheet`);
// the two sibling screens (Data Sources, About & support) ride a sheet too — Ajustes injects
// nothing into either (each screen owns its own background; About & support's own reskin is a
// separate issue).
//
// Explore · Compare · Workouts are NOT here: they already open from Cuerpo's footer; the old
// «Más» duplicate is gone.

struct AjustesView: View {
    var body: some View {
        AjustesLanding()
    }
}

// MARK: - Sheet routing

/// A sibling screen presented as a self-contained sheet.
private enum AjustesSheetScreen: String, Identifiable {
    case dataSources, support
    var id: String { rawValue }
}

/// Which profile value the wheel sheet is editing (A1).
private enum ProfileWheel: String, Identifiable {
    case age, weight, height
    var id: String { rawValue }
}

// MARK: - Content-fitted sheet

/// Sizes a sheet to its content height (so a short form doesn't open as a giant half-empty card),
/// with `.large` as a fallback when the content is taller than the fitted height (e.g. big Dynamic
/// Type). Same measure-then-detent pattern as `MuscleDetailView`: the content must hug its height
/// (no `maxHeight: .infinity`, no trailing `Spacer`) for the measured size to reflect the content.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in height = h }
            })
            .presentationDetents([.height(height), .large])
            .presentationDragIndicator(.visible)
    }
}
private extension View {
    func fittedSheet() -> some View { modifier(FittedSheet()) }
}

// MARK: - Landing

private struct AjustesLanding: View {
    @Environment(AppModel.self) var model
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var profile: ProfileStore
    // Read only to re-inject into the sibling sheets (a sheet starts a fresh environment branch).
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var health: HealthKitBridge
    @EnvironmentObject private var behavior: BehaviorStore
    @EnvironmentObject private var autoBackup: AutoBackup

    // Imperial/Metric display preference (D#103). Stored data is always SI; this only changes how
    // distances/weights/heights/temperatures are SHOWN — and lets the profile fields take imperial entry.
    @AppStorage("noop.apariencia") private var apariencia = "sistema"   // A4/FER-348
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    // Sheet drivers.
    @State private var showUnits = false
    @State private var showMaxHR = false
    // FER-183: «Fase del ciclo» vuelve a ser alcanzable (un control real la abre), ahora VIVA. El
    // opt-in gobierna, además, si el veredicto aplica el margen lútea (ver Repository, FER-183).
    @State private var showCyclePhase = false
    @AppStorage(CyclePhaseExperiment.enabledKey) private var cyclePhaseOn = false
    @AppStorage(WhitespaceMetricsExperiment.enabledKey) private var whitespaceMetrics = false
    /// FER-722: opt-in exercise media download (default off — the first/only exception to offline
    /// for exercise thumbs/loops, gated end-to-end by `MediaDownloadCoordinator`).
    @AppStorage(MediaDownloadCoordinator.enabledKey) private var exerciseMediaEnabled = false
    /// FER-93: las dos comodidades de la sesión, las dos apagadas por defecto.
    @AppStorage(SessionComfort.keepAwakeKey) private var keepScreenAwake = false
    @AppStorage(SessionComfort.restSoundKey) private var restSound = false
    @AppStorage(SessionComfort.restNotifyKey) private var restNotify = false
    /// Permiso REAL de notificaciones para «Notificar fin de descanso», releído (no `@State`
    /// volátil): mismo contrato que `AvisoMatutinoSection` — se pide al encender, si iOS niega el
    /// switch se ve apagado y se ofrece el atajo a Ajustes, y se relee al volver a primer plano
    /// (conceder en Ajustes de iOS y regresar tiene que reflejarse aquí, no quedarse congelado).
    @State private var restPermiso: UNAuthorizationStatus?
    @State private var pidiendoPermisoDescanso = false
    /// Ronda 2 #1: solo se usa para PINTAR la nota de negado — ya NO gobierna si el switch puede
    /// prenderse (ver `illnessNegado` / `encenderVigilanciaEnfermedad`).
    @State private var illnessPermiso: UNAuthorizationStatus?
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @State private var confirmDeleteMedia = false
    @State private var confirmRecalibrate = false
    @State private var profileWheel: ProfileWheel? = nil
    @State private var presentedSheet: AjustesSheetScreen? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                header
                profileSection
                moreSection
                footer
            }
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.top, LiquidSpace.s400)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .pantallaFondo()
        .task { await sincronizarPermisosDeAviso() }
        // Volver de Ajustes de iOS es EXACTAMENTE cuando estos dos permisos pudieron cambiar (mismo
        // contrato que `AvisoMatutinoSection`): sin esto, conceder allá y regresar aquí encontraba
        // los switches todavía congelados en su verdad vieja.
        .onChange(of: scenePhase) { _, fase in
            guard fase == .active else { return }
            Task { await sincronizarPermisosDeAviso() }
        }
        .sheet(isPresented: $showUnits) {
            UnidadesSheet()
        }
        .sheet(isPresented: $showMaxHR) {
            MaxHRSheet(profile: profile)
        }
        .sheet(isPresented: $showCyclePhase) {
            CyclePhaseSheet().environmentObject(repo)
        }
        .sheet(item: $profileWheel) { wheel in
            ProfileWheelSheet(wheel: wheel, profile: profile)
        }
        .sheet(item: $presentedSheet) { screen in sheetContent(screen) }
        // Confirm de recalibrar cuelga del landing ESTABLE (no del idle-branch de `recalibrateRow`):
        // si viviera solo en el `else`, el swap a «Deshacer» desmontaría al presentador a media salida.
        // El de borrar-animaciones vive en la tarjeta de Biblioteca (vista distinta) — dos
        // `liquidConfirm` en el mismo nodo no (bug FER-174).
        .liquidConfirm(
            isPresented: $confirmRecalibrate,
            title: String(localized: "Recalibrate your recovery?"),
            context: String(localized: "RECOVERY · BASELINE"),
            message: String(localized: "Your baseline will re-anchor from today and your earlier nights will be ignored. You'll lose your recovery number for a few days while it recalibrates. Your data and history aren't deleted."),
            actions: [
                .init(String(localized: "Leave the baseline as is"), role: .primary),
                .init(String(localized: "Recalibrate from today"), role: .destructive) {
                    model.recalibrateBaseline()
                }
            ]
        )
    }

    // MARK: - Header (one-off chrome: wordmark + a privacy line)

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            // FER-176: the wordmark alone, no `gearshape` — Tendencias doesn't repeat its dock glyph
            // next to its title either (`TendenciasGlyph`, not the tab bar's SF Symbol); a tab root
            // doesn't need to echo the icon that got you here.
            // Ronda 2 #24: la clave-fuente era el texto español «Ajustes» (una isla), marcada
            // `stale` en el catálogo — un prune futuro se la habría llevado. Ahora usa la MISMA
            // clave inglesa que el rótulo del dock (`LiquidTabRotulos+Cenit.swift`), así que
            // pantalla y dock siguen diciendo lo mismo en cualquier idioma.
            Text(String(localized: "Settings"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "On this iPhone · no account · no server"))
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Footer (version + a compact echo of the header's offline promise)

    private var footer: some View {
        Text(String(localized: "Cénit \(appVersion) · everything is computed on your iPhone"))
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.tinta500)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Profile (Age/Weight/Height/Max HR open a wheel sheet; Sex is inline)

    private var profileSection: some View {
        section(String(localized: "Profile")) {
            VStack(spacing: .zero) {
                LiquidListRow(title: String(localized: "Age"), trailing: "\(profile.age)",
                              a11yHint: String(localized: "Opens a picker")) { profileWheel = .age }
                sexRow
                LiquidListRow(title: String(localized: "Weight"), trailing: weightDisplay,
                              a11yHint: String(localized: "Opens a picker")) { profileWheel = .weight }
                LiquidListRow(title: String(localized: "Height"), trailing: heightDisplay,
                              a11yHint: String(localized: "Opens a picker")) { profileWheel = .height }
                LiquidListRow(title: String(localized: "Max heart rate"), trailing: maxHRDisplay,
                              a11yHint: String(localized: "Opens a picker"),
                              divider: false) { showMaxHR = true }
            }
            .liquidTarjetaSeccion(padding: LiquidSpace.s300)
        }
    }

    /// Sex is a `Picker`, not a value+chevron row, so it can't be a `LiquidListRow` — this
    /// hand-builds the same row geometry (padding, bottom hairline) so it seams into the same card.
    /// Ronda 2 #10: three segments + `.fixedSize()` truncated Male/Female/Non-binary at 390 pt —
    /// a menu never truncates and needs no width hack.
    /// A4/FER-348: selector de apariencia (Sistema/Claro/Oscuro) — mismo geometría de fila que sexRow.
    private var aparienciaRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(String(localized: "settings.appearance", defaultValue: "Appearance")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(String(localized: "settings.appearance", defaultValue: "Appearance"), selection: $apariencia) {
                Text(String(localized: "settings.appearance.system", defaultValue: "System")).tag("sistema")
                Text(String(localized: "settings.appearance.light", defaultValue: "Light")).tag("claro")
                Text(String(localized: "settings.appearance.dark", defaultValue: "Dark")).tag("oscuro")
            }
            .labelsHidden().pickerStyle(.menu).tint(LiquidColor.tinta700)
            .accessibilityLabel(String(localized: "settings.appearance", defaultValue: "Appearance"))
        }
        .padding(.vertical, LiquidSpace.s300)
        .padding(.horizontal, LiquidSpace.s100)
    }

    private var sexRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(String(localized: "Sex")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(String(localized: "Sex"), selection: $profile.sex) {
                Text(String(localized: "Male")).tag("male")
                Text(String(localized: "Female")).tag("female")
                Text(String(localized: "Non-binary")).tag("nonbinary")
            }
            .labelsHidden().pickerStyle(.menu).tint(LiquidColor.tinta700)
            .accessibilityLabel(String(localized: "Sex"))
        }
        .padding(.vertical, 11)  // token-exempt(paridad): paridad fila LiquidListRow (padding interno no público)
        .padding(.horizontal, LiquidSpace.s100)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)  // token-exempt(paridad): paridad divisor LiquidListRow (no público)
        }
    }

    private var weightDisplay: String {
        unitSystem == .imperial
            ? "\(Int(UnitFormatter.kgToPounds(profile.weightKg).rounded())) lb"
            : String(format: "%.1f kg", profile.weightKg)
    }
    private var heightDisplay: String {
        UnitFormatter.heightFromCentimeters(profile.heightCm, system: unitSystem)
    }
    private var maxHRDisplay: String {
        profile.hrMaxOverride > 0
            ? "\(profile.hrMaxOverride) bpm"
            : String(localized: "Automatic · \(profile.hrMax) bpm")
    }

    // MARK: - More (grouped nav rows + toggle blocks, each in its own overlined card)

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            section(String(localized: "App")) {
                VStack(spacing: .zero) {
                    LiquidListRow(title: String(localized: "Units & format"), subtitle: unitsSubtitle,
                                  divider: true) { showUnits = true }
                    aparienciaRow
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
            section(String(localized: "Data")) {
                VStack(spacing: .zero) {
                    LiquidListRow(title: String(localized: "Data Sources"),
                                  subtitle: String(localized: "Apple Health · backup")) { presentedSheet = .dataSources }
                    recalibrateRow
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
            // Ronda 2 #2: la única excepción de red de la app vivía escondida bajo «Experimental»,
            // junto a métricas opt-in que nada tienen que ver con una descarga — quien se saltaba
            // esa sección nunca veía el único control de red del app. Su propia sección, fuera de
            // Experimental.
            section(String(localized: "Exercise library")) { exerciseLibraryCard }
            // FER-1021: el interruptor de «vigilar enfermedad» vivía en la difunta AutomationsView
            // (retirada con la banda). El motor sigue vivo y ruteado a Apple (temp de muñeca + FC en
            // reposo nocturna, FER-884); esto le repone el acceso para que la feature sea alcanzable.
            // «Salud» es el nombre de la app de Apple, no de esta sección. Ronda 2 #12: tampoco
            // «Watch» en inglés — en una app de Apple Watch ese nombre es el hardware, no la sección.
            section(String(localized: "Monitoring")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    // Ronda 2 #1 (revierte una regresión de ronda 1): la superficie viva de esta
                    // feature es el banner de Hoy, NO una notificación — a diferencia del aviso
                    // matutino / recordatorio de entreno, cuya ÚNICA superficie SÍ es la notificación.
                    // El switch sigue SIEMPRE la preferencia (`behavior.illnessWatch`), nunca el
                    // permiso del sistema: negarlo en Ajustes de iOS apaga el AVISO, no la vigilancia,
                    // así que el switch no se deshabilita ni se auto-apaga por esa respuesta.
                    Toggle(isOn: Binding(get: { illnessEncendido }, set: { encenderVigilanciaEnfermedad($0) })) {
                        Text(String(localized: "Watch for illness signs"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    .tint(LiquidColor.verdePrimario)
                    .frame(minHeight: 44)
                    // Ronda 3 #3: interpola el nombre real de la pestaña (`Today`/«Hoy»), no el
                    // literal español «Hoy» dentro de la cadena fuente inglesa — el dock usa esa
                    // MISMA clave (`LiquidTabRotulos+Cenit.swift`), así que en UI inglesa esto ya
                    // dice «Today», el nombre real de la pestaña.
                    Text(String(localized: "I cross your wrist temperature with your resting nighttime pulse to warn you early of a possible illness. It's approximate, not a diagnosis, and I need about two weeks of data. If it fires, you'll see it in \(String(localized: "Today")) and, if you've allowed notifications, in a notification."))
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                    if illnessNegado {
                        LiquidNotaLine(String(localized: "You'll still see it in \(String(localized: "Today")); I can't send you a notification until you allow it."),
                                      tono: LiquidColor.atencionTexto)
                        Button { abrirAjustesDeIOS() } label: {
                            Text(String(localized: "Open Settings")).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
                        }
                        .buttonStyle(.liquidPress)
                        .frame(minHeight: 32)
                    }
                }
                .liquidTarjetaSeccion()
            }
            // El aviso matutino trae su propia sección entera (switch + hora + estado real del
            // permiso); vive en `AjustesAvisoMatutino.swift` (FER-177, ya migrada a Liquid Glass).
            AvisoMatutinoSection()
            // El recordatorio del día que toca entrenar, mismo patrón; vive en
            // `AjustesRecordatorioEntreno.swift` (FER-178, ya migrada a Liquid Glass).
            RecordatorioEntrenoSection()
            // La puerta informada del «Historial de FA». Trae su propio overline y se calla sola
            // cuando las series de latidos ya llegan; vive en `AjustesHistorialFA.swift` (FER-115,
            // ya migrada a Liquid Glass).
            HistorialFASection()
            section(String(localized: "During a session")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    Toggle(isOn: $keepScreenAwake) {
                        Text(String(localized: "Keep the screen on"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    .tint(LiquidColor.verdePrimario)
                    .frame(minHeight: 44)
                    .onChange(of: keepScreenAwake) { _, on in
                        // Ronda 3 #5: prender/apagar a media sesión tiene que surtir efecto ya, no
                        // en la siguiente. Apagar es incondicional (siempre seguro); prender solo
                        // si hay sesión viva — `applyKeepAwake` ya AND-ea la bandera con `active`,
                        // pero `active` aquí significa «hay sesión», no «el switch está en on».
                        if on {
                            if model.strengthSession != nil { SessionComfort.applyKeepAwake(active: true) }
                        } else {
                            SessionComfort.applyKeepAwake(active: false)
                        }
                    }
                    Text(String(localized: "If you don't touch your phone, iOS locks it mid-set. It only applies while the session is open, and it uses more battery: your iPhone goes back to its normal auto-lock when the session ends."))
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                    LiquidCapilar(eje: .horizontal)
                    Toggle(isOn: $restSound) {
                        Text(String(localized: "Sound when a timed rest ends"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    .tint(LiquidColor.verdePrimario)
                    .frame(minHeight: 44)
                    Text(String(localized: "A short system tone next to the haptic, for a rest counted by the clock. It follows your ring switch, and it only sounds with the app on screen: if the iPhone locked, there's no sound."))
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                    LiquidCapilar(eje: .horizontal)
                    Toggle(isOn: Binding(get: { restEncendido }, set: { encenderAvisoDescanso($0) })) {
                        Text(String(localized: "Notify me when rest is up"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    .tint(LiquidColor.verdePrimario)
                    .frame(minHeight: 44)
                    .disabled(pidiendoPermisoDescanso || restNegado)
                    if restNegado {
                        LiquidNotaLine(String(localized: "Notices are off in iOS Settings, so I cannot reach you."),
                                      tono: LiquidColor.atencionTexto)
                        Button { abrirAjustesDeIOS() } label: {
                            Text(String(localized: "Open Settings")).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
                        }
                        .buttonStyle(.liquidPress)
                        .frame(minHeight: 32)
                    }
                    Text(String(localized: "The only notice that survives locking your phone: a notification your iPhone delivers on its own, for when you leave it on the floor between sets. It's scheduled and delivered on your device; nothing leaves it."))
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .liquidTarjetaSeccion()
            }
            section(String(localized: "Experimental")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    experimentalTogglesCard
                    // FER-183: «Fase del ciclo» en su propia tarjeta de navegación — misma receta
                    // que «Units & format» — en vez de al final de la tarjeta de switches (padding
                    // distinto, chevron peleando con el cromo de toggle).
                    VStack(spacing: .zero) {
                        LiquidListRow(
                            title: String(localized: "Cycle phase"),
                            subtitle: cyclePhaseOn
                                ? String(localized: "On · adjusts your recovery on luteal days")
                                : String(localized: "Off · a self-knowledge experiment"),
                            divider: false) { showCyclePhase = true }
                    }
                    .liquidTarjetaSeccion(padding: LiquidSpace.s300)
                }
            }
            section(String(localized: "More")) {
                VStack(spacing: .zero) {
                    LiquidListRow(title: String(localized: "About & support"),
                                  subtitle: String(localized: "Version \(appVersion) · what Cénit is"),
                                  divider: false) { presentedSheet = .support }
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
        }
    }

    /// The experimental-metrics toggle, alone (ronda 2 #2 moved the media download out of this card).
    private var experimentalTogglesCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Toggle(isOn: $whitespaceMetrics) {
                Text(String(localized: "Experimental metrics"))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            }
            .tint(LiquidColor.verdePrimario)
            .frame(minHeight: 44)
            Text(String(localized: "New, approximate readings: nocturnal vagal reserve, thermal stability, night respiration and post-session recovery. They need several days of use to read well."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
    }

    /// The exercise-media download, in its own «Exercise library» card (ronda 2 #2), out from under
    /// «Experimental»: it's the app's only network exception (ExerciseDB's CDN, opt-in, off by
    /// default), not an unstable metric — burying it next to opt-in metrics hid the one control that
    /// actually matters for the offline promise.
    private var exerciseLibraryCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Toggle(isOn: $exerciseMediaEnabled) {
                Text(String(localized: "Downloaded exercise animations"))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            }
            .tint(LiquidColor.verdePrimario)
            .frame(minHeight: 44)
            .onChange(of: exerciseMediaEnabled) { _, enabled in
                if enabled { Task { await mediaCoordinator.bulkDownloadThumbsIfNeeded() } }
                else { mediaCoordinator.resetDownloadState() }
            }
            Text(String(localized: "Downloads each exercise's animation from ExerciseDB's image CDN, an external service. They're saved on your iPhone forever and work offline afterwards. This is the only exception to Cénit's zero-network rule: fetching each image exposes your IP to that service, like loading any image on the internet; no other data of yours (not even the exercise name) ever leaves. Turning this off stops future downloads; it doesn't delete what's already saved."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
            mediaDownloadStatus
            // Ronda 2 #13 (revierte una regresión de ronda 1): visible cuando hay caché EN DISCO,
            // no cuando `downloadState` de ESTA sesión no es `.idle` — al relanzar la app el estado
            // vuelve a `.idle` aunque el caché siga lleno, así que el botón se volvía inalcanzable
            // sin antes encender el toggle (disparando red) solo para poder borrar. El diálogo de
            // confirmación NO cuelga de este botón: vive en el cuerpo estable del landing, junto al
            // de Recalibrar, para que borrar (que hace desaparecer este botón) no desmonte al
            // presentador a media salida.
            if mediaCoordinator.hasCachedMedia {
                LiquidCapilar(eje: .horizontal)
                Button(role: .destructive) { confirmDeleteMedia = true } label: {
                    Text(String(localized: "Delete downloaded animations"))
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.negativo)
                }
                .buttonStyle(.plain)
            }
        }
        .liquidTarjetaSeccion()
        // Confirm de borrar-animaciones en la tarjeta ESTABLE de Biblioteca (siempre montada;
        // solo el botón es condicional), NO en el landing: así NO comparte nodo con el confirm
        // de Recalibrar (bug FER-174) y borrar no tumba al presentador a media salida.
        .liquidConfirm(
            isPresented: $confirmDeleteMedia,
            title: String(localized: "Delete all downloaded exercise animations?"),
            context: String(localized: "LIBRARY · ANIMATIONS"),
            message: String(localized: "Saved animations are deleted from your iPhone. You can re-download them anytime."),
            actions: [
                .init(String(localized: "Keep the animations"), role: .primary),
                .init(String(localized: "Delete the animations"), role: .destructive) {
                    mediaCoordinator.deleteAllCachedMedia()
                    mediaCoordinator.resetDownloadState()
                }
            ]
        )
    }

    /// «Recalibrar recuperación» (FER-677): re-anchors every nightly baseline from today. Two states —
    /// idle (tap → confirmation) and recalibrated (shows the date + a quiet «Deshacer»). The action is
    /// reversible, so «Deshacer» skips a dialog; recalibrating is what carries the warning.
    @ViewBuilder
    private var recalibrateRow: some View {
        if profile.canUndoRecalibration {
            // The «Deshacer» state doesn't fit `LiquidListRow` (its trailing slot is a plain
            // String, not a button) — hand-built to the same row geometry.
            HStack(spacing: LiquidSpace.s300) {
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(String(localized: "Recalibrate recovery"))
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    Text(String(localized: "Recalibrated on \(recalibratedDateText)"))
                        .font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Undo")) { model.undoRecalibrateBaseline() }
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.negativo)
                    .buttonStyle(.plain)
            }
            .padding(.vertical, 11)  // token-exempt(paridad): paridad fila LiquidListRow (padding interno no público)
            .padding(.horizontal, LiquidSpace.s100)
        } else {
            // Recalibrar es una ACCIÓN (abre un confirm), no navegación: fila a mano con el ícono
            // `arrow.clockwise` del original, no un `LiquidListRow` (cuyo chevron prometería empujar a
            // otra pantalla). Misma geometría de fila que la rama «Deshacer».
            Button { confirmRecalibrate = true } label: {
                HStack(spacing: LiquidSpace.s300) {
                    VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                        Text(String(localized: "Recalibrate recovery"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                        Text(String(localized: "Restarts your calibration from today if your baseline went wrong (an anomalous stretch)."))
                            .font(LiquidType.unidadCompacta).foregroundStyle(LiquidColor.tinta500)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "arrow.clockwise")
                        .font(LiquidType.iconSF(size: 14)).foregroundStyle(LiquidColor.tinta700)
                }
                .padding(.vertical, 11)  // token-exempt(paridad): paridad fila LiquidListRow (padding interno no público)
                .padding(.horizontal, LiquidSpace.s100)
                .contentShape(Rectangle())
            }
            .buttonStyle(.liquidPress)
        }
    }

    /// The `baselineEpoch` day-key ("YYYY-MM-DD") shown as a localized medium date, e.g. «10 jul 2026».
    private var recalibratedDateText: String {
        // Local parser (write side of the day-key contract) — same zone as the stored key (FER-754).
        guard let date = DayKey.localFormatter.date(from: profile.baselineEpoch) else { return profile.baselineEpoch }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Real feedback for the bulk thumb download (FER-778) — replaces the mute toggle-and-hope. Quiet
    /// by design: nothing while idle/off, a live count while running, a one-line result after.
    @ViewBuilder
    private var mediaDownloadStatus: some View {
        switch mediaCoordinator.downloadState {
        case .idle:
            EmptyView()
        case .downloading(let completed, let total):
            HStack(spacing: LiquidSpace.s150) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Downloading \(completed)/\(total)…"))
            }
            .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
        case .completed(let matched, let total):
            Text(total == 0
                 ? String(localized: "Already fully downloaded.")
                 : String(localized: "Download complete: \(matched)/\(total) exercises with animation."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
        case .failed:
            Text(String(localized: "Couldn't download. Check your connection and try again."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.negativo)
        }
    }

    /// Live units summary, e.g. «Metric · °C».
    private var unitsSubtitle: String {
        let sys = unitSystem == .metric ? String(localized: "Metric") : String(localized: "Imperial")
        let temp: String
        switch temperatureRaw {
        case TemperatureUnit.celsius.rawValue:    temp = "°C"
        case TemperatureUnit.fahrenheit.rawValue: temp = "°F"
        default:                                  temp = "°C/°F"
        }
        return "\(sys) · \(temp)"
    }

    // MARK: - Notification permission contract (illness watch + rest-end notice)
    //
    // The rest-end notice follows the `AvisoMatutinoSection` contract: the system permission is
    // requested the instant the switch turns ON (never at launch, never mid-session); if iOS denies
    // it the switch shows OFF and disabled with a note + an «Open Settings» deep-link, instead of
    // staying lit and promising a notice that will never arrive; and the real permission is reread
    // whenever the app returns to the foreground. Its ONLY surface IS the system notification, so
    // that contract fits it exactly.
    //
    // The illness watch does NOT share that contract (ronda 2 #1 reverts a ronda-1 regression that
    // copied it wholesale): its live surface is the Hoy banner, not a notification, so the switch
    // always reflects the PREFERENCE alone — never disabled, never auto-off on a denial. The
    // permission is still requested on enable (for the system notice), and still reread on
    // foreground, purely to decide whether to show the «you'll still see it in Hoy» note.

    /// The illness-watch switch shows exactly the preference — the permission never overrides it.
    private var illnessEncendido: Bool { behavior.illnessWatch }
    /// Preference ON but the system notice denied: the banner in Hoy still fires, only the
    /// notification won't — the note below says so, the switch stays on.
    private var illnessNegado: Bool {
        guard behavior.illnessWatch, let illnessPermiso else { return false }
        return illnessPermiso == .denied
    }
    private func encenderVigilanciaEnfermedad(_ on: Bool) {
        // La preferencia manda YA, pase lo que pase con el permiso que se pide abajo.
        behavior.illnessWatch = on
        model.reevaluateIllness()
        guard on else { return }
        Task {
            var estado = await IllnessNotifier.authorizationStatus()
            if estado == .notDetermined {
                _ = await IllnessNotifier.requestAuthorization()
                estado = await IllnessNotifier.authorizationStatus()
            }
            illnessPermiso = estado
        }
    }

    /// Same shape for the rest-end notice; `restNotify` keeps holding what the owner ASKED for
    /// (`RestEndNotifier.schedule` rechecks the real system permission at schedule time regardless).
    private var restEncendido: Bool {
        guard restNotify else { return false }
        guard let restPermiso else { return true }
        return restPermiso == .authorized
    }
    private var restNegado: Bool {
        guard restNotify, let restPermiso else { return false }
        return restPermiso == .denied
    }
    private func encenderAvisoDescanso(_ on: Bool) {
        guard on else {
            restNotify = false
            RestEndNotifier.cancel()
            return
        }
        pidiendoPermisoDescanso = true
        Task {
            var estado = await RestEndNotifier.authorizationStatus()
            if estado == .notDetermined {
                _ = await RestEndNotifier.requestAuthorization()
                estado = await RestEndNotifier.authorizationStatus()
            }
            restPermiso = estado
            restNotify = true
            pidiendoPermisoDescanso = false
        }
    }

    /// Reads both real permissions — called on appear and every time the app returns to the
    /// foreground (`scenePhase == .active`), so Ajustes de iOS granting/denying either one is
    /// reflected here without needing to toggle anything.
    @MainActor
    private func sincronizarPermisosDeAviso() async {
        illnessPermiso = await IllnessNotifier.authorizationStatus()
        restPermiso = await RestEndNotifier.authorizationStatus()
    }

    private func abrirAjustesDeIOS() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Section scaffolding (Liquid: inset franja overline, DataSourcesView's pattern)

    @ViewBuilder
    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(verbatim: title)
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sibling sheet (Data Sources · About & support — each owns its own background)

    @ViewBuilder
    private func sheetContent(_ screen: AjustesSheetScreen) -> some View {
        switch screen {
        case .dataSources:
            NavigationStack {
                DataSourcesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { presentedSheet = nil }
                                .foregroundStyle(LiquidColor.tinta900)
                        }
                    }
            }
            .environment(model)
            .environmentObject(repo)
            .environmentObject(health)
            .environmentObject(behavior)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        case .support:
            NavigationStack {
                SupportView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Done")) { presentedSheet = nil }
                                .foregroundStyle(LiquidColor.tinta900)
                        }
                    }
            }
            .environment(model)
            .environmentObject(repo)
            .environmentObject(health)
            .environmentObject(behavior)
            .environmentObject(autoBackup)
            .preferredColorScheme(.light)
        }
    }
}

// MARK: - Profile wheel (a focused wheel for Age / Weight / Height)

/// «Editar perfil» — a single value behind a `Picker(.wheel)`, honouring the imperial display
/// preference (the wheel itself shows lb / ft·in and writes the SI equivalent back). Ronda 2 #8:
/// the wheel used to write straight into `profile.*` on every tick (a stray flick silently retuned
/// Tanaka, HR zones and kcal) with no way back — it now edits a LOCAL snapshot and only reaches
/// `profile.*` on «Listo»; «Cancelar» discards it. `profile` arrives as a plain reference (not
/// `@EnvironmentObject`): the caller already holds it and the local snapshot must be seeded once,
/// at init, before the environment would even be available.
private struct ProfileWheelSheet: View {
    let wheel: ProfileWheel
    let profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var age: Int
    @State private var weightKg: Double
    @State private var heightCm: Double

    init(wheel: ProfileWheel, profile: ProfileStore) {
        self.wheel = wheel
        self.profile = profile
        _age = State(initialValue: profile.age)
        _weightKg = State(initialValue: profile.weightKg)
        _heightCm = State(initialValue: profile.heightCm)
    }

    // Ronda 3 #1: NO NavigationStack — no abraza su contenido, llena el detent y rompe
    // `.fittedSheet()` (la rueda quedaba recortada en el detent inicial de 320). Cancelar/Listo
    // viven como una barra DENTRO del VStack que `.fittedSheet()` mide, no en un toolbar de nav.
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .foregroundStyle(LiquidColor.tinta700)
                Spacer()
                Button(String(localized: "Done")) {
                    profile.age = age
                    profile.weightKg = weightKg
                    profile.heightCm = heightCm
                    dismiss()
                }
                .foregroundStyle(LiquidColor.tinta900)
            }
            .font(LiquidType.boton)

            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text(String(localized: "Profile"))
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(verbatim: title)
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            wheelBody
                .frame(maxWidth: .infinity)
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pantallaFondo()
        .fittedSheet()
    }

    private var title: String {
        switch wheel {
        case .age: return String(localized: "Age")
        case .weight: return String(localized: "Weight")
        case .height: return String(localized: "Height")
        }
    }

    @ViewBuilder private var wheelBody: some View {
        switch wheel {
        case .age:
            Picker(String(localized: "Age"), selection: $age) {
                ForEach(13...100, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
        case .weight:
            if unitSystem == .imperial {
                let pounds = Binding<Double>(
                    get: { UnitFormatter.kgToPounds(weightKg) },
                    set: { weightKg = UnitFormatter.poundsToKg($0) })
                let opts = Array(stride(from: 66.0, through: 551.0, by: 1))
                let lb = snapped(pounds, options: opts)
                Picker(String(localized: "Weight in pounds"), selection: lb) {
                    ForEach(opts, id: \.self) { Text("\(Int($0)) lb").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            } else {
                let opts = Array(stride(from: 30.0, through: 250.0, by: 0.5))
                let kg = snapped($weightKg, options: opts)
                Picker(String(localized: "Weight in kilograms"), selection: kg) {
                    ForEach(opts, id: \.self) { Text(String(format: "%.1f kg", $0)).tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            }
        case .height:
            if unitSystem == .imperial {
                let inchesValue = Binding<Double>(
                    get: { UnitFormatter.cmToInches(heightCm).rounded() },
                    set: { heightCm = $0 * UnitFormatter.centimetersPerInch })
                let opts = Array(stride(from: 47.0, through: 91.0, by: 1))
                let inches = snapped(inchesValue, options: opts)
                Picker(String(localized: "Height in inches"), selection: inches) {
                    ForEach(opts, id: \.self) { v in
                        let ft = Int(v) / 12, inch = Int(v) % 12
                        Text("\(ft)′ \(inch)″").tag(v)
                    }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            } else {
                let opts = Array(stride(from: 120.0, through: 230.0, by: 1))
                let cm = snapped($heightCm, options: opts)
                Picker(String(localized: "Height in centimeters"), selection: cm) {
                    ForEach(opts, id: \.self) { Text("\(Int($0)) cm").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            }
        }
    }

    /// A wheel-safe binding: the selection always lands on a tag in `options` (snaps the stored value
    /// to the nearest grid point), so the picker never shows an empty selection for an off-grid value.
    private func snapped(_ base: Binding<Double>, options: [Double]) -> Binding<Double> {
        Binding(
            get: { options.min(by: { abs($0 - base.wrappedValue) < abs($1 - base.wrappedValue) }) ?? base.wrappedValue },
            set: { base.wrappedValue = $0 })
    }
}

// MARK: - Max heart rate (auto / manual)

/// «FC máxima» — a focused sheet over `profile.hrMaxOverride` (0 = auto). The segmented control is pure
/// UI sugar on that one value: Auto shows the Tanaka estimate large; Manual reveals a wheel writing the
/// override (and notes it's anulando the auto estimate). Ronda 2 #8: same fix as `ProfileWheelSheet` —
/// edits a LOCAL snapshot, only reaches `profile.hrMaxOverride` on «Listo»; «Cancelar» discards it.
private struct MaxHRSheet: View {
    let profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    /// Local mode toggle. Drives the LOCAL override: Auto → 0; Manual → keep/seed a concrete bpm.
    @State private var manual: Bool
    @State private var overrideBpm: Int

    init(profile: ProfileStore) {
        self.profile = profile
        let auto = Int((208 - 0.7 * Double(profile.age)).rounded())
        _manual = State(initialValue: profile.hrMaxOverride > 0)
        _overrideBpm = State(initialValue: profile.hrMaxOverride > 0 ? profile.hrMaxOverride : auto)
    }

    /// The Tanaka auto estimate (208 − 0.7·age), shown in Auto and referenced in Manual.
    private var autoBpm: Int { Int((208 - 0.7 * Double(profile.age)).rounded()) }

    // Ronda 3 #1: NO NavigationStack (ver ProfileWheelSheet) — Cancelar/Listo en una barra
    // dentro del VStack que mide `.fittedSheet()`, para que la rueda Manual (que crece) no
    // se recorte en el detent inicial.
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
            HStack {
                Button(String(localized: "Cancel")) { dismiss() }
                    .foregroundStyle(LiquidColor.tinta700)
                Spacer()
                Button(String(localized: "Done")) {
                    profile.hrMaxOverride = manual ? overrideBpm : 0
                    dismiss()
                }
                .foregroundStyle(LiquidColor.tinta900)
            }
            .font(LiquidType.boton)

            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text(String(localized: "Profile"))
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(String(localized: "Max heart rate"))
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }

            Picker(String(localized: "Mode"), selection: $manual) {
                Text(String(localized: "Automatic")).tag(false)
                Text(String(localized: "Manual")).tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: manual) { _, isManual in
                if isManual, overrideBpm == 0 { overrideBpm = autoBpm }
            }

            if manual {
                Picker(String(localized: "Maximum heart rate"), selection: $overrideBpm) {
                    ForEach(100...230, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
                .frame(maxWidth: .infinity)
                Text(String(localized: "Overriding the automatic estimate (\(autoBpm))."))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
            } else {
                VStack(alignment: .center, spacing: LiquidSpace.s100) {
                    Text("\(autoBpm)")
                        .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                    Text(String(localized: "bpm · Tanaka"))
                        .font(LiquidType.clausulaCampo).foregroundStyle(LiquidColor.tinta500)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiquidSpace.s600)
                Text(String(localized: "Estimated from your age (208 − 0.7 × age). Set it manually if you know your true max."))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pantallaFondo()
        .fittedSheet()
    }
}

// MARK: - Units & format (Liquid sheet)

/// «Unidades y formato» — the display-only unit prefs. Nothing stored changes; this only changes
/// how values are shown.
private struct UnidadesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    // Ronda 3 #1: NO NavigationStack (ver ProfileWheelSheet). Aquí no hubo nunca Cancelar —
    // los bindings son vivos (`$unitSystemRaw`/`$temperatureRaw`), solo hay Listo para cerrar.
    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
            HStack {
                Spacer()
                Button(String(localized: "Done")) { dismiss() }
                    .foregroundStyle(LiquidColor.tinta900)
            }
            .font(LiquidType.boton)

            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                Text(String(localized: "Display"))
                    .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
                Text(String(localized: "Units & format"))
                    .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900)
            }
            Text(String(localized: "Your data is always stored the same way: this only changes how distances, weights, heights and temperatures are shown."))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                HStack(spacing: LiquidSpace.s400) {
                    Text(String(localized: "Measurement system")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker(String(localized: "Measurement system"), selection: $unitSystemRaw) {
                        Text(String(localized: "Metric")).tag(UnitSystem.metric.rawValue)
                        Text(String(localized: "Imperial")).tag(UnitSystem.imperial.rawValue)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                LiquidCapilar(eje: .horizontal)
                HStack(spacing: LiquidSpace.s400) {
                    Text(String(localized: "Temperature")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Ronda 2 #11 (revierte una regresión de ronda 1): «Match system»/«Según el
                    // sistema» alargó la etiqueta y reabrió el mismo truncado que un segmentado de
                    // 3 con `.fixedSize()` ya tenía — un menú no trunca y no necesita el hack de
                    // ancho.
                    Picker(String(localized: "Temperature"), selection: $temperatureRaw) {
                        Text(String(localized: "Match system")).tag("")
                        Text("°C").tag(TemperatureUnit.celsius.rawValue)
                        Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                    }
                    .labelsHidden().pickerStyle(.menu).tint(LiquidColor.tinta700)
                }
            }
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pantallaFondo()
        .fittedSheet()
    }
}

#endif
