import SwiftUI

// MARK: - Sellos de métrica de Hoy
//
// Los diez glifos que retratan lo que mide cada señal (la luna del sueño, el termómetro de
// la piel, el medidor del estrés con sus zonas…). Sustituyen al orbe de partículas como
// sello de la Matriz — salvo en el Guardián, que conserva su orbe VIVO porque su sello dice
// el estado del par (ver `SelloGuardianVivo`).
//
// La geometría NO se escribe aquí: la forja `Tools/sellos-hoy/forge.py` la genera y la
// vuelca en `SelloMetricaPaths.swift`, que es la única fuente de los paths y de los tonos.
// La forja verifica por número lo que un ojo no alcanza a esa escala: simetría de espejo,
// área segura, y que ningún rasgo (remate, ranura, aire estructural) caiga por debajo del
// pixel al tamaño real del sello — 20 pt en la Matriz.
//
// El dibujo ocupa el lado COMPLETO del sello, no una fracción como `LiquidIconDrop`: esa
// gota está hecha para símbolos de sistema, que traen su propio margen; estos lo traen por
// dentro (la tinta vive en [2,22] del viewBox 24). Encogerlos otra vez los rompería.

public enum SelloMetrica: String, Sendable, CaseIterable {
    case sueno, reposo, guardian, piel, respiracion, carga, esfuerzo, hrv, estres, pasos

    /// Cómo se rellena una parte: plano, o el lavado vertical de la familia.
    public enum Relleno: Sendable, Equatable {
        case plano(Color)
        /// Claro arriba → base abajo (la luz cae desde arriba en todo el sistema).
        case vertical(Color, Color)
    }

    /// Una parte del sello, en orden de pintado (del fondo al frente).
    public struct Parte: Sendable {
        let d: String
        let relleno: Relleno
        /// La parte lleva hueco tallado ⇒ se rellena con regla par-impar.
        let talla: Bool

        init(d: String, relleno: Relleno, talla: Bool) {
            self.d = d
            self.relleno = relleno
            self.talla = talla
        }
    }
}

/// El sello dibujado, con su gota de identidad al 10 % detrás.
public struct SelloMetricaVista: View {
    private let sello: SelloMetrica
    private let lado: CGFloat
    private let gota: Bool

    /// - Parameters:
    ///   - lado: el lado del sello en puntos. 20 en la Matriz (el mismo hueco que dejaba el
    ///     orbe), 28 en la cabecera de una hoja de resumen.
    ///   - gota: el halo de identidad al 10 %. Se apaga donde el contexto ya lo pone.
    public init(_ sello: SelloMetrica, lado: CGFloat, gota: Bool = true) {
        self.sello = sello
        self.lado = lado
        self.gota = gota
    }

    public var body: some View {
        ZStack {
            if gota {
                Circle().fill(sello.tono.opacity(0.10))
            }
            Canvas(opaque: false) { ctx, size in
                // El viewBox del forjador es 24×24; todo lo demás es proporción.
                let k = size.width / 24
                ctx.scaleBy(x: k, y: k)
                let trazos = Self.trazos(sello)
                for (trazo, parte) in zip(trazos, sello.partes) {
                    let estilo = FillStyle(eoFill: parte.talla)
                    switch parte.relleno {
                    case .plano(let color):
                        ctx.fill(trazo, with: .color(color), style: estilo)
                    case .vertical(let claro, let base):
                        // `objectBoundingBox` del SVG: el lavado recorre la caja de ESTA
                        // parte, no la del sello — si no, las partes chicas salen planas.
                        let caja = trazo.boundingRect
                        ctx.fill(trazo,
                                 with: .linearGradient(
                                    Gradient(colors: [claro, base]),
                                    startPoint: CGPoint(x: caja.midX, y: caja.minY),
                                    endPoint: CGPoint(x: caja.midX, y: caja.maxY)),
                                 style: estilo)
                    }
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }

    /// Los paths parseados, una vez por sello y compartidos entre instancias y cuadros: la
    /// Matriz monta nueve sellos y volver a parsear ~100 nodos por cuadro sería basura pura
    /// (mismo criterio que la caché de direcciones de `OrbeVivo`). El Canvas puede dibujar
    /// fuera de MainActor → candado clásico, no aislamiento.
    private static let candado = NSLock()
    nonisolated(unsafe) private static var cache: [String: [Path]] = [:]

    private static func trazos(_ sello: SelloMetrica) -> [Path] {
        candado.lock()
        defer { candado.unlock() }
        if let hecho = cache[sello.rawValue] { return hecho }
        let trazos = sello.partes.map { SVGPathData.path($0.d) }
        cache[sello.rawValue] = trazos
        return trazos
    }
}

#Preview("Sellos · tamaños reales") {
    VStack(spacing: 26) {
        // El tamaño de la Matriz — donde tienen que aguantar.
        HStack(spacing: 14) {
            ForEach(SelloMetrica.allCases, id: \.self) { s in
                SelloMetricaVista(s, lado: 20)
            }
        }
        // El de la cabecera de hoja.
        HStack(spacing: 14) {
            ForEach(SelloMetrica.allCases, id: \.self) { s in
                SelloMetricaVista(s, lado: 28)
            }
        }
        HStack(spacing: 18) {
            ForEach([SelloMetrica.piel, .estres, .carga, .pasos], id: \.self) { s in
                SelloMetricaVista(s, lado: 72)
            }
        }
    }
    .padding(32)
    .background(LiquidColor.fondoGradient)
}
