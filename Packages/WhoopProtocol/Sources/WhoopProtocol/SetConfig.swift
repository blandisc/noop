import Foundation

/// `SET_CONFIG` (command 0x78) — enable named firmware data-stream packet types on the WHOOP 4.0.
///
/// Reverse-engineered from the official WHOOP app's BLE handshake (FER-156 HCI capture, 2026-06-16):
/// the app writes a burst of these to enable the biometric record streams (the `r19` family, plus
/// `write_r24`/`write_r25`) that the strap then records to flash and offloads. NOOP never sent
/// `SET_CONFIG` at all — that is the leading hypothesis (FER-93b) for why a power-reset 4.0 stops
/// persisting biometry until the official app re-enables the streams.
///
/// Pure: this builds only the command PAYLOAD (the bytes after `[type][seq][cmd]`); the caller frames
/// it with the standard COMMAND envelope (`crc8` + `crc32`, via `WhoopCommand.frame`). No CoreBluetooth,
/// no I/O — byte-for-byte verified against the capture in `SetConfigTests`.
public enum SetConfig {
    /// ASCII key field width observed on the wire (key, null-padded to this many bytes).
    public static let keyFieldWidth = 32
    /// Total payload length observed on the wire: `[0x01] + key(32) + [value] + zero-pad` = 65 bytes.
    public static let payloadLength = 65

    /// Build the `SET_CONFIG` payload for one config key, matching the official app byte-for-byte:
    /// `[0x01][key: 32 B ASCII, null-padded][value: 1 B][0x00 …]` (total `payloadLength`).
    public static func payload(key: String, value: UInt8) -> [UInt8] {
        var p: [UInt8] = [0x01]                               // sub-opcode (SET)
        var k = Array(key.utf8)
        if k.count > keyFieldWidth { k = Array(k.prefix(keyFieldWidth)) }
        p += k
        p += [UInt8](repeating: 0, count: keyFieldWidth - k.count)   // null-pad key to 32 B
        p.append(value)                                       // value byte
        p += [UInt8](repeating: 0, count: max(0, payloadLength - p.count))  // zero-pad tail
        return p
    }

    /// The exact burst the official app sends on a fresh connection (FER-156) — keys, values, and
    /// ORDER verbatim from the capture. Enables the `general_ab_test` / `sigproc_10_sec_dp` toggles
    /// and the `r19` v2–v6 / `write_r24`/`write_r25` / `capsense_wear_detect` streams.
    public static let officialBurst: [(key: String, value: UInt8)] = [
        ("general_ab_test",             0x32),
        ("sigproc_10_sec_dp",           0x32),
        ("enable_r19_packets",          0x32),
        ("enable_r19_v2_packets",       0x32),
        ("enable_r19_v3_packets",       0x32),
        ("enable_r19_v4_packets",       0x31),
        ("enable_r19_v5_packets",       0x32),
        ("enable_r19_v6_packets",       0x32),
        ("enable_write_r24_packets",    0x31),
        ("enable_write_r25_packets",    0x31),
        ("enable_capsense_wear_detect", 0x32),
    ]
}
