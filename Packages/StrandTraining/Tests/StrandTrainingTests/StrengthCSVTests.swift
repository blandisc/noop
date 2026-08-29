import XCTest
@testable import StrandTraining

// FER-224 — strength-training history export to CSV. The generator is pure/Foundation-only; these
// tests cover the two places a naive implementation breaks: escaping a field that crosses commas +
// quotes + a line break all at once, and resolving the exercise by NAME (not id).
final class StrengthCSVTests: XCTestCase {

    private func row(exerciseName: String = "Sentadilla", notes: String? = nil,
                      routineName: String? = "Empuje A") -> StrengthCSV.Row {
        StrengthCSV.Row(date: Date(timeIntervalSince1970: 1_735_000_000), routineName: routineName,
                        exerciseName: exerciseName, setIndex: 1, setKind: .work, weightKg: 60,
                        reps: 8, timeS: nil, distanceM: nil, rpe: 8.5, restTakenS: 90, notes: notes)
    }

    func testHeaderColumns() {
        XCTAssertEqual(StrengthCSV.header,
            "date,routine,exercise,set_index,set_kind,weight_kg,reps,time_s,distance_m,rpe,rest_taken_s,notes")
    }

    /// A fixture that would pass with a naive `joined(separator: ",")` generator MUST fail first —
    /// this one crosses all three special characters at once inside a single field.
    func testNotesEscapeCrossesCommaQuoteAndNewline() {
        let notes = "Dolor en el hombro, dijo \"no puedo más\"\nparar aquí"
        let line = StrengthCSV.line(for: row(notes: notes))

        // The notes field must be one single quoted CSV field, not split by its internal comma/newline.
        let expectedNotesField = "\"Dolor en el hombro, dijo \"\"no puedo más\"\"\nparar aquí\""
        XCTAssertTrue(line.hasSuffix(expectedNotesField),
                      "expected the escaped notes field at the end of the line, got: \(line)")

        // Round-trip: a naive split on "," would produce more than 12 fields. A correct CSV parser
        // (respecting quotes) must recover exactly 12.
        XCTAssertEqual(parseCSVLine(line).count, 12)
        XCTAssertEqual(parseCSVLine(line).last, notes)
    }

    func testRoutineNameWithCommaIsQuoted() {
        let line = StrengthCSV.line(for: row(routineName: "Piernas, día pesado"))
        XCTAssertEqual(parseCSVLine(line)[1], "Piernas, día pesado")
    }

    /// The exercise column must carry the resolved display NAME, never the catalog/custom id — an id
    /// in the CSV is useless to the user opening it outside the app.
    func testExerciseColumnIsNameNotId() {
        let line = StrengthCSV.line(for: row(exerciseName: "Press de banca"))
        let fields = parseCSVLine(line)
        XCTAssertEqual(fields[2], "Press de banca")
        XCTAssertFalse(fields[2].hasPrefix("ex_"), "exercise column looks like an id, not a name")
    }

    func testNumericFieldsAndEmptyOptionals() {
        let line = StrengthCSV.line(for: row())
        let fields = parseCSVLine(line)
        XCTAssertEqual(fields[3], "1")       // set_index
        XCTAssertEqual(fields[4], "work")    // set_kind
        XCTAssertEqual(fields[5], "60")      // weight_kg (whole number, no ".0")
        XCTAssertEqual(fields[6], "8")       // reps
        XCTAssertEqual(fields[7], "")        // time_s absent
        XCTAssertEqual(fields[8], "")        // distance_m absent
        XCTAssertEqual(fields[9], "8.5")     // rpe
        XCTAssertEqual(fields[10], "90")     // rest_taken_s
        XCTAssertEqual(fields[11], "")       // notes absent
    }

    func testAppendRowsStreamsMultipleLinesWithHeaderSeparately() {
        var out = StrengthCSV.header + "\n"
        StrengthCSV.appendRows([row(exerciseName: "Sentadilla"), row(exerciseName: "Peso muerto")], to: &out)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 3) // header + 2 rows
        XCTAssertTrue(lines[1].contains("Sentadilla"))
        XCTAssertTrue(lines[2].contains("Peso muerto"))
    }

    // Minimal RFC-4180 line parser for assertions — respects quoted fields containing commas/newlines.
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\""); i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == "," { fields.append(field); field = "" }
                else { field.append(c) }
            }
            i += 1
        }
        fields.append(field)
        return fields
    }
}
