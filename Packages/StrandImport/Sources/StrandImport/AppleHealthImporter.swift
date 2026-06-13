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
    public func `import`(from url: URL, progress: ProgressHandler? = nil) throws -> AppleHealthImportResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ImportError.fileNotFound(url.path)
        }

        if isDir.boolValue {
            guard let xmlURL = findExportXML(inFolder: url) else {
                throw ImportError.missingEntry("export.xml")
            }
            return try importXML(at: xmlURL, progress: progress)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "xml" {
            return try importXML(at: url, progress: progress)
        }
        if ext == "zip" {
            return try importZip(at: url, progress: progress)
        }
        // Unknown extension: try zip first, then raw XML.
        if let z = try? importZip(at: url, progress: progress) { return z }
        return try importXML(at: url, progress: progress)
    }

    /// Stream-parse a raw `export.xml` file.
    public func importXML(at xmlURL: URL, progress: ProgressHandler? = nil) throws -> AppleHealthImportResult {
        // Stream from disk via an InputStream rather than XMLParser(contentsOf:), which would load
        // the entire (multi-hundred-MB) file into memory before parsing.
        guard let stream = InputStream(url: xmlURL) else {
            throw ImportError.fileNotFound(xmlURL.path)
        }
        return try runParser(XMLParser(stream: stream), progress: progress)
    }

    /// Parse a `Data` blob of XML (used for the zip-streaming path and tests).
    public func importXML(data: Data, progress: ProgressHandler? = nil) throws -> AppleHealthImportResult {
        let parser = XMLParser(data: data)
        return try runParser(parser, progress: progress)
    }

    // MARK: - Zip handling

    private func importZip(at zipURL: URL, progress: ProgressHandler? = nil) throws -> AppleHealthImportResult {
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

        return try importXML(at: tmp, progress: progress)
    }

    // MARK: - Core parse

    private func runParser(_ parser: XMLParser, progress: ProgressHandler? = nil) throws -> AppleHealthImportResult {
        let delegate = HealthXMLDelegate(progress: progress)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        let ok = parser.parse()
        if !ok || delegate.parseError != nil {
            let msg = delegate.parseError?.localizedDescription
                ?? parser.parserError?.localizedDescription
                ?? "unknown error"
            throw ImportError.xmlParseFailed(msg)
        }
        return delegate.makeResult()
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

    private let dateParser = HealthDateParser()

    init(progress: AppleHealthImporter.ProgressHandler? = nil) {
        self.progress = progress
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
                if elementsSeen % progressTick == 0 { progress?(elementsSeen) }
                handleRecord(attributeDict)

            case "Workout":
                elementsSeen += 1
                if elementsSeen % progressTick == 0 { progress?(elementsSeen) }
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

        let source = attrs["sourceName"]
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

    func makeResult() -> AppleHealthImportResult {
        let summary = ImportSummary(
            sourceKind: .appleHealth,
            recordCount: recordCount + workouts.count,
            earliest: earliestStart,
            latest: latestStart,
            countsByCategory: countsByType
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
        guard let date = formatter.date(from: raw) else {
            // Fallback: try a few alternative shapes (ISO-8601, no seconds).
            return parseFallback(raw)
        }
        return (date, Self.offsetMinutes(from: raw))
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
