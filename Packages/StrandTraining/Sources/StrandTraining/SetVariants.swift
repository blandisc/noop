import Foundation

// SetVariants.swift — las constantes de dominio de las variantes de serie de la ola 1 (FER-327 · E6).
//
// Viven aquí, en StrandTraining (puro, Foundation-only), y no en la pantalla, porque son REGLAS DEL
// ENTRENAMIENTO, no de una vista: si mañana el escalón del drop deja de ser −20 %, cambia UNA vez.
// Devuelven kilos CRUDOS a propósito: StrandTraining no puede importar `PlateMath` (vive en
// StrandAnalytics, que no depende de StrandTraining — ver docs/ARCHITECTURE.md), así que el redondeo a
// «lo que de verdad se puede construir con tus discos» lo compone la capa app con `PlateMath.snap`.

public enum SetVariants {

    /// Fracción del peso de la serie madre con la que abre un escalón de drop: **0,8 (−20 %)**.
    ///
    /// Método: el «drop set» clásico — llevar una serie cerca del fallo, bajar la carga de inmediato y
    /// seguir sin descanso. La reducción de ~20 % es la CONVENCIÓN de gimnasio más citada (la banda que
    /// se repite en la práctica es 10–30 %); la revisión sistemática de Schoenfeld & Grgic (2018),
    /// «Can Drop Set Training Enhance Muscle Growth?» (Strength and Conditioning Journal 40(6):95-98),
    /// describe la técnica y concluye que la evidencia de superioridad hipertrófica frente al
    /// entrenamiento tradicional a volumen igualado es LIMITADA. Es decir: una convención razonable y
    /// editable por quien entrena, **no** una prescripción ni un efecto prometido. Ninguna superficie
    /// de la app promete un resultado por hacer drops.
    ///
    /// (Cita a verificar por /biomecanico antes del merge, como marca el spec.)
    public static let dropFraction = 0.8

    /// Cuántos escalones de drop puede colgar una misma serie madre: **3**. Es un tope de PRODUCTO, no
    /// una regla fisiológica: encadenar más allá de tres bajadas deja de ser una serie y se vuelve una
    /// captura ilegible en la tarjeta (y en el acta), y a −20 % compuesto el cuarto escalón ya está por
    /// debajo de la mitad del peso de trabajo (0,8⁴ ≈ 0,41).
    public static let maxDropSteps = 3

    /// El peso CRUDO con el que abre el siguiente escalón de drop a partir del peso de la serie de la
    /// que cuelga (la madre, o el escalón anterior si se encadenan). Sin redondear: quien lo consume
    /// pasa el resultado por `PlateMath.snap` para caer en un peso construible.
    public static func dropTargetKg(fromKg: Double) -> Double {
        max(0, fromKg * dropFraction)
    }
}
