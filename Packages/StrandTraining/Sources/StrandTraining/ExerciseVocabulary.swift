import Foundation

// Bilingual display vocabulary for the exercise catalog's controlled terms (FER-501).
//
// Muscle and equipment values are CANONICAL ENGLISH KEYS: the library filter, the muscle-fatigue
// map (`MuscleAtlas`/FER-350) and the load math all join on them, so the stored value never changes.
// These tables localize only the DISPLAY — the app shows the Spanish label while every filter/join
// keeps comparing the English key. Closed vocabularies (17 muscles, 12 equipment), so a static
// dictionary is exhaustive; a key without a translation falls back to its English (title-cased by
// the app). es-MX standard gym terminology.

/// Muscle group display labels. Keys are the catalog's canonical (lowercased) English muscle names.
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

/// Equipment display labels. Keys are the catalog's canonical (lowercased) English equipment names.
public enum EquipmentVocabulary {
    /// English key → Spanish display label. Covers every equipment type the catalog uses.
    public static let es: [String: String] = [
        "bands": "Bandas",
        "barbell": "Barra",
        "body only": "Peso corporal",
        "cable": "Polea",
        "dumbbell": "Mancuerna",
        "e-z curl bar": "Barra Z",
        "exercise ball": "Pelota de ejercicio",
        "foam roll": "Rodillo de espuma",
        "kettlebells": "Pesas rusas",
        "machine": "Máquina",
        "medicine ball": "Balón medicinal",
        "other": "Otro",
    ]
}
