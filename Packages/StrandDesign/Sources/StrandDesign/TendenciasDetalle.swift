import SwiftUI

// MARK: - «Detalle de Tendencias Final» — componentes compartidos (FER-856/857)
//
// El esqueleto estándar de las cuatro pantallas de detalle (Recuperación, Sueño, Esfuerzo, Estrés)
// comparte estas piezas, del handoff `design-handoff/detalle-tendencias-final`:
//
//   · `SeccionFranja` — cabecera de sección a sangre completa (sustituye a los overlines flotantes)
//   · `SeccionBloque` — franja + contenido con el padding handoff bajo ella
//   · `TileSurface`   — el tile para todo escalar (label overline + valor + delta/caption/swatch)
//   · `BarraAncla`    — el ÚNICO formato legal de caption (rect 2×10 del color del dato + texto)
//   · `Metodo`        — el DisclosureGroup «Cómo se calcula» sobre superficie
//   · `PieMetodo`     — divisor + método + sello de origen al pie de la pantalla
//   · `QueMedimosCard`— la tarjeta del ⓘ del héroe («What we measure»)
//   · `ChipTendencia` — píldora rellena «tendencia, no causa» (no confundir con InlineFlagChip)
//   · `QueLaMueveHeader` — overline + ChipTendencia de la cabecera «qué la mueve»
//   · `HeatLegend`    — la leyenda de swatches del calendario 90 días
//   · `OnFieldOpacity`— las opacidades sancionadas del texto sobre el campo invertido del héroe
//
// Los componentes son mudos en copy: reciben `String`/`LocalizedStringKey` ya localizados desde la
// capa de app (el paquete no carga catálogo propio). El selector de periodo es el
// `SegmentedPillControl` themed existente; la gráfica de historial es `GraficaRangos` (archivo
// propio); el sello es `OriginStamp`.

// MARK: - Opacidades sobre campo invertido

/// Opacidades sancionadas para texto/chrome sobre el campo saturado del héroe invertido (el texto
/// es `theme.paper` sobre el hue de la pantalla). Del handoff: secundarios 0.72–0.78, cápsula 0.16.
public enum OnFieldOpacity {
    /// Texto secundario sobre el campo («/100», «vs tu base», el driver del veredicto).
    public static let secondary: Double = 0.75
    /// Fondo de la cápsula secundaria («+6 vs tu base», «en curso»).
    public static let capsule: Double = 0.16
    /// Chrome atenuado (el trazo del ⓘ).
    public static let dimChrome: Double = 0.8
    /// Regla/divisor vertical entre dos datos sobre el campo invertido.
    public static let divider: Double = 0.28
}

// MARK: - SeccionFranja

/// Cabecera de sección a sangre completa: fondo `patternBlock` de borde a borde, overline
/// Grotesk 11/600 tracking 1.4 en tinta secundaria, con una `pista` opcional a la derecha.
/// El caller la coloca SIN padding horizontal (a sangre); el contenido bajo ella lleva el suyo.
public struct SeccionFranja: View {
    private let titulo: String
    private let pista: String?
    private let theme: InstrumentoTheme

