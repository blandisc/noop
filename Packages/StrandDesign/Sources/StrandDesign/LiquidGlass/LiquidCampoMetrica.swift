import SwiftUI

// MARK: - Liquid Glass · Campo de métrica (FER-102, pantallas de detalle)
//
// La cabecera A SANGRE y TEÑIDA de una pantalla de detalle de Tendencias: una masa plana del
// tono de la métrica que llega a los cuatro cantos, con el numeral calado encima.
//
// POR QUÉ EXISTE (decisión del dueño, 2026-08-17): al migrar Tendencias de papel a vidrio, lo
// que el dueño pidió conservar del papel fue exactamente esto — «me gusta que llenen el espacio
// completo de izquierda a derecha, que sean planas, y la cabecera entera teñida». El resto de la
// pantalla sí cambia de material; el campo cambia de FONDO (papel cálido → suelo casi blanco) y
// de tipografía, pero conserva su forma.
//
// EXCEPCIÓN SANCIONADA a «el tono nunca tiñe el fondo de una tarjeta» (LIQUID-GLASS.md §8): el
// campo NO es una tarjeta, es el cielo de la pantalla, y no flota — no tiene radio, ni borde, ni
// sombra, ni margen. Mismo estatuto que `LiquidHill`. La regla sigue viva para todo lo que va
// debajo: ahí el tono se retira a las marcas (barras, celdas, la joya de la gráfica).
//
// LO QUE LO HACE VIDRIO Y NO TINTA: dos especulares de 1 pt. Arriba, un streak al 55 % que dice
// dónde empieza el material; abajo, `vidrioEspecular` (.92) que separa el campo del suelo sin
// una línea dura. Ninguno de los dos brilla ni degrada — el dueño pidió plano y esto no lo rompe.
//
// CONTRASTE: el calado va en `papelAlto` sobre el tono PLENO. La pasada de /ui midió los alfas
// contra WCAG AA y subió los rótulos de .75 a .85 (a .75 daban 3.99:1 sobre índigo, bajo el
// mínimo de 4.5). `CampoContrasteTests` fija ese piso para que no se vuelva a bajar.

/// La cabecera teñida a sangre de una pantalla de detalle: numeral (o par de numerales),
/// veredicto, cláusula y una pastilla opcional, calados sobre una masa plana del tono.
public struct LiquidCampoMetrica<Trailing: View>: View {
    /// Un numeral del campo con su unidad y su rótulo.
    public struct Dato: Equatable, Sendable {
        /// El número ya formateado («7:12», «84»). El campo nunca formatea: recibe texto.
        public let valor: String
        /// La unidad corta («h», «/100»). Vacía si no aplica.
        public let unidad: String
        /// El rótulo en caja alta bajo el numeral («DORMIDO», «REGULARIDAD»).
        public let rotulo: String
        /// Cómo debe leerlo VoiceOver («7 horas 12 minutos») — «7:12» se dicta como una hora
        /// del reloj y decía «siete doce». Si es nil, se dicta `valor` + `unidad`.
        public let a11y: String?

        public init(valor: String, unidad: String = "", rotulo: String, a11y: String? = nil) {
            self.valor = valor
            self.unidad = unidad
            self.rotulo = rotulo
            self.a11y = a11y
        }
    }

    private let tono: Color
    private let titulo: String
    private let datos: [Dato]
    private let veredicto: String?
    private let clausula: String?
    private let pastilla: String?
    private let onVolver: (() -> Void)?
    private let volverTitulo: String
    private let trailing: Trailing

    /// Alfa de los rótulos y la cláusula sobre el tono pleno. **Piso de contraste**: a .75 el
    /// papel sobre índigo daba 3.99:1 (AA pide 4.5). No bajar sin re-medir.
    static var alfaRotulo: Double { 0.85 }
    /// Alfa del separador entre los dos numerales del par.
    static var alfaSeparador: Double { 0.28 }

    public init(tono: Color,
                titulo: String,
                datos: [Dato],
                veredicto: String? = nil,
                clausula: String? = nil,
                pastilla: String? = nil,
                volverTitulo: String = "",
                onVolver: (() -> Void)? = nil,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.tono = tono
        self.titulo = titulo
        self.datos = datos
        self.veredicto = veredicto
        self.clausula = clausula
        self.pastilla = pastilla
        self.volverTitulo = volverTitulo
        self.onVolver = onVolver
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            if let onVolver {
                Button(action: onVolver) {
                    HStack(spacing: LiquidSpace.s050) {
                        Image(systemName: "chevron.left")
                            .font(LiquidType.iconSF(size: 14))
                        Text(volverTitulo)
                    }
                    .foregroundStyle(LiquidColor.papelAlto.opacity(Self.alfaRotulo))
                }
                .buttonStyle(.plain)
                .frame(minHeight: LiquidControl.hitTarget, alignment: .leading)
                .accessibilityLabel(Text(volverTitulo))
            }

            HStack(spacing: LiquidSpace.s200) {
                Text(titulo)
                    .font(LiquidType.franja)
                    .tracking(LiquidType.franjaTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(0.9))
                Spacer(minLength: 0)
                trailing
            }

            numerales

            if let veredicto {
                Text(veredicto)
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.papelAlto)
                    .padding(.top, LiquidSpace.s050)
            }

