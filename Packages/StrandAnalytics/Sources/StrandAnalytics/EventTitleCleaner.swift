import Foundation

// EventTitleCleaner.swift — turn a messy real calendar title into a short display label, conservatively.
// Pure, DB-free. (FER-433)
//
// Real titles are "RE: FW: Revisión de diseño NOOP // Detalle (Sala 4B)", not "Junta". We strip known
// noise and cut at the first structural delimiter, but never guess so hard we lose meaning. The CALLER
// always keeps the original (for VoiceOver / tap); this only computes the DISPLAY string. If cleaning
// would empty the title, we fall back to the trimmed original. Truncation is the view's job, not ours.

public enum EventTitleCleaner {

    /// Leading prefixes peeled off (case-insensitive), repeatedly — handles "RE: FW: …".
    private static let prefixes = ["re:", "fw:", "fwd:", "rv:", "invitación:", "invitation:",
                                   "cancelado:", "canceled:", "cancelled:"]
    /// Structural delimiters; we keep only the text before the EARLIEST one.
    private static let cutMarkers = ["—", "–", "//", " ("]

    /// A conservative display title. Never empty unless the original was empty.
    public static func clean(_ raw: String) -> String {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = original

        // 1. Peel leading bracket tags ([EXT], [Externo], …) and known prefixes, repeatedly.
        var changed = true
        while changed {
            changed = false
            s = s.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
                s = String(s[s.index(after: close)...]); changed = true; continue
            }
            for p in prefixes where s.lowercased().hasPrefix(p) {
                s = String(s.dropFirst(p.count)); changed = true; break
            }
        }

        // 2. Cut at the earliest structural delimiter (— – // " (").
        var cutIdx = s.endIndex
        for m in cutMarkers {
            if let r = s.range(of: m), r.lowerBound < cutIdx { cutIdx = r.lowerBound }
        }
        s = String(s[..<cutIdx])

        // 3. Drop a trailing meeting-link suffix ("… @ Google Meet", "@ Zoom").
        if let r = s.range(of: " @ ") { s = String(s[..<r.lowerBound]) }

        // 4. Remove emoji / pictographic scalars (and their joiners/selectors). Guard on non-ASCII so
        //    emoji-capable ASCII (digits, #, *) and accented letters (é, ñ) survive.
        let kept = s.unicodeScalars.filter { sc in
            if sc.value == 0xFE0F || sc.value == 0x200D { return false }
            if sc.properties.isEmoji && !sc.isASCII { return false }
            return true
        }
        s = String(String.UnicodeScalarView(kept))

        // 5. Collapse whitespace and trim.
        s = s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).joined(separator: " ")

        // 6. If cleaning emptied it, fall back to the original (never return "" for a non-empty title).
        return s.isEmpty ? original : s
    }
}
