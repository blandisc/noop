import Foundation
import ZIPFoundation

/// Parses an Apple Health export (`export.xml`, possibly inside `export.zip`)
/// into normalized Swift models using a **streaming SAX parser**
/// (`XMLParser`/`XMLParserDelegate`) — never a DOM, because the file can exceed
/// 1 GB.
///
/// Behaviour (per Strand design spec §3.1 / §7.1):
/// - Maintains an element stack to track nesting (`Correlation`, `Workout`,
///   `MetadataEntry`, etc.).
/// - Filters to the relevant `Record` types only.
/// - `OxygenSaturation` is a 0–1 fraction → multiplied by 100.
/// - `SleepAnalysis` category values mapped to `SleepStage`.
/// - **Dedupe:** records nested inside a `<Correlation>` also appear at top
///   level → only top-level records are ingested, and a final dedupe pass on
///   `type+start+end+source+value` removes any residual duplicates.
/// - Dates `yyyy-MM-dd HH:mm:ss Z` parsed with `Locale(en_US_POSIX)`.
public struct AppleHealthImporter {

    public init() {}

    /// Health types Strand cares about (prefix already stripped).
    public static let relevantTypes: Set<String> = [
        "HeartRate",
        "RestingHeartRate",
        "HeartRateVariabilitySDNN",
        "WalkingHeartRateAverage",
        "OxygenSaturation",
        "BodyTemperature",
        "AppleSleepingWristTemperature",
        "RespiratoryRate",
        "ActiveEnergyBurned",
        "BasalEnergyBurned",
        "VO2Max",
        "StepCount",
        "SleepAnalysis",
        // Body composition
        "BodyMass",
        "BodyFatPercentage",
        "LeanBodyMass",
        "BodyMassIndex",
    ]

    // MARK: - Public entry points

    /// Whether a filename plausibly names the Apple Health export XML.
    ///
    /// Apple localizes the filename by device language — `export.xml` (English),
    /// `exportación.xml` (Spanish), `Export.xml` (German), `exportation.xml`
    /// (French), … — so matching the English literal breaks every non-English
    /// export. Accept any `.xml`, excluding the clinical-records twin, whose
    /// `_cda` suffix is constant across languages (`export_cda.xml`,
    /// `exportación_cda.xml`, …).
    static func isHealthExportXMLName(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasSuffix(".xml") && !n.hasSuffix("_cda.xml")
    }

    /// Periodic progress callback: total `<Record>`/`<Workout>` elements seen so
    /// far. Fired off the main thread (the importer runs on a background executor)
    /// roughly every 50k elements, so the UI can show live progress instead of a
    /// frozen-looking spinner on a multi-minute import.
    public typealias ProgressHandler = @Sendable (_ elementsParsed: Int) -> Void

    /// Import from `export.zip` or a path to `export.xml` (or a folder
    /// containing it).
    /// `isCancelled`, when supplied, is polled on each progress tick during the (multi-minute) XML
    /// parse; returning `true` aborts the parse and throws `CancellationError` so a user who leaves
    /// mid-import stops the work promptly instead of letting it run to completion (FER-33).
    public func `import`(from url: URL, progress: ProgressHandler? = nil,
                         isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ImportError.fileNotFound(url.path)
        }

        if isDir.boolValue {
            guard let xmlURL = findExportXML(inFolder: url) else {
                throw ImportError.missingEntry("export.xml")
            }
            return try importXML(at: xmlURL, progress: progress, isCancelled: isCancelled)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "xml" {
            return try importXML(at: url, progress: progress, isCancelled: isCancelled)
        }
        if ext == "zip" {
            return try importZip(at: url, progress: progress, isCancelled: isCancelled)
        }
        // Unknown extension: try zip first, then raw XML.
        if let z = try? importZip(at: url, progress: progress, isCancelled: isCancelled) { return z }
        return try importXML(at: url, progress: progress, isCancelled: isCancelled)
    }

