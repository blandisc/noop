#!/usr/bin/env python3
"""Bake del catálogo de ejercicios — normaliza free-exercise-db al catálogo bundleado (FER-923).

Fuente: free-exercise-db (yuhonas), The Unlicense / dominio público.
  https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json

Lee ./cache/free-exercise-db.json (bajado por pull.py) y escribe:
  * Packages/StrandTraining/.../Resources/exercises.json      (catálogo EN)
  * Packages/StrandTraining/.../Resources/exercises.json.zlib  (raw DEFLATE, lo que lee el app)
  * ./cache/pending-es.json                                    (strings a traducir p/ el overlay es)

Transforms:
  * id      = id nativo de free-exercise-db (slug, ej. "Barbell_Bench_Press_-_Medium_Grip").
  * músculos: free-exercise-db YA usa las 17 llaves canónicas de MuscleAtlas → identidad (0 mapeo).
  * equipment: EQUIP_MAP → llaves de EquipmentVocabulary.
  * bodyParts: derivado de primaryMuscles (MUSCLE_TO_BODYPART) — el app filtra la biblioteca por esto.
  * type: derivado de category/equipment (derive_type).
  * gifUrl: null (sin media; el arte Cénit se hornea aparte, FER-919; el loader deriva gifUrl del still).

Pure/determinista, sin red. Uso: python3 transform.py
"""
import json, os, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "cache", "free-exercise-db.json")
RES = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining", "Resources"))
OUT_EN = os.path.join(RES, "exercises.json")
OUT_ZLIB = os.path.join(RES, "exercises.json.zlib")
OUT_PENDING = os.path.join(HERE, "cache", "pending-es.json")

# Las 17 llaves canónicas de MuscleAtlas — free-exercise-db usa exactamente estas (verificado).
CANON_MUSCLES = {
    "abdominals", "abductors", "adductors", "biceps", "calves", "chest", "forearms",
    "glutes", "hamstrings", "lats", "lower back", "middle back", "neck", "quadriceps",
    "shoulders", "traps", "triceps",
}

# free-exercise-db equipment -> llave de EquipmentVocabulary. Lo no mapeado -> None (opcional en el schema).
EQUIP_MAP = {
    "body only": "body weight", "barbell": "barbell", "dumbbell": "dumbbell",
    "cable": "cable", "machine": "leverage machine", "kettlebells": "kettlebell",
    "bands": "band", "medicine ball": "medicine ball", "exercise ball": "stability ball",
    "e-z curl bar": "ez barbell", "foam roll": "roller", "other": None,
}

# primaryMuscle -> región de BodyPartVocabulary (back, cardio, chest, lower arms, lower legs,
# neck, shoulders, upper arms, upper legs, waist). El app filtra la biblioteca por bodyParts.
MUSCLE_TO_BODYPART = {
    "chest": "chest", "shoulders": "shoulders", "biceps": "upper arms", "triceps": "upper arms",
    "forearms": "lower arms", "lats": "back", "middle back": "back", "lower back": "back",
    "traps": "back", "abdominals": "waist", "quadriceps": "upper legs", "hamstrings": "upper legs",
    "glutes": "upper legs", "abductors": "upper legs", "adductors": "upper legs",
    "calves": "lower legs", "neck": "neck",
}

TIME_SIGNALS = ("stretch", "plank", "hold", "isometric", "wall sit", "wall-sit", "pose", "bridge")


def derive_type(category, equipment):
    c = (category or "").lower()
    if c == "cardio":
        return "distance"
    if c == "stretching":
        return "time"
    if equipment in (None, "body weight"):
        return "bodyweight"
    return "weightReps"


def body_parts(primary, category):
    if (category or "").lower() == "cardio":
        return ["cardio"]
    out = []
    for m in primary:
        bp = MUSCLE_TO_BODYPART.get(m)
        if bp and bp not in out:
            out.append(bp)
    return out


def norm_muscles(names):
    return [m for m in (n.lower().strip() for n in names) if m in CANON_MUSCLES]


def write_zlib(path, obj):
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    co = zlib.compressobj(9, zlib.DEFLATED, -15)   # raw DEFLATE == Apple Compression .zlib
    open(path, "wb").write(co.compress(data) + co.flush())


def main():
    src = json.load(open(SRC))
    recs = []
    for e in src:
        raw_eq = (e.get("equipment") or "").lower().strip() or None
        equip = EQUIP_MAP.get(raw_eq, None)
        prim = norm_muscles(e.get("primaryMuscles", []))
        name = e["name"].strip()
        typ = derive_type(e.get("category"), equip)
        if typ == "weightReps" and any(s in name.lower() for s in TIME_SIGNALS):
            typ = "time"
        recs.append({
            "id": e["id"],
            "name": name,
            "type": typ,
            "equipment": equip,
            "bodyParts": body_parts(prim, e.get("category")),
            "primaryMuscles": prim,
            "secondaryMuscles": norm_muscles(e.get("secondaryMuscles", [])),
            "instructions": [s.strip() for s in e.get("instructions", []) if s.strip()],
            "gifUrl": None,
        })
    recs.sort(key=lambda r: r["name"].lower())

    json.dump(recs, open(OUT_EN, "w"), ensure_ascii=False, indent=1)
    write_zlib(OUT_ZLIB, recs)

    pending = []
    for r in recs:
        pending.append({"id": r["id"], "field": "name", "idx": 0, "en": r["name"]})
        for i, ins in enumerate(r["instructions"]):
            pending.append({"id": r["id"], "field": "instructions", "idx": i, "en": ins})
    os.makedirs(os.path.dirname(OUT_PENDING), exist_ok=True)
    json.dump(pending, open(OUT_PENDING, "w"), ensure_ascii=False)

    from collections import Counter
    print(f"exercises: {len(recs)} -> {OUT_EN} (+ .zlib {os.path.getsize(OUT_ZLIB)} B)")
    print(f"type: {dict(Counter(r['type'] for r in recs))}")
    print(f"equipment nulls: {sum(1 for r in recs if r['equipment'] is None)}")
    print(f"no primaryMuscles: {sum(1 for r in recs if not r['primaryMuscles'])}")
    print(f"no bodyParts: {sum(1 for r in recs if not r['bodyParts'])}")
    print(f"pending es strings: {len(pending)}")
    bad = {m for r in recs for m in r["primaryMuscles"] + r["secondaryMuscles"] if m not in CANON_MUSCLES}
    print(f"muscles fuera de las 17 llaves: {bad or 'NINGUNO'}")


if __name__ == "__main__":
    main()
