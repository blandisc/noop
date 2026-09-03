import Foundation

/// The copy-paste prompt the workout-import screen puts on the clipboard (FER-496).
///
/// The user pastes it into their own LLM (ChatGPT/Claude) together with their training plan (text /
/// photo / PDF); the LLM returns a `noop.workout.v1` file the user then imports. Bundled here as the
/// single source — not scattered string literals. Two languages: the device language picks one, but
/// **each prompt accepts a plan written in Spanish OR English** (the model detects it and keeps the
/// exercise names as written). NOOP itself never makes a network call — the user runs the LLM step.
///
/// Two hard-won rules for any future edit (FER-825/827):
/// - **Short enough to stay a MESSAGE.** The prompt once carried the 1500-line exercise catalog
///   (FER-521) so the LLM could pick exact ids; that made chat apps attach the paste as a FILE, and a
///   file that dictates format/behavior trips prompt-injection defenses — Claude refused it twice,
///   regardless of wording. The catalog is gone: the on-device matcher (FER-794/797) resolves by
///   name, so ids are unnecessary. Keep the whole prompt well under ~40 lines.
/// - **The USER's first person.** "I want to import my plan…", requirements phrased as what the app
///   needs — never system-style imperatives ("Return ONLY…").
enum WorkoutPrompt {

    /// The prompt for the current device language (Spanish device → `es`, otherwise `en`).
    static func forCurrentLocale() -> String {
        Locale.current.language.languageCode?.identifier == "es" ? es : en
    }

    private static let es = """
    Hola — quiero importar mi plan de entrenamiento de fuerza a la app que uso (Cénit, funciona sin
    internet). La app solo puede leer un archivo JSON con una estructura fija, así que te pido que
    conviertas mi plan (te lo doy abajo, puede venir en español o inglés, como texto o foto) a este
    formato. Para que la app lo acepte, necesito que tu respuesta sea solo el JSON, sin texto antes
    ni después:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "semanas":0, "semana_ligera":"", "al_terminar":"",
      "rutinas":[ { "nombre":"", "etiqueta":"", "dia":0,
        "ejercicios":[ {"id":"", "nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    Cómo llenar cada campo:
    - "idioma": el idioma de mi plan, "es" o "en". Las llaves del JSON quedan en español tal como
      están; solo los valores siguen el idioma del plan.
    - "id": déjalo vacío ("") — la app reconoce los ejercicios por su nombre.
    - "nombre" del ejercicio: tal cual aparece en mi plan, sin traducirlo ni cambiarlo.
    - "unidad": "kg" o "lb", según la unidad de los pesos de mi plan.
    - Una entrada en "rutinas" por cada día/rutina (ej. Empuje, Jalón, Pierna), en orden. "etiqueta"
      es opcional y solo informativa (ej. "Lunes"). "dia" es el día de la semana de esa rutina
      (1 = lunes … 7 = domingo), si mi plan lo dice; si no, omítelo.
    - Si mi plan dura varias semanas y la última es más ligera: "semanas" (4 a 8), "semana_ligera"
      ("menos_series", "menos_series_y_peso" o "ninguna") y "al_terminar" ("repetir" el ciclo o
      "un_ciclo" solo). Si mi plan es una sola semana que se repite siempre igual, omite los tres.
    - "tipo": "weightReps" (peso × reps, lo normal), "bodyweight" (peso corporal), "time" (por
      tiempo, ej. plancha) o "distance" (cardio por distancia). Ante la duda, "weightReps".
    - "series" = número de series de trabajo (entero ≥ 1).
    - Por favor no inventes datos: pon "reps", "peso", "descanso_seg" solo si mi plan los indica;
      si no, omite el campo (o déjalo en 0).
    - "calentamiento_pcts": fracciones del peso de trabajo para calentar (ej. [0.4,0.6,0.8]); si mi
      plan no lo dice, déjalo [].
    - "superset": el mismo número entero para los ejercicios que van en superserie; si va solo, null.

    Aquí está mi plan:
    [pega tu entrenamiento o adjunta la foto]
    """

    private static let en = """
    Hi — I want to import my strength-training plan into the app I use (Cénit, works fully offline).
    The app can only read a JSON file with a fixed structure, so I'm asking you to convert my plan
    (I'll give it to you below, in Spanish or English, as text or a photo) into this format. For the
    app to accept it, I need your reply to be just the JSON, no text before or after:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "semanas":0, "semana_ligera":"", "al_terminar":"",
      "rutinas":[ { "nombre":"", "etiqueta":"", "dia":0,
        "ejercicios":[ {"id":"", "nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    How to fill each field:
    - "idioma": the language my plan is in, "es" or "en". The JSON keys stay in Spanish as shown;
      only the values follow the plan's language.
    - "id": leave it empty ("") — the app recognizes exercises by their name.
    - Each exercise "nombre": exactly as written in my plan, without translating or changing it.
    - "unidad": "kg" or "lb", matching the unit my plan's weights are written in.
    - One "rutinas" entry per day/routine (e.g. Push, Pull, Legs), in order. "etiqueta" is optional
      and informational only (e.g. "Monday"). "dia" is that routine's weekday (1 = Monday … 7 =
      Sunday), if my plan says; otherwise leave it out.
    - If my plan runs several weeks and the last one is lighter: "semanas" (4 to 8), "semana_ligera"
      ("menos_series", "menos_series_y_peso" or "ninguna") and "al_terminar" ("repetir" the cycle or
      "un_ciclo" once). If my plan is one week repeated forever the same, leave all three out.
    - "tipo": "weightReps" (weight × reps, the usual), "bodyweight", "time" (held/timed, e.g. plank)
      or "distance" (distance cardio). When in doubt, "weightReps".
    - "series" = number of working sets (integer ≥ 1).
    - Please don't invent data: fill "reps", "peso", "descanso_seg" only if my plan states them;
      otherwise omit the field (or leave it 0).
    - "calentamiento_pcts": warm-up fractions of the working weight (e.g. [0.4,0.6,0.8]); leave []
      if my plan doesn't say.
    - "superset": the same integer for exercises done as a superset; null for a standalone exercise.

    Here is my plan:
    [paste your workout or attach the photo]
    """
}