    /// Stream-parse a raw `export.xml` file.
    public func importXML(at xmlURL: URL, progress: ProgressHandler? = nil,
                          isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        // Stream from disk via an InputStream rather than XMLParser(contentsOf:), which would load
        // the entire (multi-hundred-MB) file into memory before parsing.
        guard let raw = InputStream(url: xmlURL) else {
            throw ImportError.fileNotFound(xmlURL.path)
        }
        // Wrap the disk stream in a sanitizer so XML-1.0-illegal bytes (stray control chars, broken
        // UTF-8 from a decade-old export) are scrubbed in fixed-size chunks BEFORE libxml2 sees them.
        // Without this a single bad byte mid-file (libxml2 error 65 / SpaceRequired etc.) aborts the
        // whole multi-year import. The sanitizer is itself an InputStream, so streaming/memory bounds
        // are preserved — nothing is buffered to RAM or disk.
        let sanitizer = SanitizingInputStream(source: raw)
        return try runParser(XMLParser(stream: sanitizer), sanitizer: sanitizer, progress: progress, isCancelled: isCancelled)
    }

    /// Parse a `Data` blob of XML (used for the zip-streaming path and tests).
    public func importXML(data: Data, progress: ProgressHandler? = nil,
                          isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        // Route the in-memory path through the same sanitizing stream so tests and the (rare) data
        // path get identical tolerance to illegal bytes / broken UTF-8 as the disk path.
        let sanitizer = SanitizingInputStream(source: InputStream(data: data))
        return try runParser(XMLParser(stream: sanitizer), sanitizer: sanitizer, progress: progress, isCancelled: isCancelled)
    }

    // MARK: - Zip handling

    private func importZip(at zipURL: URL, progress: ProgressHandler? = nil,
                           isCancelled: (@Sendable () -> Bool)? = nil) throws -> AppleHealthImportResult {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ImportError.notAZipOrFolder(zipURL.path)
        }

        // Locate the export XML entry by filename anywhere in the archive
        // (Apple nests it under apple_health_export/). The name is localized
        // by device language, so prefer an exact "export.xml" and otherwise
        // take the largest non-CDA .xml (the main export dwarfs anything else).
        var target: Entry?
        var fallback: (entry: Entry, size: UInt64)?
        for entry in archive where entry.type == .file {
            let name = (entry.path as NSString).lastPathComponent
            if name.lowercased() == "export.xml" {
                target = entry
                break
            }
            if Self.isHealthExportXMLName(name) {
                let size = entry.uncompressedSize
                if fallback == nil || size > fallback!.size { fallback = (entry, size) }
            }
        }
        guard let entry = target ?? fallback?.entry else { throw ImportError.missingEntry("export.xml") }

        // Guard the device's temp volume before decompressing: iOS sandboxes the
        // temporary directory and a multi-hundred-MB export can exceed free space,
        // which would otherwise fail mid-write with a truncated/partial XML (silent
        // data loss). Require headroom for the decompressed size (a 4× ratio is
        // typical for this XML) plus a margin; fail early with a clear error.
        let tmpDir = FileManager.default.temporaryDirectory
        if let free = try? tmpDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage {
            let estimated = Int64(entry.uncompressedSize) + (64 << 20)   // +64 MB margin
            if free < estimated {
                throw ImportError.xmlParseFailed(
                    "Not enough free space to import this export (needs ~\(estimated >> 20) MB). Free up space and try again.")
            }
        }

