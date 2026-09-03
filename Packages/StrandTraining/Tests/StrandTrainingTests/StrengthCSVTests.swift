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
            "date,routine,exercise,set_index,set_kind,weight_kg,reps,time_s,distance_m,rpe,rest_taken_s,notes,set_mode")
    }

    /// A fixture that would pass with a naive `joined(separator: ",")` generator MUST fail first —
    /// this one crosses all three special characters at once inside a single field.
    func testNotesEscapeCrossesCommaQuoteAndNewline() {
        let notes = "Dolor en el hombro, dijo \"no puedo más\"\nparar aquí"
        let line = StrengthCSV.line(for: row(notes: notes))

        // The notes field must be one single quoted CSV field, not split by its internal comma/newline.
        // Since ola 1 (v42) `set_mode` follows it as the 13th column (blank for a standard set).
        let expectedNotesField = "\"Dolor en el hombro, dijo \"\"no puedo más\"\"\nparar aquí\","
        XCTAssertTrue(line.hasSuffix(expectedNotesField),
                      "expected the escaped notes field followed by a blank set_mode, got: \(line)")

        // Round-trip: a naive split on "," would produce more than 13 fields. A correct CSV parser
        // (respecting quotes) must recover exactly 13, with the notes intact in column 12.
        XCTAssertEqual(parseCSVLine(line).count, 13)
        XCTAssertEqual(parseCSVLine(line)[11], notes)
        XCTAssertEqual(parseCSVLine(line).last, "")
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

    /// FER-224 defect fix: `set_index` must reset PER EXERCISE, not follow the raw position across
    /// the whole session. A session logged squat, squat, bench, bench must number the bench sets 1, 2
    /// — never 3, 4 (what a naive `sets.enumerated()` over the flat, position-ordered array would
    /// produce, and did before this fix). This test would FAIL against that old flat-index code.
    func testSetIndexResetsPerExerciseWithInterleavedExercises() {
        func input(_ exerciseId: String, _ exerciseName: String) -> StrengthCSV.SetInput {
            StrengthCSV.SetInput(date: Date(timeIntervalSince1970: 1_735_000_000), routineName: "Empuje A",
                                 exerciseId: exerciseId, exerciseName: exerciseName, setKind: .work,
                                 weightKg: 40, reps: 10, timeS: nil, distanceM: nil, rpe: nil,
                                 restTakenS: nil, notes: nil)
        }
        // Session order (DB `position` order): squat, squat, bench, bench — NOT interleaved as a
        // superset here, just two exercises back to back, which is already enough to break a flat index.
        let sets = [
            input("ex_squat", "Sentadilla"),
            input("ex_squat", "Sentadilla"),
            input("ex_bench", "Press de banca"),
            input("ex_bench", "Press de banca"),
        ]
        let rows = StrengthCSV.rows(forSessionSets: sets)
        XCTAssertEqual(rows.map(\.setIndex), [1, 2, 1, 2])
        XCTAssertEqual(rows.map(\.exerciseName), ["Sentadilla", "Sentadilla", "Press de banca", "Press de banca"])
    }

    /// A superset (A, B, A, B — non-contiguous blocks of the same exercise) keeps ONE running counter
    /// per exercise across the gaps: A1, B1, A2, B2 — the count the user did, not a per-block reset.
    func testSetIndexKeepsRunningAcrossNonContiguousSupersetBlocks() {
        func input(_ exerciseId: String, _ exerciseName: String) -> StrengthCSV.SetInput {
            StrengthCSV.SetInput(date: Date(timeIntervalSince1970: 1_735_000_000), routineName: nil,
                                 exerciseId: exerciseId, exerciseName: exerciseName, setKind: .work,
                                 weightKg: 20, reps: 12, timeS: nil, distanceM: nil, rpe: nil,
                                 restTakenS: nil, notes: nil)
        }
        let sets = [
            input("ex_a", "Ejercicio A"), input("ex_b", "Ejercicio B"),
            input("ex_a", "Ejercicio A"), input("ex_b", "Ejercicio B"),
        ]
        let rows = StrengthCSV.rows(forSessionSets: sets)
        XCTAssertEqual(rows.map(\.setIndex), [1, 1, 2, 2])
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

    /// Ola 1 (v42): `set_mode` is the 13th column. A standard set writes it blank (pre-ola-1 readers see
    /// their 12 columns plus one empty field); a drop writes `drop`, an AMRAP `amrap`.
    func testSetModeIsLastColumnBlankForStandard() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let standard = StrengthCSV.Row(date: date, routineName: nil, exerciseName: "Press", setIndex: 1,
                                       setKind: .work, weightKg: 80, reps: 8, timeS: nil, distanceM: nil,
                                       rpe: nil, restTakenS: nil, notes: nil)
        let drop = StrengthCSV.Row(date: date, routineName: nil, exerciseName: "Press", setIndex: 2,
                                   setKind: .work, weightKg: 64, reps: 9, timeS: nil, distanceM: nil,
                                   rpe: nil, restTakenS: nil, notes: nil, setMode: .drop)
        XCTAssertTrue(StrengthCSV.line(for: standard).hasSuffix(","), "standard = blank last field")
        XCTAssertTrue(StrengthCSV.line(for: drop).hasSuffix(",drop"))
        XCTAssertEqual(StrengthCSV.line(for: drop).split(separator: ",", omittingEmptySubsequences: false).count, 13)
    }
}
