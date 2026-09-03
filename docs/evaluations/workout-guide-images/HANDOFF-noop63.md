# Handoff — Evaluación `bryllim/workout-guide` → imágenes/animaciones de ejercicios para Cénit

> **Para:** la sesión *workout-guide repository evaluation* (rama `claude/workout-guide-analysis-01aedb`, nunca pusheada a origin).
> **De:** sesión `noop-63` (evaluación independiente, repo `blandisc/noop`, rama `claude/reference-application-qsy8ua`).
> **Objetivo:** decidir cómo darle a cada ejercicio del catálogo de Cénit una ilustración (y opcionalmente animación), inspirado en el tweet de Bryl Lim (@bryllim_). Todo lo de abajo está **verificado contra el código**, no supuesto. Los números son medidos.

---

## 0. TL;DR (lo que hay que saber)

- El tweet dice «generé +1000 SVGs con Image Gen». **Falso en el fondo:** el arte base es **open-source (Everkinetic, CC BY-SA 4.0)**; el repo publica **302 ejercicios × 3 frames = 906 SVGs**. La IA solo expandió/normalizó.
- **El método real de vectorización NO usa IA.** Es determinista: `PNG con alfa → potrace → svgo`.
- **Encaja en Cénit sin fricción de arquitectura:** ya tenemos catálogo (`StrandTraining`), pantalla (`ExerciseLibraryScreen`) y **un parser SVG→`Path`** (`StrandDesign/…/SVGPathData.swift`). Generación = build-time ⇒ **offline intacto**.
- **Cobertura si solo adoptamos su set: ~100–150 de nuestros 873 (~12–17%)**, concentrada en levantamientos comunes; el long tail (~700) no recibe nada.
- **Licencia es la decisión de fondo:** arte = **CC BY-SA 4.0** (atribución + share-alike).
- **Animación:** su «animación» = **3 frames fijos que se alternan** (flipbook). Replicable offline. Morphing fluido **no** sale de este método.

---

## 1. Qué es realmente el repo (provenance honesto)

Fuente: `README.md`, `ATTRIBUTION.md`, `LICENSES.md`, `packages/workout-guide/manifest.json`.

