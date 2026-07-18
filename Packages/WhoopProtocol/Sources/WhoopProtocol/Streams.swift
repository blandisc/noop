import Foundation
import BiometricStreams

/// Map a device-epoch timestamp to wall-clock unix seconds via a pure linear offset.
/// Assumes strap clock and wall clock tick at the same rate (no skew/drift). Port of _to_wall.
private func toWall(_ deviceTs: Int?, _ deviceClockRef: Int, _ wallClockRef: Int) -> Int? {
    guard let deviceTs = deviceTs else { return nil }
    return wallClockRef + (deviceTs - deviceClockRef)
}

/// Turn parsed frames into datastore rows. Port of interpreter.extract_streams.
///
/// HR/R-R are taken ONLY from REALTIME_DATA (type 40). REALTIME_RAW_DATA (type 43) also
/// carries an HR byte but streams alongside type-40 during raw collection, so routing both
/// would double-count HR for the same instants. CRC-failed and non-ok frames are skipped.
public func extractStreams(_ parsed: [ParsedFrame],
                           deviceClockRef: Int, wallClockRef: Int) -> Streams {
    var out = Streams()
    for r in parsed {
        if !r.ok || r.crcOK == false { continue }
        let p = r.parsed
        switch r.typeName {
        case "REALTIME_DATA":
            let ts = toWall(p["timestamp"]?.intValue, deviceClockRef, wallClockRef)
            if let ts = ts, let bpm = p["heart_rate"]?.intValue {
                out.hr.append(HRSample(ts: ts, bpm: bpm))
            }
            // Unlike Python, drop RR rows when timestamp is absent (a ts-less RR row is unstorable).
            if let ts = ts, let rrs = p["rr_intervals"]?.intArrayValue {
                for rr in rrs { out.rr.append(RRInterval(ts: ts, rrMs: rr)) }
            }
        case "EVENT":
            // EVENT timestamps are real RTC unix seconds — already wall-clock, NOT offset.
            guard let ts = p["event_timestamp"]?.intValue else { continue }
            let kind = p["event"]?.stringValue ?? ""
            // BATTERY_LEVEL events (every ~8 min) carry SoC/mV/charging + a real RTC ts →
            // the DENSE battery series (the post-hook decoded the fields).
            if kind.hasPrefix("BATTERY_LEVEL") { appendBattery(&out, ts: ts, p: p) }  // "BATTERY_LEVEL(3)"
            var payload = p
            payload.removeValue(forKey: "event")
            payload.removeValue(forKey: "event_timestamp")
            out.events.append(StreamEvent(ts: ts, kind: kind, payload: payload))
        case "COMMAND_RESPONSE":
            // No device timestamp on COMMAND_RESPONSE → stamp battery at wallClockRef.
            appendBattery(&out, ts: wallClockRef, p: p)
        default:
            continue
        }
    }
    return out
}

/// Append a BatterySample from a parsed frame's battery_pct/battery_mV/battery_charging
/// fields (no-op when neither soc nor mv is present). charging is a real Bool only when the
/// frame reported it (BATTERY_LEVEL events); command responses leave it nil.
func appendBattery(_ out: inout Streams, ts: Int, p: [String: ParsedValue]) {
    let soc = p["battery_pct"]?.doubleValue
    let mv = p["battery_mV"]?.intValue
    guard soc != nil || mv != nil else { return }
    let charging = p["battery_charging"]?.intValue.map { $0 != 0 }
    out.battery.append(BatterySample(ts: ts, soc: soc, mv: mv, charging: charging))
}