            if let clausula {
                Text(clausula)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(Self.alfaRotulo))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let pastilla {
                // Sin relleno: el fill traslúcido al 16 % daba 3.96:1 y además era vidrio
                // decorativo dentro de una masa que ya es plana (pasada /ui).
                Text(pastilla)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(0.92))
                    .padding(.horizontal, LiquidSpace.s250)
                    .padding(.vertical, LiquidSpace.s075)
                    .overlay(
                        Capsule().stroke(LiquidColor.papelAlto.opacity(0.42), lineWidth: 1)
                    )
                    .padding(.top, LiquidSpace.s050)
            }
        }
        .padding(.horizontal, LiquidSpace.s550)
        .padding(.bottom, LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) { fondo }
    }

    /// Uno o dos numerales. El par se apila en tamaños de accesibilidad: a AX3 el numeral
    /// crece a ~80 pt y dos lado a lado no caben en 393 pt (DESIGN.md §8.8).
    @ViewBuilder private var numerales: some View {
        if datos.count > 1 {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 0) { parEnFila }
                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    ForEach(Array(datos.enumerated()), id: \.offset) { numeral($0.element) }
                }
            }
        } else if let uno = datos.first {
            numeral(uno)
        }
    }

    @ViewBuilder private var parEnFila: some View {
        ForEach(Array(datos.enumerated()), id: \.offset) { idx, dato in
            if idx > 0 {
                Rectangle()
                    .fill(LiquidColor.papelAlto.opacity(Self.alfaSeparador))
                    .frame(width: 1, height: 46)
                    .padding(.horizontal, LiquidSpace.s400)
                    .accessibilityHidden(true)
            }
            numeral(dato)
        }
    }

    private func numeral(_ dato: Dato) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s100) {
                Text(dato.valor)
                    .font(LiquidType.numeralCampo)
                    .lineSpacing(LiquidType.numeralCampoLineSpacing)
                if !dato.unidad.isEmpty {
                    Text(dato.unidad)
                        .font(LiquidType.numeralHojaUnidad)
                        .foregroundStyle(LiquidColor.papelAlto.opacity(Self.alfaRotulo))
                }
            }
            .foregroundStyle(LiquidColor.papelAlto)
            Text(dato.rotulo)
                .font(LiquidType.label)
                .tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.papelAlto.opacity(Self.alfaRotulo))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dato.rotulo))
        .accessibilityValue(Text(dato.a11y ?? "\(dato.valor) \(dato.unidad)"))
    }

    /// El tono PLENO (nunca degradado: el dueño pidió plano) con los dos especulares de 1 pt.
    private var fondo: some View {
        tono
            .overlay(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.55), location: 0.18),
                        .init(color: .white.opacity(0.55), location: 0.82),
                        .init(color: .white.opacity(0), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: LiquidColor.vidrioEspecular, location: 0.5),
                        .init(color: .white.opacity(0), location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
    }
}

#if DEBUG
#Preview("Liquid · Campo de métrica") {
    ScrollView {
        VStack(spacing: LiquidSpace.s800) {
            LiquidCampoMetrica(
                tono: LiquidColor.indigo,
                titulo: "Sueño",
                datos: [
                    .init(valor: "7:12", unidad: "h", rotulo: "Dormido",
                          a11y: "7 horas 12 minutos"),
                    .init(valor: "84", unidad: "/100", rotulo: "Regularidad"),
                ],
                veredicto: "Suficiente",
                clausula: "Cubriste el 88 % de tu necesidad · regularidad alta",
                pastilla: "+18 min vs tu base",
                volverTitulo: "Tendencias",
                onVolver: {}
            )
            LiquidCampoMetrica(
                tono: LiquidColor.verdeProfundo,
                titulo: "Preparación",
                datos: [.init(valor: "23", unidad: "de 26", rotulo: "Mañanas en rango")],
                veredicto: "En rango",
                clausula: "Las últimas 30 mañanas, contadas una por una."
            )
        }
    }
    .background(LiquidColor.fondoGradient)
}
#endif
