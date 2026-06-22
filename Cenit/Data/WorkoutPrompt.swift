import Foundation

/// The copy-paste prompt the workout-import screen puts on the clipboard (FER-496).
///
/// The user pastes it into their own LLM (ChatGPT/Claude) together with their training plan (text /
/// photo / PDF); the LLM returns a `noop.workout.v1` file the user then imports. Bundled here as the
/// single source — not scattered string literals. Two languages: the device language picks one, but
/// **each prompt accepts a plan written in Spanish OR English** (the model detects it and keeps the
/// exercise names as written). NOOP itself never makes a network call — the user runs the LLM step.
enum WorkoutPrompt {

    /// The prompt for the current device language (Spanish device → `es`, otherwise `en`).
    static func forCurrentLocale() -> String {
        (Locale.current.language.languageCode?.identifier == "es") ? es : en
    }

    static let es = """
    Convierte el plan de entrenamiento de fuerza que te doy en un archivo JSON para importar a una app.
    El plan puede venir en español o en inglés (texto o imagen). Devuelve ÚNICAMENTE el JSON válido,
    sin texto antes ni después, con EXACTAMENTE este formato:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "rutinas":[ { "nombre":"", "etiqueta":"",
        "ejercicios":[ {"nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    Reglas:
    - Detecta el idioma del plan y ponlo en "idioma": "es" o "en".
    - Las llaves del JSON quedan en español tal como están; solo los VALORES siguen el idioma del plan.
    - "unidad": "kg" o "lb" según en qué unidad están los pesos del plan.
    - Una entrada en "rutinas" por cada día/rutina del plan (ej. Empuje, Jalón, Pierna), en orden.
      "etiqueta" es opcional y solo informativa (ej. "Lunes").
    - "nombre" del ejercicio: cópialo TAL CUAL aparece, no lo traduzcas ni lo cambies.
    - "tipo": "weightReps" (peso × reps, lo normal), "bodyweight" (peso corporal), "time" (por tiempo,
      ej. plancha) o "distance" (cardio por distancia). Si no estás seguro, usa "weightReps".
    - "series" = número de series de trabajo (entero ≥ 1).
    - NO inventes datos. Pon "reps", "peso", "descanso_seg" SOLO si el plan los indica; si no, omite ese
      campo (o déjalo en 0 si lo incluyes vacío).
    - "calentamiento_pcts": fracciones del peso de trabajo para el calentamiento (ej. [0.4,0.6,0.8]); si
      el plan no lo dice, déjalo [].
    - "superset": si dos o más ejercicios son una superserie, ponles el MISMO número entero en "superset";
      si el ejercicio va solo, déjalo null.

    Aquí está mi plan:
    [pega tu entrenamiento o adjunta la foto]
    """

    static let en = """
    Convert the strength-training plan I give you into a JSON file to import into an app. The plan may
    be in Spanish or English (text or image). Return ONLY the valid JSON, with no text before or after,
    in EXACTLY this format:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "rutinas":[ { "nombre":"", "etiqueta":"",
        "ejercicios":[ {"nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    Rules:
    - Detect the plan's language and set "idioma": "es" or "en".
    - The JSON keys stay in Spanish as shown; only the VALUES follow the plan's language.
    - "unidad": "kg" or "lb", matching the unit the plan's weights are written in.
    - One "rutinas" entry per day/routine in the plan (e.g. Push, Pull, Legs), in order. "etiqueta" is
      optional and informational only (e.g. "Monday").
    - Each exercise "nombre": copy it EXACTLY as written, don't translate or change it.
    - "tipo": "weightReps" (weight × reps, the usual), "bodyweight", "time" (held/timed, e.g. plank) or
      "distance" (distance cardio). If unsure, use "weightReps".
    - "series" = number of working sets (integer ≥ 1).
    - DON'T invent data. Fill "reps", "peso", "descanso_seg" ONLY if the plan states them; otherwise omit
      that field (or leave 0 if you include it empty).
    - "calentamiento_pcts": warm-up fractions of the working weight (e.g. [0.4,0.6,0.8]); leave [] if the
      plan doesn't say.
    - "superset": if two or more exercises form a superset, give them the SAME integer in "superset";
      leave it null for a standalone exercise.

    Here is my plan:
    [paste your workout or attach the photo]
    """
}
