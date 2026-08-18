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
// CONTRASTE: el calado va sobre `LiquidColor.tonoCampo(tono)`, NO sobre el tono crudo. La
// primera versión medía el contraste solo contra el índigo de Sueño — el único tono de la
// familia que pasa WCAG AA. Sobre ámbar el rótulo daba 3.16:1, y sobre rosa/verde/ámbar no
// pasaba ni a opacidad plena. `tonoCampo` oscurece cada tono lo justo (índigo: 0 %; ámbar:
// 22 %), así que el campo de Sueño sale intacto y ningún otro puede entrar por debajo del piso.
// `LiquidCampoContrasteTests` recorre la familia entera.

/// Los alfas del calado del campo. Fuera del genérico y públicos a propósito: una pantalla en
/// `Cenit/` que dibuje algo extra sobre el campo tiene que poder usarlos en vez de inlinear
/// `0.85` — que es justo la deriva que el sistema de tokens existe para evitar.
public enum LiquidCampo {
    /// Alfa de rótulos, cláusula y unidad sobre el tono del campo. **Piso de contraste**: es el
    /// alfa que `LiquidColor.tonoCampo` usa para decidir cuánto oscurecer. Cambiarlo mueve el
    /// oscurecimiento de TODA la familia — re-mide antes.
    public static let alfaRotulo: Double = 0.85
    /// Alfa del separador entre los dos numerales del par (gemelo de `OnFieldOpacity.divider`).
    public static let alfaSeparador: Double = 0.28
    /// Alfa del especular superior: dice dónde empieza el material sin brillar.
    public static let alfaEspecularSuperior: Double = 0.55
    /// Alfa del trazo de la pastilla del sello. Token propio y no `alfaSeparador`: aquel
    /// documenta la regla ENTRE numerales, y reusarlo aquí era deriva semántica.
    public static let alfaSelloBorde: Double = 0.42
}

/// La pastilla calada del campo: el sello de confianza, o cualquier etiqueta corta que deba
/// leerse sobre el tono. Sin relleno — un fill traslúcido sobre el tono no pasa AA y además
/// es vidrio decorativo dentro de una masa que el dueño pidió plana.
public struct LiquidCampoSello: View {
    private let texto: String
    private let a11y: String?

    public init(_ texto: String, a11y: String? = nil) {
        self.texto = texto
        self.a11y = a11y
    }

    public var body: some View {
        Text(texto)
            .font(LiquidType.captionLectura)
            .foregroundStyle(LiquidColor.papelAlto.opacity(0.92))
            .padding(.horizontal, LiquidSpace.s250)
            .padding(.vertical, LiquidSpace.s075)
            .overlay(
                Capsule().strokeBorder(
                    LiquidColor.papelAlto.opacity(LiquidCampo.alfaSelloBorde), lineWidth: 1)
            )
            .accessibilityLabel(Text(a11y ?? texto))
    }
}

/// La cabecera teñida a sangre de una pantalla de detalle: numeral (o par de numerales),
/// veredicto, cláusula y una ranura libre al pie, calados sobre una masa plana del tono.
public struct LiquidCampoMetrica<Pie: View>: View {
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
        /// **El numeral nunca miente**: un dato que todavía no existe (regularidad calibrando)
        /// se pinta ATENUADO, para que «··» no se lea como una medición. El papel ya lo hacía
        /// (`OnFieldOpacity.secondary`) y la primera versión de este componente lo perdió.
        public let ausente: Bool

        public init(valor: String, unidad: String = "", rotulo: String,
                    a11y: String? = nil, ausente: Bool = false) {
            self.valor = valor
            self.unidad = unidad
            self.rotulo = rotulo
            self.a11y = a11y
            self.ausente = ausente
        }

