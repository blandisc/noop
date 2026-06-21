import Foundation

/// The copy-paste prompt the Diet capture screen puts on the clipboard (FER-371).
///
/// The user pastes it into their own LLM (ChatGPT/Claude) together with their plan (PDF/photo); the
/// LLM returns a `noop.diet.v1` file the user then imports. Bundled here as the single source — not
/// scattered string literals. Two languages: the device language picks one, but **each prompt accepts
/// a plan written in Spanish OR English** (the model detects it and never translates the food names).
/// NOOP itself never makes a network call — the user runs the LLM step.
enum DietPrompt {

    /// The prompt for the current device language (Spanish device → `es`, otherwise `en`).
    static func forCurrentLocale() -> String {
        (Locale.current.language.languageCode?.identifier == "es") ? es : en
    }

    static let es = """
    Convierte el plan de alimentación que te doy en un archivo JSON para importar a una app.
    El plan puede venir en español o en inglés (texto o imagen). Devuelve ÚNICAMENTE el JSON
    válido, sin texto antes ni después, con EXACTAMENTE este formato:

    { "schema":"noop.diet.v1", "idioma":"", "nombre":"", "ciclo":"diario",
      "comidas":[ {"id":"","nombre":"","hora_sugerida":"",
        "opciones":[{"alimentos":[]}], "notas":""} ],
      "objetivos_diarios":{}, "reglas":[] }

    Reglas:
    - Detecta el idioma del plan y ponlo en "idioma": "es" o "en".
    - NO traduzcas los ALIMENTOS: consérvalos EXACTAMENTE como aparecen.
    - Las llaves del JSON quedan en español tal como están; solo los VALORES siguen el idioma del plan.
    - Una entrada en "comidas" por cada tiempo, en orden.
    - El "nombre" de cada comida es una etiqueta CORTA del momento del día (Desayuno, Colación,
      Comida, Cena, Pre-entreno, Post-entreno…), NO el platillo; todos los alimentos van SIEMPRE
      en "opciones".alimentos. Ej.: {"nombre":"Desayuno", "opciones":[{"alimentos":["2 huevos","1 pan integral"]}]}.
    - Si una comida da equivalentes u opciones intercambiables, ponlas como varias entradas en
      "opciones"; si no, una sola.
    - Copia las cantidades tal cual ("150 g", "1 cup", "2 pza"); si no hay, omite el dato.
    - NO inventes calorías ni macros. Llena "objetivos_diarios" SOLO con números que el plan
      declare; si no, déjalo {}.
    - "hora_sugerida" solo si el plan la indica (24h "HH:MM"). Lineamientos generales van en "reglas".
    - Ciclo: si comes lo MISMO todos los días, deja "ciclo":"diario" y NO agregues "dias". Si el plan
      VARÍA por día de la semana, pon "ciclo":"semanal" y en cada comida agrega "dias" con los días en
      que aplica, como números 1=lunes … 7=domingo (ej. "dias":[1,3,5] = lun/mié/vie).

    Aquí está mi plan:
    [pega tu dieta o adjunta la foto]
    """

    static let en = """
    Convert the meal plan I give you into a JSON file to import into an app. The plan may be
    in Spanish or English (text or image). Return ONLY the valid JSON, with no text before or
    after, in EXACTLY this format:

    { "schema":"noop.diet.v1", "idioma":"", "nombre":"", "ciclo":"diario",
      "comidas":[ {"id":"","nombre":"","hora_sugerida":"",
        "opciones":[{"alimentos":[]}], "notas":""} ],
      "objetivos_diarios":{}, "reglas":[] }

    Rules:
    - Detect the plan's language and set "idioma": "es" or "en".
    - DO NOT translate the FOODS: keep them EXACTLY as written.
    - The JSON keys stay in Spanish as shown; only the VALUES follow the plan's language.
    - One "comidas" entry per eating occasion, in order.
    - Each meal's "nombre" is a SHORT label for the time of day in the plan's language (Breakfast,
      Snack, Lunch, Dinner, Pre-workout, Post-workout / Desayuno, Comida, Cena…), NOT the dish; all
      foods ALWAYS go in "opciones".alimentos. E.g. {"nombre":"Breakfast", "opciones":[{"alimentos":["2 eggs","1 slice whole-grain bread"]}]}.
    - If a meal offers interchangeable options/equivalents, list them as multiple "opciones"
      entries; otherwise one.
    - Copy quantities verbatim ("150 g", "1 cup", "2 pza"); omit if absent.
    - DO NOT invent calories or macros. Fill "objetivos_diarios" ONLY with numbers the plan
      states; otherwise leave it {}.
    - "hora_sugerida" only if the plan indicates it (24h "HH:MM"). General guidelines go in "reglas".
    - Cycle: if you eat the SAME every day, keep "ciclo":"diario" and DON'T add "dias". If the plan
      VARIES by day of the week, set "ciclo":"semanal" and add "dias" to each meal with the days it
      applies, as numbers 1=Monday … 7=Sunday (e.g. "dias":[1,3,5] = Mon/Wed/Fri).

    Here is my plan:
    [paste your diet or attach the photo]
    """
}
