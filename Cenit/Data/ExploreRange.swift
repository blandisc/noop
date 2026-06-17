import Foundation

// MARK: - Range
//
// The W/M/3M/6M/1Y/ALL window shared by every metric drill-down: the dark Metric
// Explorer (`MetricDetailView`) and the unified light Detalle de Métrica
// (`MetricDetailScreen`, FER-185). Extracted from `MetricExplorerView.swift` so the
// new screen doesn't have to import the Explorer to reuse the window model.

/// The W/M/3M/6M/1Y/ALL window, driving the single SegmentedPillControl.
enum ExploreRange: Int, CaseIterable, Identifiable, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365, all = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .week: return String(localized: "W"); case .month: return String(localized: "M")
        case .quarter: return String(localized: "3M"); case .half: return String(localized: "6M")
        case .year: return String(localized: "1Y"); case .all: return String(localized: "ALL")
        }
    }
    var name: String {
        switch self {
        case .week: return String(localized: "week"); case .month: return String(localized: "month")
        case .quarter: return String(localized: "quarter"); case .half: return String(localized: "6 months")
        case .year: return String(localized: "year"); case .all: return String(localized: "all time")
        }
    }
    /// Trailing days the window spans (nil = everything).
    var days: Int? { self == .all ? nil : rawValue }

    /// Ascending order of every range, the basis for the auto-expand search.
    private static let ascending: [ExploreRange] = [.week, .month, .quarter, .half, .year, .all]

    /// This range plus every LARGER range, ascending — the auto-expand search order
    /// when the selected window holds zero points. ALW always terminates the chain.
    var widening: [ExploreRange] {
        guard let i = Self.ascending.firstIndex(of: self) else { return [.all] }
        return Array(Self.ascending[i...])
    }
}