- **302 ejercicios × 3 frames = 906 SVGs** + 906 PNG fuente. Transparentes, **512×512**, `viewBox="0 0 512 512"`.
- Arte base = **[Everkinetic](https://github.com/everkinetic/data)**, **CC BY-SA 4.0**. Bryl expandió (más ejercicios/frames, normalización, metadata, gallery Astro). Textual: «Seventy-six first-pose frames are vector-traced adaptations of rasterized Everkinetic SVGs».
- **Formato del SVG:** un solo `<path fill="#fff" fill-rule="evenodd" d="…">` — **silueta rellena monocroma** (recoloreable por `fill`), **NO trazo de una línea**. ~13–19 KB de path cada uno (potrace = cientos de subpaths).
- **`manifest.json`** (566 KB, array de 302). Entrada tipo:
  ```json
  { "id":"exercise-bench-press", "slug":"bench-press", "name":"Bench Press",
    "exerciseType":"weight_reps", "equipment":"Barbell", "primaryMuscle":"Chest",
    "secondaryMuscles":["Triceps","Shoulders"], "isStretch":false,
    "frames":[{ "index":1, "path":"assets/bench-press/frame-1.svg", "width":512, "height":512,
                "format":"svg", "attribution":{ "creator":"Bryl Lim", "license":"CC BY-SA 4.0",
                "source":{ "name":"Everkinetic", "url":"…", "changes":"Rasterized … recolored … vector-traced." }}}, … ]}
  ```
- **API npm** (`src/index.ts`): `getExercise(idOrSlug)`, `searchExercises(query, filters)`, `getAssetUrl(idOrSlug, frameIndex, {baseUrl})`. Búsqueda con `normalizeSearchText` (NFD + lowercase + colapsa no-alfanum).

---

## 2. El método (pipeline exacto) — `scripts/lib/vectorize-png.mjs`

Deps: **`potrace`**, **`sharp`**, **`svgo`**. Runner: `scripts/vectorize-assets.mjs` (recorre `assets/**.png`, escribe `.svg` al lado).

Pasos, por imagen:
1. **`sharp`**: exige canal alfa; `ensureAlpha().extractChannel('alpha').negate().png()` → **máscara** blanco/negro de la silueta.
2. **`potrace`** traza la máscara → SVG. Opciones exactas:
   ```js
   { alphaMax:1, background: potrace.Potrace.COLOR_TRANSPARENT, color:'#fff',
     optCurve:true, optTolerance:0.2, threshold:128, turdSize:0 }
   ```
3. **`svgo`** `optimize(svg, { multipass:true })` → SVG final.

**Clave:** el paso que convierte a vector es **100% determinista** (potrace). La IA («codex + Image Gen») solo sirve para **fabricar/expandir el raster fuente**, no para vectorizar. O sea: si le damos NUESTROS PNG, sale NUESTRO estilo por la misma tubería.

---

## 3. Licencia (la decisión de fondo)

- **Código:** MIT. **Arte (`assets/`):** **CC BY-SA 4.0** (Atribución + **ShareAlike**).
- Para Cénit (app **comercial, cerrada, offline**):
  - ✅ Se **puede** empaquetar; el ShareAlike aplica a los *derivados del arte*, **no** al código de la app. No viola offline (es bundle).
  - ⚠️ Obligaciones: (a) **atribuir** Everkinetic + Bryl + licencia (créditos in-app + repo); (b) si **modificamos el arte** (re-trazar, restilizar, hornear variantes) y lo distribuimos, ese derivado va **también bajo CC BY-SA 4.0**. Recolorear en runtime probablemente no cuenta como derivado distribuido; hornear una versión restilizada sí.
  - Everkinetic upstream tiene la misma licencia y es usable directo (Bryl solo agrega normalización 512×512 + manifest + ejercicios extra).

---

## 4. Encaje en Cénit (hechos del código, con paths)

**Catálogo — `Packages/StrandTraining/Sources/StrandTraining/Exercise.swift`**
- `struct Exercise` (id, name, nameES?, type, equipment?, bodyParts, primaryMuscles, secondaryMuscles, instructions, instructionsES?, gifUrl?).
- `enum ExerciseCatalog`: `.all` (decodifica el resource), `.index`, `.byID`, **`stillURL(id:)`** (mira `Resources/exercise-stills/{id}.jpg`).
- **Resource:** `Resources/exercises.json.zlib` (+ overlay es `exercises.es.json.zlib`). **Apple `.zlib` = DEFLATE raw** → descomprime con `node zlib.inflateRawSync` (NO `inflateSync`/`unzipSync`).
- **Medido:** el resource shippeado tiene **873 ejercicios**, con **ids por nombre** (`Romanian_Deadlift`, `Face_Pull`, `Smith_Machine_Bench_Press`…). ⚠️ El comentario del código dice «la id es la de ExerciseDB (`01qpYSe`)» (FER-779) pero **el resource de este checkout NO** — es un dataset por-nombre. Confirmar en qué estado está la rama real.

**Stills hoy — `Resources/exercise-stills/`**
- **En este checkout hay 1 solo `.jpg`** (los stills están gitignored/LFS fuera del clone). ⇒ **hoy casi las 873 filas caen al placeholder de papel**. El hueco visual es real, no hipotético.

**Pantalla — `Cenit/Screens/ExerciseLibraryScreen.swift`** (+ `ExerciseDetailScreen.swift`)
- Fila = `ExerciseThumbView(exercise:side:52)` con borde 2px en `familyTint` (via `theme.movementFamilyTint(primaryMuscles:)` → push=ámbar/pull=teal/legs=índigo) + nombre (`StrengthDisplay.name`) + subtítulo `músculo·equipo`. Secciones por músculo + banda «Con historial tuyo».

**Render vectorial YA existe — `Packages/StrandDesign/Sources/StrandDesign/LiquidGlass/SVGPathData.swift`**
- `SVGPathData.path(_ d: String) -> Path`: parsea atributo `d` a `Path` de SwiftUI. Subset soportado: **M/L/H/V/C/S/Q/A/Z** (con arcos elípticos). ⚠️ Es **`internal`** (enum sin `public`) ⇒ el componente de render debe vivir **dentro de StrandDesign**.

**Paleta «Instrumento diurno» — `…/StrandDesign/Instrumento.swift` (base/día)**
```
paper #F4F1E8 · surface #FBF9F2 · hairline #E6E0D2 · hairlineStrong #D8D0BD
ink   #221D16 · dataRecovery #0C8F62 (verde) · dataStrain #C4631F (ámbar/ember)
```
(Familias de movimiento aprox: empuje=ember #C4631F, jalón=teal, pierna=índigo.)

---

## 5. Crosswalk medido (números exactos)

- Nuestro catálogo: **873**. Bryl: **302**.
- **Match exacto por nombre: 100/302 (33%).**
- **Match fuzzy por tokens (quita equipo/postura, singulariza, despacia): 148/302 (49%)** — pero con **falsos positivos** (colapsa variantes de equipo: `bench-press`→`Dumbbell Bench Press`, `barbell-row`→`Seated Cable Rows`).
- **Rango honesto de cobertura útil si solo adoptamos: ~100–150 de nuestros 873 (~12–17%)**, en los levantamientos comunes (barra/mancuerna/peso corporal). **Long tail (~700: cardio, máquinas, estiramientos) sin cobertura.**
- Matiz a favor: nuestros nombres están muy calificados por equipo, así que **una silueta genérica de Bryl puede servir a varias variantes nuestras** si mapeamos por **patrón de movimiento** (curación manual) — sube la cobertura útil.
- Artefactos: `crosswalk.json` (100 hits exactos+strip), `hits2.json` (148 fuzzy). Script: `gen-preview.mjs`.

---

## 6. Render en Cénit — detalles técnicos a resolver

- **`fill-rule="evenodd"`:** potrace usa evenodd; SwiftUI `Path` rellena en nonzero por default → renderizar con `FillStyle(eoFill: true)` o `.fill(style:)`.
- **Performance:** paths ~15 KB con cientos de subpaths → **parsear en cada fila de un `LazyVStack` que hace scroll es riesgo**. Cachear el `Path` construido (no re-parsear por frame). Hacer un spike de medición.
- **Horneado (patrón del repo):** un blob comprimido keyed por id, igual que `exercises.json.zlib` → p.ej. `exercise-glyphs.json.zlib` = `{ id: "d-string" }`. Añadir `ExerciseCatalog.glyphPath(id:)` junto a `stillURL(id:)` en `StrandTraining` (Foundation-only, solo guarda el string). El render (SVGPathData + componente SwiftUI) vive en `StrandDesign`. **No rompe la dirección de dependencias** y **no necesita migración de DB** (asset read-only keyed por id existente).
- **Baker dev-time** bajo `Tools/` (espejo de `Tools/bake-exercisedb/`). **Offline intacto:** generación/vectorización es build-time; runtime solo lee bundle, cero red.

---

## 7. Animaciones (con el asterisco importante)

- La «animación» de Bryl = **3 frames fijos** (reposo → medio → contracción) que se **alternan**. Es un **flipbook de 3 páginas**, no movimiento fluido.
- **Replicable idéntico y barato:** alternar/cross-fade entre 3 `Path` con timer. Cénit ya tiene `StrandDesign/…/Motion.swift`.
- **Morphing fluido NO sale de este método:** los paths de potrace **no están alineados** entre frames (distinto número de subpaths) → SwiftUI no puede interpolar suave entre pose A y B. Para fluidez real: **Lottie / Rive**, o **GIF** (Cénit ya tiene los GIF de ExerciseDB como movimiento, **opt-in con red**, en `Cenit/Media/`).
- **Recomendación:** el **swap de 3 frames es el punto dulce** (offline, on-brand, suficiente para reconocer el movimiento). Lottie/Rive es otra liga (peso + librería + trabajo); no mezclar en el primer paso.

---

## 8. Opciones estratégicas

| | Ruta | Costo | Cobertura | Estilo | Licencia |
|---|---|---|---|---|---|
| **A** | Adoptar el set abierto (recolorear a tinta) | crosswalk + curación | ~100–150 de 873 | Everkinetic | CC BY-SA 4.0 |
| **B** | Su pipeline (potrace/sharp/svgo) con **nuestro** raster «Instrumento diurno» | generación + gate anti-slop a escala | ~873 | 100% nuestro | sin licencia ajena |
| **C** | Híbrido: A ya, B para el long tail / converger a estilo propio | lo de A ahora, B después | subset ya, todo después | mixto → propio | mixta |

**Recomendación de esta evaluación: C (híbrido).** Retira ya el hueco visual en los ejercicios más usados con bajo costo, sin bloquear el estilo propio.

---

## 9. Decisiones abiertas (esto es `/pm`)

1. **¿La silueta rellena de Everkinetic pega con «Instrumento diurno»** o se siente ajena / preferimos trazo de una línea? (juzgar sobre el preview HTML — ver §11).
2. **¿La licencia CC BY-SA 4.0 es aceptable** para bundle comercial? (Si no → mata la opción A; B queda intacta.)
3. **Alcance v1:** ¿arrancamos por los ~100–150 comunes, o por *starter-templates + ejercicios con historial + los sin still*?
4. **Animación v1:** ¿3-frame swap sí/no? (Lottie/Rive fuera de v1.)

---

## 10. Proceso (Cénit)

Es feature real con pipeline + componente de design system + asset on-device + **decisión de licencia** ⇒ **carril PESADO**:
`/pm` (requerimiento + criterios; DoD: «offline = generación build-time», «gate de curación», «atribución CC BY-SA») → `/arquitecto` (ligero: glyph blob junto a stills en `StrandTraining`, render en `StrandDesign` con `eoFill` + cache de `Path`, sin migración, baker en `Tools/`) → `/ui` (contrato de estilo + AI Slop Test + preview HTML por estado) → `/implement` + gate `/qa`.

---

## 11. Artefactos de esta sesión

Commiteados en la rama `claude/reference-application-qsy8ua`, carpeta `docs/evaluations/workout-guide-images/`:
- **`HANDOFF.md`** — este documento.
- **`cenit-siluetas-spike.html`** — preview: siluetas reales recoloreadas a tinta sobre papel, layout real de la fila + detalle con 3 frames. Ábrelo en el navegador (autocontenido, SVGs inline).
- **`gen-preview.mjs`** — generador del preview (RECORD: tiene paths hardcodeados al clone `/home/user/bryllim/workout-guide` y al scratchpad de esa sesión; sirve como referencia del método, no corre verbatim en otro entorno).
- **`crosswalk.json`** (100 hits exacto+strip), **`hits2.json`** (148 fuzzy).

Fuera del repo (efímeros de la sesión origen):
- Clone de Bryl: `/home/user/bryllim/workout-guide` (shallow, read-only).
- Catálogo nuestro decodificado desde `Packages/StrandTraining/Sources/StrandTraining/Resources/exercises.json.zlib` (873, `node zlib.inflateRawSync`).

---

## 12. Nota sobre esta otra sesión

La rama `claude/workout-guide-analysis-01aedb` **nunca se pusheó a origin** (`upstream_exists:false`) y no hay transcript local, así que esta evaluación se hizo **independientemente** — no se leyó tu trabajo. Si tú (la sesión) tienes hallazgos adicionales (p.ej. sobre el estado real de las ids ExerciseDB post-FER-779, o los stills LFS), **haz push de tu rama** para poder cruzarlos. Los puntos a validar contra tu trabajo: (1) ¿el catálogo real ya es ExerciseDB `01qpYSe` o sigue por-nombre?; (2) ¿dónde viven los ~1324 stills baked?; (3) ¿algún crosswalk o mapeo por patrón de movimiento que ya hayas construido?
