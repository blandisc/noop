#!/usr/bin/env python3
"""Stage 2 of the ExerciseDB bake — normalize the raw OSS cache into the bundled catalog.

Reads ./cache/oss_pages.ndjson (from pull.py) and writes the English catalog resource
`Packages/StrandTraining/.../Resources/exercises.json` plus `pending-es.json` (the strings
the es-MX overlay still needs). Pure/deterministic; no network.

Key transforms (see README for the why):
  * id  = native EDB exerciseId (e.g. "01qpYSe")
  * muscles: OSS's ~50 fine names are normalized DOWN to NOOP's 17 canonical MuscleAtlas keys
    (MUSCLE_MAP), so MuscleAtlas / MuscleVocabulary / MuscleFatigueMap stay untouched.
  * type: derived from equipments/bodyParts/name (derive_type).
  * instructions: the "Step:N " prefix is stripped.
  * gifUrl: kept as a string only (media is fetched lazily via the opt-in flow, FER-722).

Usage:  python3 transform.py
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache", "oss_pages.ndjson")
RES = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining", "Resources"))
OUT_EN = os.path.join(RES, "exercises.json")
OUT_PENDING = os.path.join(HERE, "cache", "pending-es.json")

# OSS muscle name -> one of NOOP's 17 canonical MuscleAtlas keys. Anything not here is DROPPED
# from primary/secondary (it doesn't map to a silhouette region and doesn't feed the load math).
MUSCLE_MAP = {
    "abdominals": "abdominals", "abs": "abdominals", "core": "abdominals",
    "lower abs": "abdominals", "obliques": "abdominals", "serratus anterior": "abdominals",
    "abductors": "abductors",
    "adductors": "adductors", "inner thighs": "adductors", "groin": "adductors",
    "biceps": "biceps", "brachialis": "biceps",
    "calves": "calves", "soleus": "calves", "shins": "calves",
    "chest": "chest", "pectorals": "chest", "upper chest": "chest",
    "forearms": "forearms", "wrist extensors": "forearms", "wrist flexors": "forearms",
    "grip muscles": "forearms", "wrists": "forearms", "hands": "forearms",
    "glutes": "glutes",
    "hamstrings": "hamstrings",
    "lats": "lats", "latissimus dorsi": "lats",
    "lower back": "lower back", "spine": "lower back",
    "middle back": "middle back", "back": "middle back", "upper back": "middle back",
    "rhomboids": "middle back",
    "neck": "neck", "levator scapulae": "neck", "sternocleidomastoid": "neck",
    "quadriceps": "quadriceps", "quads": "quadriceps", "hip flexors": "quadriceps",
    "shoulders": "shoulders", "deltoids": "shoulders", "delts": "shoulders",
    "rear deltoids": "shoulders", "rotator cuff": "shoulders",
    "traps": "traps", "trapezius": "traps",
    "triceps": "triceps",
    # deliberately dropped (no silhouette region): cardiovascular system, ankles,
    # ankle stabilizers, feet
}
DROP_MUSCLES = {"cardiovascular system", "ankles", "ankle stabilizers", "feet"}

CARDIO_EQUIP = {"stationary bike", "elliptical machine", "stepmill machine",
                "skierg machine", "upper body ergometer"}
TIME_SIGNALS = ("stretch", "plank", "hold", "isometric", "wall sit", "wall-sit", "pose")

STEP = re.compile(r"^\s*Step\s*:?\s*\d+\s*[\.\)]?\s*", re.I)


def norm_muscles(names):
    out = []
    for m in names:
        k = MUSCLE_MAP.get(m.lower().strip())
        if k and k not in out:
            out.append(k)
    return out


def derive_type(equipments, body_parts, name):
    eq = {e.lower() for e in equipments}
    bp = {b.lower() for b in body_parts}
    n = name.lower()
    if "cardio" in bp and eq & CARDIO_EQUIP:
        return "distance"
    if any(s in n for s in TIME_SIGNALS):
        return "time"
    if "cardio" in bp:
        return "time"
    if eq <= {"body weight", "assisted"}:
        return "bodyweight"
    return "weightReps"


def load_unique():
    by_id = {}
    for line in open(CACHE):
        line = line.strip()
        if not line:
            continue
        for e in json.loads(line).get("data", []):
            by_id[e["exerciseId"]] = e
    return list(by_id.values())


def main():
    recs = []
    unmapped = {}
    for e in load_unique():
        for m in e.get("targetMuscles", []) + e.get("secondaryMuscles", []):
            ml = m.lower().strip()
            if ml not in MUSCLE_MAP and ml not in DROP_MUSCLES:
                unmapped[ml] = unmapped.get(ml, 0) + 1
        recs.append({
            "id": e["exerciseId"],
            "name": e["name"].strip(),
            "type": derive_type(e.get("equipments", []), e.get("bodyParts", []), e["name"]),
            "equipment": (e.get("equipments") or [None])[0],
            "bodyParts": [b.lower().strip() for b in e.get("bodyParts", [])],
            "primaryMuscles": norm_muscles(e.get("targetMuscles", [])),
            "secondaryMuscles": norm_muscles(e.get("secondaryMuscles", [])),
            "instructions": [STEP.sub("", s).strip() for s in e.get("instructions", []) if STEP.sub("", s).strip()],
            "gifUrl": e.get("gifUrl"),
        })
    recs.sort(key=lambda r: r["name"].lower())
    with open(OUT_EN, "w") as f:
        json.dump(recs, f, ensure_ascii=False, indent=1)

    pending = []
    for r in recs:
        pending.append({"id": r["id"], "field": "name", "idx": 0, "en": r["name"]})
        for i, ins in enumerate(r["instructions"]):
            pending.append({"id": r["id"], "field": "instructions", "idx": i, "en": ins})
    with open(OUT_PENDING, "w") as f:
        json.dump(pending, f, ensure_ascii=False)

    from collections import Counter
    types = Counter(r["type"] for r in recs)
    print(f"exercises: {len(recs)} -> {OUT_EN}")
    print(f"type distribution: {dict(types)}")
    print(f"pending es strings: {len(pending)}")
    if unmapped:
        print(f"UNMAPPED muscles (dropped): {dict(sorted(unmapped.items(), key=lambda kv:-kv[1]))}")


if __name__ == "__main__":
    main()