        // Decompress export.xml to a temp file (chunks go straight to disk, so RAM stays bounded),
        // then stream-parse it from disk. This replaces a pipe-fed background parser that could
        // deadlock or crash with a broken-pipe exception on a malformed/malicious export.
        let tmp = tmpDir.appendingPathComponent("noop-health-\(UUID().uuidString).xml")
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tmp) else {
            throw ImportError.xmlParseFailed("could not open a temp file for import")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var written = 0
        let cap = 8 << 30   // 8 GB decompressed ceiling (real exports are < 2 GB) — zip-bomb guard
        do {
            _ = try archive.extract(entry, bufferSize: 1 << 20) { chunk in
                written += chunk.count
                if written > cap { throw ImportError.xmlParseFailed("export.xml too large") }
                try handle.write(contentsOf: chunk)
            }
        } catch {
            try? handle.close()
            throw ImportError.xmlParseFailed("could not read export.xml from zip: \(error.localizedDescription)")
        }
        try? handle.close()

        return try importXML(at: tmp, progress: progress, isCancelled: isCancelled)
    }

    // MARK: - Core parse

    private func runParser(
        _ parser: XMLParser,
        sanitizer: SanitizingInputStream? = nil,
        progress: ProgressHandler? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> AppleHealthImportResult {
        let delegate = HealthXMLDelegate(progress: progress, isCancelled: isCancelled)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        let ok = parser.parse()

        // A user-requested cancel aborts the parse; surface it as cancellation rather than letting
        // the tolerant-partial path below treat the abort as a successful partial import (FER-33).
        if delegate.wasCancelled { throw CancellationError() }

        // How many illegal-byte runs the sanitizer scrubbed before the parser ran. Always surfaced.
        let scrubbedRuns = sanitizer?.scrubbedRunCount ?? 0

        if !ok || delegate.parseError != nil {
            // TOLERANT PARSE: a hard XML error can still slip past the sanitizer (e.g. a structurally
            // broken tag, not just a bad byte). If we already parsed at least one record, keep the
            // partial result rather than discarding a whole 15-year import over the tail. The dropped
            // span is COUNTED and surfaced, never hidden.
            if delegate.hasAnyRecord {
                return delegate.makeResult(extraSkippedSpans: scrubbedRuns + 1)
            }
            let msg = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "unknown error"
            throw ImportError.xmlParseFailed(msg)
        }
        return delegate.makeResult(extraSkippedSpans: scrubbedRuns)
    }

    private func findExportXML(inFolder folder: URL) -> URL? {
        let fm = FileManager.default
        // Common location first.
        let direct = folder.appendingPathComponent("export.xml")
        if fm.fileExists(atPath: direct.path) { return direct }
        let nested = folder.appendingPathComponent("apple_health_export/export.xml")
        if fm.fileExists(atPath: nested.path) { return nested }
        // Otherwise search, accepting localized names ("exportación.xml", …):
        // an exact "export.xml" wins, else the largest non-CDA candidate.
        var best: (url: URL, size: Int)?
        if let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in e {
                let name = u.lastPathComponent
                if name.lowercased() == "export.xml" { return u }
                guard Self.isHealthExportXMLName(name) else { continue }
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if best == nil || size > best!.size { best = (u, size) }
            }
        }
        return best?.url
    }
}

// MARK: - SAX delegate

final class HealthXMLDelegate: NSObject, XMLParserDelegate {

    // Streaming sink: records fold into per-day aggregates as they parse, so we
    // never retain the tens of millions of raw samples a multi-year export holds.
    private let aggregator = AppleHealthDayAggregator()
    private(set) var workouts: [HealthWorkout] = []   // bounded (hundreds)
    private(set) var countsByType: [String: Int] = [:]
    private(set) var parseError: Error?

    // Running summary state (replaces deriving it from a retained samples array).
    private var recordCount = 0
    private var earliestStart: Date?
    private var latestStart: Date?

    // Element nesting stack (just the element names).
    private var stack: [String] = []
    // Depth of the current Correlation, if inside one. Records nested inside a
    // Correlation are skipped (they also appear top-level) — this is what the
    // old global dedupe set guarded, so dropping that set (an OOM source: one
    // entry per record) is safe; the Correlation skip already covers it.
    private var correlationDepth = 0

    // Progress reporting: total Record/Workout elements seen, fired every `tick`.
    private let progress: AppleHealthImporter.ProgressHandler?
    private var elementsSeen = 0
    private let progressTick = 50_000

    // Cooperative cancellation: polled at each progress tick. On a cancel we abort the parse and set
    // `wasCancelled` so `runParser` can throw `CancellationError` (FER-33).
    private let isCancelled: (@Sendable () -> Bool)?
    private(set) var wasCancelled = false

    /// True once at least one usable record/workout/sleep row was parsed. Drives the tolerant-parse
    /// decision: a hard error AFTER real data was seen keeps the partial result instead of failing.
    var hasAnyRecord: Bool {
        // O(1) running state (no retained samples/sleep arrays — the OOM fix);
        // `recordCount` already tallies every record incl. sleep, via note(type:start:).
        recordCount > 0 || !workouts.isEmpty
    }

    private let dateParser = HealthDateParser()

    init(progress: AppleHealthImporter.ProgressHandler? = nil,
         isCancelled: (@Sendable () -> Bool)? = nil) {
        self.progress = progress
        self.isCancelled = isCancelled
    }

