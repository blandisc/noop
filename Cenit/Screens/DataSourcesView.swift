import SwiftUI
import UniformTypeIdentifiers
import CenitDesign
import CenitStore
import StrandAnalytics
import StrandTraining
#if os(iOS)
import HealthKit   // HKAuthorizationStatus, for the write-back permission tally
import UIKit       // UIApplication.openSettingsURLString
import StrandImport
#endif

// MARK: - Fuentes de datos — Liquid Glass · El Eje (FER-108)
//
// Hoja Liquid Glass · El Eje (familia FER-104 / Compare·Explore): `LiquidSheetFondo`, overlines
// inset (`bloque`), tarjetas `liquidTarjetaSeccion`, filas `LiquidChecklistRow`/`LiquidListRow`,
// acciones `LiquidGlassButton`. Solo piel: importers, sync Apple Health, cobertura, backup/
// restore e iCloud auto-backup intactos.
//
// Color = identidad (FER-108): checklist vía `MetricIdentity.identity(forIngestKey:)` +
// `MetricCatalog.descriptor(forIngestKey:)?.canonicalTitle` — nunca `identity(forKey:)` sobre
// una ingest key cruda. Apple Health por-fuente sigue en `NavigationLink { AppleHealthView() }`
// dentro del NavigationStack que monta cada caller.

struct DataSourcesView: View {
    @Environment(AppModel.self) var model
    @EnvironmentObject var repo: Repository
    @State private var showingImporter = false
    @State private var importTarget: ImportTarget = .appleHealth
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    // Live two-way Apple Health. Injected by CenitApp.
    @EnvironmentObject private var health: HealthKitBridge
    @State private var hkBusy = false
    /// Opt-in mirror of finished strength sessions into Apple Health (FER-390). Off by default.
    @AppStorage(HealthKitBridge.saveStrengthWorkoutsKey) private var saveStrengthWorkouts = false
    /// FER-742: opt-in — record the strength session on the paired Apple Watch (real HR + calories, closes
    /// the rings). Off by default; the row only appears when a watch is paired.
    @AppStorage(WorkoutMirroringBridge.mirrorToWatchKey) private var recordOnWatch = false
    #if DEBUG
    /// FER-1008 spike (dev-only, never in a store build): export Apple's nocturnal beat-to-beat R-R so a
    /// nocturnal Apple RMSSD can be validated against the strap on paired nights.
    @State private var exportingHeartbeats = false
    @State private var heartbeatSummary: String?
    #endif
    #endif

    // Backup & restore + automatic iCloud backup — migrated here from SettingsView for FER-337 so no
    // content is orphaned when the old Settings screen goes away.
    @State private var backupBusy = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var showBackupAlert = false
    @State private var backupAlertIsError = false
    #if os(iOS)
    @EnvironmentObject private var autoBackup: AutoBackup
    #endif

