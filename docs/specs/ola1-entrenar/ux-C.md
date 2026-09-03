# UX · Ola 1 · pieza ④ «importar el historial de Strong y Hevy»

Carril pesado. Persistir el origen de cada sesión (idempotencia + etiqueta) exige columna nueva → contradice el «sin migración» de la propuesta base.

## Inventario
1. Entrada: DataSourcesView.swift:177-217 (sección Import, `blockPlano` + `LiquidGlassButton` + progreso + resumen) y :701-723 (`ImportTarget` + `fileImporter`): caso `.strengthCSV` con `[.commaSeparatedText]`.
2. Resolver nombres: WorkoutImportView.swift:261-380 (`mappingFlow`: auto-match ✦, «¿Quisiste decir…?», chips Match/Crear/Omitir, Undo) sobre `WorkoutExerciseReconciler` (WorkoutProgram.swift:250-458) + `ExerciseAliasTable.bundled` + alias aprendidos (`repo.learnedExerciseAliases`, WorkoutImportView.swift:118,741). Se EXTRAE el paso de mapeo a un componente compartido.
3. Crear ejercicio propio: `CreateExerciseSheet` (ExerciseLibraryScreen.swift:506-544).
4. Modelo destino: `StrengthSession` (Training.swift:285-309: sin campo de origen) y `SetEntry` (:319-348). lb→kg ya existe (`WorkoutWeightUnit.lbToKg`, WorkoutProgram.swift:33). Columnas del CSV propio: StrengthCSV.swift:10-11.
5. Después: WorkoutHistoryScreen.swift:1166-1178 (vacío), :1924-1946 (sello «Fuente»), fila cardio con `Origen .manual/.apple` (:526); hub primer uso EntrenarView.swift:1146-1201.

## Flujo
Ajustes › Datos y fuentes › Importar, segundo bloque bajo «Exportación de Apple Health». Hoja modal de 4 pasos (Archivo → Revisar → Resolver → Listo; Resolver se salta si no hay pendientes). Otras entradas: Historial vacío: «¿Vienes de Strong o Hevy? Importa tu historial ›». Hub primer uso: NO.

**Paso 1 · Archivo.** «Tu historial, de Strong o Hevy» · kicker «Importar historial · un archivo, cero red». Dos filas plegadas: «Strong: Perfil › Ajustes › Exportar datos. Guarda el .csv en Archivos.» · «Hevy: Perfil › Ajustes › Exportar e importar datos › Exportar CSV. Guarda el .csv en Archivos.» (rutas a verificar). Botón «Elegir archivo .csv…». Pie: «Cénit reconoce cuál de las dos es por sus columnas. Nada sale de tu teléfono.»
Detección por nombre de columna: Hevy = `exercise_title` + `set_type` + `weight_kg`/`weight_lbs`; Strong = `Exercise Name` + `Set Order` + `Workout Name`; el CSV propio de Cénit también se acepta. Otro → «no reconocido».

**Paso 2 · Revisar.** Titular «214 sesiones» · «Strong · ene 2022 a ago 2026». Filas: «Ejercicios reconocidos · 61 de 68»; «Por resolver · 7» (tocable); «Ya estaban en Cénit · 0» (si > 0, interruptor «Importarlas de todos modos», apagado); «Con esfuerzo (RPE) · 140 de 214» + «Estas entran a tu carga como estimada. Las demás quedan sin carga.»; «Unidad de peso · kg» o selector kg/lb SOLO si el archivo no la declara, pista «Peso más alto del archivo: 315 → 143 kg». CTA «Importar 214 sesiones» (o «Resolver 7 y continuar»). «Cancelar».

**Paso 3 · Resolver.** Mismo componente de mapeo. Por nombre: verbatim + «en 38 sesiones», sugerencia ✦ «¿Quisiste decir… Aperturas en polea alta?» «Usar», chips «Elegir del catálogo» / «Crear propio» / «Ignorar». Ignorar: «Ignorar deja fuera 38 series; la sesión sí se importa». Botón «Faltan 4 por resolver» → «Continuar». Decisión se recuerda (alias aprendido).

**Progreso.** «Leyendo… 120 de 214 sesiones» → «Guardando…». Cancelar visible en Leyendo; en Guardando «Ya casi». Todo o nada: una transacción.

**Paso 4 · Listo.** «214 sesiones en tu historial» · «Récords, 1RM y mapa muscular ya se recalcularon con tu historia.» Si hubo sesiones con RPE en los últimos 28 días: «12 sesiones recientes entran a tu carga. Tu veredicto de mañana puede cambiar.» Acciones: «Ver historial» · si no hay plan «Arma tu semana» · «Listo».

**Después.** Historial: sello de origen «Strong» / «Hevy» en fila y detalle. Detalle: «Estimada · esfuerzo 8 · 52 min» o «Sin carga · el archivo no trae esfuerzo»; sin FC ni zonas. Biblioteca: «Mejor marca» refleja el récord importado. Hub: sin cambio de estado.