        /// El dato que aún no se puede medir: «··» atenuado, con el motivo para VoiceOver.
        public static func calibrando(rotulo: String, motivo: String,
                                      marca: String = "··") -> Dato {
            Dato(valor: marca, rotulo: rotulo, a11y: motivo, ausente: true)
        }
    }

    private let tono: Color
    private let titulo: String
    private let glifo: LiquidIcon.Glyph?
    private let datos: [Dato]
    private let veredicto: String?
    private let clausula: String?
    private let onVolver: (() -> Void)?
    private let volverTitulo: String
    private let onInfo: (() -> Void)?
    private let infoAbierto: Bool
    private let infoEtiqueta: String
    private let pie: Pie

    /// - Parameters:
    ///   - tono: la identidad de la métrica. Se oscurece con `LiquidColor.tonoCampo` para que
    ///     el calado pase AA — el caller pasa el tono de la familia, no un tono ya oscurecido.
    ///   - pie: la ranura libre bajo la cláusula. Aquí van el sello de confianza y avisos en
    ///     prosa (siestas excluidas) — cosas que no caben en una cápsula de una línea.
    public init(tono: Color,
                titulo: String,
                glifo: LiquidIcon.Glyph? = nil,
                datos: [Dato],
                veredicto: String? = nil,
                clausula: String? = nil,
                volverTitulo: String = "",
                onVolver: (() -> Void)? = nil,
                infoAbierto: Bool = false,
                infoEtiqueta: String = "",
                onInfo: (() -> Void)? = nil,
                @ViewBuilder pie: () -> Pie = { EmptyView() }) {
        self.tono = tono
        self.titulo = titulo
        self.glifo = glifo
        self.datos = datos
        self.veredicto = veredicto
        self.clausula = clausula
        self.volverTitulo = volverTitulo
        self.onVolver = onVolver
        self.infoAbierto = infoAbierto
        self.infoEtiqueta = infoEtiqueta
        self.onInfo = onInfo
        self.pie = pie()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            if let onVolver { botonVolver(onVolver) }
            encabezado
            numerales
                // Un solo elemento para VoiceOver: el papel cerraba el héroe con
                // `children: .combine` y la primera versión lo abrió en 6 paradas por
                // cabecera × 10 pantallas.
                .accessibilityElement(children: .contain)
            if let veredicto {
                Text(veredicto)
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.papelAlto)
                    .padding(.top, LiquidSpace.s050)
            }
            if let clausula {
                Text(clausula)
                    .font(LiquidType.clausulaCampo)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                    .fixedSize(horizontal: false, vertical: true)
            }
            pie.padding(.top, LiquidSpace.s150)
        }
        .padding(.horizontal, LiquidSpace.s550)
        .padding(.bottom, LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fondo)
    }

    // MARK: - Partes

    private func botonVolver(_ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: LiquidSpace.s050) {
                Image(systemName: "chevron.left")
                    .font(LiquidType.iconSF(size: 14))
                Text(volverTitulo)
                    .font(LiquidType.filaRango)
            }
            .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
            // DENTRO del label y con `contentShape`: con `.plain`, un `.frame` por fuera no
            // agranda el área táctil — el toque seguía siendo el del texto (~20 pt).
            .frame(minHeight: LiquidControl.hitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(volverTitulo))
    }

    private var encabezado: some View {
        HStack(spacing: LiquidSpace.s200) {
            if let glifo {
                LiquidIcon(glifo, size: LiquidType.franjaTamano,
                           color: LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                    .accessibilityHidden(true)
            }
            Text(titulo)
                .font(LiquidType.franja)
                .tracking(LiquidType.franjaTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.papelAlto.opacity(0.9))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(LiquidType.infoGlifo)
                        .foregroundStyle(LiquidColor.papelAlto
                            .opacity(infoAbierto ? 1 : LiquidCampo.alfaRotulo))
                        .frame(width: LiquidControl.hitTarget,
                               height: LiquidControl.hitTarget, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(infoEtiqueta))
            }
        }
    }

    /// Uno o dos numerales. El par se apila cuando no cabe: a AX3 el numeral crece a ~80 pt y
    /// dos lado a lado no entran en 393 pt (DESIGN.md §8.8).
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
            if idx > 0 { separador }
            numeral(dato)
        }
    }

    /// La regla entre numerales. Escala con el numeral: fija a 46 pt quedaba ridícula al lado
    /// de un numeral de ~80 a AX3.
    private var separador: some View {
        Rectangle()
            .fill(LiquidColor.papelAlto.opacity(LiquidCampo.alfaSeparador))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, LiquidSpace.s550)
            .accessibilityHidden(true)
    }

    private func numeral(_ dato: Dato) -> some View {
        // Un dato ausente se atenúa: «··» a alfa pleno es indistinguible de una medición.
        let alfa = dato.ausente ? LiquidCampo.alfaRotulo : 1.0
        return VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s150) {
                Text(dato.valor)
                    .font(LiquidType.numeralCampo)
                    .lineSpacing(LiquidType.numeralCampoLineSpacing)
                    .foregroundStyle(LiquidColor.papelAlto.opacity(alfa))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !dato.unidad.isEmpty {
                    Text(dato.unidad)
                        .font(LiquidType.unidadCampo)
                        .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
                }
            }
            Text(dato.rotulo)
                .font(LiquidType.label)
                .tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.papelAlto.opacity(LiquidCampo.alfaRotulo))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(dato.rotulo))
        .accessibilityValue(Text(dato.a11y ?? "\(dato.valor) \(dato.unidad)"))
    }

    /// El tono del campo (oscurecido lo justo para AA) PLENO — nunca degradado: el dueño pidió
    /// plano — con los dos especulares de 1 pt.
    ///
    /// El fondo NO ignora el safe area: eso es decisión de la pantalla, no del componente (el
    /// papel también la dejaba al caller). Una pantalla que quiera el tinte bajo el status bar
    /// aplica `.ignoresSafeArea(edges: .top)` al contenedor y le da su propio padding superior.
    private var fondo: some View {
        LiquidColor.tonoCampo(tono)
            .overlay(alignment: .top) {
                especular(LiquidCampo.alfaEspecularSuperior)
            }
            .overlay(alignment: .bottom) {
                especular(1.0, color: LiquidColor.vidrioEspecular)
            }
    }

    private func especular(_ alfa: Double, color: Color = .white) -> some View {
        LinearGradient(
            stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(alfa), location: 0.18),
                .init(color: color.opacity(alfa), location: 0.82),
                .init(color: color.opacity(0), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

#if DEBUG
#Preview("Liquid · Campo de métrica") {
    ScrollView {
        VStack(spacing: LiquidSpace.s800) {
            LiquidCampoMetrica(
                tono: LiquidColor.indigo,
                titulo: "Sueño",
                glifo: .luna,
                datos: [
                    .init(valor: "7:12", unidad: "h", rotulo: "Dormido",
                          a11y: "7 horas 12 minutos"),
                    .init(valor: "84", unidad: "/100", rotulo: "Regularidad"),
                ],
                veredicto: "Suficiente",
                clausula: "Cubriste el 88 % de tu necesidad · regularidad alta",
                volverTitulo: "Tendencias",
                onVolver: {},
                infoEtiqueta: "Qué medimos",
                onInfo: {}
            )
            // Regularidad calibrando: el numeral no miente.
            LiquidCampoMetrica(
                tono: LiquidColor.indigo,
                titulo: "Sueño",
                glifo: .luna,
                datos: [
                    .init(valor: "6:40", unidad: "h", rotulo: "Dormido",
                          a11y: "6 horas 40 minutos"),
                    .calibrando(rotulo: "Regularidad",
                                motivo: "aún sin base, faltan 3 noches"),
                ],
                veredicto: "Casi suficiente",
                clausula: "Aún aprendo tu horario · faltan 3 noches"
            )
            // Ámbar: el tono que NO pasaba AA sin oscurecer.
            LiquidCampoMetrica(
                tono: LiquidColor.atencion,
                titulo: "Esfuerzo",
                datos: [.init(valor: "14.2", rotulo: "Carga del día")],
                veredicto: "Por encima de lo tuyo",
                clausula: "El día más cargado de la semana."
            )
        }
    }
    .background(LiquidColor.fondoGradient)
}
#endif
