# ICONOS — borrador de vocabulario canónico (FER-269c · Fase 3)

> **Solo reporte.** Cero cambios de producción. Inventario auditado de los **65** hits
> `dimension: iconografia` / `rule: literal-systemName` en [`CENSO.json`](CENSO.json).
> Agrupa por **concepto** (lo que el usuario entiende), no por string SF. Compañero de
> [`ICONOGRAFIA.md`](ICONOGRAFIA.md) y del catálogo `StrandIcon`.

## Totales

| Sección | Conceptos | Hits del censo |
|---|---:|---:|
| §1 Colisiones (mismo concepto, símbolos distintos) | 3 | 8 |
| §2 Patrones intencionales (no colisión) | 3 | 5 |
| §3 Sin colisión (un solo símbolo por concepto) | 35 | 52 |
| **Total** | **41** | **65** |

Cada uno de los 65 hits aparece en exactamente una sección.

---

## 1 · Colisiones

Criterio: **2+ símbolos SF distintos** para el **mismo** concepto de usuario. Propuesta = símbolo
dominante en el árbol, salvo razón fuerte (`StrandIcon` / HIG). Una línea de razón.

### 1.1 Agregar

| | |
|---|---|
| **Concepto** | Añadir un ítem (ejercicio, métrica) |
| **Símbolos en uso** | `plus` · `plus.circle.fill` |
| **Canónico propuesto** | **`plus`** |
| **Razón** | Coincide con `StrandIcon.add`; HIG trata el plus desnudo como la acción «Add» genérica. |
| **Sitios a cambiar** | `Cenit/Screens/CompareView.swift:358` (`plus.circle.fill` → `plus`) |

| Símbolo | Archivo:línea | Contexto |
|---|---|---|
| `plus` | `Cenit/Screens/Hoja/HojaPlegada.swift:57` | CTA «Add exercise» |
| `plus.circle.fill` | `Cenit/Screens/CompareView.swift:358` | CTA «Add metric» / «Max 4» |

Hits: **2**.

---

### 1.2 Más acciones (menú ···)

| | |
|---|---|
| **Concepto** | Abrir el menú de acciones secundarias («···») |
| **Símbolos en uso** | `ellipsis` · `ellipsis.circle` |
| **Canónico propuesto** | **`ellipsis`** |
| **Razón** | Empate 2/2, pero `StrandIcon.more` ya fija `ellipsis`. Unificar evita glifos distintos para la misma puerta (banda vs toolbar). Si se prefiere la forma de toolbar HIG (`ellipsis.circle`), promover el catálogo y migrar los inline — no dejar ambos. |
| **Sitios a cambiar** | `Cenit/Screens/WorkoutDetailScreen.swift:335`, `Cenit/Screens/WorkoutHistoryScreen.swift:1625` (`ellipsis.circle` → `ellipsis`) |

| Símbolo | Archivo:línea | Contexto |
|---|---|---|
| `ellipsis` | `Cenit/Screens/WeeklyPlanEditorView.swift:569` | Menú de carpeta |
| `ellipsis` | `Cenit/Screens/WeeklyPlanEditorView.swift:699` | Menú de rutina |
| `ellipsis.circle` | `Cenit/Screens/WorkoutDetailScreen.swift:335` | Menú de acciones de sesión |
| `ellipsis.circle` | `Cenit/Screens/WorkoutHistoryScreen.swift:1625` | Toolbar «More options» |

Hits: **4**.

---

### 1.3 Confirmación «guardado en Salud»

| | |
|---|---|
| **Concepto** | El entrenamiento quedó reflejado / guardado en Apple Health |
| **Símbolos en uso** | `checkmark` · `checkmark.seal.fill` |
| **Canónico propuesto** | **`checkmark`** |
| **Razón** | Alineado a `StrandIcon.confirm`; HIG reserva `checkmark.seal` para contenido verificado/autenticado, no para un mirror de persistencia. |
| **Sitios a cambiar** | `Cenit/Screens/LiveStrengthSheet.swift:1685` (`checkmark.seal.fill` → `checkmark`) |

| Símbolo | Archivo:línea | Contexto |
|---|---|---|
| `checkmark` | `CenitWatch/Screens/WatchSummaryView.swift:68` | Línea «Saved to Health» |
| `checkmark.seal.fill` | `Cenit/Screens/LiveStrengthSheet.swift:1685` | Fila del recibo «health saved» |

Hits: **2**.

> Los demás `checkmark` del censo (hecho / cubierto / listo genérico) usan ya el canónico sin
> rival — van en §3.

---

## 2 · Patrones intencionales (no colisión)

Variantes deliberadas donde el código comunica **estado**, no vocabulario inconsistente.

### 2.1 Selección en lista (filled ≠ confirmación)

| Estado | Símbolo | Archivo:línea | Por qué no es colisión |
|---|---|---|---|
| Ítem seleccionado (toggle) | `checkmark.circle.fill` | `Cenit/Screens/ExerciseLibraryScreen.swift:362` | Filled = seleccionado (patrón HIG de selección), no «confirmar acción». |

Hits: **1**.

