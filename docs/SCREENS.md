# NOOP iOS — Inventario de Pantallas

**Fuente de verdad textual** del mapa de pantallas. La representación visual vive en [`docs/screen-map.html`](screen-map.html).

**Regla de mantenimiento:** si tu PR modifica un `*View.swift`, actualiza la sección correspondiente aquí y en el array `SCREENS` de `screen-map.html`, y actualiza la fecha en el toolbar del HTML. Mismo PR, no opcional.

---

## Estructura de navegación global

```
Tab bar → 18 destinos principales (sidebar en macOS, tab bar en iOS)
SettingsView → WhatsNewView (sheet) · NotificationSettingsView (push)
TodayView   → LiveView (fullScreenCover) · MetricInfoSheet (sheet) · SupportView (toolbar)
WorkoutsView → ManualWorkoutSheet (sheet: add / edit)
MetricExplorerView → MetricDetailView (NavigationLink push, interno)
```

---

## Dashboard

### TodayView
**Archivo:** `Strand/Screens/TodayView.swift`  
**Descripción:** Hub principal — veredicto de readiness, síntesis del día, métricas clave, entrenamientos recientes.

| Estado | Condición de entrada |
|--------|---------------------|
| Empty / First launch | Ningún strap visto nunca |
| Calibrando (1–3 noches) | `calibrationNightsLogged < 4` |
| Sin lectura de hoy | Strap visto, sin offload de hoy |
| Veredicto listo | Recovery score calculado |

**Nota — indicador de sincronización (iOS):** cuando `live.backfilling == true`, la `syncMeta` en la `utilityRow` muestra "Syncing strap history…" en tono terciario/mono en lugar del texto habitual "Synced X ago". No hay pill ni color prominente; el texto vuelve al estado normal al terminar el backfill. El pill `SyncingHistoryNote` se conserva solo en el path macOS de esta vista.

**Nota — footnote de procedencia (fondo del scroll):** en lugar del antiguo `SectionHeader + NoopCard` de tres renglones, la procedencia aparece como dos líneas compactas en `StrandFont.footnote` / `textTertiary`: (1) badges `SourceBadge` con conteos por fuente (Whoop y/o Apple Health, omitidos si no hay datos), (2) estado del último sync del strap (en `statusWarning` si hay error). El bloque completo se oculta si no hay datos de ninguna fuente ni sync registrado.

**Componentes:** `HealthAlertBanner`, `CalibrationProgressCard`, `LiveHeartbeatRow`, `ReadinessGaugeBar`, `RecoveryRing`, `InsightCard`, `StatTile ×10`, `ChartCard (HR Trend)`, `SourceBadge`  
**Navegación:** → `LiveView` (fullScreenCover, "See it beat by beat") · → `MetricInfoSheet` (sheet, tap métrica) · → `SupportView` (toolbar ❤)

---

### HealthView
**Archivo:** `Strand/Screens/HealthView.swift`  
**Descripción:** Vitales en vivo — HR desde la correa, respiración, SpO₂, RHR, HRV, temperatura de piel.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos | Sin HR en vivo ni datos de hoy |
| Streaming HR | Strap bonded + HR > 0 + worn |
| Datos históricos | Datos de hoy disponibles |

**Componentes:** `Sparkline`, `StatePill (STREAMING/IDLE)`, `StatTile ×5`

---

### SleepView
**Archivo:** `Strand/Screens/SleepView.swift`  
**Descripción:** Análisis de sueño — etapas, eficiencia, consistencia, vs. típico.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos de noche | Sin intervalos de sueño registrados (muestra `ComingSoon`, sin pill de sincronización) |
| Apple Health | Fuente `apple-health` (sin duración en cama) |
| WHOOP · hipnograma | Intervalos WHOOP persistidos |
| WHOOP · estimado | Hipnograma aproximado (stacked bar) |

**Componentes:** `ChartCard (hipnograma/stacked bar)`, `StatTile ×7`, `Stages vs Typical Card`, `Duration Trend ChartCard`

---

### StressView
**Archivo:** `Strand/Screens/StressView.swift`  
**Descripción:** Monitor de estrés 0–3 basado en RHR + HRV vs. baseline 30 días.

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | `StressModel` en cálculo |
| Sin datos | Historial vacío |
| Score calculado | z-score disponible |