    /// Fire the periodic progress callback and poll for cancellation. Returns true if the caller
    /// should stop (the parse was aborted) — checked at each `progressTick`.
    private func reportProgressAndCheckCancel(_ parser: XMLParser) -> Bool {
        progress?(elementsSeen)
        if isCancelled?() == true {
            wasCancelled = true
            parser.abortParsing()
            return true
        }
        return false
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let parentIsCorrelation = (stack.last == "Correlation")
        stack.append(elementName)

        // Drain per-element: a multi-year export.xml has tens of millions of elements, each
        // bridging an attribute dictionary + temporaries (date parsing). Without a pool these
        // accumulate until parse() returns, inflating peak memory. Pool drains every element.
        autoreleasepool {
            switch elementName {
            case "Correlation":
                correlationDepth += 1

            case "Record":
                // Skip records nested inside a Correlation (deduped to top-level).
                if parentIsCorrelation || correlationDepth > 0 {
                    return
                }
                elementsSeen += 1
                if elementsSeen % progressTick == 0, reportProgressAndCheckCancel(parser) { return }
                handleRecord(attributeDict)

            case "Workout":
                elementsSeen += 1
                if elementsSeen % progressTick == 0, reportProgressAndCheckCancel(parser) { return }
                handleWorkout(attributeDict)

            default:
                break
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "Correlation", correlationDepth > 0 {
            correlationDepth -= 1
        }
        if stack.last == elementName {
            stack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Ignore benign "no data" / EOF style errors that can occur when the
        // streaming pipe closes; only record genuine malformed-XML errors.
        let ns = parseError as NSError
        if ns.domain == XMLParser.errorDomain {
            // Code 5 == NSXMLParserPrematureDocumentEndError can happen on empty
            // streams; treat truly empty as non-fatal only if we parsed nothing.
            if ns.code == XMLParser.ErrorCode.prematureDocumentEndError.rawValue,
               recordCount == 0, workouts.isEmpty {
                self.parseError = parseError
                return
            }
        }
        self.parseError = parseError
    }

    // MARK: Record handling

    private func handleRecord(_ attrs: [String: String]) {
        guard let rawType = attrs["type"] else { return }
        let type = Self.stripPrefix(rawType)
        guard AppleHealthImporter.relevantTypes.contains(type) else { return }

        guard
            let startStr = attrs["startDate"],
            let endStr = attrs["endDate"],
            let (start, _) = dateParser.parse(startStr),
            let (end, endOffset) = dateParser.parse(endStr)
        else { return }

        let unit = attrs["unit"]
        let rawValue = attrs["value"]

        if type == "SleepAnalysis" {
            // Sleep is a category record; its value is a stage enum string. Fold
            // straight into per-night stage totals.
            let stage = SleepStage.from(rawValue: rawValue ?? "")
            aggregator.addSleep(stage: stage, start: start, end: end, tzOffsetMin: endOffset)
            note(type: type, start: start)
            return
        }

        var numeric = rawValue.flatMap { Double($0) }
        // OxygenSaturation is a 0–1 fraction → percent.
        if type == "OxygenSaturation", let v = numeric {
            numeric = v * 100.0
        }

        // Fold this reading into its local day immediately; nothing is retained.
        aggregator.addRecord(type: type, value: numeric, unit: unit,
                             start: start, tzOffsetMin: endOffset, end: end)
        note(type: type, start: start)
    }

    /// Tally a parsed record into the running summary (count, type histogram,
    /// earliest/latest start) — replaces deriving these from a retained array.
    private func note(type: String, start: Date) {
        recordCount += 1
        countsByType[type, default: 0] += 1
        if earliestStart == nil || start < earliestStart! { earliestStart = start }
        if latestStart == nil || start > latestStart! { latestStart = start }
    }

    // MARK: Workout handling

    private func handleWorkout(_ attrs: [String: String]) {
        guard
            let startStr = attrs["startDate"],
            let endStr = attrs["endDate"],
            let (start, _) = dateParser.parse(startStr),
            let (end, endOffset) = dateParser.parse(endStr)
        else { return }

        let rawActivity = attrs["workoutActivityType"] ?? "Unknown"
        let activity = Self.stripPrefix(rawActivity)

        var durationS: Double?
        if let dStr = attrs["duration"], let d = Double(dStr) {
            // durationUnit is typically "min"; default to minutes per Apple's export.
            let unit = (attrs["durationUnit"] ?? "min").lowercased()
            switch unit {
            case "min": durationS = d * 60.0
            case "sec", "s": durationS = d
            case "hr", "h": durationS = d * 3600.0
            default: durationS = d * 60.0
            }
        }

        let distanceM = attrs["totalDistance"].flatMap { Double($0) }.map { meters -> Double in
            let unit = (attrs["totalDistanceUnit"] ?? "km").lowercased()
            switch unit {
            case "km": return meters * 1000.0
            case "mi": return meters * 1609.344
            case "m":  return meters
            default:   return meters * 1000.0
            }
        }

        let energyKcal = attrs["totalEnergyBurned"].flatMap { Double($0) }
        // Apple exports energy in kcal by default (totalEnergyBurnedUnit "kcal").

        let workout = HealthWorkout(
            activityType: activity,
            durationS: durationS,
            distanceM: distanceM,
            energyKcal: energyKcal,
            start: start,
            end: end,
            tzOffsetMin: endOffset,
            sourceName: attrs["sourceName"]
        )
        workouts.append(workout)
        countsByType["Workout", default: 0] += 1
        if earliestStart == nil || start < earliestStart! { earliestStart = start }
        if latestStart == nil || start > latestStart! { latestStart = start }
    }

    // MARK: Result

    /// Build the normalized result. `extraSkippedSpans` carries the number of dropped XML spans
    /// (sanitizer-scrubbed illegal-byte runs, plus 1 if a hard parse error truncated the tail) so the
    /// summary reports a partial import honestly instead of looking complete. Earliest/latest/count
    /// come from O(1) running state (no retained samples array — the OOM fix).
    func makeResult(extraSkippedSpans: Int = 0) -> AppleHealthImportResult {
        let summary = ImportSummary(
            sourceKind: .appleHealth,
            recordCount: recordCount + workouts.count,
            earliest: earliestStart,
            latest: latestStart,
            countsByCategory: countsByType,
            skippedSpans: extraSkippedSpans
        )
        return AppleHealthImportResult(
            daily: aggregator.merged(),
            workouts: workouts,
            summary: summary
        )
    }

    // MARK: Helpers

    /// Strip the HealthKit identifier prefix from a type string.
    /// `HKQuantityTypeIdentifierHeartRate` → `HeartRate`,
    /// `HKCategoryTypeIdentifierSleepAnalysis` → `SleepAnalysis`,
    /// `HKWorkoutActivityTypeRunning` → `Running`.
    static func stripPrefix(_ raw: String) -> String {
        let prefixes = [
            "HKQuantityTypeIdentifier",
            "HKCategoryTypeIdentifier",
            "HKDataTypeIdentifier",
            "HKWorkoutActivityType",
        ]
        for p in prefixes where raw.hasPrefix(p) {
            return String(raw.dropFirst(p.count))
        }
        return raw
    }
}

// MARK: - Date parsing for Apple Health

/// Parses Apple Health dates `yyyy-MM-dd HH:mm:ss Z` (space before a colon-less
/// offset) with `en_US_POSIX`, returning a UTC `Date` plus the original offset
/// in minutes.
final class HealthDateParser {
    private let formatter: DateFormatter

    init() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        self.formatter = f
    }

    /// Returns (utcDate, offsetMinutes).
    func parse(_ raw: String) -> (Date, Int)? {
        // Fast path first: the canonical Apple shape is fixed-width, so a hand-rolled scan is
        // ~10–20× cheaper than `DateFormatter.date(from:)` — and this runs twice per record
        // (start + end) over tens of millions of records. Anything that doesn't match falls
        // through to the formatter/ISO path below, so tolerance is unchanged.
        if let fast = Self.fastParse(raw) { return fast }
        guard let date = formatter.date(from: raw) else {
            // Fallback: try a few alternative shapes (ISO-8601, no seconds).
            return parseFallback(raw)
        }
        return (date, Self.offsetMinutes(from: raw))
    }

    /// Allocation-free parse of Apple Health's canonical `yyyy-MM-dd HH:mm:ss Z` shape
    /// (e.g. `2024-06-01 14:30:00 -0500`, also accepts `+01:00` and `Z`). Returns nil on ANY
    /// deviation so `parse` can fall back to the slow `DateFormatter` path — correctness over the
    /// odd malformed row is preserved while the overwhelmingly-common shape stays on the fast path.
    static func fastParse(_ raw: String) -> (Date, Int)? {
        let b = Array(raw.utf8)
        guard b.count >= 19 else { return nil }

        @inline(__always) func num(_ start: Int, _ len: Int) -> Int? {
            var v = 0
            for i in start..<(start + len) {
                let c = b[i]
                guard c >= 48, c <= 57 else { return nil }   // ASCII '0'..'9'
                v = v * 10 + Int(c - 48)
            }
            return v
        }

        // Fixed separators: "----:--:-- " → '-' '-' ' ' ':' ':'
        guard b[4] == 45, b[7] == 45, b[10] == 32, b[13] == 58, b[16] == 58 else { return nil }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
              let h = num(11, 2), let mi = num(14, 2), let s = num(17, 2),
              mo >= 1, mo <= 12, d >= 1, d <= 31, h < 24, mi < 60, s < 62 else { return nil }

        // Offset token after the time. Tolerate a single leading space then "+HHMM"/"-HHMM"/
        // "+HH:MM"/"Z"; a bare time with no offset is treated as +0000 (Apple always emits one).
        var i = 19
        if i < b.count, b[i] == 32 { i += 1 }
        var offsetMin = 0
        if i < b.count {
            let c = b[i]
            if c == 90 || c == 122 {                          // 'Z' / 'z'
                offsetMin = 0
            } else if c == 43 || c == 45 {                    // '+' / '-'
                let sign = (c == 45) ? -1 : 1
                i += 1
                guard let oh = num(i, 2) else { return nil }
                i += 2
                if i < b.count, b[i] == 58 { i += 1 }         // optional ':' in "+HH:MM"
                let om = num(i, 2) ?? 0
                offsetMin = sign * (oh * 60 + om)
            } else {
                return nil
            }
        }

        let days = CivilDate.daysFromCivil(y, mo, d)
        // UTC = local civil time − offset.
        let utcSeconds = Double(days) * 86_400.0
            + Double(h * 3600 + mi * 60 + s)
            - Double(offsetMin * 60)
        return (Date(timeIntervalSince1970: utcSeconds), offsetMin)
    }

    private func parseFallback(_ raw: String) -> (Date, Int)? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) {
            return (d, Self.offsetMinutes(from: raw))
        }
        return nil
    }

