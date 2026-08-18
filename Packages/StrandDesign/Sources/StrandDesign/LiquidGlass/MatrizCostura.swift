import SwiftUI

// MARK: - La COSTURA del guardián (FER-80) → el MODELO y el MAPEO del par (FER-118)
//
// El guardián tiene UNA regla: una señal sola nunca empuja tu día; solo el PAR, dos noches
// seguidas. La costura (FER-80, propuesta C2) la dibujaba como dos orillas espejadas sobre un
// eje; en «Hoy en atmósfera» (FER-118) el dueño eligió otra figura —«los dos hilos de puntos»,
// `MatrizHilos`— y la costura dejó de dibujarse. Lo que NO cambió, y por eso vive aquí como
// espacio de nombres, es lo que hacía honesta a la costura y hace honestos a los hilos:
//   · `Noche`: la noche del par ya normalizada contra SU PROPIA banda (0 = centro, 1 = filo,
//     >1 = fuera, nil = no se leyó o no se pudo juzgar), con el ANCLA al juicio del motor puesta
//     por el builder (marcado fuera ≥ 1.02, no marcado ≤ 0.98).
//   · `fraccionFilo`: la traducción de esa magnitud a distancia en el dibujo, con el hueco del
//     filo que vuelve VISIBLE lo que el motor marcó, el marco inviolable y el lado bajo apretado.
// Sus siete invariantes siguen fijados en `MatrizCosturaMapeoTests`; el payload de la Matriz
// sigue llamándose `.costura(noches:)` porque son los mismos datos.
public enum MatrizCostura {
    /// Una noche del par, ya normalizada: 0 = en el centro de tu banda, 1 = en su filo,
    /// >1 = fuera. `nil` = esa señal no se leyó (o no se pudo juzgar) esa noche.
    public struct Noche: Sendable, Equatable {
        public let temp: Double?
        public let resp: Double?
        /// El motor marcó las DOS fuera esa noche: el día que el par vota.
        public let parFuera: Bool
        /// Revisión adversarial P-2: una señal sin magnitud no puede dibujarse como si hubiera
        /// caído en el centro de tu banda. Un hueco es un hueco: su orilla se interrumpe.
        ///
        /// Se DERIVAN del valor, no se reciben: mientras fueron parámetros con default, el tipo
        /// permitía construir `Noche(temp: nil, resp: 0.5)` —bandera en false, valor nil— y esa
        /// noche se dibujaba pegada al eje con su joya encima. La mentira que P-2 mató seguía
        /// siendo representable, esperando al próximo llamador (tercera vuelta adversarial).
        public var tempSinLectura: Bool { temp == nil }
        public var respSinLectura: Bool { resp == nil }

        public init(temp: Double?, resp: Double?, parFuera: Bool = false) {
            self.temp = temp
            self.resp = resp
            self.parFuera = parFuera
        }
    }

    /// Dónde cae el filo de tu banda por el lado de ADENTRO, y dónde por el de AFUERA.
    ///
    /// El hueco entre los dos (0.17 del recorrido ≈ 3.2 pt) es DELIBERADO y es la pieza que
    /// hace visible una garantía que antes solo era cierta en los números: lo que el motor
    /// marcó fuera se dibuja más lejos del eje que lo que no marcó. Con el mapeo continuo
    /// anterior, esas dos noches quedaban a 0.245 pt una de otra —bajo un trazo de 2.2 pt—,
    /// así que el chip decía «vigilando tu temperatura» y la gráfica no lo respaldaba.
    private static let filoDentro: CGFloat = 0.58
    private static let filoFuera: CGFloat = 0.75
    /// La suavidad de cada tramo (rpm/°C→pixeles).
    private static let kDentro: Double = 0.8
    private static let kFuera: Double = 1.2
    /// Cuánto del recorrido puede ocupar el lado BAJO (por debajo de tu centro).
    private static let ladoBajoFrac: CGFloat = 0.22

    /// Magnitud firmada contra la banda de esa señal → fracción del recorrido del labio [0,1].
    ///
    /// Por tramos, con un salto en el filo. Tres cosas que el mapeo tiene que cumplir a la vez:
    ///
    /// 1. EL MARCO ES INVIOLABLE. Los dos tramos saturan (nunca pasan de 1), así que el labio
    ///    es siempre menor que el medio alto. Recortar en seco —lo que hacía la primera vuelta
    ///    de esta revisión— sacaba la orilla del Canvas y mandaba al mismo pixel una noche de
    ///    17 rpm y una de 25.
    /// 2. EL DIBUJO NO PUEDE CONTRADECIR AL MOTOR. De ahí el hueco: cualquier noche marcada
    ///    fuera cae por encima de `filoFuera` y cualquiera no marcada, por debajo de
    ///    `filoDentro`. **Esto solo se sostiene si el ANCLA del builder sigue viva** (empuja lo
    ///    marcado a ≥1.02 y lo no marcado a ≤0.98): es ella la que mantiene VACÍA la banda
    ///    (0.98, 1.02), y sin ella la escala aproximada de la respiración podría saltar el
    ///    hueco por su cuenta y afirmar «fuera» donde el motor no dijo nada. El ancla no es
    ///    cosmética: es el invariante que hace honesta esta discontinuidad.
    /// 3. EL LADO BAJO EXISTE PERO NO GRITA. El centinela nunca marca una noche fría ni una
    ///    respiración lenta, así que ese lado no puede parecer que te saliste — pero tampoco
    ///    puede desaparecer contra el eje: dos noches distintas jamás se dibujan al mismo alto.
    ///    (Su altura sí comparte rango con la parte baja del lado alto; es ambigüedad entre dos
    ///    estados que NO votan, y el scrub la desambigua con el número.)
    public static func fraccionFilo(_ v: Double) -> CGFloat {
        func dentro(_ x: Double) -> CGFloat {
            let norm = 1 / (1 + kDentro)                    // para que 1 banda = filoDentro
            return filoDentro * CGFloat((x / (x + kDentro)) / norm)
        }
        // El lado bajo usa la MISMA curva, escalada. Sin `min`: acotarlo con un recorte lo
        // aplanaba a partir de una banda —−0.9 °C y −1.1 °C caían en el mismo pixel—, que es
        // justo lo que este mapeo existe para no hacer. La curva ya está acotada sola (tiende a
        // 1.044·0.22 ≈ 0.23, muy por debajo del filo), así que el recorte nunca hizo falta.
        if v < 0 { return dentro(-v) * ladoBajoFrac }
        if v < 1 { return dentro(v) }
        let u = v - 1
        return filoFuera + (1 - filoFuera) * CGFloat(u / (u + kFuera))
    }

}
