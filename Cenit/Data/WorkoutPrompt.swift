import Foundation
import StrandTraining

/// The copy-paste prompt the workout-import screen puts on the clipboard (FER-496 / FER-521).
///
/// The user pastes it into their own LLM (ChatGPT/Claude) together with their training plan (text /
/// photo / PDF); the LLM returns a `noop.workout.v1` file the user then imports. Bundled here as the
/// single source — not scattered string literals. Two languages: the device language picks one, but
/// **each prompt accepts a plan written in Spanish OR English** (the model detects it and keeps the
/// exercise names as written). NOOP itself never makes a network call — the user runs the LLM step.
///
/// FER-521: the prompt now carries NOOP's exercise catalog (id + localized name) and asks the LLM to
/// pick the exact `id` for each exercise it recognizes. The importer then matches by id — exact and
/// language-proof — so far fewer exercises fall to the manual mapping step. The catalog makes the paste
/// longer, but it's one tap to copy; an exercise the LLM can't place just keeps an empty id + a name.
///
/// Voice matters (FER-825): the prompt is written in the USER's first person ("I want to import my
/// plan…"), never as system-style imperatives ("Return ONLY…"). The paste is long enough that chat
/// apps attach it as a file, and a file that commands the model directly trips prompt-injection
/// defenses — Claude refused the old imperative wording. Keep any future edit in the requester's voice.
enum WorkoutPrompt {

    /// The prompt for the current device language (Spanish device → `es`, otherwise `en`), with the
    /// exercise catalog appended in that language.
    static func forCurrentLocale() -> String {
        let spanish = Locale.current.language.languageCode?.identifier == "es"
        let (intro, tail) = spanish ? (esIntro, esTail) : (enIntro, enTail)
        return intro + "\n\n" + catalogBlock(localized: spanish) + "\n\n" + tail
    }

    /// `id<TAB>name` for every bundled exercise, in the device language — the reference the LLM picks
    /// the `id` from. Pure data, no network.
    private static func catalogBlock(localized: Bool) -> String {
        let header = localized
            ? "Esta es la lista de ejercicios que mi app conoce (id ⇥ nombre), para que puedas tomar el \"id\" de la izquierda cuando el ejercicio esté aquí:"
            : "This is the list of exercises my app knows (id ⇥ name), so you can take the \"id\" on the left when the exercise is in it:"
        let lines = ExerciseCatalog.all
            .map { "\($0.id)\t\($0.displayName(localized: localized))" }
            .joined(separator: "\n")
        return header + "\n" + lines
    }

    private static let esIntro = """
    Hola — quiero importar mi plan de entrenamiento de fuerza a la app que uso (Cénit, funciona sin
    internet). Copié este texto desde la app para pedírtelo; trátalo como mi solicitud. La app solo
    puede leer un archivo JSON con una estructura fija, así que te pido que conviertas mi plan (te lo
    doy abajo, puede venir en español o inglés, como texto o foto) a ese formato.

    Para que la app lo acepte, necesito que tu respuesta sea solo el JSON (sin texto antes ni después
    — cualquier otra cosa hace que la importación falle), con esta estructura:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "rutinas":[ { "nombre":"", "etiqueta":"",
        "ejercicios":[ {"id":"", "nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    Así llena la app cada campo (lo que necesita para poder leerlo):
    - "idioma": el idioma en que está mi plan, "es" o "en".
    - Las llaves del JSON quedan en español tal como están; solo los valores siguen el idioma del plan.
    - "id": si el ejercicio aparece en la lista de abajo, copia su "id" tal cual (la columna izquierda,
      antes del tabulador), aunque mi plan lo nombre distinto. La lista tiene muchas variantes del mismo
      movimiento (agarre, inclinación, máquina): si mi plan no especifica la variante, elige la básica
      con el mismo equipo (ej. "press de banca" → "Press de banca con barra", no la guillotina ni la
      declinada) — un id de la variante básica me sirve más que un "id" vacío. Si no está en la lista,
      deja "id":"" y pon un "nombre" claro.
    - "nombre" del ejercicio: cópialo tal cual aparece en mi plan, sin traducirlo ni cambiarlo.
    - "unidad": "kg" o "lb", según la unidad de los pesos de mi plan.
    - Una entrada en "rutinas" por cada día/rutina del plan (ej. Empuje, Jalón, Pierna), en orden.
      "etiqueta" es opcional y solo informativa (ej. "Lunes").
    - "tipo": "weightReps" (peso × reps, lo normal), "bodyweight" (peso corporal), "time" (por tiempo,
      ej. plancha) o "distance" (cardio por distancia). Ante la duda, "weightReps".
    - "series" = número de series de trabajo (entero ≥ 1).
    - Por favor no inventes datos: pon "reps", "peso", "descanso_seg" solo si mi plan los indica; si no,
      omite ese campo (o déjalo en 0 si lo incluyes vacío).
    - "calentamiento_pcts": fracciones del peso de trabajo para calentar (ej. [0.4,0.6,0.8]); si mi plan
      no lo dice, déjalo [].
    - "superset": si dos o más ejercicios son superserie, ponles el mismo número entero; si va solo, null.
    """