    /// Extract the trailing numeric UTC offset (`+0100`, `-0500`, `+01:00`, `Z`)
    /// from a date string, in minutes.
    static func offsetMinutes(from raw: String) -> Int {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("Z") || trimmed.hasSuffix("z") { return 0 }
        // Offset is the last token; look for the sign within the last ~6 chars.
        let tail = String(trimmed.suffix(6))
        guard let signRange = tail.range(of: "[+-]", options: .regularExpression) else {
            return 0
        }
        let offStr = String(tail[signRange.lowerBound...])
        let sign = offStr.hasPrefix("-") ? -1 : 1
        let digits = offStr.dropFirst().filter { $0.isNumber }
        guard digits.count >= 2 else { return 0 }
        let s = String(digits)
        var hours = 0, minutes = 0
        if s.count >= 4 {
            hours = Int(s.prefix(2)) ?? 0
            minutes = Int(s.dropFirst(2).prefix(2)) ?? 0
        } else {
            hours = Int(s.prefix(2)) ?? 0
        }
        return sign * (hours * 60 + minutes)
    }
}

// MARK: - Chunked sanitizing input stream

/// An `InputStream` that wraps a source stream and scrubs every byte XML 1.0 forbids — and every
/// invalid UTF-8 sequence — *as it streams*, in fixed-size chunks, before the bytes reach
/// `XMLParser`/libxml2.
///
/// WHY this exists: a single malformed byte in a multi-year Apple Health `export.xml` (a stray
/// control char, or mojibake / truncated UTF-8 from a decade-old phone) makes libxml2 abort with a
/// hard error (e.g. error 65 "SpaceRequired"), discarding everything parsed up to that point. By
/// repairing the byte stream up front the parse runs to EOF and the import survives.
///
/// It is itself a streaming `InputStream`, so memory stays bounded: it never holds more than one
/// source chunk plus, at most, the 1–3 trailing bytes of a UTF-8 sequence that straddles a chunk
/// boundary. We do NOT inflate the file to RAM or disk.
///
/// Sanitization rules (UTF-8 only — Apple Health exports declare UTF-8):
///  - Bytes `< 0x20` that are not TAB (0x09), LF (0x0A) or CR (0x0D) → dropped (XML-1.0 illegal).
///  - 0x7F and any byte sequence that is not valid UTF-8 → replaced with U+FFFD (`EF BF BD`).
///  - Valid multi-byte UTF-8 sequences are passed through byte-for-byte, including ones split across
///    a chunk boundary (the incomplete tail is carried into the next read).
///
/// `scrubbedRunCount` tracks how many *contiguous runs* of dropped/replaced bytes were scrubbed, so
/// the import summary can report "N spans skipped" honestly rather than hiding the damage.
final class SanitizingInputStream: InputStream {

