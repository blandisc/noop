#!/usr/bin/env python3
"""Genera el mapa de remapeo de ids ExerciseDB(viejo) → free-exercise-db(nuevo) — FER-923.

El id de ejercicio cambia al migrar la fuente, y 5 tablas on-device lo referencian
(routineExercise, setEntry, personalRecord, exercisePreference, importMatch). La migración
`v33` de CenitStore usa estos recursos para NO orfanar el historial del usuario:

  * exercise-id-remap.json.zlib   → { oldId: newId }  (match EXACTO de nombre normalizado)
  * legacy-exercise-data.json.zlib → { oldId: {name,type,equipment,primaryMuscles,secondaryMuscles} }
       para los viejos que NO matchean → la migración los materializa como customExercise.

Match conservador: solo nombre normalizado idéntico (lowercase, sin acentos, sin puntuación,
whitespace-collapsed). Un match FALSO es peor que no matchear (peor caso: un custom duplicado).

Requiere el catálogo VIEJO desde git:
  git show origin/iOS:Packages/.../exercises.json.zlib  → ./cache/old-exercises.json
Uso: python3 build_remap.py
"""
import json, os, re, zlib, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.path.join(HERE, "cache", "old-exercises.json")           # catálogo ExerciseDB (de git)
NEW = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining", "Resources",
    "exercises.json"))
WHOOPSTORE_RES = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "CenitStore", "Sources", "CenitStore", "Resources"))
OUT_REMAP = os.path.join(WHOOPSTORE_RES, "exercise-id-remap.json.zlib")
OUT_LEGACY = os.path.join(WHOOPSTORE_RES, "legacy-exercise-data.json.zlib")


def norm(name):
    s = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    s = s.lower()
    s = re.sub(r"[^a-z0-9 ]+", " ", s)      # quita puntuación, guiones, paréntesis
    return re.sub(r"\s+", " ", s).strip()


def write_zlib(path, obj):
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    co = zlib.compressobj(9, zlib.DEFLATED, -15)
    open(path, "wb").write(co.compress(data) + co.flush())


def main():
    old = json.load(open(OLD))
    new = json.load(open(NEW))
    # índice nombre-normalizado → newId (primero gana si hay duplicados)
    new_by_norm = {}
    for e in new:
        new_by_norm.setdefault(norm(e["name"]), e["id"])

    # Match SOLO exacto de nombre normalizado. Conservador a propósito: un match falso corrompe
    # el historial del usuario (peor que materializar). Los no-mapeados se materializan como
    # customExercise en la migración v33 → cero pérdida de datos. (Un pase por subconjunto de
    # tokens se probó y metía falsos como 'band bench press'→'reverse band bench press'; descartado.)
    remap, legacy = {}, {}
    for e in old:
        nid = new_by_norm.get(norm(e["name"]))
        if nid and nid != e["id"]:
            remap[e["id"]] = nid
        else:
            legacy[e["id"]] = {
                "name": e["name"], "type": e.get("type", "weightReps"),
                "equipment": e.get("equipment"),
                "primaryMuscles": e.get("primaryMuscles", []),
                "secondaryMuscles": e.get("secondaryMuscles", []),
            }

    os.makedirs(WHOOPSTORE_RES, exist_ok=True)
    write_zlib(OUT_REMAP, remap)
    write_zlib(OUT_LEGACY, legacy)
    print(f"old: {len(old)} · new: {len(new)}")
    print(f"remap (matched old→new): {len(remap)}  -> {OUT_REMAP} ({os.path.getsize(OUT_REMAP)} B)")
    print(f"legacy (unmatched, se materializan): {len(legacy)}  -> {OUT_LEGACY} ({os.path.getsize(OUT_LEGACY)} B)")
    print(f"tasa de match: {len(remap)/len(old)*100:.1f}%")
    # muestra de matches para revisión manual
    print("\nMuestra de matches (old name → newId):")
    om = {e["id"]: e["name"] for e in old}
    for oid, nid in list(remap.items())[:12]:
        print(f"  {om[oid]!r}  →  {nid}")


if __name__ == "__main__":
    main()