## Estados y errores
- No reconocido: «No reconozco este archivo. Cénit lee el CSV que exportan Strong y Hevy. Revisa que sea el .csv original, sin editar.» «Elegir otro».
- Columnas faltantes: «Al archivo le faltan columnas: reps, peso. Exporta de nuevo desde la app y vuelve a intentarlo.»
- Libras: Hevy `weight_lbs` → convierte; «lb · convertido a kg». Strong sin unidad → selector con pista.
- Archivo enorme (~30 000 filas): «Leyendo…» con conteo; vista previa < 5 s en iPhone de 3 años.
- Reimportar: llave = origen + minuto de inicio. «Ya estaban · 214», CTA «Nada nuevo por importar» deshabilitado.
- Strong y luego Hevy traslapadas: inicio a ±30 min de una guardada (cualquier origen) = «ya estaba»; el interruptor las deja entrar.
- Peso corporal / tiempo / distancia: `duration_seconds` → timeS; `distance_km` → distanceM; sin peso y con reps → reps. Choque de tipo → advertencia en Resolver «Este ejercicio registra tiempo; el que elegiste registra peso y reps».
- Superseries de Hevy: orden conservado; agrupamiento no se persiste en sesiones. Nota: «Las superseries se guardan como ejercicios seguidos.»
- Notas: sesión → `notes`; por ejercicio/serie se anteponen con nombre.
- RPE: con RPE por serie → ① estima; sin RPE → «sin carga». Hevy `set_type = failure` → RPE 10; `dropset` → drop; `warmup` → warmup. Strong «W» en Set Order = warmup (a verificar).
- Zona horaria: hora local sin desfase; se lee en la zona actual; nota «Las horas se leen en tu zona horaria actual.»
- Cancelar: en Leyendo → paso 1, nada escrito; cerrar en Revisar/Resolver → «¿Descartar la importación?»; en Guardando no se cancela.
- Error al guardar: toast «No se pudo guardar. No se importó nada. Intenta de nuevo.»
- 1RM/récords/mapa: se recalculan solos. No verificado si el sello «PR» de recibos ya guardados es derivado o persistido.

## Relación con ①
Sí entran, retroactivas, etiquetadas. Sesión importada con RPE recibe esfuerzo estimado; `deviceId = nil`, origen «Strong/Hevy». Entra al ACWR y monotonía. Si cae en los últimos 28 días, el veredicto de mañana puede moverse; Listo lo anuncia con número. En Tendencias › Carga esos días llevan «estimada · importada». Sin RPE → «entrenaste, carga sin estimar».

## Accesibilidad
- VO Resolver: fila = grupo «Cable Fly High, en 38 sesiones, sin resolver. Sugerencia: Aperturas en polea alta»; botones sueltos (lección WorkoutImportView.swift:296-302). Resuelto: «Resuelto como …, automático» / «Ignorado». Continuar: «Faltan 4 por resolver, deshabilitado».
- VO progreso: `.updatesFrequently`, hitos.
- Dynamic Type: numeral baja de talla antes de truncar; filas a dos líneas desde AX1; nunca elipsis en el número. Tap targets ≥ 44 pt.

## Edge cases (12)
1. BOM/UTF-16 o `;` → se normaliza; si falla, «no reconocido».
2. Abierto en Excel (fechas reformateadas) → «Fechas ilegibles en 3 filas», omitidas.
3. Nombre vacío → fila omitida, contada.
4. Mayúsculas/acentos → una sola entrada en Resolver.
5. Nombre ambiguo («Row») → nunca auto-match (`autoMatch` exige ≥ 2 tokens, :336).
6. Reps = 0 o peso negativo → serie omitida; sesión se conserva.
7. Sesión sin series válidas → no se crea; omitida.
8. Sin duración (Strong `Duration` vacío) → sin carga estimada aunque haya RPE; el detalle lo dice.
9. Peso corporal con carga añadida → peso = carga añadida.
10. Crear propio y cancelar → el ejercicio ya existe (igual que hoy, :637-649).
11. Dos importaciones del mismo origen con distinto corte → solo entran las nuevas.
12. RPE fuera de 6–10 (Hevy 1–10) → < 6 se guarda como 6 con nota. (CONFLICTO con ux-A edge 11: «no se estima, sin calificar». A resolver.)

## Criterios de aceptación UX (C1–C16)
C1 Bloque «Historial de Strong o Hevy (CSV)» bajo Apple Health; abre hoja de 4 pasos.
C2 Vacío de Historial muestra la línea y abre la misma hoja; hub de primer uso no cambia.
C3 CSV de Strong y de Hevy (kg y lb) se reconocen solos; CSV ajeno → error + «Elegir otro».
C4 Vista previa en ese orden; selector kg/lb solo si el archivo no declara unidad.
C5 Con pendientes, CTA «Resolver N y continuar»; Resolver bloquea hasta resolver o ignorar todos.
C6 Nombre resuelto se recuerda.
C7 Reimportar → «Ya estaban · N», cero sesiones nuevas.
C8 Otro origen a ±30 min se omite por defecto; entra con el interruptor.
C9 Con RPE y duración → «estimada» y aparecen en Tendencias › Carga; sin RPE → «Sin carga…» y no mueven el ACWR.
C10 Listo dice cuántas sesiones de los últimos 28 días entraron a la carga.
C11 Cada sesión importada muestra «Strong»/«Hevy» en fila y sello Fuente; nunca «Medido en el dispositivo».
C12 «Mejor marca» y 1RM reflejan el mejor set importado.
C13 Cancelar en Leyendo deja la base intacta; cerrar en Revisar/Resolver pide confirmación.
C14 30 000 filas → vista previa < 5 s; Cancelar responde.
C15 VO lee cada fila como grupo con botones sueltos; AX5 sin truncar.
C16 Ningún copy dice «medimos» sobre importadas; sin RPE = sin carga.

## Preguntas al dueño
1. ¿Columna `source`/`importKey` en `strength_session` (migración) o tabla aparte de llaves? Recomiendo columna.
2. ¿Ofrecer crear rutinas a partir de los nombres de entreno importados? Recomiendo no en esta ola (candidato ola 2).
