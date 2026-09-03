# Decisión — imágenes/animaciones de ejercicio para Cénit (`bryllim/workout-guide`)

> **Consolida:** el handoff de `noop-63` (rama `claude/reference-application-qsy8ua`,
> `HANDOFF-noop63.md`) + la evaluación de esta rama (`claude/workout-guide-analysis-01aedb`,
> artifact `3ca7d941-322f-4fb1-8628-86d980ee84bf`).
> **Autor:** sesión workout-guide-analysis. **Fecha:** 2026-09-03. Todo verificado contra código, git e X.

## 1. Las dos evaluaciones coinciden en lo esencial

Ambas, hechas por separado, llegaron a los mismos hechos:

- El repo es **302 ejercicios × 3 frames = 906 SVG**, arte base **Everkinetic**, licencia **CC BY-SA 4.0**.
- El SVG es **silueta rellena monocroma** (`<path fill="#fff" fill-rule="evenodd">`), no trazo de una línea. Recoloreable por `fill`.
- El método de vectorización es **determinista, sin IA**: `PNG con alfa → sharp (máscara) → potrace → svgo`. La IA solo fabrica el ráster fuente.
- **Cobertura si solo adoptamos su set: baja.** Medición de noop-63: **100/302 exactos, 148/302 fuzzy** (con falsos positivos por colapso de equipo). El long tail (~700: cardio, máquinas, estiramientos) no recibe nada.
- **Animación = flipbook de 3 frames** que se alternan. Replicable offline. Morphing fluido NO sale de este método (los paths de potrace no están alineados entre frames).
- **Encaja sin fricción:** ya existe catálogo (`StrandTraining`), pantalla (`ExerciseLibraryScreen`), parser `SVGPathData` (en `StrandDesign`, `internal`), y el hueco `stillURL(id:)`. Generación build-time ⇒ offline intacto.

## 2. Lo que ESTA sesión aporta encima del handoff

- **Provenance confirmada en la fuente.** El handoff dice «la IA solo expandió». Lo verifiqué en X directo: Bryl Lim (@bryllim_, 24–25 ago 2026) escribió «Generated over a 1000 svgs on my workout app with @thsottiaux's codex with Image Gen» y «Mine were png -> svg». O sea el ráster se generó con **Codex + Image Gen de OpenAI**, luego **potrace**. **Esto refuerza la opción B:** el proceso completo es reproducible con NUESTRO motor de imágenes, no depende del autor.
- Nunca publicó prompts ni figura de referencia; a quien le pidió el proceso no respondió. No hay «guía de cómo hacerlos» en ningún lado — solo esas dos frases.

## 3. Dónde el handoff estaba desactualizado (correcciones medidas)

Ver §5 para las 3 preguntas del §12 del handoff. Dos supuestos del handoff resultaron falsos:

