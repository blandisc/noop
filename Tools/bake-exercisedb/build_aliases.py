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
    (["barbell bench press"],
     ["press de banca", "press banca", "press banca con barra", "press de pecho con barra",
      "bench press", "flat bench press", "press plano", "press de banca plano",
      "press plano con barra"]),
    (["barbell incline bench press"],
     ["press inclinado", "press inclinado con barra", "incline bench press",
      "press de banca inclinado"]),
    (["dumbbell incline bench press"],
     ["press inclinado con mancuernas", "incline dumbbell press", "incline dumbbell bench press"]),
    (["dumbbell bench press"],
     ["press de banca con mancuernas", "press plano con mancuernas", "dumbbell bench press"]),
    (["barbell close-grip bench press"],
     ["press cerrado", "press de banca agarre cerrado", "close grip bench press"]),
    (["smith bench press"],
     ["press de banca en smith", "press de banca en maquina smith"]),
    (["lever chest press"],
     ["press de pecho en maquina", "chest press", "machine chest press"]),
    (["lever seated fly"],
     ["pec deck", "peck deck", "contractor de pecho", "aperturas en maquina", "mariposa en maquina",
      "pec fly", "machine fly"]),
    (["dumbbell incline fly", "cable incline fly"],
     ["aperturas inclinadas", "apertura inclinada", "incline fly"]),
    (["dumbbell fly"],
     ["aperturas con mancuernas", "aperturas planas", "vuelos de pecho", "dumbbell fly", "flyes"]),
    (["cable standing fly"],
     ["aperturas en polea", "cruce de poleas", "cable crossover", "crossover en polea", "cable fly"]),
    (["chest dip"],
     ["fondos", "fondos en paralelas", "dips", "fondos de pecho", "chest dips"]),
    # — Hombro
    (["barbell standing wide military press", "barbell seated overhead press"],
     ["press militar", "press militar de pie", "press militar con barra", "military press",
      "standing military press", "overhead press", "ohp", "press de hombros con barra"]),
    (["barbell seated overhead press"],
     ["press militar sentado", "seated overhead press", "press de hombros sentado con barra"]),
    (["dumbbell seated shoulder press"],
     ["press de hombro con mancuernas", "press de hombros con mancuernas",
      "dumbbell shoulder press", "shoulder press", "press de hombro"]),
    (["dumbbell standing overhead press"],
     ["press de hombro de pie con mancuernas", "standing dumbbell press",
      "press militar con mancuernas", "press militar de pie con mancuernas"]),
    (["dumbbell front raise"],
     ["elevaciones frontales", "elevacion frontal", "front raise",
      "elevacion frontal con mancuernas"]),
    (["dumbbell rear lateral raise", "dumbbell incline rear lateral raise",
      "dumbbell lying rear lateral raise"],
     ["pajaros", "pájaros", "aperturas posteriores", "rear delt fly", "reverse fly"]),
    (["cable rear delt row (with rope)"],
     ["face pull", "face pulls", "jalon a la cara"]),
    (["dumbbell arnold press"],
     ["press arnold", "arnold press"]),
    (["dumbbell lateral raise"],
     ["elevaciones laterales", "elevacion lateral", "lateral raises", "lateral raise",
      "vuelos laterales", "elevaciones laterales con mancuernas"]),
    (["barbell rear delt raise"],
     ["elevacion posterior", "vuelos posteriores", "rear delt raise"]),
    (["barbell upright row"],
     ["remo al menton", "remo vertical", "upright row", "remo al cuello"]),
    (["barbell shrug"],
     ["encogimientos", "encogimientos con barra", "encogimiento de hombros", "shrugs",
      "barbell shrug"]),
    (["dumbbell shrug"],
     ["encogimientos con mancuernas", "dumbbell shrug"]),
    # — Espalda
    (["pull-up"],
     ["dominadas", "dominada", "pull up", "pull ups", "dominadas pronas"]),
    (["chin-up"],
     ["dominadas supinas", "dominada supina", "chin up", "chin ups"]),
    (["cable lat pulldown full range of motion"],
     ["jalon al pecho", "jalón al pecho", "jalon dorsal", "lat pulldown", "pulldown",
      "jalon en polea", "polea al pecho", "jalon frontal"]),
    (["cable low seated row"],
     ["remo sentado", "remo en polea", "remo sentado en polea", "seated cable row", "cable row",
      "remo bajo en polea", "remo en polea baja"]),
    (["barbell bent over row"],
     ["remo con barra", "remo inclinado con barra", "remo inclinado", "bent over row",
      "barbell row", "remo con barra (bent-over)", "bent-over row", "remo con barra inclinado"]),
    (["barbell pendlay row"],
     ["remo pendlay", "pendlay row"]),
    (["lever t bar row"],
     ["remo en t", "remo t", "t-bar row", "remo con barra t", "remo t con apoyo"]),
    (["dumbbell bent over row"],
     ["remo con mancuerna", "remo con mancuernas", "remo unilateral con mancuerna",
      "dumbbell row", "one arm dumbbell row", "remo con mancuerna a una mano",
      "remo a una mano"]),
    (["lever seated row", "lever narrow grip seated row"],
     ["remo en maquina", "machine row", "remo sentado en maquina"]),
    (["weighted pull-up"],
     ["dominadas lastradas", "dominada lastrada", "weighted pull up", "dominadas con lastre"]),
    # — Pierna
    (["sled 45в° leg press", "sled 45 degrees leg press"],
     ["prensa de pierna", "prensa de piernas", "prensa 45", "prensa de pierna 45",
      "prensa de pierna 45°", "prensa inclinada", "leg press", "prensa"]),
    (["barbell full squat"],
     ["sentadilla", "sentadillas", "sentadilla con barra", "squat", "back squat",
      "barbell squat", "sentadilla trasera", "sentadilla libre"]),
    (["barbell front squat"],
     ["sentadilla frontal", "front squat"]),
    (["dumbbell goblet squat"],
     ["sentadilla goblet", "goblet squat"]),
    (["sled hack squat"],
     ["sentadilla hack", "hack squat"]),
    (["barbell lunge"],
     ["zancadas con barra", "desplantes con barra", "estocadas con barra"]),
    (["dumbbell lunge"],
     ["zancadas", "zancada", "desplantes", "desplante", "lunges", "lunge", "estocadas",
      "estocada", "zancadas con mancuernas"]),
    (["dumbbell single leg split squat"],
     ["sentadilla bulgara", "sentadilla búlgara", "bulgarian split squat", "split squat bulgaro"]),
    (["barbell romanian deadlift"],
     ["peso muerto rumano", "romanian deadlift", "rdl", "peso muerto rumano con barra"]),
    (["barbell deadlift"],
     ["peso muerto", "peso muerto convencional", "deadlift", "conventional deadlift",
      "peso muerto con barra"]),
    (["barbell sumo deadlift"],
     ["peso muerto sumo", "sumo deadlift"]),
    (["barbell good morning"],
     ["buenos dias", "buenos días", "good morning", "good mornings"]),
    (["barbell glute bridge"],
     ["hip thrust", "hip thrust con barra", "empuje de cadera", "puente de gluteo con barra",
      "puente de gluteos con barra", "hip thrust en maquina"]),
    (["lever lying leg curl"],
     ["curl femoral", "curl femoral acostado", "curl de pierna", "leg curl", "lying leg curl",
      "femoral acostado", "curl femoral en maquina"]),
    (["lever seated leg curl"],
     ["curl femoral sentado", "seated leg curl", "femoral sentado"]),
    (["lever leg extension"],
     ["extension de pierna", "extensión de pierna", "extensiones de pierna",
      "extension de cuadriceps", "extensión de cuádriceps", "leg extension",
      "extensiones de cuadriceps"]),
    (["lever seated hip abduction"],
     ["abduccion de cadera", "abducciones de cadera", "hip abduction", "abductores en maquina"]),
    (["bodyweight standing calf raise"],
     ["elevacion de pantorrilla", "elevaciones de pantorrilla", "elevacion de talones",
      "elevacion de pantorrilla de pie", "elevación de pantorrilla de pie", "calf raise",
      "calf raises", "standing calf raise", "pantorrillas de pie"]),
    (["lever seated calf raise"],
     ["elevacion de pantorrilla sentado", "seated calf raise", "pantorrilla sentado",
      "elevacion de talones sentado"]),
    # — Bíceps
    (["barbell curl"],
     ["curl de biceps con barra", "curl de bíceps con barra", "curl con barra", "barbell curl",
      "curl de biceps barra"]),
    (["cable curl"],
     ["curl de biceps en polea", "curl en polea", "curl con polea de pie"]),
    (["dumbbell biceps curl"],
     ["curl de biceps", "curl de bíceps", "curl con mancuernas", "curl de biceps con mancuernas",
      "biceps curl", "dumbbell curl", "curl de bíceps con mancuernas"]),
    (["dumbbell hammer curl"],
     ["curl martillo", "hammer curl", "curl de martillo", "curl martillo con mancuernas"]),
    (["barbell preacher curl"],
     ["curl predicador", "curl en banco scott", "preacher curl", "curl scott",
      "curl predicador con barra"]),
    (["ez barbell curl", "ez-bar biceps curl", "barbell curl"],
     ["curl con barra z", "curl con barra ez", "ez curl", "ez bar curl"]),
    (["barbell wrist curl"],
     ["curl de muneca", "curl de muñeca", "wrist curl", "curl de antebrazo"]),
    # — Tríceps
    (["cable pushdown"],
     ["extension de triceps en polea", "extensión de tríceps en polea", "jalon de triceps",
      "jalón de tríceps", "empuje de triceps en polea", "pushdown", "triceps pushdown",
      "extension de triceps en polea alta", "jalon de triceps en polea"]),
    (["barbell lying triceps extension skull crusher"],
     ["press frances", "press francés", "rompecraneos", "rompecráneos", "skull crusher",
      "skullcrusher", "skull crushers"]),
    (["barbell lying triceps extension"],
     ["extension de triceps acostado", "extensión de tríceps acostado", "lying triceps extension"]),
    (["barbell standing overhead triceps extension"],
     ["extension de triceps sobre la cabeza", "extensión de tríceps sobre la cabeza",
      "overhead triceps extension", "extension de triceps de pie"]),
    (["dumbbell seated bench extension", "dumbbell standing triceps extension",
      "dumbbell seated triceps extension", "dumbbell incline triceps extension"],
     ["extension de triceps con mancuerna", "extension de triceps con mancuernas",
      "dumbbell triceps extension"]),
    (["dumbbell kickback"],
     ["patada de triceps", "patada de tríceps", "kickback", "kickbacks",
      "patada trasera de triceps"]),
    (["triceps dip"],
     ["fondos de triceps", "fondos de tríceps", "fondos en banco", "triceps dips", "bench dips"]),
    # — Core
    (["crunch floor"],
     ["abdominales", "abdominal", "crunch", "crunches", "encogimientos abdominales"]),
    (["cable kneeling crunch"],
     ["abdominales en polea", "crunch en polea", "cable crunch"]),
    (["russian twist"],
     ["giro ruso", "giros rusos", "russian twist", "twist ruso"]),
    (["hanging leg raise"],
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