    public init(_ titulo: String, pista: String? = nil, theme: InstrumentoTheme) {
        self.titulo = titulo
        self.pista = pista
        self.theme = theme
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(titulo)
                .font(InstrumentoType.grotesk(11, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkSecondary)
            if let pista {
                Spacer(minLength: 10)
                Text(pista)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.patternBlock)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - SeccionBloque

/// Una sección del esqueleto Final: `SeccionFranja` a sangre + el contenido con el padding handoff
/// bajo ella (default 14 · 20 · 22; TrainingLoad pasa `leading: 14` en «The hill»). La `pista`
/// opcional viaja a la franja. El título llega ya localizado.
public struct SeccionBloque<Content: View>: View {
    private let titulo: String
    private let pista: String?
    private let contentPadding: EdgeInsets
    private let theme: InstrumentoTheme
    private let content: Content

    public init(_ titulo: String,
                pista: String? = nil,
                contentPadding: EdgeInsets = EdgeInsets(top: 14, leading: 20, bottom: 22, trailing: 20),
                theme: InstrumentoTheme,
                @ViewBuilder content: () -> Content) {
        self.titulo = titulo
        self.pista = pista
        self.contentPadding = contentPadding
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SeccionFranja(titulo, pista: pista, theme: theme)
            content
                .padding(contentPadding)
        }
    }
}

// MARK: - QueMedimosCard

/// La tarjeta del ⓘ bajo el héroe: overline «What we measure» + explicación en tinta secundaria,
/// superficie `.instrumentoCard(.control)`. `bottomInset` default 14 (Recovery/Strain/Stress/Sleep);
/// TrainingLoad pasa `0` para no empujar la franja «The hill». Copy ya localizado (LocalizedStringKey).
public struct QueMedimosCard: View {
    private let title: LocalizedStringKey
    private let explanation: LocalizedStringKey
    private let theme: InstrumentoTheme
    private let bottomInset: CGFloat

    public init(title: LocalizedStringKey, explanation: LocalizedStringKey,
                theme: InstrumentoTheme, bottomInset: CGFloat = 14) {
        self.title = title
        self.explanation = explanation
        self.theme = theme
        self.bottomInset = bottomInset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(InstrumentoType.grotesk(13, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text(explanation)
                .font(InstrumentoType.grotesk(12))
                .lineSpacing(3)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme)
        .padding(EdgeInsets(top: 12, leading: 20, bottom: bottomInset, trailing: 20))
    }
}

// MARK: - ChipTendencia

/// Píldora rellena estándar «tendencia, no causa» del ADN: fondo `patternBlock`, grotesk 9/600
/// tracking 1 uppercase, radio cápsula. Color de texto: `inkMuted` (el token de tinta más tenue
/// disponible; no hay `inkTenue` — `inkTertiary` es para overlines legibles AA; este chip es
/// chrome de disclaimers). NO es `InlineFlagChip` (ese sigue para avisos Low conf / Estimate).
public struct ChipTendencia: View {
    private let text: LocalizedStringKey
    private let theme: InstrumentoTheme

    public init(_ text: LocalizedStringKey, theme: InstrumentoTheme) {
        self.text = text
        self.theme = theme
    }

    public var body: some View {
        Text(text)
            .font(InstrumentoType.grotesk(9, weight: .semibold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(theme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.patternBlock, in: Capsule())
    }
}

// MARK: - QueLaMueveHeader

/// Cabecera de la tarjeta «qué la mueve / lo que vemos»: overline grotesk 10/600 tracking 1.2
/// uppercase en `inkTertiary` + `ChipTendencia`. El copy llega localizado desde la app.
public struct QueLaMueveHeader: View {
    private let overline: LocalizedStringKey
    private let chip: LocalizedStringKey
    private let theme: InstrumentoTheme

    public init(_ overline: LocalizedStringKey, chip: LocalizedStringKey, theme: InstrumentoTheme) {
        self.overline = overline
        self.chip = chip
        self.theme = theme
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(overline)
                .font(InstrumentoType.grotesk(10, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)
            ChipTendencia(chip, theme: theme)
        }
    }
}

// MARK: - TileSurface

/// El tile para todo escalar: superficie radio 12 con hairline, label overline (Grotesk 9/600
/// tracking 1.1), valor tabular (hue solo con valencia o identidad), delta y caption opcionales,
/// y un swatch de identidad opcional junto al label.
public struct TileSurface: View {
    private let label: String
    private let value: String
    private let valueColor: Color?
    private let valueSize: CGFloat
    private let caption: String?
    private let swatch: Color?
    private let delta: String?
    private let deltaColor: Color?
    private let theme: InstrumentoTheme

    public init(label: String, value: String, valueColor: Color? = nil, valueSize: CGFloat = 15,
                caption: String? = nil, swatch: Color? = nil,
                delta: String? = nil, deltaColor: Color? = nil,
                theme: InstrumentoTheme) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.valueSize = valueSize
        self.caption = caption
        self.swatch = swatch
        self.delta = delta
        self.deltaColor = deltaColor
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if let swatch {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(swatch)
                        .frame(width: 8, height: 8)
                }
                Text(label)
                    .font(InstrumentoType.grotesk(9, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(InstrumentoType.groteskNumber(valueSize, weight: .medium))
                    .foregroundStyle(valueColor ?? theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta {
                    Text(delta)
                        .font(InstrumentoType.groteskNumber(11, weight: .semibold))
                        .foregroundStyle(deltaColor ?? theme.inkTertiary)
                }
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.inkTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - BarraAncla

/// El único formato legal de caption bajo un instrumento: un rectángulo 2×10 del color del dato que
/// explica + texto 11pt en tinta terciaria. Ningún caption flota sin su ancla.
public struct BarraAncla: View {
    private let texto: String
    private let color: Color
    private let theme: InstrumentoTheme

    public init(_ texto: String, color: Color, theme: InstrumentoTheme) {
        self.texto = texto
        self.color = color
        self.theme = theme
    }

    public var body: some View {
        // La barra (rect 2pt) abarca TODA la altura del texto — no una raya de 10pt: en captions de dos
        // renglones cubría solo el primero. Overlay a la izquierda del texto: su alto lo fija el texto.
        Text(texto)
            .font(.system(size: 11))
            .lineSpacing(2.5)
            .foregroundStyle(theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 7)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 2)
            }
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Metodo

#if !os(watchOS)
/// El DisclosureGroup «Cómo se calcula» estandarizado: superficie radio 12, padding 14, plegado por
/// defecto. El título llega localizado desde la app; el contenido es libre.
public struct Metodo<Content: View>: View {
    private let title: String
    private let theme: InstrumentoTheme
    private let content: Content
    @State private var expanded = false

    public init(title: String, theme: InstrumentoTheme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                content
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Pie de pantalla Final: divisor hairline (opcional) + el `Metodo{…}` del caller + sello de origen.
/// El sello es un `@ViewBuilder` porque las pantallas ensamblan `OriginStamp` con firmas distintas
/// (origin/when/inProgress) y a veces un `FusionAgreementRow` debajo (Sueño). `showsDivider: false`
/// cubre estados de calibración sin raya. Padding default = el handoff (16 · 20 · 26 · 20).
public struct PieMetodo<MetodoContent: View, Sello: View>: View {
    private let theme: InstrumentoTheme
    private let showsDivider: Bool
    private let contentPadding: EdgeInsets
    private let metodo: MetodoContent
    private let sello: Sello

    public init(showsDivider: Bool = true,
                contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 20, bottom: 26, trailing: 20),
                theme: InstrumentoTheme,
                @ViewBuilder metodo: () -> MetodoContent,
                @ViewBuilder sello: () -> Sello) {
        self.showsDivider = showsDivider
        self.contentPadding = contentPadding
        self.theme = theme
        self.metodo = metodo()
        self.sello = sello()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsDivider {
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)
                    .padding(.horizontal, 20)
            }
            VStack(alignment: .leading, spacing: 10) {
                metodo
                sello
            }
            .padding(contentPadding)
        }
    }
}
#endif

// MARK: - HeatLegend

/// La leyenda del calendario 90 días: una fila de swatches 8×8 radio 2 + palabra en 10pt terciaria.
public struct HeatLegend: View {
    private let items: [(color: Color, label: String)]
    private let theme: InstrumentoTheme

    public init(_ items: [(color: Color, label: String)], theme: InstrumentoTheme) {
        self.items = items
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                    Text(item.label)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SeccionFranja") {
    let t = InstrumentoTheme.base
    VStack(spacing: 14) {
        SeccionFranja("HOY, VS TU NORMAL", theme: t)
        SeccionFranja("CALENDARIO · 90 DÍAS", pista: "últimos 3 meses", theme: t)
    }
    .background(t.paper)
}

#Preview("TileSurface") {
    let t = InstrumentoTheme.base
    HStack(spacing: 8) {
        TileSurface(label: "VS AYER", value: "+6", valueColor: t.verdictDeep, caption: "puntos", theme: t)
        TileSurface(label: "VFC", value: "48→52", caption: "ms", delta: "+4", deltaColor: t.verdictDeep, theme: t)
        TileSurface(label: "PROF.", value: "22%", swatch: t.dataSleepDeep, delta: "+3", theme: t)
    }
    .padding(20)
    .background(t.paper)
}

#if !os(watchOS)
#Preview("BarraAncla + Metodo + HeatLegend") {
    let t = InstrumentoTheme.base
    VStack(alignment: .leading, spacing: 18) {
        BarraAncla("El pronóstico es una proyección, no una garantía.", color: t.verdict, theme: t)
        Metodo(title: "Cómo se calcula", theme: t) {
            Text("Cada señal se compara con tu propia base de 30 días.")
                .font(.system(size: 13))
                .foregroundStyle(t.inkSecondary)
        }
        HeatLegend([(t.verdict, "listo"), (t.warning, "recuperando"),
                    (t.critical, "bajo"), (t.rangeBand, "sin dato")], theme: t)
    }
    .padding(20)
    .background(t.paper)
}

#Preview("QueMedimos + SeccionBloque + Chip + PieMetodo") {
    let t = InstrumentoTheme.base
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            QueMedimosCard(title: "What we measure",
                           explanation: "Recovery blends several signals with your own baseline.",
                           theme: t)
            SeccionBloque("HOY, VS TU NORMAL", theme: t) {
                Text("Contenido de la sección")
                    .font(.system(size: 13))
                    .foregroundStyle(t.inkSecondary)
            }
            SeccionBloque("CALENDARIO · 90 DÍAS", pista: "últimos 3 meses", theme: t) {
                QueLaMueveHeader("What moves your strain", chip: "trend, not cause", theme: t)
            }
            PieMetodo(theme: t) {
                Metodo(title: "How it's calculated", theme: t) {
                    Text("Each signal is compared to your own 30-day base.")
                        .font(.system(size: 13))
                        .foregroundStyle(t.inkSecondary)
                }
            } sello: {
                OriginStamp(origin: .computed, when: "today", theme: t)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }
    .background(t.paper)
}
#endif
#endif