    private static let esTail = """
    Aquí está mi plan:
    [pega tu entrenamiento o adjunta la foto]
    """

    private static let enIntro = """
    Hi — I want to import my strength-training plan into the app I use (Cénit, works fully offline). I
    copied this text from the app to ask you; please treat it as my own request. The app can only read
    a JSON file with a fixed structure, so I'm asking you to convert my plan (I'll give it to you below,
    in Spanish or English, as text or a photo) into that format.

    For the app to accept it, I need your reply to be just the JSON (no text before or after — anything
    else makes the import fail), with this structure:

    { "schema":"noop.workout.v1", "idioma":"", "unidad":"kg", "programa":"",
      "rutinas":[ { "nombre":"", "etiqueta":"",
        "ejercicios":[ {"id":"", "nombre":"", "tipo":"weightReps", "series":0, "reps":0,
          "peso":0, "descanso_seg":0, "calentamiento_pcts":[], "superset":null} ] } ] }

    This is how the app fills each field (what it needs to be able to read it):
    - "idioma": the language my plan is in, "es" or "en".
    - The JSON keys stay in Spanish as shown; only the values follow the plan's language.
    - "id": if the exercise appears in the list below, copy its "id" as-is (the left column, before the
      tab), even if my plan names it differently. The list holds many variants of the same movement
      (grip, incline, machine): if my plan doesn't specify the variant, pick the basic one with the same
      equipment (e.g. "bench press" → "barbell bench press", not the guillotine or decline variant) — a
      basic-variant id helps me more than an empty "id". If it's not in the list, leave "id":"" and give
      a clear "nombre".
    - Each exercise "nombre": copy it exactly as written in my plan, without translating or changing it.
    - "unidad": "kg" or "lb", matching the unit my plan's weights are written in.
    - One "rutinas" entry per day/routine in the plan (e.g. Push, Pull, Legs), in order. "etiqueta" is
      optional and informational only (e.g. "Monday").
    - "tipo": "weightReps" (weight × reps, the usual), "bodyweight", "time" (held/timed, e.g. plank) or
      "distance" (distance cardio). When in doubt, "weightReps".
    - "series" = number of working sets (integer ≥ 1).
    - Please don't invent data: fill "reps", "peso", "descanso_seg" only if my plan states them;
      otherwise omit that field (or leave 0 if you include it empty).
    - "calentamiento_pcts": warm-up fractions of the working weight (e.g. [0.4,0.6,0.8]); leave [] if my
      plan doesn't say.
    - "superset": if two or more exercises form a superset, give them the same integer; null if alone.
    """

    private static let enTail = """
    Here is my plan:
    [paste your workout or attach the photo]
    """
}