    private let source: InputStream
    /// Bytes lifted from `source` but not yet sanitized — only a partial UTF-8 sequence sitting at a
    /// chunk boundary ever lives here (≤ 3 bytes), plus transiently a full read chunk during scrub.
    private var carry: [UInt8] = []
    /// Sanitized bytes ready to hand to the parser but not yet consumed by `read`.
    private var outBuffer: [UInt8] = []
    private var outOffset = 0
    private var sourceEOF = false
    private var sourceError: Error?

    /// Number of contiguous illegal-byte runs scrubbed (one increment per run, not per byte), so the
    /// summary reports a sensible "spans skipped" figure even on a heavily-corrupted export.
    private(set) var scrubbedRunCount = 0
    /// Tracks whether the previous emitted byte was itself a scrub, so a run of N consecutive bad
    /// bytes counts as ONE span, not N.
    private var inScrubRun = false

    private let chunkSize: Int

    init(source: InputStream, chunkSize: Int = 1 << 16) {
        self.source = source
        self.chunkSize = max(chunkSize, 8)
        // InputStream's designated init; the data is ignored because we override read().
        super.init(data: Data())
    }

    // MARK: InputStream lifecycle

    override func open() { source.open() }
    override func close() { source.close() }

    override var streamError: Error? { sourceError }
    override var streamStatus: Stream.Status {
        if sourceError != nil { return .error }
        if sourceEOF && outOffset >= outBuffer.count { return .atEnd }
        return source.streamStatus
    }