### 2.2 Marcadores de serie (Watch · done / current / pending)

Tres símbolos, un solo control de progreso con estados mutuamente excluyentes:

| Estado | Símbolo | Archivo:línea |
|---|---|---|
| Serie hecha | `checkmark` | `CenitWatch/Screens/WatchLiveFaceView.swift:384` |
| Serie actual | `circle.fill` | `CenitWatch/Screens/WatchLiveFaceView.swift:385` |
| Serie pendiente | `circle` | `CenitWatch/Screens/WatchLiveFaceView.swift:386` |

Hits: **3**.

### 2.3 Sello «nada que guardar» (≠ Health save)

| Concepto | Símbolo | Archivo:línea | Nota |
|---|---|---|---|
| Sesión vacía descartada — historial limpio | `checkmark.seal` | `Cenit/Screens/LiveStrengthSheet.swift:1369` | Narrativa de integridad («nada se registró»). Distinto de §1.3; si Fase 4 unifica sellos, decidir aparte. |

Hits: **1**.

---

## 3 · Conceptos sin colisión (sanos)

Un solo símbolo SF por concepto entre los hits restantes (**52**).

| Concepto | Símbolo | Archivo:línea | Notas |
|---|---|---|---|
| Info / revelar (onboarding) | `info.circle` | `Cenit/Onboarding/OnboardingActoEncendido.swift:235` | `StrandIcon.info` |
| Volver / atrás | `chevron.left` | `Cenit/Onboarding/OnboardingPiezas.swift:787`, `Cenit/Screens/CuerpoView.swift:124` | `StrandIcon.back` |
| Abrir app Salud (externa) | `arrow.up.forward.app` | `Cenit/Screens/AjustesHistorialFA.swift:135` | Handoff a otra app |
| Recalibrar recuperación | `arrow.clockwise` | `Cenit/Screens/AjustesView.swift:525` | Refresh de baseline |
| Negación («qué no hace») | `xmark` | `Cenit/Screens/CyclePhaseView.swift:188` | Bullet de «no» — ver §4 sobrecarga |
| Cubierto / importado OK | `checkmark` | `Cenit/Screens/DataSourcesView.swift:444` | Chip sobre círculo verde |
| Ajustes del sistema | `gearshape` | `Cenit/Screens/DataSourcesView.swift:520` | Permisos Apple Health |
| Backup iCloud activo | `checkmark.icloud.fill` | `Cenit/Screens/DataSourcesView.swift:785` | Destino iCloud |
| Ayuda / trucos | `questionmark.circle` | `Cenit/Screens/EntrenarView.swift:1360` | Distinto de `info.circle` |
| Video / media de ejercicio | `play.rectangle` | `Cenit/Screens/ExerciseDetailScreen.swift:278`, `:657` | Hint descarga + YouTube |
| Historial vacío (tiempo) | `clock.arrow.circlepath` | `Cenit/Screens/ExerciseDetailScreen.swift:893`, `Cenit/Screens/WorkoutHistoryScreen.swift:1186` | Empty de marcas / workouts |
| Error / advertencia | `exclamationmark.triangle` | `Cenit/Screens/Hoja/RoutineSheetLive.swift:435`, `Cenit/Screens/LiveStrengthSheet.swift:973`, `Cenit/Screens/WorkoutEditSheet.swift:361`, `Cenit/Screens/WorkoutImportView.swift:264`, `CenitWatch/Screens/WatchSummaryView.swift:75` | 5/5 outline; drift vs `StrandIcon.warning` (`.fill`) — ver §4 |
| Entrar a modo Foco | `arrow.up.left.and.arrow.down.right` | `Cenit/Screens/Hoja/RoutineSheetLiveCabecera.swift:68`, `Cenit/Screens/Hoja/RoutineSheetLiveTarjeta.swift:58` | Expand / focus |
| Descartar aviso (deload) | `xmark` | `Cenit/Screens/Hoja/RoutineSheetLiveTarjeta.swift:155` | `StrandIcon.close`; a11y «Dismiss» |
| Hecho (ejercicio en Foco) | `checkmark` | `Cenit/Screens/Hoja/RoutineSheetLiveFoco.swift:440` | Overlay en círculo verde |
| Frecuencia cardíaca / pulso | `heart.fill` | `Cenit/Screens/LiveStrengthSheet.swift:769`; `CenitWidgets/RestLiveActivity.swift:268`, `:576`, `:618`, `:634`, `:670`, `:694` | `StrandIcon.heart` · 7 hits |
| Origen Apple Watch | `applewatch` | `Cenit/Screens/LiveStrengthSheet.swift:1489` | Procedencia en recibo |
| Récord personal | `star` | `Cenit/Screens/LiveStrengthSheet.swift:1765` | Cabecera de PRs |
| Tendencia a la baja | `arrow.down` | `Cenit/Screens/LiveStrengthSheet.swift:1835` | Pareado con `StrandIcon.up` (`arrow.up`); **no** `StrandIcon.down` (`chevron.down` = colapsar) |
| Eliminar | `trash` | `Cenit/Screens/RoutineSetEditing.swift:260`, `Cenit/Screens/WeeklyPlanEditorView.swift:1061` | |
| Tickets / recibos | `doc.plaintext` | `Cenit/Screens/SavedTicketsScreen.swift:126`, `Cenit/Screens/WorkoutHistoryScreen.swift:1076` | Empty + fila nav |
| Ocultar teclado | `chevron.down` | `Cenit/Screens/SessionKeypad.swift:169` | `StrandIcon.down` |
| Invitar calendario | `calendar.badge.clock` | `Cenit/Screens/StressDayMapView.swift:57` | Empty/permiso estrés×calendario |
| Deseleccionar (peek) | `arrow.uturn.backward` | `Cenit/Screens/TrainingBodyScreen.swift:377` | Undo de selección, no «volver» |
| Marcar todo recuperado | `arrow.counterclockwise` | `Cenit/Screens/TrainingBodyScreen.swift:392` | Reset del mapa (≠ recalibrar) |
| Cambiar rutina del día | `arrow.left.arrow.right` | `Cenit/Screens/WeeklyPlanEditorView.swift:308` | Swap / reassign |
| Picker de rutina | `chevron.up.chevron.down` | `Cenit/Screens/WorkoutEditSheet.swift:224` | Afordancia de selector |
| Sugerencia de reconciliación | `sparkles` | `Cenit/Screens/WorkoutImportView.swift:353` | «Did you mean…» |
| Importación terminada | `checkmark` | `Cenit/Screens/WorkoutImportView.swift:537` | Héroe de cierre |
| Confirmar log de serie (Watch) | `checkmark` | `CenitWatch/Screens/WatchLiveFaceView.swift:87` | Flash post-log |
| Listo / descanso terminado | `checkmark` | `CenitWatch/Screens/WatchSessionRootView.swift:195` | «Ready» |
| Fallo de HealthKit (Watch) | `heart.text.square` | `CenitWatch/Screens/WatchSessionRootView.swift:165` | Error de Health, no pulso |
| Ver recibo en iPhone | `chevron.right` | `CenitWatch/Screens/WatchSummaryView.swift:38` | `StrandIcon.disclosure` |
| Pausado (Live Activity) | `pause.fill` | `CenitWidgets/RestLiveActivity.swift:615`, `:646` | Fase `.paused` |
| Temporizador de descanso | `timer` | `CenitWidgets/RestLiveActivity.swift:679` | Rest por reloj (no HR) |

