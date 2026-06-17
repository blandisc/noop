import Foundation

/// One static field entry from a packet spec's "fields" array.
public struct FieldSpec: Codable, Equatable, Sendable {
    public let off: Int
    public let len: Int
    public let dtype: String?
    public let name: String
    public let cat: String
    public let `enum`: String?
    public let note: String?
}

/// One IMU axis: [name, off, cat] in the JSON (a heterogeneous 3-element array).
public struct AxisSpec: Equatable, Sendable {
    public let name: String
    public let off: Int
    public let cat: String
}

/// A REALTIME_RAW_DATA variant keyed by payload data_len ("1917" = IMU, "1921" = optical).
public struct VariantSpec: Equatable, Sendable {
    public let kind: String
    public let note: String
    // imu-only
    public let hrOff: Int?
    public let rrCountOff: Int?
    public let rrFirstOff: Int?
    public let samples: Int?
    public let axes: [AxisSpec]
    public let tailFrom: Int?
    // optical-only (new layout)
    public let ppgOff: Int?
    public let ppgStride: Int?
    public let ppgSamples: Int?
    public let configFrom: Int?
    public let configTo: Int?
}

/// One type-47 HISTORICAL_DATA version layout (keyed by the version byte = seq).
public struct VersionSpec: Equatable, Sendable {
    public let kind: String?
    public let fields: [FieldSpec]
    public let rrFirstOff: Int?
    public let ref: String?
}

public struct PacketSpec: Equatable, Sendable {
    public let name: String
    public let type: Int
    public let aliases: [Int]
    public let post: String?
    public let fields: [FieldSpec]
    public let variants: [String: VariantSpec]
    public let versions: [String: VersionSpec]
}

public struct Schema: Sendable {
    public var enums: [String: [String: String]]
    public var envelope: [FieldSpec]
    public var packets: [String: PacketSpec]
    private var byType: [Int: PacketSpec]

    public init(enums: [String: [String: String]], envelope: [FieldSpec], packets: [String: PacketSpec]) {
        self.enums = enums
        self.envelope = envelope
        self.packets = packets
        var idx: [Int: PacketSpec] = [:]
        for (_, spec) in packets {
            idx[spec.type] = spec
            for alias in spec.aliases {
                idx[alias] = spec
            }
        }
        self.byType = idx
    }
}

public extension Schema {
    func typeName(_ v: Int) -> String {
        enums["PacketType"]?[String(v)] ?? "type\(v)"
    }

    func enumName(_ enumName: String, _ v: Int) -> String {
        if let name = enums[enumName]?[String(v)] {
            return "\(name)(\(v))"
        }
        return String(format: "0x%02X(%d)", v, v)
    }

    func packet(forType v: Int) -> PacketSpec? {
        byType[v]
    }

    /// Pick the layout for a type-47 version byte, following a `ref` chain (V12 -> V24).
    /// Mirrors interpreter._resolve_version: base entry's keys, then this entry's non-ref
    /// keys override.
    func resolveVersion(_ versions: [String: VersionSpec], _ version: Int) -> VersionSpec? {
        guard var entry = versions[String(version)] else { return nil }
        var seen = Set<String>()
        while let ref = entry.ref, !seen.contains(ref) {
            seen.insert(ref)
            guard let base = versions[ref] else { break }
            // base keys, then entry's non-ref keys override.
            entry = VersionSpec(
                kind: entry.kind ?? base.kind,
                fields: entry.fields.isEmpty ? base.fields : entry.fields,
                rrFirstOff: entry.rrFirstOff ?? base.rrFirstOff,
                ref: nil)
        }
        return entry
    }
}

// MARK: - JSON loading (Bundle.module) with cache

private struct RawAxis: Decodable {
    let name: String
    let off: Int
    let cat: String
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = try c.decode(String.self)
        off = try c.decode(Int.self)
        cat = try c.decode(String.self)
    }
}