    override var hasBytesAvailable: Bool {
        outOffset < outBuffer.count || !sourceEOF
    }

    /// Fill `buffer` with up to `len` sanitized bytes. Returns the count, 0 at EOF, or -1 on a
    /// source read error (the parser then surfaces it; the tolerant-parse layer decides whether to
    /// keep what was parsed so far).
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard len > 0 else { return 0 }
        // Top up the sanitized output buffer until we have something to give or the source is drained.
        while outOffset >= outBuffer.count {
            if sourceEOF {
                // Drain any remaining carry: at true EOF a leftover partial UTF-8 sequence is itself
                // invalid and becomes a single U+FFFD.
                if !carry.isEmpty {
                    flushCarryAtEOF()
                    if outOffset < outBuffer.count { break }
                }
                return 0
            }
            if let err = sourceError { _ = err; return -1 }
            refill()
        }
        let available = outBuffer.count - outOffset
        let n = min(len, available)
        outBuffer.withUnsafeBufferPointer { src in
            buffer.update(from: src.baseAddress! + outOffset, count: n)
        }
        outOffset += n
        if outOffset >= outBuffer.count {
            outBuffer.removeAll(keepingCapacity: true)
            outOffset = 0
        }
        return n
    }

    override func getBuffer(
        _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
        length len: UnsafeMutablePointer<Int>
    ) -> Bool {
        // No zero-copy buffer; force callers (XMLParser) onto read(_:maxLength:).
        return false
    }

    // MARK: Sanitizing core

    /// Read one chunk from the source, append it to `carry`, scrub the carry up to the last complete
    /// UTF-8 boundary, and stage the result in `outBuffer`.
    private func refill() {
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        let n = chunk.withUnsafeMutableBufferPointer { ptr -> Int in
            source.read(ptr.baseAddress!, maxLength: chunkSize)
        }
        if n < 0 {
            sourceError = source.streamError
                ?? NSError(domain: "SanitizingInputStream", code: -1)
            return
        }
        if n == 0 {
            sourceEOF = true
            return
        }
        carry.append(contentsOf: chunk[0..<n])
        // Scrub everything except a possible incomplete trailing UTF-8 sequence, which we hold back
        // so a sequence split across chunk reads isn't misclassified as invalid.
        scrub(holdIncompleteTail: true)
    }

    /// At EOF, anything left in `carry` is final: a dangling partial sequence is genuinely invalid.
    private func flushCarryAtEOF() {
        scrub(holdIncompleteTail: false)
    }

    /// Consume `carry`, emit sanitized bytes into `outBuffer`. When `holdIncompleteTail` is true the
    /// trailing bytes of a not-yet-complete (but so-far-valid) UTF-8 sequence are left in `carry` for
    /// the next chunk.
    private func scrub(holdIncompleteTail: Bool) {
        var i = 0
        let bytes = carry
        let count = bytes.count
        outBuffer.reserveCapacity(outBuffer.count + count)

        while i < count {
            let b = bytes[i]

            // 1) ASCII fast path.
            if b < 0x80 {
                if b >= 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
                    // 0x20–0x7F (incl. DEL 0x7F, which XML 1.0 permits) pass through unchanged.
                    outBuffer.append(b)
                    inScrubRun = false
                } else {
                    // XML-1.0-illegal C0 control char (< 0x20, not TAB/LF/CR) → drop.
                    noteScrub()
                }
                i += 1
                continue
            }

            // 2) Multi-byte UTF-8. Determine the expected sequence length from the lead byte.
            let seqLen: Int
            if b & 0xE0 == 0xC0 { seqLen = 2 }
            else if b & 0xF0 == 0xE0 { seqLen = 3 }
            else if b & 0xF8 == 0xF0 { seqLen = 4 }
            else { seqLen = 0 } // 0x80–0xBF continuation as a lead, or 0xF8–0xFF: invalid.

            if seqLen == 0 {
                emitReplacement()
                i += 1
                continue
            }

            // Not enough bytes yet for the full sequence?
            if i + seqLen > count {
                if holdIncompleteTail {
                    // Could still be a valid sequence finishing in the next chunk — carry it over.
                    break
                } else {
                    // EOF with a truncated sequence: invalid.
                    emitReplacement()
                    i += 1
                    continue
                }
            }

            // Validate the continuation bytes AND reject overlong / surrogate / out-of-range
            // encodings (the cases libxml2 rejects). Mirrors the well-formed-UTF-8 ranges.
            if isValidUTF8Sequence(bytes, start: i, length: seqLen) {
                for k in 0..<seqLen { outBuffer.append(bytes[i + k]) }
                inScrubRun = false
                i += seqLen
            } else {
                // Only the lead byte is consumed; the (invalid) continuation bytes are re-examined.
                emitReplacement()
                i += 1
            }
        }

        // Anything from `i` onward is the held-back incomplete tail (or nothing).
        if i >= count {
            carry.removeAll(keepingCapacity: true)
        } else {
            carry = Array(bytes[i..<count])
        }
    }

    /// Emit a U+FFFD replacement and account for the scrub run.
    private func emitReplacement() {
        outBuffer.append(contentsOf: [0xEF, 0xBF, 0xBD]) // U+FFFD in UTF-8
        // The replacement is also part of a scrub run; count it.
        noteScrub()
    }

    /// Account for one scrubbed byte, collapsing consecutive bad bytes into a single counted span.
    private func noteScrub() {
        if !inScrubRun {
            scrubbedRunCount += 1
            inScrubRun = true
        }
    }

    /// Validate a UTF-8 sequence of `length` bytes starting at `start`, including the overlong /
    /// surrogate / range constraints (RFC 3629), so we only pass through encodings libxml2 accepts.
    private func isValidUTF8Sequence(_ bytes: [UInt8], start: Int, length: Int) -> Bool {
        let b0 = bytes[start]
        switch length {
        case 2:
            // Valid 2-byte lead is C2..DF. C0/C1 also match `b & 0xE0 == 0xC0` (so seqLen==2) but are
            // overlong encodings of ASCII — reject them here.
            guard b0 >= 0xC2 else { return false }
            return isCont(bytes[start + 1])
        case 3:
            let b1 = bytes[start + 1]
            guard isCont(bytes[start + 2]) else { return false }
            switch b0 {
            case 0xE0: return b1 >= 0xA0 && b1 <= 0xBF            // exclude overlong
            case 0xED: return b1 >= 0x80 && b1 <= 0x9F            // exclude UTF-16 surrogates
            default:   return isCont(b1)
            }
        case 4:
            let b1 = bytes[start + 1]
            guard isCont(bytes[start + 2]), isCont(bytes[start + 3]) else { return false }
            switch b0 {
            case 0xF0: return b1 >= 0x90 && b1 <= 0xBF            // exclude overlong
            case 0xF4: return b1 >= 0x80 && b1 <= 0x8F            // exclude > U+10FFFF
            case 0xF1...0xF3: return isCont(b1)
            default: return false
            }
        default:
            return false
        }
    }

    @inline(__always)
    private func isCont(_ b: UInt8) -> Bool { b & 0xC0 == 0x80 }
}
