import XCTest
@testable import Cenit

// MetricDirectionTests.swift — the per-metric «good direction» the dynamic-average Δ colours by (FER-563).
//
// The Detalle de Métrica caption «Average · {window} · {value} · {Δ%} vs previous» colours its Δ from
// `MetricDescriptor.higherIsBetter` (HRV↑, resting HR↓, respiration↓, SpO₂↑, steps↑; effort & skin temp
// neutral). This guards that table so a catalog edit can't silently flip a metric's colour — the exact
// good-direction map the handoff (FER-562) specified.

final class MetricDirectionTests: XCTestCase {

    private func direction(_ key: String) -> Bool?? {
        MetricCatalog.all.first { $0.key == key }?.higherIsBetter
    }

    func testGoodDirectionPerMetric() {
        XCTAssertEqual(direction("hrv"), .some(true), "HRV: higher is better")
        XCTAssertEqual(direction("rhr"), .some(false), "Resting HR: lower is better")
        XCTAssertEqual(direction("resp_rate"), .some(false), "Respiration: lower is better (FER-563)")
        XCTAssertEqual(direction("spo2"), .some(true), "SpO₂: higher is better")
        XCTAssertEqual(direction("steps"), .some(true), "Steps: higher is better")
        XCTAssertEqual(direction("strain"), .some(Bool?.none), "Effort: neutral (no colour)")
        XCTAssertEqual(direction("skin_temp"), .some(Bool?.none), "Skin temp: neutral (no colour)")
    }
}