private struct RawVariant: Decodable {
    let kind: String
    let note: String
    let hr_off: Int?
    let rr_count_off: Int?
    let rr_first_off: Int?
    let samples: Int?
    let axes: [RawAxis]?
    let tail_from: Int?
    // optical (new layout) + IMU metadata that does not change output
    let ppg_off: Int?
    let ppg_stride: Int?
    let ppg_dtype: String?
    let ppg_samples: Int?
    let ppg_rate_hz: Int?
    let config_from: Int?
    let config_to: Int?
    let accel_scale: Double?
    let accel_unit: String?
    let gyro_scale: Double?
    let gyro_unit: String?
}

private struct RawVersion: Decodable {
    let kind: String?
    let fields: [FieldSpec]?
    let rr_first_off: Int?
    let ref: String?
}

private struct RawPacket: Decodable {
    let type: Int
    let aliases: [Int]?
    let post: String?
    let fields: [FieldSpec]?
    let variants: [String: RawVariant]?
    let versions: [String: RawVersion]?
}

private struct RawSchema: Decodable {
    let enums: [String: [String: String]]
    let envelope: [FieldSpec]
    let packets: [String: RawPacket]
}

/// Schema + per-type post-hook registry, compiled exactly once. A `static let` gives `dispatch_once`
/// semantics: the JSON is decoded and the hooks built a single time, even when `parseFrame` is first
/// called concurrently from the dedicated BLE queue and a detached decode task (FER-183). After init
/// the value is fully immutable, so the parse hot path reads it lock-free — replacing the old lazily
/// mutated `_cachedSchema`/`postHooks` globals, which were only race-free while everything ran on the
/// main thread.
enum CompiledProtocol {
    static let shared: (schema: Schema, postHooks: [String: PostHook]) = (buildSchema(), buildPostHooks())
}

/// The compiled protocol schema. Thread-safe and memoized via `CompiledProtocol.shared`.
public func loadSchema() -> Schema { CompiledProtocol.shared.schema }

/// Decode + compile the schema from the bundled JSON. Called exactly once by `CompiledProtocol.shared`.
private func buildSchema() -> Schema {
    guard let url = Bundle.module.url(forResource: "whoop_protocol", withExtension: "json") else {
        fatalError("whoop_protocol.json missing from Bundle.module resources")
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        fatalError("failed to read whoop_protocol.json: \(error)")
    }
    let raw: RawSchema
    do {
        raw = try JSONDecoder().decode(RawSchema.self, from: data)
    } catch {
        fatalError("failed to decode whoop_protocol.json: \(error)")
    }
    var packets: [String: PacketSpec] = [:]
    for (name, rp) in raw.packets {
        var variants: [String: VariantSpec] = [:]
        for (key, rv) in rp.variants ?? [:] {
            variants[key] = VariantSpec(
                kind: rv.kind,
                note: rv.note,
                hrOff: rv.hr_off,
                rrCountOff: rv.rr_count_off,
                rrFirstOff: rv.rr_first_off,
                samples: rv.samples,
                axes: (rv.axes ?? []).map { AxisSpec(name: $0.name, off: $0.off, cat: $0.cat) },
                tailFrom: rv.tail_from,
                ppgOff: rv.ppg_off,
                ppgStride: rv.ppg_stride,
                ppgSamples: rv.ppg_samples,
                configFrom: rv.config_from,
                configTo: rv.config_to)
        }
        var versions: [String: VersionSpec] = [:]
        for (key, rvr) in rp.versions ?? [:] {
            versions[key] = VersionSpec(
                kind: rvr.kind,
                fields: rvr.fields ?? [],
                rrFirstOff: rvr.rr_first_off,
                ref: rvr.ref)
        }
        packets[name] = PacketSpec(
            name: name,
            type: rp.type,
            aliases: rp.aliases ?? [],
            post: rp.post,
            fields: rp.fields ?? [],
            variants: variants,
            versions: versions)
    }
    return Schema(enums: raw.enums, envelope: raw.envelope, packets: packets)
}