Hits en §3: **52** (verificación: 8 + 5 + 52 = 65).

---

## 4 · Notas para Fase 4 (fuera del defecto central)

No son colisiones «mismo concepto / símbolos distintos», pero el censo las deja a la vista:

1. **Sobrecarga de `xmark`.** Mismo glifo para (a) descartar aviso (`RoutineSheetLiveTarjeta.swift:155`, concepto *cerrar*) y (b) bullet de negación (`CyclePhaseView.swift:188`, concepto *«no hace»*). Invertido del defecto buscado: un símbolo, dos conceptos. Fase 4: reservar `xmark` a `StrandIcon.close` y usar otro glifo (p. ej. guión / texto) para la lista de límites.
2. **Drift `StrandIcon.warning`.** Catálogo = `exclamationmark.triangle.fill`; los 5 literales del censo usan outline. Elegir uno y alinear catálogo ↔ árbol.
3. **`StrandIcon.down` vs tendencia.** El catálogo mapea `down` → `chevron.down` (colapsar). La tendencia a la baja ya usa bien `arrow.down`. No mezclar; si se necesita tendencia en el catálogo, añadir un caso distinto (`trendDown`).

---

## 5 · Vocabulario canónico propuesto (resumen)

Acciones de alta frecuencia alineadas a `StrandIcon` + hallazgos de este censo:

| Concepto | Canónico | Origen |
|---|---|---|
| Agregar | `plus` | `StrandIcon.add` + §1.1 |
| Más acciones | `ellipsis` | `StrandIcon.more` + §1.2 |
| Confirmar / hecho / guardado Salud | `checkmark` | `StrandIcon.confirm` + §1.3 |
| Cerrar / descartar | `xmark` | `StrandIcon.close` |
| Volver | `chevron.left` | `StrandIcon.back` |
| Disclosure / entrar | `chevron.right` | `StrandIcon.disclosure` |
| Info | `info.circle` | `StrandIcon.info` |
| Advertencia | `exclamationmark.triangle` *(outline, de facto del árbol)* o `.fill` *(catálogo)* — resolver §4.2 | |
| FC / pulso | `heart.fill` | `StrandIcon.heart` |
| Eliminar | `trash` | de facto |
| Seleccionado (lista) | `checkmark.circle.fill` | patrón §2.1 |
| Foco / expandir | `arrow.up.left.and.arrow.down.right` | de facto |

**Sitios concretos a tocar en una Fase 4 de unificación (solo los de colisión):**

1. `CompareView.swift:358`
2. `WorkoutDetailScreen.swift:335`
3. `WorkoutHistoryScreen.swift:1625`
4. `LiveStrengthSheet.swift:1685`

Cuatro literales. El resto del censo ya es coherente por concepto.
