#!/usr/bin/env python3
"""Derive the import-alias table (FER-794) — common gym names → native ExerciseDB id.

FER-779 replaced the curated catalog with ExerciseDB OSS (1500 hyper-specific entries: 37 "bench
press" variants, no plain "press militar de pie"), which broke the import matcher's name tier.
This script restores the bridge the retired synonym table (FER-522) provided: it maps the
~popular names people actually write in training plans (es-MX + EN) to the catalog entry that
best represents the *basic* variant of the movement.

The mapping is keyed by the catalog's exact English `name` (stable across re-bakes as long as
the dataset keeps the exercise), so it's reviewable and re-derivable: run again after a re-bake
and it fails loudly if a referenced exercise disappeared.

Output: Packages/StrandImport/Sources/StrandImport/Resources/exercise-aliases.json
        { "<alias as a human writes it>": "<native id>" } — the Swift loader normalizes keys.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandTraining", "Sources", "StrandTraining",
    "Resources", "exercises.json"))
OUT = os.path.abspath(os.path.join(
    HERE, "..", "..", "Packages", "StrandImport", "Sources", "StrandImport",
    "Resources", "exercise-aliases.json"))

# movement → (candidate catalog EN names, first that exists wins) + the aliases that map to it.
# Aliases are written the way a person types them (accents optional in lookups — the Swift
# normalizer strips diacritics). Keep aliases UNambiguous: never a bare word ("press", "remo")
# that could mean several movements — the adversarial trap test enforces this.
MOVES = [
    # — Pecho
    (["Barbell Bench Press - Medium Grip", "Bench Press - Powerlifting"],
     ["press de banca", "press banca", "press banca con barra", "press de pecho con barra",
      "bench press", "flat bench press", "press plano", "press de banca plano",
      "press plano con barra"]),
    (["Barbell Incline Bench Press - Medium Grip"],
     ["press inclinado", "press inclinado con barra", "incline bench press",
      "press de banca inclinado"]),
    (["Incline Dumbbell Press"],
     ["press inclinado con mancuernas", "incline dumbbell press", "incline dumbbell bench press"]),
    (["Dumbbell Bench Press"],
     ["press de banca con mancuernas", "press plano con mancuernas", "dumbbell bench press"]),
    (["Close-Grip Barbell Bench Press"],
     ["press cerrado", "press de banca agarre cerrado", "close grip bench press"]),
    (["Smith Machine Bench Press"],
     ["press de banca en smith", "press de banca en maquina smith"]),
    (["Leverage Chest Press", "Machine Bench Press", "Cable Chest Press"],
     ["press de pecho en maquina", "chest press", "machine chest press"]),
    (["Butterfly", "Reverse Machine Flyes"],
     ["pec deck", "peck deck", "contractor de pecho", "aperturas en maquina", "mariposa en maquina",
      "pec fly", "machine fly"]),
    (["Incline Dumbbell Flyes", "Incline Cable Flye"],
     ["aperturas inclinadas", "apertura inclinada", "incline fly"]),
    (["Dumbbell Flyes"],
     ["aperturas con mancuernas", "aperturas planas", "vuelos de pecho", "dumbbell fly", "flyes"]),
    (["Cable Crossover", "Flat Bench Cable Flyes"],
     ["aperturas en polea", "cruce de poleas", "cable crossover", "crossover en polea", "cable fly"]),
    (["Dips - Chest Version"],
     ["fondos", "fondos en paralelas", "dips", "fondos de pecho", "chest dips"]),
    # — Hombro
    (["Standing Military Press", "Seated Barbell Military Press", "Barbell Shoulder Press"],
     ["press militar", "press militar de pie", "press militar con barra", "military press",
      "standing military press", "overhead press", "ohp", "press de hombros con barra"]),
    (["Seated Barbell Military Press"],
     ["press militar sentado", "seated overhead press", "press de hombros sentado con barra"]),
    (["Dumbbell Shoulder Press"],
     ["press de hombro con mancuernas", "press de hombros con mancuernas",
      "dumbbell shoulder press", "shoulder press", "press de hombro"]),
    (["Standing Dumbbell Press", "Standing Palms-In Dumbbell Press"],
     ["press de hombro de pie con mancuernas", "standing dumbbell press",
      "press militar con mancuernas", "press militar de pie con mancuernas"]),
    (["Front Dumbbell Raise", "Front Two-Dumbbell Raise"],
     ["elevaciones frontales", "elevacion frontal", "front raise",
      "elevacion frontal con mancuernas"]),
    (["Lying Rear Delt Raise", "Dumbbell Lying Rear Lateral Raise", "Seated Bent-Over Rear Delt Raise"],
     ["pajaros", "pájaros", "aperturas posteriores", "rear delt fly", "reverse fly"]),
    (["Face Pull", "Cable Rope Rear-Delt Rows"],
     ["face pull", "face pulls", "jalon a la cara"]),
    (["Arnold Dumbbell Press"],
     ["press arnold", "arnold press"]),
    (["Side Lateral Raise", "Seated Side Lateral Raise"],
     ["elevaciones laterales", "elevacion lateral", "lateral raises", "lateral raise",
      "vuelos laterales", "elevaciones laterales con mancuernas"]),
    (["Barbell Rear Delt Row"],
     ["elevacion posterior", "vuelos posteriores", "rear delt raise"]),
    (["Upright Barbell Row"],
     ["remo al menton", "remo vertical", "upright row", "remo al cuello"]),
    (["Barbell Shrug"],
     ["encogimientos", "encogimientos con barra", "encogimiento de hombros", "shrugs",
      "barbell shrug"]),
    (["Dumbbell Shrug"],
     ["encogimientos con mancuernas", "dumbbell shrug"]),
    # — Espalda
    (["Pullups"],
     ["dominadas", "dominada", "pull up", "pull ups", "dominadas pronas"]),
    (["Chin-Up"],
     ["dominadas supinas", "dominada supina", "chin up", "chin ups"]),
    (["Full Range-Of-Motion Lat Pulldown", "Wide-Grip Lat Pulldown"],
     ["jalon al pecho", "jalón al pecho", "jalon dorsal", "lat pulldown", "pulldown",
      "jalon en polea", "polea al pecho", "jalon frontal"]),
    (["Seated Cable Rows"],
     ["remo sentado", "remo en polea", "remo sentado en polea", "seated cable row", "cable row",
      "remo bajo en polea", "remo en polea baja"]),
    (["Bent Over Barbell Row"],
     ["remo con barra", "remo inclinado con barra", "remo inclinado", "bent over row",
      "barbell row", "remo con barra (bent-over)", "bent-over row", "remo con barra inclinado"]),
    (["Lying T-Bar Row", "T-Bar Row with Handle"],
     ["remo en t", "remo t", "t-bar row", "remo con barra t", "remo t con apoyo"]),
    (["One-Arm Dumbbell Row", "Bent Over Two-Dumbbell Row"],
     ["remo con mancuerna", "remo con mancuernas", "remo unilateral con mancuerna",
      "dumbbell row", "one arm dumbbell row", "remo con mancuerna a una mano",
      "remo a una mano"]),
    (["Leverage Iso Row", "Leverage High Row"],
     ["remo en maquina", "machine row", "remo sentado en maquina"]),
    (["Weighted Pull Ups"],
     ["dominadas lastradas", "dominada lastrada", "weighted pull up", "dominadas con lastre"]),
    # — Pierna
    (["Leg Press"],
     ["prensa de pierna", "prensa de piernas", "prensa 45", "prensa de pierna 45",
      "prensa de pierna 45°", "prensa inclinada", "leg press", "prensa"]),
    (["Barbell Full Squat", "Barbell Squat"],
     ["sentadilla", "sentadillas", "sentadilla con barra", "squat", "back squat",
      "barbell squat", "sentadilla trasera", "sentadilla libre"]),
    (["Front Barbell Squat"],
     ["sentadilla frontal", "front squat"]),
    (["Goblet Squat"],
     ["sentadilla goblet", "goblet squat"]),
    (["Hack Squat", "Barbell Hack Squat"],
     ["sentadilla hack", "hack squat"]),
    (["Barbell Lunge"],
     ["zancadas con barra", "desplantes con barra", "estocadas con barra"]),
    (["Dumbbell Lunges"],
     ["zancadas", "zancada", "desplantes", "desplante", "lunges", "lunge", "estocadas",
      "estocada", "zancadas con mancuernas"]),
    (["Split Squat with Dumbbells", "Smith Single-Leg Split Squat"],
     ["sentadilla bulgara", "sentadilla búlgara", "bulgarian split squat", "split squat bulgaro"]),
    (["Bodyweight Walking Lunge", "Barbell Walking Lunge"],
     ["zancadas caminando", "zancada caminando", "desplantes caminando", "walking lunge",
      "walking lunges"]),
    (["Romanian Deadlift"],
     ["peso muerto rumano", "romanian deadlift", "rdl", "peso muerto rumano con barra"]),
    (["Barbell Deadlift"],
     ["peso muerto", "peso muerto convencional", "deadlift", "conventional deadlift",
      "peso muerto con barra"]),
    (["Sumo Deadlift"],
     ["peso muerto sumo", "sumo deadlift"]),
    (["Good Morning"],
     ["buenos dias", "buenos días", "good morning", "good mornings"]),
    (["Barbell Hip Thrust", "Barbell Glute Bridge"],
     ["hip thrust", "hip thrust con barra", "empuje de cadera", "puente de gluteo con barra",
      "puente de gluteos con barra", "hip thrust en maquina"]),
    (["Lying Leg Curls"],
     ["curl femoral", "curl femoral acostado", "curl de pierna", "leg curl", "lying leg curl",
      "femoral acostado", "curl femoral en maquina"]),
    (["Seated Leg Curl"],
     ["curl femoral sentado", "seated leg curl", "femoral sentado"]),
    (["Leg Extensions"],
     ["extension de pierna", "extensión de pierna", "extensiones de pierna",
      "extension de cuadriceps", "extensión de cuádriceps", "leg extension",
      "extensiones de cuadriceps"]),
    (["Standing Calf Raises", "Rocking Standing Calf Raise"],
     ["elevacion de pantorrilla", "elevaciones de pantorrilla", "elevacion de talones",
      "elevacion de pantorrilla de pie", "elevación de pantorrilla de pie", "calf raise",
      "calf raises", "standing calf raise", "pantorrillas de pie"]),
    (["Seated Calf Raise", "Barbell Seated Calf Raise"],
     ["elevacion de pantorrilla sentado", "seated calf raise", "pantorrilla sentado",
      "elevacion de talones sentado"]),
    # — Bíceps
    (["Barbell Curl"],
     ["curl de biceps con barra", "curl de bíceps con barra", "curl con barra", "barbell curl",
      "curl de biceps barra"]),
    (["Standing Biceps Cable Curl", "Lying Cable Curl"],
     ["curl de biceps en polea", "curl en polea", "curl con polea de pie"]),
    (["Dumbbell Bicep Curl", "Seated Dumbbell Curl"],
     ["curl de biceps", "curl de bíceps", "curl con mancuernas", "curl de biceps con mancuernas",
      "biceps curl", "dumbbell curl", "curl de bíceps con mancuernas"]),
    (["Hammer Curls", "Cross Body Hammer Curl"],
     ["curl martillo", "hammer curl", "curl de martillo", "curl martillo con mancuernas"]),
    (["Preacher Curl"],
     ["curl predicador", "curl en banco scott", "preacher curl", "curl scott",
      "curl predicador con barra"]),
    (["EZ-Bar Curl"],
     ["curl con barra z", "curl con barra ez", "ez curl", "ez bar curl"]),
    (["Palms-Up Barbell Wrist Curl Over A Bench", "Seated Palm-Up Barbell Wrist Curl", "Cable Wrist Curl"],
     ["curl de muneca", "curl de muñeca", "wrist curl", "curl de antebrazo"]),
    # — Tríceps
    (["Triceps Pushdown", "Triceps Pushdown - Rope Attachment"],
     ["extension de triceps en polea", "extensión de tríceps en polea", "jalon de triceps",
      "jalón de tríceps", "empuje de triceps en polea", "pushdown", "triceps pushdown",
      "extension de triceps en polea alta", "jalon de triceps en polea"]),
    (["EZ-Bar Skullcrusher"],
     ["press frances", "press francés", "rompecraneos", "rompecráneos", "skull crusher",
      "skullcrusher", "skull crushers"]),
    (["Lying Triceps Press"],
     ["extension de triceps acostado", "extensión de tríceps acostado", "lying triceps extension"]),
    (["Standing Overhead Barbell Triceps Extension"],
     ["extension de triceps sobre la cabeza", "extensión de tríceps sobre la cabeza",
      "overhead triceps extension", "extension de triceps de pie"]),
    (["Standing Dumbbell Triceps Extension", "Dumbbell One-Arm Triceps Extension"],
     ["extension de triceps con mancuerna", "extension de triceps con mancuernas",
      "dumbbell triceps extension"]),
    (["Tricep Dumbbell Kickback"],
     ["patada de triceps", "patada de tríceps", "kickback", "kickbacks",
      "patada trasera de triceps"]),
    (["Dips - Triceps Version", "Bench Dips"],
     ["fondos de triceps", "fondos de tríceps", "fondos en banco", "triceps dips", "bench dips"]),
    # — Core
    (["Crunches"],
     ["abdominales", "abdominal", "crunch", "crunches", "encogimientos abdominales"]),
    (["Cable Crunch"],
     ["abdominales en polea", "crunch en polea", "cable crunch"]),
    (["Russian Twist"],
     ["giro ruso", "giros rusos", "russian twist", "twist ruso"]),
    (["Hanging Leg Raise"],
     ["elevacion de piernas colgado", "elevación de piernas colgado",
      "elevaciones de piernas colgado", "hanging leg raise", "elevacion de piernas en barra",
      "elevaciones de rodillas colgado"]),
]


def main():
    catalog = json.load(open(CATALOG))
    by_name = {}
    for e in catalog:
        by_name.setdefault(e["name"], e["id"])   # first wins, like the app's index

    aliases = {}
    errors = []
    for candidates, alias_list in MOVES:
        eid = next((by_name[c] for c in candidates if c in by_name), None)
        if eid is None:
            errors.append(f"none of {candidates} exist in the catalog")
            continue
        for alias in alias_list:
            if alias in aliases and aliases[alias] != eid:
                errors.append(f"alias {alias!r} maps to two ids ({aliases[alias]}, {eid})")
            aliases[alias] = eid
    if errors:
        sys.exit("build_aliases: FAILED\n  " + "\n  ".join(errors))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(dict(sorted(aliases.items())), f, ensure_ascii=False, indent=1)
    print(f"aliases: {len(aliases)} entries over {len(MOVES)} movements -> {OUT}")


if __name__ == "__main__":
    main()
