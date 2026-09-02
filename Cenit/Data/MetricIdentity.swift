import SwiftUI
import CenitDesign

// MetricIdentity.swift — the ONE «catalog metric → Liquid identity» bridge (FER-104 / TND-29, foco 4).
//
// Three rival identity maps decide a metric's colour/glyph today:
//   • the canonical one — `LiquidMetricSheetView.tono` / `.glifo` (the Hoy sheet), keyed by SHEET id;
//   • `MetricExplorerView.metricAccent` — a second map keyed by catalog key, in `theme.*` roles;
//   • Compare's colour-by-index — position in the picked list, no identity at all.
//
// This coins ONE bridge, calqued verbatim from the canonical sheet map but keyed by the CATALOG key
// (so it covers the full ~35-metric catalog, not just the ~10 the sheet surfaces). It is the puente
// the visual migration (TND-30/31) will point Compare and Explore at, retiring `metricAccent` and the
// colour-by-index. This block only COINS + TESTS it — it does not repaint anything yet.
//
// Fallback (documented, revised FER-108 · Grok D1): a catalog metric with no canonical family falls
// to NEUTRAL ink (`tinta500`) with no glyph — NOT `verdePrimario`. That green already means «verdict /
// recovery», so lending it to a metric with no identity (the body-composition metrics weight / body
// fat / lean mass / BMI, VO₂max, calories energy_kcal / active_kcal, the HR-zone splits, strength
// time) is the same defect the paper had: a colour that already means something else. Neutral tinta
// says «no identity assigned yet» honestly — colour only when it means something (the Instrumento
// principle); the metric's label separates the tiles. `recovery` IS verdePrimario legitimately (its
// real identity), so it is mapped EXPLICITLY, not via the fallback. TND-30/31 must consciously assign
// the no-family metrics a real family; until then neutral is the honest state.

/// The single identity bridge for a catalog metric: its Liquid hue and (optional) drop glyph.
enum MetricIdentity {

    /// (hue, glyph) for a catalog `key`, calqued from `LiquidMetricSheetView.tono` / `.glifo`. Keys
    /// with no canonical identity return `(verdePrimario, nil)` — see the file note.
    static func identity(forKey key: String) -> (hue: Color, glyph: LiquidIcon.Glyph?) {
        switch key {
        // Sleep family → índigo · luna. The sheet maps the sleep concept there; the catalog splits it
        // into 13 keys — all share the family.
        case "sleep_performance", "sleep_total_min", "in_bed_min", "hours_vs_needed_pct",
             "sleep_consistency", "restorative_pct", "restorative_min", "sleep_efficiency",
             "sleep_deep_min", "sleep_rem_min", "sleep_light_min", "sleep_need_min", "sleep_debt_min":
            return (LiquidColor.indigo, .luna)

        // HRV → cian · onda.
        case "hrv":
            return (LiquidColor.cian, .onda)

        // Heart rate → rosa · corazón. Intraday HR (`heart_rate`) and the catalog's resting / average
        // / max HR all belong to the one family — the Tendencias landing shows an intraday «Heart Rate»
        // column, so `heart_rate` is mapped here explicitly, not left to the neutral fallback (FER-100).
        case "heart_rate", "rhr", "avg_hr", "max_hr":
            return (LiquidColor.rosa, .corazon)

        // Effort (strain) → ámbar · llama.
        case "strain":
            return (LiquidColor.ambar, .llama)

        // Skin temperature → dorado propio · termómetro (FER-79 D2: keeps its own gold, not Effort's
        // ámbar which is also the attention colour).
        case "skin_temp":
            return (LiquidColor.doradoTemp, .termo)

        // Steps → teal · figura.
        case "steps":
            return (LiquidColor.teal, .pasos)

        // Respiration + blood oxygen → azul · pulmones (SpO₂ shares the respiratory family, same
        // criterion the sheet uses — the Liquid glyph set has no «drop»).
        case "resp_rate", "spo2":
            return (LiquidColor.azul, .resp)

        // Stress accompanies, it doesn't vote (HJ-09): the sheet denies it the verdict green and reads
        // it on its own heat ramp. Collapsed here to the ramp's representative mid-ocre for a static
        // identity chip — it must NOT fall through to `verdePrimario`, so it is mapped explicitly.
        case "stress":
            return (LiquidColor.estresMedio, .estres)

        // Recovery IS the verdict green legitimately (its real identity, not a gap) — mapped
        // explicitly, like stress, so it does NOT ride the fallback below.
        case "recovery":
            return (LiquidColor.verdePrimario, nil)

        // No canonical identity yet → NEUTRAL ink (tinta500), no glyph. NOT verdePrimario: that green
        // already means «verdict / recovery», so lending it to a metric with no family (body
        // composition, VO₂max, calories, HR-zone splits, strength time) is the same defect the paper
        // had — a colour that already means something else. Neutral tinta says «no identity assigned»
        // honestly (colour only when it means something, the Instrumento principle); the metric's
        // label carries it. TND-30/31 must consciously assign these a real family (FER-108 · Grok D1).
        default:
            return (LiquidColor.tinta500, nil)
        }
    }

    /// The Liquid hue for a catalog metric.
    static func hue(for metric: MetricDescriptor) -> Color { identity(forKey: metric.key).hue }

    /// The Liquid drop glyph for a catalog metric (nil when it has none).
    static func glyph(for metric: MetricDescriptor) -> LiquidIcon.Glyph? { identity(forKey: metric.key).glyph }

    /// Identity for an INGEST key (what the Apple-Health screens speak). Normalizes through
    /// `MetricCatalog.catalogKey(forIngestKey:)` first, so `resting_hr` reads as `rhr` (rosa · corazón)
    /// and `asleep_min` as the sleep family (índigo · luna) instead of falling to the `verdePrimario`
    /// default. The port MUST use this, never `identity(forKey:)` on a raw ingest key (FER-108).
    static func identity(forIngestKey key: String) -> (hue: Color, glyph: LiquidIcon.Glyph?) {
        identity(forKey: MetricCatalog.catalogKey(forIngestKey: key))
    }
}