**Componentes:** `Hero Gauge Card`, `StatTile ×2 (RHR / HRV vs. 30d)`, `ChartCard (tendencia)`, `Metodología (z-score)`

---

## Actividad

### WorkoutsView
**Archivo:** `Strand/Screens/WorkoutsView.swift`  
**Descripción:** Log de actividad — importado (WHOOP, Apple), detectado automáticamente, manual.

| Estado | Condición de entrada |
|--------|---------------------|
| Cargando | `loaded == false` |
| Sin sesiones | `allRows.isEmpty` |
| Ventana vacía (auto-widen) | Rango seleccionado sin sesiones, expande a siguiente |
| Con sesiones | Sesiones en el rango actual |

**Componentes:** `SegmentedPillControl (7D–All)`, `StatTile ×5`, `Activity Breakdown`, `HR Zones`, `Sessions table`  
**Navegación:** → `ManualWorkoutSheet` (sheet: add · edit vía context menu)

---

### TrendsView
**Archivo:** `Strand/Screens/TrendsView.swift`  
**Descripción:** Análisis longitudinal — Recovery, HRV, RHR, Day Strain.

| Estado | Condición de entrada |
|--------|---------------------|
| Ventana vacía | Sin puntos en el rango; expande automáticamente |
| Un solo punto | Solo 1 día disponible |
| Múltiples puntos | ≥ 2 puntos; renderiza gráficas |

**Componentes:** `SegmentedPillControl (W–ALL)`, `Hero ChartCard (Recovery)`, `ChartCard ×3 (HRV/RHR/Strain)`, `YearHeatStrip`

---

