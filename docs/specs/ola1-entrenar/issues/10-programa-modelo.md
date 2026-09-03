## Contexto
El plan es un calendario de siete casillas que se repite. Un programa es ese calendario más un contador de semanas y una regla para la última (semana ligera). Fuente: `arq-B.md §⑤` con E3/E4/E5/E6 (v2), D1/D3/D5/D6 (biomecánico), N4 (Grok R1), decisiones D-Q2/D-Q3/D-Q4, y el pulido de programas (prender/apagar, repetir ciclo).

## Objetivo
`Program` singleton con semana derivada (nunca guardada), regla de semana ligera pura, frontera de progresión, cuatro motores como datos sobre las plantillas existentes, y el import desde tu IA con `semanas`, `semana_ligera` y `dia`.

**Carril:** pesado (modelo + migración ya en E1 + import). Gate /biomecanico. **Depende de E1, E4 y E6 mergeados**: los hunks de `ProgressionState`/`ProgressionPlanner` (frontera `deload`, `raise = nil` en ligera) se escriben rebaseados sobre E4; `PlateMath.snap` y el SQL de series vienen de E6.

## Reglas y lógica
- Rango de semanas: **producto (UI): 4…6**; **import desde IA: 4…8**; `ProgramCalendar` NO clampa: recibe `weeks` ya validado. `endMode` amplía la tabla canónica v2 §C (pulido del dueño «Al terminar el ciclo»).
- `ProgramCalendar.position(startTs:trainedWeekStarts:now:weeks:calendar:) -> Position { cycle, week (1…weeks), isLight, weeksUntilLight }` con lunes-primero (helper compartido con `TrainingWeeks.mondayFirst`): `n` = semanas con ≥1 sesión estrictamente anteriores a la semana actual desde el inicio; `week = (n mod weeks) + 1`; `cycle = n / weeks`. Semana en blanco no avanza. Empezar a mitad de semana: esa semana es la 1.
- `endMode`: `repeat` (al terminar la ligera vuelve a la 1 con los pesos ganados) · `single` (al terminar, el programa se termina solo y queda la semana normal).
- `ProgramDeload.apply(rule:to:[RoutineSet])`: `volumeOnly` → series de trabajo `max(1, Int((n × 0.5).rounded(.down)))` (4→2, 3→1, 1→1), calentamientos intactos, peso igual; `volumeAndLoad` → lo mismo + peso × (1 − `ProgressionMath.deloadFraction`) (7.5 %) redondeado con `PlateMath.snap`; `none` → identidad. Constantes `ligeraSeriesFactor = 0.5` y `deloadFraction` reutilizada (UNA familia). Citas en cabecera: Bell 2023 (DOI 10.1186/s40798-023-00633-0), Bell 2024 (PMC10948666), rotuladas «convención, no receta».
- Servido: en `RoutineSheetLogic.load()` (.today/.planDay) si `isLight` → transforma la semilla EN MEMORIA; `StrengthSessionModel.make` aplica el peso final; `ProgressionPlanner.evaluate` devuelve `raise = nil` en semana ligera. **Nunca** se escribe en `routineSet` (test byte a byte).
- Persistencia de la sesión: `programWeek`, `deload = 1` (E1). Snapshot en curso gana ambos.
- `ProgressionMath.PastSession.deload: Bool` = FRONTERA: `current` = última no-deload; en `metRun` una deload se salta (no cuenta, no rompe); en `failRun` rompe (reinicia estancamiento); `lastWorkSets` y `ProgressionPlanner.visible` excluyen `deload = 1`. `optedOut` no se usa. El deload reactivo (−7.5 % tras 3) **sigue vivo** dentro del programa (D1).
- Motores (`ProgramTemplate`, datos): `linear-novice` = full-body L/M/V, `progressionSessions = 1` solo en slots de barra (mancuerna/aislamiento n = 2), `progressionUseRPE = false`, `deloadRule = .none`; `full-body-3` (n = 2); `ppl-6` = push/pull/legs L→S (etiqueta «intermedio»); `upper-lower-4` = upper L/J, lower M/V. `materialize(now:names:)` reusa `StarterTemplate.makeRoutine` y escribe rutinas + `RoutineSchedule` + `program` en una transacción.
- Import IA (`WorkoutProgram` v1, campos opcionales retrocompatibles): raíz `semanas: Int?` (4…8; fuera → `unsupportedSemanas`), `semana_ligera: "menos_series" | "menos_series_y_peso" | "ninguna"` (default ninguna), `al_terminar: "repetir" | "un_ciclo"` (default repetir); por rutina `dia: Int?` (1…7); sin `dia` → asigna días libres L→D como las plantillas. Si el archivo trae semanas distintas entre sí (no soportado), el parser no falla: importa la semana 1 y marca `warnings: [.weeksDiffer]` para que la UI lo diga.
- Terminar programa: borra la fila `program`; rutinas y calendario intactos.

## Alcance técnico
Nuevos: `Packages/StrandTraining/.../Program.swift` (Program, ProgramCalendar, ProgramTemplate), `ProgramDeload.swift`. Tocados: `ProgressionState.swift` (PastSession.deload + frontera), `StarterTemplates.swift`, `TrainingWeeks.swift` (`mondayFirst`, ~:35, hacerlo interno compartido), `Packages/StrandImport/.../WorkoutProgram.swift`, `CenitStore/StrengthStore.swift` (program CRUD, exclusiones SQL), `Cenit/Screens/Hoja/RoutineSheetLogic.swift:26-75`, `Cenit/Data/ProgressionPlanner.swift`, `Cenit/App/AppModel+Strength.swift`.

## Fuera de alcance
Pantallas (E11). Ondas de carga entre semanas.

## Criterios de aceptación
- [ ] `ProgramCalendarTests`: start martes sin sesiones → semana 1; 3 semanas entrenadas → 4; una en blanco no avanza; 5 entrenadas con weeks=5 → ciclo 2 semana 1 (repeat) o programa terminado (single); cruce de año.
- [ ] `ProgramDeloadTests`: 4→2, 3→1, 1→1, 5→2; calentamientos intactos; volumeOnly no toca peso; volumeAndLoad usa 7.5 % y cae en peso construible; none identidad.
- [ ] `ProgressionStateTests`: [miss, miss, deload, miss] → `.stalled(1)`; [met, deload, met] n=2 → `.readyToAdvance`; newest deload → current es la anterior; [miss, miss, miss] en semana 2 → `.deloading` (reactivo vivo).
- [ ] `StrengthStoreTests`: guardar sesión descargada no cambia `routineSet` (byte a byte); `lastWorkSets` ignora deload; program CRUD.
- [ ] `StarterTemplatesTests`: los 4 motores referencian ids existentes; `materialize` no duplica slots; linear-novice con n=1 solo en barra y RPE off.
- [ ] `WorkoutProgramTests`: payload v1 actual parsea igual (`program == nil`); con `semanas: 5` y con `semanas: 8` parsea; `semanas: 3` y `semanas: 9` → `unsupportedSemanas` (sin clamp silencioso); semanas distintas → warning, no error.
- [ ] `StrengthSessionSnapshotTests`: `programWeek`/`deload` ida y vuelta.

## Definition of Done
- [ ] `swift test` verde en StrandTraining, StrandAnalytics, StrandImport, CenitStore; `Tools/verify.sh` verde; /biomecanico PASS; /qa PASS.