1. **Los ~1324 stills NO están en LFS/gitignore. Fueron BORRADOS.** FER-800 (#762) horneó stills por id de ExerciseDB; FER-923 (#971) migró a free-exercise-db (que no trae media) y **eliminó** esos stills. El dir hoy ships vacío salvo `README.md`. El «~1324» del comentario en `Exercise.swift:105` es texto viejo de la era FER-800.
2. **El catálogo NO usa ids de ExerciseDB.** El comentario `Exercise.swift:16-17` («Since FER-779 the catalog IS ExerciseDB … 01qpYSe») quedó **stale**: FER-923 (#971) revirtió el esquema a **por-nombre** (`Romanian_Deadlift`). El recurso shippeado son **873 por-nombre, 0 tipo `01qpYSe`**. El handoff midió lo mismo y marcó la duda; queda **confirmada**: gana el recurso, el comentario miente.

## 4. Recomendación: **B (pipeline propio), sin puente A**

El handoff recomienda **C (híbrido: A ya + B después)**. Yo recomiendo **B directo**, por tres razones que el handoff no pondera:

1. **Consistencia > velocidad.** A cubre solo ~100–150 en estilo Everkinetic; el resto quedaría en otro estilo. Eso deja la app con **dos estilos de ilustración conviviendo** durante semanas. El dueño es perfeccionista de consistencia (regla `quisquilloso`): «la misma cosa se ve igual en todas partes». Un puente A que hay que desmontar cuesta más de lo que ahorra.
2. **Ya tenemos con qué hacer B, y es el mismo método del repo.** FER-919 dejó receta de-riesgada: figura maestra + generación por lote, estilo «Balance» aprobado. La confirmación de que Bryl hizo exactamente eso (ráster IA → potrace) cierra el círculo. B da **873/873 en un solo estilo propio, sin licencia ajena, sin crosswalk**.
3. **La licencia se evita entera.** B no arrastra CC BY-SA 4.0 (atribución + share-alike + pantalla de créditos). Con B el arte es 100% nuestro.

**Cuándo A/C sí valdría:** solo si el dueño quiere el hueco cerrado **esta semana** en los levantamientos comunes y acepta (a) el periodo de dos estilos y (b) la obligación CC BY-SA. Si esa urgencia no existe, B es la ruta limpia.

### Forma de B (technical, del handoff — lo suscribo)
- **Baker dev-time** en `Tools/` (espejo de `Tools/bake-exercisedb/`): genera ráster «Balance» → `sharp → potrace → svgo`.
- Hornear a **`exercise-glyphs.json.zlib`** = `{ id: "d-string" }`, keyed por el id por-nombre actual. Añadir `ExerciseCatalog.glyphPath(id:)` junto a `stillURL(id:)` en `StrandTraining` (Foundation-only). **Sin migración de DB.**
- Render en `StrandDesign` (donde vive `SVGPathData`): `Path` con `FillStyle(eoFill: true)` + **cache del Path** (no re-parsear por fila del `LazyVStack`). Spike de performance primero.
- **Animación v1:** swap de 3 frames. Lottie/Rive fuera de v1.
- Offline intacto: todo build-time, runtime solo lee bundle.

## 5. Respuestas a las 3 preguntas abiertas (§12 del handoff)

- **(a) ¿ids ExerciseDB o por-nombre?** → **Por-nombre.** El recurso shippeado tiene 873 con ids tipo `Romanian_Deadlift` (0 tipo `01qpYSe`). El comentario de `Exercise.swift` que dice «FER-779 → ExerciseDB `01qpYSe`» está **stale**: FER-923 (#971) revirtió a free-exercise-db por-nombre. Cualquier mapeo debe usar los ids por-nombre.
- **(b) ¿Dónde viven los ~1324 stills baked?** → **Ya no existen.** FER-800 (#762) los horneó por id de ExerciseDB; FER-923 (#971) los **borró** al migrar a free-exercise-db (sin media). `exercise-stills/` ships vacío (solo `README.md`); `stillURL` devuelve `nil` para todo. **Hoy casi las 873 filas caen al placeholder de papel** — el hueco es real. No es LFS.
- **(c) ¿Construí un crosswalk/mapeo por patrón de movimiento?** → **No uno mejor que el suyo.** Mi match fuzzy dio ~180/302 pero con umbral más laxo (infla con falsos positivos). El de noop-63 (100 exacto / 148 fuzzy, con los falsos positivos ya marcados en `crosswalk.json`/`hits2.json`) es **más honesto y lo adopto como el bueno.** No construí un mapa manual por patrón de movimiento; si se va por A/C, ese mapa es trabajo de curación de `/pm`.

## 6. Proceso
Carril **PESADO** (pipeline + componente de design system + asset on-device + decisión de licencia si aplica A):
`/pm` → `/arquitecto` (glyph blob + render eoFill + cache, sin migración, baker en Tools) → `/ui` (estilo «Balance» + AI Slop Test + preview HTML por estado) → `/implement` + gate `/qa`.
Si el dueño elige B: la decisión de licencia desaparece del alcance.

## 7. Artefactos
- `HANDOFF-noop63.md` (evaluación independiente de noop-63).
- `crosswalk.json` (100 exactos), `hits2.json` (148 fuzzy) — de noop-63.
- Preview de siluetas recoloreadas a tinta: `cenit-siluetas-spike.html` (en la rama de noop-63) + mi artifact `3ca7d941-322f-4fb1-8628-86d980ee84bf`.