### InsightsView
**Archivo:** `Strand/Screens/InsightsView.swift`  
**Descripción:** Correlaciones — comportamientos que afectan recovery/HRV/sleep/RHR (Pearson r, Cohen's d).

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | Correlaciones en proceso |
| Sin journal | Sin entradas de journal |
| Con comportamientos | Journal + outcomes disponibles |
| Correlaciones (Pearson r) | Métricas cruzadas calculadas |

**Componentes:** `JournalLogCard`, `Behavior Effects Cards (Cohen's d)`, `RBar chart (Pearson r)`, `Metric Relationships Card`

---

## Análisis

### MetricExplorerView / MetricDetailView
**Archivo:** `Strand/Screens/MetricExplorerView.swift`  
**Descripción:** Catálogo de métricas por categoría (Sleep, Strain, Workouts, Vitals, Body). Tap → dossier completo de una métrica.

| Estado | Condición de entrada |
|--------|---------------------|
| Lista por categoría | Vista raíz |
| Detalle · sin datos | Ventana sin puntos (auto-widen) |
| Detalle · un punto | 1 día disponible en el rango |
| Detalle · tendencia | ≥ 2 puntos; muestra gráfica |

**Componentes:** `MetricCatalog grouped list`, `Hero StatTile`, `ChartCard (tendencia)`, `Avg/Min/Max footer`, `Banding vs baseline`  
**Navegación:** → `MetricDetailView` (push interno, NavigationLink)

---

### CompareView
**Archivo:** `Strand/Screens/CompareView.swift`  
**Descripción:** Superponer 2–4 métricas en gráfica normalizada (0–1) + Pearson r entre pares.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin selección | `selected.isEmpty` |
| < 2 métricas | Solo 1 métrica seleccionada |
| 2+ métricas | Gráfica overlay + tarjetas de correlación |

**Componentes:** `Multi-select picker`, `SegmentedPillControl`, `Overlay ChartCard (normalizado 0–1)`, `Correlation rows (Pearson r + p-value)`

---

### AppleHealthView
**Archivo:** `Strand/Screens/AppleHealthView.swift`  
**Descripción:** Historia de Apple Health — Steps, Active Energy, VO₂ Max, vitales, cuerpo, sueño.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin datos | Fuente `apple-health` vacía |
| Ventana vacía (auto-widen) | Rango sin puntos |
| Con datos | Puntos disponibles en el rango |

**Componentes:** `StatTile hero por métrica`, `ChartCard ×4 secciones (Heart / Activity / Body / Sleep)`, `SegmentedPillControl`

---

### IntelligenceView
**Archivo:** `Strand/Screens/IntelligenceView.swift`  
**Descripción:** Scores on-device (recovery, strain, sleep desde streams crudos de la correa, sin cloud).

| Estado | Condición de entrada |
|--------|---------------------|
| Calculando | `IntelligenceEngine` en progreso |
| Sin datos (mid-offload o pending wear) | Muestra `DataPendingNote` sin pill de sincronización; el offload en curso ya se refleja en `syncMeta` de TodayView |
| Resultados por día | Análisis reciente disponible |

**Componentes:** `Explainer Card (pesos: HRV 60% / RHR 20% / sleep 15% / resp 5%)`, `Day Cards (Recovery/Strain/Sleep + NOOP badge)`, `Toolbar Recompute`

---

## Dispositivo

### LiveView
**Archivo:** `Strand/Screens/LiveView.swift`  
**Descripción:** Monitor ECG en vivo + gestión de correa (pairing, model picker, workout logging, offload).

| Estado | Condición de entrada |
|--------|---------------------|
| No bonded | Sin strap vinculado |
| Bonded, sin conexión | Strap conocido pero desconectado |
| Conectado, no puesto | `state == .connected` + `worn == false` |
| Puesto · Streaming | `worn == true` + HR en vivo |
| monitorOnly mode | `monitorOnly: true` (desde TodayView "beat by beat") |

**Componentes:** `ECG Hero Sparkline`, `Session Tally`, `Live Signals (zone / %max)`, `Sync Signals (battery / last sync)`, `Data Receipt (frame counts)`, `Coverage Strip (28d heat map)`, `Strap Management (model picker / buzz / offload / forget)`

---

### AutomationsView
**Archivo:** `Strand/Screens/AutomationsView.swift`  
**Descripción:** Double-tap → acción Mac, wear on/off → lock, coaching haptic, alarmas, illness watch.

| Estado | Condición de entrada |
|--------|---------------------|
| Strap no bonded | Sin strap vinculado |
| Strap bonded | Strap vinculado |

**Componentes:** `StatePill (bonded/not)`, `Action picker (None / App / Shortcut)`, `Shortcut name field`, `Test button`, `Moments list (últimos 5 double-taps)`

---

### BreathingView
**Archivo:** `Strand/Screens/BreathingView.swift`  
**Descripción:** Trainer de respiración con biofeedback HRV en vivo (pacing haptic + visual).

| Estado | Condición de entrada |
|--------|---------------------|
| Setup (pace selector) | Pantalla inicial |
| Idle · bonded | Strap conectado, listo para iniciar |
| Corriendo | Sesión activa + timer + haptics |
| Completo | Sesión terminada |

**Componentes:** `Pace selector (Relax 4–6 / Coherence 5.5 / Box 4–4)`, `Timer display`, `Live HR + zone`, `Rolling RMSSD chart`, `Strap bonded pill`

---

### IntervalTimerView
**Archivo:** `Strand/Screens/IntervalTimerView.swift`  
**Descripción:** HIIT timer haptic silencioso (work/rest, buzzes en transiciones).

| Estado | Condición de entrada |
|--------|---------------------|
| Config | Pantalla inicial (inputs) |
| Idle | Configurado, listo para iniciar |
| Corriendo | Timer activo, fase actual visible |
| Completo | Rondas terminadas |

**Componentes:** `Duration inputs (Work / Rest / Rounds)`, `Timer display grande`, `Progress ring (phase)`, `Round counter`, `Start / Pause / Reset`

---

## App

### CoachView
**Archivo:** `Strand/Screens/CoachView.swift`  
**Descripción:** LLM coaching — pregunta sobre recovery/strain/sleep, integración OpenAI/Anthropic.

| Estado | Condición de entrada |
|--------|---------------------|
| Sin clave API | `keyDraft` vacío, sin key guardada |
| Sin consentimiento | Key guardada, toggle data sharing off |
| Vacío (consentido) | Consent dado, sin mensajes aún |
| Con mensajes | Transcript con bubbles |
| Error (API / red) | Error en llamada al LLM |

**Componentes:** `Setup Card (provider/model/key)`, `Consent Bar (toggle)`, `Transcript (bubbles)`, `Suggestion Chips (scroll H)`, `Composer + send button`, `Privacy Footnote`

---

### SettingsView
**Archivo:** `Strand/Screens/SettingsView.swift`  
**Descripción:** Configuración — perfil (edad, sexo, peso, altura), unidades, strap, experimental, backup, about.

| Estado | Condición de entrada |
|--------|---------------------|
| Vista única (scrollable) | Siempre |

**Componentes:** `SettingsSection cards`, `FormRow (age/sex/weight/height)`, `Units toggles (metric/imperial / °C/°F)`, `Strap card`, `Experimental toggle (Puffin)`, `Backup card (export/restore)`, `About card`  
**Navegación:** → `WhatsNewView` (sheet) · → `NotificationSettingsView` (push)

---

### DataSourcesView
**Archivo:** `Strand/Screens/DataSourcesView.swift`  
**Descripción:** Importar datos — WHOOP export (.zip), Apple Health export, sincronización en vivo Apple Health (iOS).

| Estado | Condición de entrada |
|--------|---------------------|
| Idle | Sin proceso en curso |
| Importando WHOOP | `WhoopImporter` corriendo |
| Importando Apple Health | `HealthImporter` corriendo |
| Import completo | Proceso terminado, muestra conteos |

**Componentes:** `WHOOP Export Card`, `Apple Health Export Card`, `Apple Health Live Card (iOS, toggle)`, `Live Strap Card`, `File importer (fileImporter)`

---

### SupportView
**Archivo:** `Strand/Screens/SupportView.swift`  
**Descripción:** Donaciones + contacto + atribución. Contenido estático.

| Estado | Condición de entrada |
|--------|---------------------|
| Estático | Siempre |

**Componentes:** `Built On Card (atribución)`, `Donate Card (BTC/ETH + copy)`, `Contact Card (mailto)`, `Disclaimer Card`

---

## Sheets y Modales

### ManualWorkoutSheet
**Archivo:** `Strand/Screens/ManualWorkoutSheet.swift`  
**Presentado por:** `WorkoutsView` (add / edit via context menu)

| Estado | Condición de entrada |
|--------|---------------------|
| Modo agregar | `editing == nil` |
| Modo editar | `editing != nil` (precargado) |
| Validación fallida | Campos requeridos inválidos; Save desactivado |

**Componentes:** `Sport TextField`, `DatePicker (start)`, `Duration spinner (minutos)`, `Avg HR (opcional)`, `kcal (opcional)`

---

### MetricInfoSheet
**Archivo:** `Strand/Screens/MetricInfoSheet.swift`  
**Presentado por:** `TodayView` (tap cualquier métrica del grid)

| Estado | Condición de entrada |
|--------|---------------------|
| Estático por métrica | Siempre (strain / sleep / HRV / RHR / SpO₂ / steps) |

**Componentes:** `Metric name + headline`, `Valor actual + color`, `Bands (3–4 rangos + active highlight)`, `Nota opcional`

---

### WhatsNewView
**Archivo:** `Strand/Screens/WhatsNewView.swift`  
**Presentado por:** `SettingsView` ("What's New") · auto-shown on app update

| Estado | Condición de entrada |
|--------|---------------------|
| Lista scrollable | Siempre |

**Componentes:** `Expectations Card`, `Release Cards (AppChangelog.releases)`

---

### NotificationSettingsView
**Archivo:** `Strand/Screens/NotificationSettingsView.swift`  
**Presentado por:** `SettingsView` (push)

| Estado | Condición de entrada |
|--------|---------------------|
| Alertas desactivadas | Master toggle off |
| Activado, sin apps | Toggle on, ninguna app configurada |
| Activado, con apps | Toggle on + apps con buzz pattern |

**Componentes:** `Master Card (toggle + strap pill + test buzz)`, `Category Cards (per-app toggle + buzz pattern picker)`, `Behaviour Card (quiet hours time range)`

---

## Resumen

| Sección | Pantallas | Estados |
|---------|-----------|---------|
| Dashboard | 4 | 14 |
| Actividad | 3 | 10 |
| Análisis | 4 | 13 |
| Dispositivo | 4 | 13 |
| App | 4 | 8 |
| Sheets & Modales | 4 | 9 |
| **Total** | **23** | **~67** |

*Actualizado: 2026-06-15*
