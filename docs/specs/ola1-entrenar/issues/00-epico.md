## Contexto
Benchmark 2026-09-01 (14 apps): 0/14 cambian la prescripción de fuerza por HRV/sueño; Cénit es la única con veredicto fisiológico real, pero (a) una sesión de fuerza sin Apple Watch aporta 0 a la carga, (b) las reps en reserva se capturan y no gobiernan nada, (c) no hay AMRAP/drop, (d) no hay import de Strong/Hevy, (e) no hay programas de varias semanas. La ola 1 pone Entrenar a la par en los ejes 1, 2, 3 y 5 del benchmark y cierra dos de los tres eslabones del círculo «sesión → carga → veredicto».

Los requerimientos se trabajaron en un taller adversarial (2026-09-02): 3 UX + 2 arquitectos, gates biomecánico/estadístico/criterio, 5 rondas de Grok hasta CONVERGE (24→10→5→4→0). Fuentes (léelas antes de codear): carpeta del taller `/private/tmp/claude-501/-Users-fer-iracheta-code-noop--claude-worktrees-new-session-ac9284/d9d4b932-78bc-42b0-9b01-58f45f8317c4/scratchpad/ola1/` (carpeta padre de `issues/`) — `CONSOLIDACION-v5.md` manda sobre v4→v1 y sobre `ux-A/B/C.md`, `arq-A/B.md`; `gate-biomecanico-1.md`, `gate-estadistico-1.md`, `cso-session-rpe-reloj.md`; los artefactos HTML del dueño en `artefactos/` (`ola1-pantallas.html` = pantallas y regla de selectores; `ola1-requerimientos.html`; `ola1-a-fondo.html`); bloques «CA sustituidos» en v4 §C y v5 §C. La entrega 1 del épico copia esa carpeta a `docs/specs/ola1-entrenar/` para que sea durable.

## Objetivo
Entregar las cinco piezas de la ola 1 con sus pantallas y su tutorial, 100 % offline, con matemática citada y probada, sin reabrir FER-85, FER-171, FER-251 ni el héroe v18.

**Carril:** pesado (épico). Cada sub-issue trae su propio carril.

## Decisiones del dueño (cerradas 2026-09-02; no re-litigar)
- D-Q12 La carga NO vota en el veredicto en esta ola. Ninguna pantalla dice que una sesión cambia el veredicto. Issue aparte en backlog («la carga vota», gate /cso).
- D-Q13 Se pregunta «¿qué tan duro estuvo?» SIEMPRE al cerrar fuerza, también con reloj. **D-Q13 manda sobre E17/N8 y sobre la fila «arq-A · regla por sesión» del bloque C de v4: E17 queda retirada para la pregunta UI.** La regla de FUENTE se mantiene: `sessionRpe != nil` → 'rpe'; si no y cobertura FC ≥ 0.8 → 'hr'; si no → nil. Prellenado «sugerido» (punteado), un toque, saltable. Con reloj: el esfuerzo manda la carga de fuerza; la FC queda como «costo cardiovascular» (existente). Nunca «el mayor de los dos».
- D-Q1 Cumplir reps con ≥2 reps en reserva en todas las series → sube en 1 sesión. D-Q6 Ritmo por reps en reserva se elige por ejercicio; en rutinas existentes nace en «Constante» (migración DEFAULT 0); plantillas nuevas lo encienden en slots de barra/compuestos, apagado en aislamiento y en «Lineal para empezar».
- D-Q2 El contador de semanas solo avanza en semanas con ≥1 sesión. D-Q3 Semana ligera default = series ×0,5 (mín 1), peso igual; opción «menos series y menos peso» usa `deloadFraction` 7,5 %. D-Q4 Cuatro motores = plantillas existentes + semanas; sin biblioteca de coaches. D-Q10 La semana ligera cambia solo kicker y meta del héroe existente. D-Q8 «Programa» no aparece en el first-run. D-Q9 Sin rutinas desde nombres importados.
- D-Q7 La celda de reps de «las que puedas» arranca vacía («máx»).
- Vocabulario final (en toda la app, incl. el teclado): «reps en reserva» (RIR) — nunca «Q» ni «Quedaban»; «las que puedas» (AMRAP), «bajar y seguir» (drop), «llegué al fallo» (0 en reserva), «semana ligera» (nunca «descarga»: colisiona con bajar medios), «esfuerzo estimado».
- Regla de selectores: segmentado solo para etiquetas de una palabra/número (riel único gris, elegido en blanco, nunca dos líneas); opciones con explicación → lista con palomita; valor que abre pantalla → fila con chevron; acciones → botones cortos.