    /// FER-224: strength-training history export to CSV (Hevy-parity gap). Separate from
    /// full-data Backup/Restore above — this is a human-readable spreadsheet, not a restore file.
    @State private var strengthCSVBusy = false
    @State private var strengthCSVError = false
    /// FER-333 · E9: Strong/Hevy/Cénit CSV import sheet (4 steps).
    @State private var showStrengthCSVImport = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s800) {
                header
                importSection
                appleHealthSection
                #if os(iOS)
                coverageSection
                backupSection
                #endif
            }
            .padding(.horizontal, LiquidSpace.s550)
            .padding(.top, LiquidSpace.s550)
            .padding(.bottom, LiquidSpace.s800)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background { LiquidSheetFondo().ignoresSafeArea() }
        // A single target-aware importer avoids SwiftUI collapsing competing importers on the same screen.
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: importTarget.allowedContentTypes,
                      allowsMultipleSelection: false) { result in
            handleImportResult(result, for: importTarget)
        }
        // FER-837 / FER-280·2c: backup/export result → `LiquidAviso` (receta HealthAlert);
        // inset, tap-to-dismiss y auto-descarte de 8 s quedan en el caller.
        .overlay(alignment: .top) {
            if showBackupAlert {
                LiquidAviso(
                    titulo: backupAlertTitle,
                    cuerpo: backupAlertMessage,
                    tono: backupAlertIsError ? LiquidColor.negativo : LiquidColor.positivo)
                    .padding(.horizontal, LiquidSpace.s550)
                    .padding(.top, LiquidSpace.s300)
                    .onTapGesture { showBackupAlert = false }
                    .transition(LiquidMotion.fallingFadeTransition)
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        showBackupAlert = false
                    }
            }
        }
        .animation(LiquidMotion.glassOut(LiquidMotion.quick), value: showBackupAlert)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(String(localized: "Sources"))
                .font(LiquidType.cabeceraEstante).tracking(LiquidType.cabeceraEstanteTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Data Sources"))
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "Everything stays on this iPhone. Bring your history in once, then it's yours."))
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Section scaffolding (inset overline, Compare's `bloque` pattern)

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(verbatim: title)
                .font(LiquidType.franja).tracking(LiquidType.franjaTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A quiet block on the bare screen ground: a title + supporting copy, no surface. Import and the
    /// checklist-adjacent notes stay on the paper (the mock's `bloque-plano`); grouped content gets a
    /// card via `blockCard` below.
    @ViewBuilder
    private func blockPlano<Content: View>(_ title: String, subtitle: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(verbatim: title).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
            Text(verbatim: subtitle).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    /// Same title+subtitle block, floated on its own `liquidTarjetaSeccion` card (backup & restore,
    /// automatic iCloud backup).
    @ViewBuilder
    private func blockCard<Content: View>(_ title: String, subtitle: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        blockPlano(title, subtitle: subtitle, content: content)
            .liquidTarjetaSeccion()
    }

    private var capilar: some View { LiquidCapilar(eje: .horizontal) }

    // MARK: - Importar (Apple Health .zip)

    private var importSection: some View {
        section(String(localized: "Import")) {
            appleHealthImportBlock
            #if os(iOS)
            strengthHistoryImportBlock
            #endif
        }
    }

    private var appleHealthImportBlock: some View {
        let importingAppleHealth = model.isImporting(.appleHealth)
        return blockPlano(
            String(localized: "Apple Health Export"),
            subtitle: String(localized: "Import an Apple Health export (Health app → profile → Export All Health Data → export.zip). 7 years of HR, HRV, sleep, SpO₂, steps and more: streamed locally. Large exports take a minute or two.")) {
            HStack(spacing: LiquidSpace.s300) {
                LiquidGlassButton(importingAppleHealth ? String(localized: "Working…") : String(localized: "Choose export.zip…"),
                                  variant: .glass) { presentImporter(.appleHealth) }
                    .disabled(model.hasActiveImport)
                    .opacity(model.hasActiveImport ? 0.6 : 1)
                if importingAppleHealth {
                    ProgressView().controlSize(.small).tint(LiquidColor.tinta500)
                    if let n = model.appleHealthImportProgress {
                        Text("\(n) records").font(LiquidType.unidadCompacta)
                            .foregroundStyle(LiquidColor.tinta500)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            if let s = model.appleHealthImportSummary {
                // A failed import is a WARNING, not a crash: `atencionTexto` (the ámbar the paper's
                // `theme.warning` used), never `negativo` (critical). FER-108 · Grok.
                Text(verbatim: s).font(LiquidType.captionLectura)
                    .foregroundStyle(model.appleHealthImportFailed ? LiquidColor.atencionTexto : LiquidColor.positivo)
            }
            // FER-115: coverage grid — macOS only (iOS shows it in its own «Cobertura» section)
            #if !os(iOS)
            if !repo.days.isEmpty || !repo.appleHealthDays.isEmpty {
                capilar
                coverageBodyView
            }
            #endif
        }
    }

    #if os(iOS)
    /// FER-333 · E9: segundo bloque bajo Apple Health — historial Strong/Hevy/Cénit (CSV).
    private var strengthHistoryImportBlock: some View {
        blockPlano(
            String(localized: "Strong or Hevy history (CSV)"),
            subtitle: String(localized: "Bring your lifting history from Strong or Hevy. Cénit reads the CSV on this iPhone. Nothing leaves your phone.")) {
            HStack(spacing: LiquidSpace.s300) {
                LiquidGlassButton(String(localized: "Import history…"), variant: .glass) {
                    showStrengthCSVImport = true
                }
                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $showStrengthCSVImport) {
            StrengthHistoryImportSheet(
                onComplete: { },
                // QA D4: ninguna de las dos tiene ruta hoy — `DataSourcesView()` se construye sin
                // parámetros en sus tres call sites (CuerpoView/AjustesView/TodayView) y ninguno le
                // pasa un coordinador de navegación hacia Historial o el planificador de semana.
                // Cablearla exigiría un closure nuevo en 3+ archivos fuera del hunk de este issue;
                // se deja documentado en vez de improvisar una ruta. «Listo» sigue siendo la salida.
                onOpenHistory: nil,
                onArmWeek: nil)
                .environmentObject(repo)
                .preferredColorScheme(.light)
        }
    }
    #endif

    // MARK: - Apple Health (live sync + permissions + "View imported data")

    private var appleHealthSection: some View {
        #if os(iOS)
        section(String(localized: "Apple Health")) { appleHealthLiveBody }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    /// iOS-only: connect + drive the live two-way Apple Health sync, and surface what it did. Beyond
    /// the connect/sync control it shows live per-stage progress, a coverage summary (days + span), a
    /// per-metric "what landed" list, a Settings deep-link, and the link to the per-source viewer. (FER-70)
    @ViewBuilder
    private var appleHealthLiveBody: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(String(localized: "Sync the last few weeks, on-device: Cénit reads your Apple Health HR, HRV, sleep, SpO₂ and steps. Nothing leaves your iPhone; your strength workouts are saved back to Apple Health when you allow it. (For a one-time bulk history, use the export import above.)"))
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)

            switch health.auth {
            case .unavailable:
                Text(String(localized: "Apple Health isn’t available on this device."))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
            case .authorized:
                appleHealthAuthorizedBody
            case .unknown, .denied:
                appleHealthConnectBody
            }
            if let err = health.lastError {
                // A HealthKit error is a warning to surface, not a critical alarm (paper: theme.warning).
                LiquidNotaLine(err, tono: LiquidColor.atencionTexto)
            }

            strengthWorkoutToggle
            watchRecordingRow

            // Reachability for the per-source Apple Health viewer. Pushed within this screen's
            // NavigationStack — «Ver datos importados ›».
            appleHealthNavRow
        }
        // Load coverage + write permissions on appear so opening the screen shows "X days imported"
        // and the per-metric list without forcing a re-import first.
        .task { await health.refreshStatus() }
        // FER-742: recompute paired-watch availability so the «Grabar en el Apple Watch» row shows its
        // right state (hidden / disabled+nudge / on) as soon as the screen opens.
        .task { model.refreshWatchPairing() }
    }

    /// FER-742: opt-in — record the strength session on the paired Apple Watch (real HR + calories, closes
    /// the rings). Hidden without a paired watch; disabled with an install nudge when the watch has no
    /// Cénit app. Enabling it requests the same workout-share scope as the neighbor toggle.
    @ViewBuilder
    private var watchRecordingRow: some View {
        if model.watchPaired {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Toggle(isOn: $recordOnWatch) {
                    VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                        Text(String(localized: "Record on Apple Watch"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                        Text(String(localized: "When you start a strength session, your watch records real heart rate and calories and closes your rings. It replaces the estimated save for that session."))
                            .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(LiquidColor.verdePrimario)
                .disabled(!model.watchAppInstalled)
                .onChange(of: recordOnWatch) { _, on in
                    if on { Task { await health.requestWorkoutShareAuthorization() } }
                }
                if !model.watchAppInstalled {
                    LiquidNotaLine(String(localized: "Install Cénit on your watch from the Watch app."),
                                  tono: LiquidColor.atencionTexto)
                }
            }
            .liquidTarjetaSeccion()
        }
    }

    /// Opt-in: write finished strength sessions to Apple Health as workouts so they show in Health /
    /// Fitness and (via estimated active energy) count toward the iPhone's Move ring — no Apple Watch
    /// needed (FER-390). Off by default; flipping it on requests only the workout + active-energy
    /// share, independent of the main sync connection above.
    private var strengthWorkoutToggle: some View {
        Toggle(isOn: $saveStrengthWorkouts) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(String(localized: "Save workouts to Apple Health"))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                Text(String(localized: "Your strength sessions appear in Health and count toward your Move ring, with estimated calories."))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(LiquidColor.verdePrimario)
        .disabled(health.auth == .unavailable)
        .onChange(of: saveStrengthWorkouts) { _, on in
            if on { Task { await health.requestWorkoutShareAuthorization() } }
        }
        .liquidTarjetaSeccion()
    }

    /// «Ver datos importados ›» — the ONE door to `AppleHealthView`, unchanged (destination-closure
    /// `NavigationLink`, no `.navigationDestination(for:)` rewrite). `LiquidListRow` renders bare (no
    /// `action:`) so it composes as a plain label inside the link, its own dot + chevron doing the
    /// affordance work the mock shows.
    private var appleHealthNavRow: some View {
        NavigationLink {
            AppleHealthView()
        } label: {
            LiquidListRow(
                title: String(localized: "View imported data"),
                tone: health.auth == .authorized ? LiquidColor.verdePrimario : LiquidColor.tinta500,
                divider: false)
        }
        .buttonStyle(.plain)
        .liquidTarjetaSeccion(padding: LiquidSpace.s300)
    }

    /// Authorized: the sync/reimport control, then either live progress (mid-sync) or the coverage
    /// summary + per-metric status of what has been imported.
    @ViewBuilder
    private var appleHealthAuthorizedBody: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(health.syncing ? String(localized: "Syncing…") : String(localized: "Sync now"),
                              variant: .primary) { Task { await health.sync() } }
                .disabled(health.syncing)
                .opacity(health.syncing ? 0.6 : 1)
            Spacer(minLength: 0)
        }

        #if DEBUG
        // DEV (FER-1008 spike): vuelca los latidos nocturnos que Apple guardó en HealthKit para medir un
        // RMSSD de Apple contra la banda en noches pareadas. One-shot, pide su propio permiso, no toca la
        // DB ni el sync. Gateado a DEBUG: nunca llega a una build de tienda.
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            LiquidGlassButton(exportingHeartbeats ? "Exportando latidos…" : "Exportar latidos de Apple (dev)",
                              variant: .glass) {
                Task {
                    exportingHeartbeats = true
                    let (csv, summary) = await health.exportAppleHeartbeatSeries()
                    heartbeatSummary = summary
                    exportingHeartbeats = false
                    FileExport.exportText(csv, suggestedName: "apple-rr.csv")
                }
            }
            .disabled(exportingHeartbeats)
            .opacity(exportingHeartbeats ? 0.6 : 1)
            if let s = heartbeatSummary {
                Text(verbatim: s).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #endif

        if health.syncing {
            appleHealthSyncProgress
        } else {
            appleHealthCoverageSection
            appleHealthMetricList
            if let at = health.lastSync {
                Text(String(localized: "Last synced \(at.formatted(.relative(presentation: .named)))"))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
            }
        }
        appleHealthPermissionsFooter
    }

    /// Not connected yet (or declined): the connect button, plus a Settings path when declined.
    @ViewBuilder
    private var appleHealthConnectBody: some View {
        HStack(spacing: LiquidSpace.s300) {
            LiquidGlassButton(hkBusy ? String(localized: "Connecting…") : String(localized: "Connect Apple Health"),
                              variant: .primary) {
                Task {
                    hkBusy = true
                    await health.requestAuthorization()
                    if health.auth == .authorized { await health.sync() }
                    hkBusy = false
                }
            }
            .disabled(hkBusy)
            .opacity(hkBusy ? 0.6 : 1)
            if hkBusy { ProgressView().controlSize(.small).tint(LiquidColor.tinta500) }
            Spacer(minLength: 0)
        }
        if health.auth == .denied {
            LiquidNotaLine(String(localized: "Apple Health access was declined. Enable it in Settings › Privacy & Security › Health › Cénit."),
                           tono: LiquidColor.atencionTexto)
            settingsButton
        }
    }

    /// Live, per-stage progress while `sync` runs: a tinted dot + "Importing Apple Health…", plus
    /// "Importing HRV… · 4/12" when a stage is known, so a long pull reads as in-progress.
    @ViewBuilder
    private var appleHealthSyncProgress: some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            Circle()
                .fill(LiquidColor.verdePrimario)
                .frame(width: 8, height: 8)
                .padding(.top, LiquidSpace.s125)
                .liquidShadow([.init(color: LiquidColor.verdePrimario.opacity(0.35), radius: 4, y: 0)],  // token-exempt(optico): mismo glow que el punto de LiquidListRow (tone.opacity(0.35))
                              silhouette: Circle())
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(String(localized: "Importing Apple Health…"))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                if let p = health.syncProgress {
                    Text(verbatim: "\(Self.stageLabel(p.stageKey)) · \(p.done)/\(p.total)")
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                        .monospacedDigit()
                }
            }
        }
    }

    /// "Imported history" coverage summary (days + date span) as a glass chip, or a nudge when
    /// nothing has landed.
    @ViewBuilder
    private var appleHealthCoverageSection: some View {
        if let cov = health.coverage, cov.totalDays > 0 {
            HStack(spacing: LiquidSpace.s150) {
                ZStack {
                    Circle().fill(LiquidColor.verdePrimario)
                    Image(systemName: "checkmark")
                        .font(LiquidType.iconSF(size: 12))
                        .foregroundStyle(LiquidColor.tintaSobreVerde)
                }
                .frame(width: 16, height: 16)
                Text(verbatim: "\(String(localized: "Imported history")) · \(Self.coverageSummaryText(cov))")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
            }
            .padding(.leading, LiquidSpace.s075)
            .padding(.trailing, LiquidSpace.s300)
            .padding(.vertical, LiquidSpace.s075)
            // Opaque pill: this screen is a SHEET (paper), so no translucent glass inside it
            // (design-lint `no-sheet-glass`). `.pastillaSolida` is the solid paper variant.
            .liquidGlass(.pastillaSolida)
            .accessibilityElement(children: .combine)
        } else {
            Text(String(localized: "No Apple Health data imported yet: tap Sync now to pull your recent history."))
                .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
        }
    }

    /// Per-metric "what landed" checklist: ✓ + day count for metrics that imported, an empty ring +
    /// «—» for those that didn't (no data, or a read scope the user didn't grant — HealthKit hides
    /// which, so this shows the honest observable: whether days arrived). FER-108 cimientos: hue and
    /// name resolve through the ingest-key bridge, never `identity(forKey:)` on the raw ingest key.
    @ViewBuilder
    private var appleHealthMetricList: some View {
        let cov = health.coverage
        VStack(spacing: .zero) {
            ForEach(Self.metricKeys, id: \.self) { key in
                let days = cov?.daysByMetric[key]
                let has = days != nil
                let title = MetricCatalog.descriptor(forIngestKey: key)?.canonicalTitle ?? key
                let hue = MetricIdentity.identity(forIngestKey: key).hue
                HStack(alignment: .top, spacing: LiquidSpace.s200) {
                    LiquidChecklistRow(etiqueta: title, presente: has, tono: hue)
                    Text(verbatim: has ? "\(days!) d" : "—")
                        .font(LiquidType.unidadCompacta)
                        .foregroundStyle(LiquidColor.tinta500)
                        .monospacedDigit()
                        .padding(.top, LiquidSpace.s150)
                }
            }
        }
        .liquidTarjetaSeccion()
    }

    /// Metrics shown in the per-metric status list, in display order — INGEST keys (what
    /// `HealthKitBridge` writes and `AppleHealthCoverage.daysByMetric` is keyed by). Coherent with the
    /// SQL in `appleHealthCoverage`: every key counted there is listed here, and vice versa (FER-192
    /// added `skin_temp` — imported at HealthKitBridge stage 10 and consumed by the illness/cycle-phase
    /// engines, but invisible in this checklist until now — and `avg_hr`, already counted but not shown).
    private static let metricKeys: [String] = [
        "hrv", "resting_hr", "avg_hr", "asleep_min", "spo2", "resp_rate", "skin_temp",
        "steps", "active_kcal", "vo2max",
    ]

    /// Permissions affordance: a one-line write-back tally (the status HealthKit *does* expose
    /// reliably) plus a deep link to Settings to grant any missing scope, then Sync again.
    @ViewBuilder
    private var appleHealthPermissionsFooter: some View {
        let writes = health.writePermissions
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            if !writes.isEmpty {
                let granted = writes.filter { $0.status == .sharingAuthorized }.count
                Text(String(localized: "Write-back to Apple Health: \(granted)/\(writes.count) enabled"))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
            }
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button { openSystemSettings() } label: {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: "gearshape")
                    .font(LiquidType.iconSF(size: 13)).foregroundStyle(LiquidColor.tinta700)
                Text(String(localized: "Manage Apple Health permissions"))
                    .font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta700)
            }
        }
        .buttonStyle(.liquidPress)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Stage key → localized label for the live progress line. Keys come from `HealthKitBridge`. A
    /// metric stage reads the ONE canonical name (`canonicalTitle` via the ingest-key bridge), so the
    /// sync line never says «Resting heart rate» beside a checklist row that says «Resting HR» — one
    /// name everywhere (FER-108 · Grok). The non-metric stages (sleep maps to its metric; basal energy
    /// / workouts / saving have no catalog metric) keep their own label.
    private static func stageLabel(_ key: String) -> String {
        switch key {
        case "sleep":      return MetricCatalog.descriptor(forIngestKey: "asleep_min")?.canonicalTitle ?? String(localized: "Sleep")
        case "basal_kcal": return String(localized: "Energy")
        case "workouts":   return String(localized: "Workouts")
        case "saving":     return String(localized: "Saving…")
        default:           return MetricCatalog.descriptor(forIngestKey: key)?.canonicalTitle ?? String(localized: "Apple Health")
        }
    }

    // Coverage span is stored as "yyyy-MM-dd" (UTC); parse with the shared parser, display in the user's
    // locale ("12 May" / "12 may").
    private static let shortDate: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    private static func coverageSummaryText(_ cov: AppleHealthCoverage) -> String {
        guard let fs = cov.firstDay, let ls = cov.lastDay,
              let f = Repository.parseDayKey(fs), let l = Repository.parseDayKey(ls) else {
            return "\(cov.totalDays) d"
        }
        return "\(shortDate.string(from: f)) → \(shortDate.string(from: l)) · \(cov.totalDays) d"
    }
    #endif

    // MARK: - Cobertura (30-day grid + sources summary) — iOS

    #if os(iOS)
    @ViewBuilder
    private var coverageSection: some View {
        // Hide the whole section when there's nothing to show: no strap days, and Apple Health is
        // denied/unavailable or has imported nothing (mirrors the dark screen's guards).
        let healthAccessible = health.auth != .denied && health.auth != .unavailable
        // FER-485: coverage is diagnostic — it reads the STORED day sets (unfiltered by the mode), so it
        // shows what's on the iPhone regardless of the app's current data-source filter.
        let showsCoverage = !repo.storedStrapDays.isEmpty || (!repo.storedAppleOnlyDays.isEmpty && healthAccessible)
        if showsCoverage || sourcesHasContent {
            section(String(localized: "Coverage")) {
                if showsCoverage {
                    coverageBodyView.liquidTarjetaSeccion()
                }
                if sourcesHasContent {
                    sourcesSummary
                }
            }
        }
    }
    #endif

    /// Summary line + 6×5 grid + legend (the leading section overline already names the block, so this
    /// body opens straight on the summary line).
    ///
    /// FER-192: Cénit is Apple-only (AXIOMA cero-banda — no real user ever had the strap). Coverage
    /// used to split into "on-device" (strap) vs "Apple Health only" swatches/legend/summary — band
    /// vocabulary nobody on a real device can trigger, and a false choice ("only" compared to what?).
    /// It now reads as ONE source, Apple Health: days WITH data vs days WITHOUT. `storedStrapDays`
    /// keeps existing as harmless historical plumbing (empty for every real user, proof of the
    /// «nothing is deleted» invariant if it's ever non-empty) — it's folded into the same "with data"
    /// set instead of getting its own color/label.
    @ViewBuilder
    private var coverageBodyView: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days30: [String] = (0..<30).reversed().compactMap { offset in
            cal.date(byAdding: .day, value: -offset, to: today).map { Repository.localDayKey($0) }
        }
        let withData = repo.storedStrapDays.union(repo.storedAppleOnlyDays)   // FER-485: stored coverage, unfiltered by the mode
        let withDataCount = days30.filter { withData.contains($0) }.count
        let emptyCount = 30 - withDataCount
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(coverageSummaryString(withData: withDataCount))
                .font(LiquidType.cuerpo)
                .foregroundStyle(withDataCount > 0 ? LiquidColor.tinta700 : LiquidColor.tinta500)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LiquidSpace.s100), count: 6),
                      spacing: LiquidSpace.s100) {
                ForEach(Array(days30.enumerated()), id: \.offset) { _, day in
                    Group {
                        if withData.contains(day) {
                            RoundedRectangle(cornerRadius: 4).fill(LiquidColor.azul)  // token-exempt(dato): geometría de dato
                        } else {
                            RoundedRectangle(cornerRadius: 4)  // token-exempt(dato): geometría de dato
                                .fill(LiquidColor.tinta7)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(LiquidColor.tinta10, lineWidth: 0.5))  // token-exempt(dato): geometría de dato (filo de celda vacía, paridad LiquidCalendario90)
                        }
                    }
                    .frame(height: 30)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(coverageA11yLabel(withData: withDataCount, empty: emptyCount))
            coverageLegendView(hasData: withDataCount > 0)
        }
    }

    private func coverageSummaryString(withData: Int) -> String {
        if withData == 0 { return String(localized: "No data in the last 30 days") }
        return String(localized: "\(withData) of 30 days with data")
    }

    private func coverageA11yLabel(withData: Int, empty: Int) -> String {
        String(localized: "Data coverage for the last 30 days: \(withData) days with data, \(empty) days with no data.")
    }

    /// Flow-laid legend (`LiquidFlujoLeyenda`): each peldaño keeps the swatch geometry of the canonical
    /// `LiquidCalendario90` legend, and dims to 30% when it contributed nothing this window — the same
    /// "inactive" signal the mock's `.legend-item.inactive` shows.
    private func coverageLegendView(hasData: Bool) -> some View {
        LiquidFlujoLeyenda(espacioH: LiquidSpace.s400, espacioV: LiquidSpace.s200) {
            coverageLegendItem(color: LiquidColor.azul, label: "With data", active: hasData)
            coverageLegendItem(color: LiquidColor.tinta7, label: "No data", active: true)
        }
    }

    private func coverageLegendItem(color: Color, label: LocalizedStringKey, active: Bool) -> some View {
        HStack(spacing: LiquidSpace.s125) {
            // Swatch geometry: `LiquidCalendario90.radioSwatch`/`.swatchLado` aren't `public`, so this
            // matches their values (2 / s200) directly rather than reaching into the package internals.
            RoundedRectangle(cornerRadius: 2, style: .continuous)  // token-exempt(dato): paridad LiquidCalendario90.radioSwatch (no público)
                .fill(color)
                .frame(width: LiquidSpace.s200, height: LiquidSpace.s200)
            Text(label).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
        }
        .opacity(active ? 1.0 : 0.3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sources summary (reskinned inline — was the dark `SourcesSummaryCard`)

    /// True when there's a source line worth showing (mirrors `SourcesSummaryCard`).
    private var sourcesHasContent: Bool {
        !repo.storedStrapDays.isEmpty || !repo.storedAppleOnlyDays.isEmpty
    }

    /// The compact "Sources" rollup. FER-192: Cénit is Apple-only, so this is ONE row — Apple Health ·
    /// N days — not a per-source split, and the day count is the SAME unit the coverage card above
    /// uses (days), never sleeps-vs-workouts (an old defect: the strap row counted sleep SESSIONS
    /// while its Apple sibling counted WORKOUT sessions, two incomparable units dressed as parallel
    /// rows). `storedStrapDays` is folded into the same day count instead of getting its own row —
    /// it's empty for every real user (AXIOMA cero-banda), and this way an empty case just shows 0
    /// extra rows rather than a phantom "on-device" source.
    @ViewBuilder
    private var sourcesSummary: some View {
        let days = repo.storedStrapDays.union(repo.storedAppleOnlyDays).count
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            sourceRow(name: String(localized: "Apple Health"),
                      count: days == 1 ? String(localized: "\(days) day") : String(localized: "\(days) days"),
                      tint: LiquidColor.azul)
        }
    }

    /// One source rollup row: brand name (ink) · tabular count tinted in the source's data hue (the
    /// count is the measured datum).
    private func sourceRow(name: String, count: String, tint: Color) -> some View {
        HStack(spacing: LiquidSpace.s250) {
            Text(verbatim: name).font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
            Spacer(minLength: LiquidSpace.s200)
            Text(verbatim: count).font(LiquidType.valorS).monospacedDigit().foregroundStyle(tint)
        }
    }

    // MARK: - Import plumbing (unchanged)

    private func presentImporter(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }

    private func handleImportResult(_ result: Result<[URL], Error>, for target: ImportTarget) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch target {
        case .appleHealth:
            model.importAppleHealth(url: url)
        }
    }

    private enum ImportTarget {
        case appleHealth

        var allowedContentTypes: [UTType] {
            switch self {
            case .appleHealth:
                return [.zip, .xml, .folder]
            }
        }
    }

    // MARK: - Respaldo (backup/restore + CSV + iCloud auto) — iOS

    #if os(iOS)
    private var backupSection: some View {
        section(String(localized: "Backup")) {
            backupBlock
            autoBackupBlock
            strengthCSVBlock
        }
    }

    /// FER-224: exports the strength-training history as a CSV spreadsheet — one row per logged set,
    /// exercise by name, readable outside Cénit (Excel/Numbers/Sheets). Distinct from the full-data
    /// Backup above, which is a restore-only file, not meant to be opened by a human.
    private var strengthCSVBlock: some View {
        blockCard(
            String(localized: "Export strength history (CSV)"),
            subtitle: String(localized: "Save every logged set: date, routine, exercise, weight, reps and notes, in a spreadsheet file you can open outside Cénit.")) {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                HStack(spacing: LiquidSpace.s300) {
                    LiquidGlassButton(strengthCSVBusy ? String(localized: "Exporting…") : String(localized: "Export CSV…"),
                                      variant: .glass) { runStrengthCSVExport() }
                        .disabled(strengthCSVBusy)
                        .opacity(strengthCSVBusy ? 0.6 : 1)
                    if strengthCSVBusy { ProgressView().controlSize(.small).tint(LiquidColor.tinta500) }
                    Spacer(minLength: 0)
                }
                if strengthCSVError {
                    LiquidNotaLine(String(localized: "The export couldn't be saved. Try again."), tono: LiquidColor.negativo)
                }
            }
        }
    }

    private var backupBlock: some View {
        blockCard(
            String(localized: "Backup & restore"),
            subtitle: String(localized: "Move all your Cénit data to another device. Export saves everything to one file you can copy across; import replaces this device's data with a backup.")) {
            VStack(alignment: .leading, spacing: LiquidSpace.s400) {
                HStack(spacing: LiquidSpace.s300) {
                    LiquidGlassButton(String(localized: "Export…"), variant: .glass) { runExport() }
                        .disabled(backupBusy).opacity(backupBusy ? 0.6 : 1)
                    LiquidGlassButton(String(localized: "Import…"), variant: .glass) { runImport() }
                        .disabled(backupBusy).opacity(backupBusy ? 0.6 : 1)
                    if backupBusy { ProgressView().controlSize(.small).tint(LiquidColor.tinta500) }
                    Spacer(minLength: 0)
                }
                capilar
                LiquidNotaLine(String(localized: "Importing overwrites everything currently in Cénit. Your old data is kept in a side file just in case, and Cénit needs a relaunch for an import to take effect."))
            }
        }
    }

    private var autoBackupBlock: some View {
        blockCard(
            String(localized: "Automatic iCloud backup"),
            subtitle: String(localized: "Pick a folder in iCloud Drive and Cénit keeps a fresh copy of all your data there. Your history lives only inside the app, so this is what protects it if you reinstall Cénit or switch phones. A free Apple ID is enough.")) {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                if let name = autoBackup.destinationName {
                    HStack(spacing: LiquidSpace.s150) {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(LiquidType.iconSF(size: 15)).foregroundStyle(LiquidColor.positivo)
                        Text(String(localized: "Backing up to \(name)"))
                            .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta900)
                    }
                    Text(verbatim: lastBackupText).font(LiquidType.captionLectura).foregroundStyle(LiquidColor.tinta500)
                    HStack(spacing: LiquidSpace.s300) {
                        LiquidGlassButton(String(localized: "Back up now"), variant: .glass) {
                            Task { await autoBackup.backupNow(checkpoint: { await model.repo.checkpointForBackup() }) }
                        }
                        .disabled(autoBackup.busy).opacity(autoBackup.busy ? 0.6 : 1)
                        LiquidGlassButton(String(localized: "Restore…"), variant: .glass) { runImport() }
                            .disabled(backupBusy).opacity(backupBusy ? 0.6 : 1)
                        if autoBackup.busy { ProgressView().controlSize(.small).tint(LiquidColor.tinta500) }
                        Spacer(minLength: 0)
                    }
                    capilar
                    turnOffAutoBackupButton
                } else {
                    HStack(spacing: LiquidSpace.s300) {
                        LiquidGlassButton(String(localized: "Choose iCloud Drive folder…"), variant: .glass) {
                            Task { await autoBackup.chooseFolder() }
                        }
                        LiquidGlassButton(String(localized: "Restore…"), variant: .glass) { runImport() }
                            .disabled(backupBusy).opacity(backupBusy ? 0.6 : 1)
                        Spacer(minLength: 0)
                    }
                }
                if let err = autoBackup.lastError {
                    LiquidNotaLine(err, tono: LiquidColor.negativo)
                }
            }
        }
    }

    /// The one destructive action on the screen: `LiquidGlassButton` · `.destructive`
    /// (cápsula crítica con borde, sin relleno — FER-301).
    private var turnOffAutoBackupButton: some View {
        LiquidGlassButton(String(localized: "Turn off automatic backup"),
                          variant: .destructive, expands: true) {
            autoBackup.disable()
        }
    }

    private var lastBackupText: String {
        guard let d = autoBackup.lastBackup else { return String(localized: "No backup yet.") }
        let rel = RelativeDateTimeFormatter(); rel.unitsStyle = .full
        return String(localized: "Last backup \(rel.localizedString(for: d, relativeTo: Date()))")
    }
    #endif

    /// FER-224: builds the CSV off the DB (session by session, so the whole history never sits in
    /// memory as one array of sets) then hands it to the shared share-sheet exporter.
    private func runStrengthCSVExport() {
        strengthCSVError = false
        strengthCSVBusy = true
        Task {
            let csv = await buildStrengthHistoryCSV()
            strengthCSVBusy = false
            if !FileExport.exportText(csv, suggestedName: "cenit-fuerza.csv") {
                strengthCSVError = true
            }
        }
    }

    private func buildStrengthHistoryCSV() async -> String {
        var out = StrengthCSV.header + "\n"
        guard let store = await model.repo.storeHandle() else { return out }
        let exercisesById = Dictionary(await model.repo.allExercises().map { ($0.id, $0) },
                                        uniquingKeysWith: { a, _ in a })
        let routineNamesById = Dictionary(((try? await store.routines()) ?? []).map { ($0.id, $0.name) },
                                           uniquingKeysWith: { a, _ in a })
        let sessions = (try? await store.recentSessions(limit: Int.max)) ?? []
        for session in sessions.sorted(by: { $0.startTs < $1.startTs }) {
            let sets = (try? await store.setEntries(sessionId: session.id)) ?? []
            // `setEntries` is ordered by `position` across the WHOLE session, mixing exercises — the
            // per-exercise `set_index` (squat 1, squat 2, bench 1… not squat 1, squat 2, bench 3) is
            // computed by the pure `StrengthCSV.rows(forSessionSets:)`, not here (see its doc for the
            // superset / warm-up semantics it decides).
            let inputs = sets.map { set in
                StrengthCSV.SetInput(
                    date: Date(timeIntervalSince1970: TimeInterval(session.startTs)),
                    routineName: session.routineId.flatMap { routineNamesById[$0] },
                    exerciseId: set.exerciseId,
                    exerciseName: exercisesById[set.exerciseId]?.displayName(localized: true) ?? set.exerciseId,
                    setKind: set.kind,
                    weightKg: set.weightKg,
                    reps: set.reps,
                    timeS: set.timeS,
                    distanceM: set.distanceM,
                    rpe: set.rpe,
                    restTakenS: set.restTakenS,
                    notes: session.notes,
                    setMode: set.mode)
            }
            StrengthCSV.appendRows(StrengthCSV.rows(forSessionSets: inputs), to: &out)
        }
        return out
    }

    private func runExport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runExport(checkpoint: { await model.repo.checkpointForBackup() })
            handleBackup(result)
        }
    }
    private func runImport() {
        backupBusy = true
        Task {
            let result = await DataBackup.runImport()
            handleBackup(result)
        }
    }
    @MainActor
    private func handleBackup(_ result: DataBackup.BackupResult) {
        backupBusy = false
        switch result {
        case .cancelled: return
        case .exported(let url):
            backupAlertTitle = String(localized: "Backup exported")
            backupAlertMessage = String(localized: "Saved to \(url.lastPathComponent). Copy this file to your other device and use Import there to restore everything.")
            backupAlertIsError = false; showBackupAlert = true
        case .imported:
            backupAlertTitle = String(localized: "Backup imported")
            backupAlertMessage = String(localized: "Your data has been restored. Quit and reopen Cénit for it to take effect.")
            backupAlertIsError = false; showBackupAlert = true
        case .failure(let message):
            backupAlertTitle = String(localized: "Backup problem"); backupAlertMessage = message
            backupAlertIsError = true; showBackupAlert = true
        }
    }
}
