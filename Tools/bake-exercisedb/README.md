# bake-exercisedb — regenerar el catálogo de ejercicios

Cénit es **offline**: el catálogo de ejercicios se **hornea** (predescarga) en tiempo de _build_,
nunca en runtime. Este pipeline toma el dataset abierto de **ExerciseDB OSS**
(`oss.exercisedb.dev`, sin llave) y produce los dos recursos que ship la app (FER-779):

- `Packages/StrandTraining/.../Resources/exercises.json` — catálogo inglés, ~1500 ejercicios con
  **id nativo** de ExerciseDB (ej. `01qpYSe`).
- `Packages/StrandTraining/.../Resources/exercises.es.json` — overlay es-MX (nombre + instrucciones),
  traducido por un LLM en el bake.

En runtime la app **no llama a ninguna API**: los datos son estáticos y el GIF (`gifUrl`) se baja
solo con el toggle opt-in de media (FER-722).

## Cómo regenerar

```bash
cd Tools/bake-exercisedb

# 1) Descargar el dataset OSS a ./cache/oss_pages.ndjson (1500 únicos; reanudable).
python3 pull.py

# 2) Normalizar → exercises.json (EN) + cache/pending-es.json (textos a traducir).
python3 transform.py

# 3) Traducir cache/pending-es.json a es-MX. Los textos ÚNICOS se traducen una vez
#    (dedupe: ~6k de ~10k). En esta base se hizo con un workflow de agentes Sonnet que
#    escriben lotes {en: es} a un directorio; cualquier traductor sirve mientras produzca
#    archivos batch-*.json con ese formato.
#    Los NOMBRES siguen la guía de estilo STYLE-ES.md (FER-795) — pégala en el prompt
#    del traductor; las verificaciones de salida también viven ahí.

# 4) Ensamblar el overlay es-MX desde los lotes traducidos.
python3 build_es_overlay.py <dir_de_lotes> [<dir2> ...]

# 5) Regenerar la tabla de alias del import (FER-794): nombres comunes de gym → id nativo.
#    Falla en voz alta si un ejercicio referenciado desapareció del catálogo.
python3 build_aliases.py

# 6) Hornear los stills de fila + podar media muerta (FER-800). Descarga cada gifUrl, extrae el
#    PRIMER FRAME a Resources/exercise-stills/{id}.jpg (~1324, ~8 MB) y pone gifUrl=null en las
#    404 del CDN (~176). Idempotente/reanudable: salta los stills que ya existen. Requiere Pillow.
python3 bake_stills.py
```

`./cache/` está gitignored (dataset crudo + artefactos intermedios). Solo se commitean los dos
`.json` de `Resources/`.

## Transformaciones clave (`transform.py`)

- **id** = `exerciseId` nativo de ExerciseDB → media/datos casan sin emparejar por nombre.
- **Músculos**: los ~50 nombres finos de OSS se **normalizan a las 17 keys canónicas** de
  `MuscleAtlas` (`MUSCLE_MAP`), para no tocar la silueta ni la matemática de fatiga. Cardio
  (`cardiovascular system`) no mapea a ninguna región → queda sin `primaryMuscles` (correcto).
- **type** (`ExerciseType`) se **deriva** de `equipments`/`bodyParts`/`name` (`derive_type`); el
  usuario puede corregirlo por ejercicio con el override existente (v24).
- **instructions**: se les quita el prefijo `Step:N `.
- **gifUrl**: se guarda como string; `bake_stills.py` (paso 6) lo pone en `null` si el CDN da 404.
  El GIF animado se baja opt-in (no se hornea el binario); el **still** de fila SÍ se hornea (FER-800).

## Notas del endpoint OSS

- Paginación por `after=<nextCursor>`; el cursor **da vueltas** al agotar → hay que deduplicar por
  `exerciseId` (1500 únicos).
- El TLS del host es inestable con `urllib`/Python 3.9 → `pull.py` usa `curl` con reintentos.
