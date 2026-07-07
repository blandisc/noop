import Foundation

// Bilingual display vocabulary for the exercise catalog's controlled terms (FER-501, FER-779).
//
// Muscle, equipment and body-part values are CANONICAL ENGLISH KEYS: the library filter, the
// muscle-fatigue map (`MuscleAtlas`/FER-350) and the load math all join on them, so the stored
// value never changes. These tables localize only the DISPLAY — the app shows the Spanish label
// while every filter/join keeps comparing the English key. Closed vocabularies (17 muscles, 28
// equipment, 10 body parts — the ExerciseDB catalog's terms), so a static dictionary is exhaustive;
// a key without a translation falls back to its English (title-cased by the app). es-MX standard
// gym terminology.

/// Muscle group display labels. Keys are the catalog's canonical (lowercased) English muscle names —
/// the 17 `MuscleAtlas` regions (ExerciseDB's finer names are normalized down to these at bake time).
public enum MuscleVocabulary {
    /// English key → Spanish display label. Covers every muscle the catalog uses.
    public static let es: [String: String] = [
        "abdominals": "Abdominales",
        "abductors": "Abductores",
        "adductors": "Aductores",
        "biceps": "Bíceps",
        "calves": "Pantorrillas",
        "chest": "Pecho",
        "forearms": "Antebrazos",
        "glutes": "Glúteos",
        "hamstrings": "Isquiotibiales",
        "lats": "Dorsales",
        "lower back": "Espalda baja",
        "middle back": "Espalda media",
        "neck": "Cuello",
        "quadriceps": "Cuádriceps",
        "shoulders": "Hombros",
        "traps": "Trapecios",
        "triceps": "Tríceps",
    ]
}

/// Equipment display labels. Keys are the catalog's canonical (lowercased) English equipment names
/// (ExerciseDB OSS vocabulary, FER-779).
public enum EquipmentVocabulary {
    /// English key → Spanish display label. Covers every equipment type the catalog uses.
    public static let es: [String: String] = [
        "assisted": "Asistido",
        "band": "Banda",
        "barbell": "Barra",
        "body weight": "Peso corporal",
        "bosu ball": "Balón Bosu",
        "cable": "Polea",
        "dumbbell": "Mancuerna",
        "elliptical machine": "Elíptica",
        "ez barbell": "Barra Z",
        "hammer": "Martillo",
        "kettlebell": "Pesa rusa",
        "leverage machine": "Máquina de palanca",
        "medicine ball": "Balón medicinal",
        "olympic barbell": "Barra olímpica",
        "resistance band": "Banda de resistencia",
        "roller": "Rodillo",
        "rope": "Cuerda",
        "skierg machine": "Máquina SkiErg",
        "sled machine": "Trineo",
        "smith machine": "Máquina Smith",
        "stability ball": "Pelota de estabilidad",
        "stationary bike": "Bicicleta fija",
        "stepmill machine": "Escaladora",
        "tire": "Llanta",
        "trap bar": "Barra hexagonal",
        "upper body ergometer": "Ergómetro de brazos",
        "weighted": "Con peso",
        "wheel roller": "Rueda abdominal",
    ]
}

/// Body-part display labels. Keys are the catalog's canonical (lowercased) English body-part regions
/// (ExerciseDB OSS coarse regions, FER-779) — a library filter dimension, coarser than the muscles.
public enum BodyPartVocabulary {
    /// English key → Spanish display label. Covers every body part the catalog uses.
    public static let es: [String: String] = [
        "back": "Espalda",
        "cardio": "Cardio",
        "chest": "Pecho",
        "lower arms": "Antebrazos",
        "lower legs": "Piernas (bajas)",
        "neck": "Cuello",
        "shoulders": "Hombros",
        "upper arms": "Brazos",
        "upper legs": "Piernas",
        "waist": "Core",
    ]
}
