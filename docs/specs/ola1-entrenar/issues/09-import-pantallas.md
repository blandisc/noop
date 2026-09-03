## Contexto
Con el lector de E8, falta la puerta: cuatro pasos en Ajustes › Datos y fuentes › Importar, la entrada desde el historial vacío, y el resultado honesto. Fuente: `ux-C.md` con E12/E19/E23/E25 (v2–v5), N5/N6 (v3), D-Q9, D-Q12 (ningún copy promete veredicto).

## Objetivo
Importar Strong/Hevy/Cénit en cuatro pasos (Archivo → Revisar → Resolver → Listo), sin adivinar nada, con duplicados visibles y récords recalculados.

**Carril:** pesado (flujo nuevo sobre datos). Preview HTML con el dueño.

## Comportamiento esperado
- Entrada: bloque «Historial de Strong o Hevy (CSV)» bajo «Exportación de Apple Health» en `DataSourcesView` (Import); en Historial vacío: «¿Vienes de Strong o Hevy? Importa tu historial ›». NO en el first-run del hub.
- Paso 1 «Tu historial, de Strong o Hevy» · kicker «Importar historial · un archivo, cero red»; filas plegadas con instrucciones («Strong: Perfil › Ajustes › Exportar datos» / «Hevy: Ajustes › Exportar CSV»; verificar rutas en las apps vigentes); botón «Elegir archivo .csv…» (`fileImporter`, `.commaSeparatedText`); pie «Cénit reconoce cuál de las dos es por sus columnas. Nada sale de tu teléfono.»
- Paso 2 «Revisar»: numeral «214 sesiones» · «Strong · ene 2022 a ago 2026»; filas: «Ejercicios reconocidos · 61 de 68», «Por resolver · 7 ›», «Con esfuerzo · 140 de 214» + «Estas entran a tu carga como estimadas. Las demás quedan sin carga.», «Posibles duplicados · 2 · fuera» (toggle por fila = forzar), «Unidad de peso · kg» (selector kg/lb solo si el archivo no la declara, con pista). CTA «Importar 214 sesiones» / «Resolver 7 y continuar».
- Paso 3 «Resolver»: componente compartido de mapeo (verbatim + «en 38 sesiones», sugerencia ✦ «¿Quisiste decir… Aperturas en polea alta?» + «Usar», botones cortos «Catálogo · Crear propio · Ignorar»; «Ignorar deja fuera 38 series; la sesión sí se importa»). Bloquea hasta resolver o ignorar todos. Se recuerda (alias aprendido).
- Progreso: «Leyendo… 120 de 214» (cancelable) → «Guardando… Ya casi» (no cancelable; una transacción).
- Paso 4 «Listo»: «214 sesiones en tu historial» · «Récords, 1RM y mapa muscular ya se recalcularon con tu historia.» · si N > 0: «N sesiones entran a tu carga» donde N = las que el overlay fusiona; si N = 0: «Tu historia ya alimenta récords y 1RM. Tu carga arranca con tu reloj o con tus próximas sesiones.» · si hubo duplicados fuera: «2 posibles duplicados se dejaron fuera; revísalos en Ajustes › Datos y fuentes › Importar». Acciones: «Ver historial» · si no hay plan «Arma tu semana» · «Listo». **Ninguna frase menciona el veredicto.**
- Después: sello «Strong»/«Hevy» en fila e historial y en el sello Fuente del detalle; detalle «Estimado de tu historial importado» o «Sin carga · el archivo no trae esfuerzo».

## Estados / errores (copy)
No reconocido: «No reconozco este archivo. Cénit lee el CSV que exportan Strong y Hevy. Revisa que sea el .csv original, sin editar.» «Elegir otro». Columnas faltantes: «Al archivo le faltan columnas: reps, peso. Exporta de nuevo desde la app y vuelve a intentarlo.» Reimportar el mismo: «Ya estaban · 214», CTA deshabilitado «Nada nuevo por importar». Cancelar en Revisar/Resolver: «¿Descartar la importación?». Error al guardar: «No se pudo guardar. No se importó nada. Intenta de nuevo.» Fechas ilegibles: «Fechas ilegibles en 3 filas» (omitidas, contadas). Zona horaria: «Las horas se leen en tu zona horaria actual.» Superseries: «Las superseries se guardan como ejercicios seguidos.»

## Accesibilidad
Resolver: cada fila un grupo («Cable Fly High, en 38 sesiones, sin resolver. Sugerencia: Aperturas en polea alta»), botones sueltos; «Faltan 4 por resolver, deshabilitado». Progreso `.updatesFrequently` con hitos. Dynamic Type: el numeral baja de talla antes de truncar; filas a dos líneas desde AX1; tap targets ≥ 44 pt.

## Alcance técnico
`Cenit/Screens/DataSourcesView.swift:177-217, 701-723`, extraer `mappingFlow` de `WorkoutImportView.swift:261-380` a un componente compartido, `WorkoutHistoryScreen.swift:1166-1178, 1924-1946` (vacío + sello), `WorkoutDetailScreen.swift`. Solo tokens StrandDesign; regla de selectores (acciones = botones cortos; unidad kg/lb = riel segmentado).

## Fuera de alcance
Lector (E8). Rutinas desde nombres (D-Q9).

## Criterios de aceptación
- [ ] C1 Bloque nuevo bajo Apple Health; abre la hoja de 4 pasos. C2 Vacío de Historial muestra la línea y abre la misma hoja; el hub de primer uso no cambia.
- [ ] C3 CSV de Strong y de Hevy (kg y lb) se reconocen solos; CSV ajeno → error + «Elegir otro».
- [ ] C4 Vista previa en ese orden; selector kg/lb solo si el archivo no declara unidad.
- [ ] C5 Con pendientes, CTA «Resolver N y continuar»; Resolver bloquea hasta resolver o ignorar todos. C6 El nombre resuelto se recuerda.
- [ ] C7 Reimportar → «Ya estaban · N», cero sesiones nuevas. C8 Posibles duplicados listados, fuera por defecto, entran con el toggle.
- [ ] C9 Listo dice N real de sesiones fusionadas o el copy alterno; ninguna cadena del flujo contiene «veredicto».
- [ ] C10 Cada sesión importada muestra «Strong»/«Hevy»; nunca «Medido en el dispositivo». C11 «Mejor marca» y 1RM reflejan lo importado.
- [ ] C12 Cancelar en Leyendo deja la base intacta; cerrar en Revisar/Resolver pide confirmación. C13 30 000 filas → vista previa < 5 s; Cancelar responde.
- [ ] C14 VoiceOver y AX5 según arriba.

## Definition of Done
- [ ] Preview aprobado; `Tools/verify.sh app` verde; /qa PASS; claves `es` + `en` (nunca `es-MX`).
