import Foundation

// MARK: - Decoded stream rows (the durable, compact local record)
//
// The NEUTRAL vocabulary: these shapes describe biometric data, not the source that produced it —
// no bytes, no frames, no strap. `CenitStore` persists them and `StrandAnalytics` computes over
// them without ever linking a wire protocol (FER-993 · D2). Both depend on these EXACT shapes.
// `ts` is always wall-clock unix seconds (whoever decodes the rows does the clock mapping).

public struct HRSample: Equatable, Codable, Sendable {
    public let ts: Int          // wall-clock unix seconds
    public let bpm: Int
    public init(ts: Int, bpm: Int) { self.ts = ts; self.bpm = bpm }
}

public struct RRInterval: Equatable, Codable, Sendable {
    public let ts: Int          // wall-clock unix seconds
    public let rrMs: Int
    public init(ts: Int, rrMs: Int) { self.ts = ts; self.rrMs = rrMs }
}

public struct StreamEvent: Equatable, Codable, Sendable {
    public let ts: Int          // real unix seconds (event RTC; never offset)
    public let kind: String
    public let payload: [String: ParsedValue]
    public init(ts: Int, kind: String, payload: [String: ParsedValue]) {
        self.ts = ts; self.kind = kind; self.payload = payload
    }
}

public struct BatterySample: Equatable, Codable, Sendable {
    public let ts: Int          // unix seconds — event RTC for BATTERY_LEVEL events, else wallClockRef
    public let soc: Double?
    public let mv: Int?
    public let charging: Bool?  // only the BATTERY_LEVEL event reports this; nil otherwise
    public init(ts: Int, soc: Double?, mv: Int?, charging: Bool? = nil) {
        self.ts = ts; self.soc = soc; self.mv = mv; self.charging = charging
    }
}

// MARK: - type-47 HISTORICAL_DATA biometric rows. JSON keys MUST match
// biometric_streams_golden.json exactly (see extract_historical_streams).

public struct SpO2Sample: Equatable, Codable, Sendable {
    public let ts: Int
    public let red: Int
    public let ir: Int
    public let unit: String     // "raw_adc"
    public init(ts: Int, red: Int, ir: Int, unit: String = "raw_adc") {
        self.ts = ts; self.red = red; self.ir = ir; self.unit = unit
    }
}

public struct SkinTempSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let raw: Int
    public let unit: String     // "raw_adc"
    public init(ts: Int, raw: Int, unit: String = "raw_adc") {
        self.ts = ts; self.raw = raw; self.unit = unit
    }
}

public struct RespSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let raw: Int
    public let unit: String     // "raw_adc"
    public init(ts: Int, raw: Int, unit: String = "raw_adc") {
        self.ts = ts; self.raw = raw; self.unit = unit
    }
}

public struct GravitySample: Equatable, Codable, Sendable {
    public let ts: Int
    public let x: Double
    public let y: Double
    public let z: Double
    public let unit: String     // "g"
    public init(ts: Int, x: Double, y: Double, z: Double, unit: String = "g") {
        self.ts = ts; self.x = x; self.y = y; self.z = z; self.unit = unit
    }
}

/// WHOOP 5/MG cumulative u16 step / motion counter (step_motion_counter@57). APPROXIMATE — the @57
/// step semantics are unverified against the official WHOOP app (#78). Mirrors Android StepSample.
public struct StepSample: Equatable, Codable, Sendable {
    public let ts: Int
    public let counter: Int
    public init(ts: Int, counter: Int) {
        self.ts = ts; self.counter = counter
    }
}

public struct Streams: Equatable, Codable, Sendable {
    public var hr: [HRSample]
    public var rr: [RRInterval]
    public var spo2: [SpO2Sample]
    public var skinTemp: [SkinTempSample]
    public var resp: [RespSample]
    public var gravity: [GravitySample]
    public var steps: [StepSample]
    public var events: [StreamEvent]
    public var battery: [BatterySample]
    /// #547 diagnostic: how many historical records `extractHistoricalStreams` DROPPED this chunk for an
    /// implausible own-timestamp (a bad-clock strap: far-past / bogus-2027 / future-dated). NOT persisted
    /// and NOT round-tripped through Codable (excluded from `CodingKeys`) — it is a transient observability
    /// count the Backfiller surfaces to the strap log. Defaults to 0 so it never affects golden fixtures.
    public var droppedImplausible: Int = 0
    public init(hr: [HRSample] = [], rr: [RRInterval] = [],
                spo2: [SpO2Sample] = [], skinTemp: [SkinTempSample] = [],
                resp: [RespSample] = [], gravity: [GravitySample] = [],
                steps: [StepSample] = [],
                events: [StreamEvent] = [], battery: [BatterySample] = []) {
        self.hr = hr; self.rr = rr
        self.spo2 = spo2; self.skinTemp = skinTemp; self.resp = resp; self.gravity = gravity
        self.steps = steps
        self.events = events; self.battery = battery
    }

    /// True when no decoded rows landed in any stream — used to flag a historical chunk whose rows
    /// all dropped (checksum fail / unmapped layout / out-of-range timestamp), the silent-data-loss
    /// diagnostic in `Backfiller.finishChunk` (#77).
    public var isEmpty: Bool {
        hr.isEmpty && rr.isEmpty && spo2.isEmpty && skinTemp.isEmpty && resp.isEmpty
            && gravity.isEmpty && steps.isEmpty && events.isEmpty && battery.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case hr, rr, spo2, skinTemp = "skin_temp", resp, gravity, steps, events, battery
    }

    // Custom decode so older fixtures (streams_golden.json / historical_golden.json) that
    // lack the new biometric keys still decode — missing arrays default to empty.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hr = try c.decodeIfPresent([HRSample].self, forKey: .hr) ?? []
        rr = try c.decodeIfPresent([RRInterval].self, forKey: .rr) ?? []
        spo2 = try c.decodeIfPresent([SpO2Sample].self, forKey: .spo2) ?? []
        skinTemp = try c.decodeIfPresent([SkinTempSample].self, forKey: .skinTemp) ?? []
        resp = try c.decodeIfPresent([RespSample].self, forKey: .resp) ?? []
        gravity = try c.decodeIfPresent([GravitySample].self, forKey: .gravity) ?? []
        steps = try c.decodeIfPresent([StepSample].self, forKey: .steps) ?? []
        events = try c.decodeIfPresent([StreamEvent].self, forKey: .events) ?? []
        battery = try c.decodeIfPresent([BatterySample].self, forKey: .battery) ?? []
    }
}

extension Streams { public static let empty = Streams() }
