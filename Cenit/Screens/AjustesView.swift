#if os(iOS)
import SwiftUI
import UIKit             // UIApplication.openSettingsURLString (abrir Ajustes de iOS cuando negó un permiso)
import UserNotifications // UNAuthorizationStatus, para releer el permiso real de enfermedad/descanso
import StrandDesign
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
    /// Mismo contrato para «Vigilar señales de enfermedad»: antes pedía el permiso y se olvidaba de
    /// la respuesta, dejando el switch encendido aunque iOS hubiera negado.
    @State private var illnessPermiso: UNAuthorizationStatus?
    @State private var pidiendoPermisoEnfermedad = false
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @State private var confirmDeleteMedia = false
    @State private var confirmRecalibrate = false
    @State private var profileWheel: ProfileWheel? = nil
    @State private var presentedSheet: AjustesSheetScreen? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s800) {
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
        .background { LiquidSheetFondo().ignoresSafeArea() }
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
            MaxHRSheet().environmentObject(profile)
        }
        .sheet(isPresented: $showCyclePhase) {
            CyclePhaseSheet().environmentObject(repo)
        }
        .sheet(item: $profileWheel) { wheel in
            ProfileWheelSheet(wheel: wheel).environmentObject(profile)
        }
        .sheet(item: $presentedSheet) { screen in sheetContent(screen) }
        // Both confirmations hang here, on the STABLE body of the landing (ScrollView level), not
        // inside the idle-branch Button of `recalibrateRow`: if the confirm lived only in the
        // `else` branch, the swap to the «Deshacer» state would tear down the presenter mid-dismiss.
        .confirmationDialog(
            String(localized: "Recalibrate your recovery?"),
            isPresented: $confirmRecalibrate,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Recalibrate from today"), role: .destructive) { model.recalibrateBaseline() }
            Button(String(localized: "Leave the baseline as is"), role: .cancel) { }
        } message: {
            Text(String(localized: "Your baseline will re-anchor from today and your earlier nights will be ignored. You'll lose your recovery number for a few days while it recalibrates. Your data and history aren't deleted."))
        }
        // El confirm de borrar-media NO puede colgar del mismo view que el de Recalibrar: SwiftUI solo
        // honra un `.confirmationDialog` por vista. Vive en su propio botón (siempre montado en Experimental).
    }

    // MARK: - Header (one-off chrome: wordmark + a privacy line)

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            // FER-176: the wordmark alone, no `gearshape` — Tendencias doesn't repeat its dock glyph
            // next to its title either (`TendenciasGlyph`, not the tab bar's SF Symbol); a tab root
            // doesn't need to echo the icon that got you here.
            Text(String(localized: "Ajustes"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "On this iPhone · no account · no cloud"))
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
            VStack(spacing: 0) {
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

    /// Sex is a segmented `Picker`, not a value+chevron row, so it can't be a `LiquidListRow` — this
    /// hand-builds the same row geometry (padding, bottom hairline) so it seams into the same card.
    private var sexRow: some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(String(localized: "Sex")).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(String(localized: "Sex"), selection: $profile.sex) {
                Text(String(localized: "Male")).tag("male")
                Text(String(localized: "Female")).tag("female")
                Text(String(localized: "Non-binary")).tag("nonbinary")
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
            .accessibilityLabel(String(localized: "Sex"))
        }
        .padding(.vertical, 11)  // token-exempt: paridad fila LiquidListRow (padding interno no público)
        .padding(.horizontal, LiquidSpace.s100)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: 0.5)  // token-exempt: paridad divisor LiquidListRow (no público)
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
        VStack(alignment: .leading, spacing: LiquidSpace.s800) {
            section(String(localized: "App")) {
                VStack(spacing: 0) {
                    LiquidListRow(title: String(localized: "Units & format"), subtitle: unitsSubtitle,
                                  divider: false) { showUnits = true }
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
            section(String(localized: "Data")) {
                VStack(spacing: 0) {
                    LiquidListRow(title: String(localized: "Data Sources"),
                                  subtitle: String(localized: "Apple Health · backup")) { presentedSheet = .dataSources }
                    recalibrateRow
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
            // FER-1021: el interruptor de «vigilar enfermedad» vivía en la difunta AutomationsView
            // (retirada con la banda). El motor sigue vivo y ruteado a Apple (temp de muñeca + FC en
            // reposo nocturna, FER-884); esto le repone el acceso para que la feature sea alcanzable.
            // «Salud» es el nombre de la app de Apple, no de esta sección — «Watch»/«Vigilancia» no
            // se lo roba.
            section(String(localized: "Watch")) {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    Toggle(isOn: Binding(get: { illnessEncendido }, set: { encenderVigilanciaEnfermedad($0) })) {
                        Text(String(localized: "Watch for illness signs"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    .tint(LiquidColor.verdePrimario)
                    .frame(minHeight: 44)
                    // Mismo contrato que `AvisoMatutinoSection`: negado en Ajustes de iOS, el switch
                    // no hace nada (el diálogo del sistema ya no vuelve) — tocable e inerte sería peor
                    // que deshabilitado.
                    .disabled(pidiendoPermisoEnfermedad || illnessNegado)
                    Text(String(localized: "Crosses your wrist temperature and nighttime resting heart rate to warn you early of possible illness. Approximate, not a diagnosis; needs about two weeks of data."))
                        .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                    if illnessNegado {
                        LiquidNotaLine(String(localized: "Notices are off in iOS Settings, so I cannot reach you."),
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
                        // Apagarlo a media sesión tiene que surtir efecto ya, no en la siguiente.
                        if !on { SessionComfort.applyKeepAwake(active: false) }
                    }
                    Text(String(localized: "Between sets two minutes pass without touching anything, and the phone falls asleep right when you pick it up to log. It only applies while the session is open, and it uses more battery: your iPhone goes back to its normal auto-lock when the session ends."))
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
                    VStack(spacing: 0) {
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
                VStack(spacing: 0) {
                    LiquidListRow(title: String(localized: "About & support"),
                                  subtitle: String(localized: "Version \(appVersion) · what Cénit is"),
                                  divider: false) { presentedSheet = .support }
                }
                .liquidTarjetaSeccion(padding: LiquidSpace.s300)
            }
        }
    }

    /// The two experimental toggles (whitespace metrics + exercise-animation download), one card.
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
            LiquidCapilar(eje: .horizontal)
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
            // Nada que borrar hasta que una descarga haya corrido esta sesión: el botón
            // destructivo no vive suelto prometiendo una acción sin caché detrás.
            if mediaCoordinator.downloadState != .idle {
                LiquidCapilar(eje: .horizontal)
                Button(role: .destructive) { confirmDeleteMedia = true } label: {
                    Text(String(localized: "Delete downloaded animations"))
                        .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.negativo)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    String(localized: "Delete all downloaded exercise animations?"),
                    isPresented: $confirmDeleteMedia,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Delete the animations"), role: .destructive) {
                        mediaCoordinator.deleteAllCachedMedia()
                        // El borrado por sí solo no limpia el estado de progreso: sin esto la línea
                        // seguía diciendo «Download complete: X/Y» sobre un caché vacío, y el botón
                        // destructivo se quedaba visible sin nada que borrar.
                        mediaCoordinator.resetDownloadState()
                    }
                    Button(String(localized: "Keep the animations"), role: .cancel) { }
                } message: {
                    Text(String(localized: "Saved animations are deleted from your iPhone. You can re-download them anytime."))
                }
            }
        }
        .liquidTarjetaSeccion()
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
                VStack(alignment: .leading, spacing: 2) {
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
            .padding(.vertical, 11)  // token-exempt: paridad fila LiquidListRow (padding interno no público)
            .padding(.horizontal, LiquidSpace.s100)
        } else {
            // Recalibrar es una ACCIÓN (abre un confirm), no navegación: fila a mano con el ícono
            // `arrow.clockwise` del original, no un `LiquidListRow` (cuyo chevron prometería empujar a
            // otra pantalla). Misma geometría de fila que la rama «Deshacer».
            Button { confirmRecalibrate = true } label: {
                HStack(spacing: LiquidSpace.s300) {
                    VStack(alignment: .leading, spacing: 2) {
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
                .padding(.vertical, 11)  // token-exempt: paridad fila LiquidListRow (padding interno no público)
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
                 : String(localized: "Download complete: \(matched)/\(total) exercises with video."))
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
    // Both switches follow the same contract as `AvisoMatutinoSection`: the system permission is
    // requested the instant the switch turns ON (never at launch, never mid-session); if iOS denies
    // it the switch shows OFF and disabled with a note + an «Open Settings» deep-link, instead of
    // staying lit and promising a notice that will never arrive; and the real permission is reread
    // whenever the app returns to the foreground, so granting it in iOS Settings and coming back is
    // reflected here instead of staying frozen on stale state.

    /// The illness-watch switch only shows ON when the preference AND the real permission agree.
    private var illnessEncendido: Bool {
        guard behavior.illnessWatch else { return false }
        guard let illnessPermiso else { return true }
        return illnessPermiso == .authorized
    }
    private var illnessNegado: Bool {
        guard behavior.illnessWatch, let illnessPermiso else { return false }
        return illnessPermiso == .denied
    }
    private func encenderVigilanciaEnfermedad(_ on: Bool) {
        guard on else {
            behavior.illnessWatch = false
            model.reevaluateIllness()
            return
        }
        pidiendoPermisoEnfermedad = true
        Task {
            var estado = await IllnessNotifier.authorizationStatus()
            if estado == .notDetermined {
                _ = await IllnessNotifier.requestAuthorization()
                estado = await IllnessNotifier.authorizationStatus()
            }
            illnessPermiso = estado
            behavior.illnessWatch = true
            pidiendoPermisoEnfermedad = false
            model.reevaluateIllness()
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
                    .toolbarBackground(LiquidColor.papelAlto, for: .navigationBar)
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
                    .toolbarBackground(LiquidColor.papelAlto, for: .navigationBar)
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
/// preference (the wheel itself shows lb / ft·in and writes the SI equivalent back). Stored data
/// is unchanged; only how it's entered.
private struct ProfileWheelSheet: View {
    let wheel: ProfileWheel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profile: ProfileStore
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
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
        .background { LiquidSheetFondo().ignoresSafeArea() }
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
            Picker(String(localized: "Age"), selection: $profile.age) {
                ForEach(13...100, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
        case .weight:
            if unitSystem == .imperial {
                let pounds = Binding<Double>(
                    get: { UnitFormatter.kgToPounds(profile.weightKg) },
                    set: { profile.weightKg = UnitFormatter.poundsToKg($0) })
                let opts = Array(stride(from: 66.0, through: 551.0, by: 1))
                let lb = snapped(pounds, options: opts)
                Picker(String(localized: "Weight in pounds"), selection: lb) {
                    ForEach(opts, id: \.self) { Text("\(Int($0)) lb").tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            } else {
                let opts = Array(stride(from: 30.0, through: 250.0, by: 0.5))
                let kg = snapped($profile.weightKg, options: opts)
                Picker(String(localized: "Weight in kilograms"), selection: kg) {
                    ForEach(opts, id: \.self) { Text(String(format: "%.1f kg", $0)).tag($0) }
                }
                .pickerStyle(.wheel).labelsHidden().tint(LiquidColor.tinta900)
            }
        case .height:
            if unitSystem == .imperial {
                let inchesValue = Binding<Double>(
                    get: { UnitFormatter.cmToInches(profile.heightCm).rounded() },
                    set: { profile.heightCm = $0 * UnitFormatter.centimetersPerInch })
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
                let cm = snapped($profile.heightCm, options: opts)
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
/// override (and notes it's anulando the auto estimate).
private struct MaxHRSheet: View {
    @EnvironmentObject private var profile: ProfileStore
    /// Local mode toggle. Drives the override: Auto → 0; Manual → keep/seed a concrete bpm.
    @State private var manual = false

    /// The Tanaka auto estimate (208 − 0.7·age), shown in Auto and referenced in Manual.
    private var autoBpm: Int { Int((208 - 0.7 * Double(profile.age)).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
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
                if isManual { if profile.hrMaxOverride == 0 { profile.hrMaxOverride = autoBpm } }
                else { profile.hrMaxOverride = 0 }
            }

            if manual {
                Picker(String(localized: "Maximum heart rate"), selection: $profile.hrMaxOverride) {
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
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .fittedSheet()
        .onAppear { manual = profile.hrMaxOverride > 0 }
    }
}

// MARK: - Units & format (Liquid sheet)

/// «Unidades y formato» — the display-only unit prefs. Nothing stored changes; this only changes
/// how values are shown.
private struct UnidadesSheet: View {
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s600) {
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
                    Picker(String(localized: "Temperature"), selection: $temperatureRaw) {
                        Text(String(localized: "Match system")).tag("")
                        Text("°C").tag(TemperatureUnit.celsius.rawValue)
                        Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        }
        .padding(LiquidSpace.s600)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        .fittedSheet()
    }
}

#endif