## Orden y carriles (waves de /orquesta)
1. **Esquema** (FER-E1): migraciones v42+v43 + docs + copia de specs. Bloquea todo.
2a. **Paquetes, 2 worktrees en paralelo:** A = ① motor (E2) y luego ② motor (E4) en secuencia (mismo worktree; E4 posee `ProgressionState.swift` y `ProgressionPlanner.swift`) · B = ③ modelo (E6). Claude implementa migraciones y motores (carril pesado-delicado, DECISIONS 2026-08-31).
2b. **Tras mergear A y B (cierre de 2a):** ⑤ modelo (E10) — rebaseado sobre E4 (`ProgressionState`/`ProgressionPlanner`: frontera `deload`, `raise = nil` en ligera) y sobre E6 (usa `PlateMath.snap` y el SQL de series), única dueña de `StarterTemplates.swift`/`ProgramTemplate`; en paralelo, ④ lector (E8) tras mergear E2 (usa `SessionRPE.prefill` y `SessionRPELoad`); Grok teclea E8 y revisa lo que no escribió. E2 y E10 tocan `AppModel+Strength` en funciones distintas (E2: `endStrengthSession`/save path; E10: servir la semilla). `StrengthStore.swift`: en 2a, E6 posee el SQL de series (`workSetHistory`, `lastWorkSets`, récords, invariante de adyacencia) y E2 solo añade métodos nuevos de calibración/recompute en un hunk aparte; en 2b, E8 posee `saveSessions`/`existingSessionIds` y E10 posee el CRUD de `program` y las exclusiones `deload` — nunca el mismo hunk, E10 rebaseado sobre E6.
3. **Pantallas:** E3 (①), E5 (②), E7 (③), E9 (④), E11 (⑤), E12 (vocabulario + tutorial). Propiedad de archivos compartidos (no editar el mismo hunk desde dos worktrees): `SessionKeypad`: E5 las etiquetas de reps en reserva, E7 la tecla `confirmSet`→«máx» · `EntrenarView`: E5 las líneas de `raiseLine`/héroe por reps en reserva, E11 el kicker/meta/línea de semana ligera · `RoutineSheetLiveTarjeta`: E7 menú/chip/línea de tipo, E5 solo el sufijo «· al fallo» de la fila hecha, E11 solo el playhead «· ligera» · E12 no reescribe cadenas ya cambiadas por E5/E7, solo tips y glosario. Orden de merge en la wave: E3 → E5 → E7 → E9 → E11 → E12, cada uno rebaseado sobre el anterior. Una compilación de app al cerrar la wave.
Gates: /arquitecto sobre E1; /estadistico y /cso sobre E2; /biomecanico sobre E4, E6, E10; /qa independiente en todo lo pesado; /simplify al final de cada wave.

## Fuera de alcance
Que el veredicto baje series (FER-85) · que la carga vote (ola 1b) · Watch que registra solo (ola 3) · leer entrenos de otras apps desde Apple Health y pantalla de récords (ola 2) · catálogo con imágenes · ondas de carga entre semanas · campo compuesto/aislamiento en el catálogo (ola 2) · tile «carga de hoy, parcial».

## Definition of Done del épico
- [ ] Los 12 sub-issues en done, mergeados a `iOS` y `~/code/noop` sincronizado.
- [ ] Ningún copy de la app dice que una sesión cambia el veredicto (grep del catálogo de strings por «veredicto» en Entrenar).
- [ ] `Tools/verify.sh` verde al cierre de cada wave; `app-tests` verde al cierre del épico.
- [ ] CHANGELOG con entrada por pieza; docs/ARCHITECTURE.md y DATA_MODEL al día (v43); DECISIONS.md con FER-85 transcrito y las decisiones D-Q de arriba.

## Mapa de identificadores (Multica)
Épico FER-323 · E1 = FER-324 · E2 = FER-325 · E3 = FER-330 · E4 = FER-326 · E5 = FER-331 · E6 = FER-327 · E7 = FER-332 · E8 = FER-328 · E9 = FER-333 · E10 = FER-329 · E11 = FER-334 · E12 = FER-335 · Ola 1b (backlog) = FER-336 · Docs DATA_MODEL (backlog) = FER-337. Donde un sub-issue diga «E-N», léase el FER correspondiente. Stages: 1 = E1 · 2 = E2, E4, E6 · 3 = E8, E10 · 4 = pantallas E3, E5, E7, E9, E11, E12.
