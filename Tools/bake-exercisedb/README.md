# bake-exercisedb — regenerar el catálogo de ejercicios

Cénit es **offline**: el catálogo de ejercicios se **hornea** (predescarga) en tiempo de _build_,
nunca en runtime. Este pipeline toma el dataset abierto **free-exercise-db** (yuhonas) y produce los
recursos que ship la app.

**Fuente (FER-923):** [free-exercise-db](https://github.com/yuhonas/free-exercise-db) — 873
ejercicios reales (sin la basura de duplicados/variantes de ExerciseDB), **licencia The Unlicense
(dominio público)**, `primaryMuscles` al 100%, un solo `dist/exercises.json` offline. Sustituye a
ExerciseDB OSS (~1500, **licencia no-comercial** + mucha basura), que era un riesgo legal para un app
comercial. Como Cénit pone su **propio arte** (FER-919), la base solo necesita datos limpios +
licencia sana, no media.

Recursos generados:

- `Packages/StrandTraining/.../Resources/exercises.json(.zlib)` — catálogo inglés, 873 ejercicios con
  **id nativo** de free-exercise-db (slug, ej. `Barbell_Bench_Press_-_Medium_Grip`).
- `Packages/StrandTraining/.../Resources/exercises.es.json(.zlib)` — overlay es-MX (nombre +
  instrucciones), traducido por un LLM en el bake.
- `Packages/StrandImport/.../Resources/exercise-aliases.json` — nombres comunes de gym → id nativo.
- `Packages/WhoopStore/.../Resources/{exercise-id-remap,legacy-exercise-data}.json.zlib` — los mapas
  que alimentan la **migración v33** que remapea el historial del usuario de los ids viejos
  (ExerciseDB) a los nuevos (ver `build_remap.py`).

En runtime la app **no llama a ninguna API**: los datos son estáticos y el catálogo nuevo no trae
media (el arte propio se hornea aparte en FER-919).

## Cómo regenerar

```bash
cd Tools/bake-exercisedb

# 1) Descargar free-exercise-db a ./cache/free-exercise-db.json (873).
python3 pull.py

# 2) Normalizar → exercises.json(.zlib) (EN) + cache/pending-es.json (textos a traducir, 4593).
python3 transform.py

# 3) Traducir cache/pending-es.json a es-MX. Los textos ÚNICOS se traducen una vez
#    (dedupe: ~3.9k de 4593). En esta base se hizo con un workflow de agentes que escriben
#    lotes {en: es} a un directorio; cualquier traductor sirve mientras produzca archivos
#    batch-*.json con ese formato.
#    Los NOMBRES siguen la guía de estilo STYLE-ES.md (FER-795) — pégala en el prompt del traductor.

# 4) Ensamblar el overlay es-MX desde los lotes traducidos → exercises.es.json(.zlib).
python3 build_es_overlay.py <dir_de_lotes> [<dir2> ...]

# 5) Regenerar la tabla de alias del import (FER-794): nombres comunes de gym → id nativo.
#    Falla en voz alta si un ejercicio referenciado desapareció del catálogo.
python3 build_aliases.py

# 6) (Solo migración de ids, FER-923) Regenerar los mapas old→new del remapeo de historial.
#    Requiere el cache viejo de ExerciseDB (oss_pages.ndjson) para leer los nombres viejos.
python3 build_remap.py
```

`./cache/` está gitignored (dataset crudo + artefactos intermedios). Solo se commitean los `.json(.zlib)`
de `Resources/`.

## Transformaciones clave (`transform.py`)

- **id** = id nativo (slug) de free-exercise-db.
- **Músculos**: free-exercise-db **ya usa las 17 keys canónicas** de `MuscleAtlas` → identidad, cero
  mapeo (verificado: 0 músculos fuera de las llaves). Cardio queda con `bodyParts == ["cardio"]`.
- **equipment**: `EQUIP_MAP` → llaves de `EquipmentVocabulary` (lo no mapeado → `null`, opcional).
- **bodyParts**: derivado de `primaryMuscles` (`MUSCLE_TO_BODYPART`) — el app filtra la biblioteca por esto.
- **type** (`ExerciseType`) se **deriva** de `category`/`equipment`/`name` (`derive_type`); el usuario
  puede corregirlo por ejercicio con el override existente (v24).
- **gifUrl**: `null` (sin media; el arte Cénit se hornea aparte en FER-919; el loader deriva `gifUrl`
  del still si existe).

## Migración de ids del historial (`build_remap.py` + v33)

Al cambiar la fuente, los ids de ejercicio cambian. El historial del usuario los referencia, así que
`build_remap.py` produce dos mapas (por **nombre exacto normalizado**): `exercise-id-remap` (old→new,
los que tienen match, 132) y `legacy-exercise-data` (old→datos, los sin match, 1368). La migración
**v33** de `WhoopStore` (con su `MigrationTests.testV33Remap`) los usa para reescribir los ids del
historial y materializar los no-mapeados como `customExercise` — **cero entrenamientos huérfanos**.
