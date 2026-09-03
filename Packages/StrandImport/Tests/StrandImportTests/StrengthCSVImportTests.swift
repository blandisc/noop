import XCTest
@testable import StrandImport
import StrandTraining

/// FER-328 · E8 — pure Strong / Hevy / Cénit CSV reader. Fixtures under Resources/ are anonymized
/// slices of real public exports (DaKheera47/strong-statistics, gossamr/swift-workout-importer).
final class StrengthCSVImportTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "csv"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Detect

    func testDetectsHevyByColumns() throws {
        let header = try XCTUnwrap(fixture("hevy_kg").split(whereSeparator: \.isNewline).first.map(String.init))
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: header), .hevy)
        let lb = try XCTUnwrap(fixture("hevy_lb").split(whereSeparator: \.isNewline).first.map(String.init))
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: lb), .hevy)
    }

    func testDetectsStrongByColumns() throws {
        let header = try XCTUnwrap(fixture("strong_current").split(whereSeparator: \.isNewline).first.map(String.init))
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: header), .strong)
        let legacy = try XCTUnwrap(fixture("strong_legacy").split(whereSeparator: \.isNewline).first.map(String.init))
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: legacy), .strong)
    }

    func testDetectsCenitByColumns() throws {
        let header = try XCTUnwrap(fixture("cenit_roundtrip").split(whereSeparator: \.isNewline).first.map(String.init))
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: header), .cenit)
    }

    func testRejectsUnknownHeader() {
        XCTAssertNil(StrengthCSVImporter.detectDialect(header: "foo,bar,baz"))
        XCTAssertThrowsError(try StrengthCSVImporter.parse(text: "foo,bar\n1,2\n")) { err in
            XCTAssertEqual(err as? StrengthCSVImporter.ImportError, .unknownHeader)
        }
    }

    // MARK: - Hevy

    func testHevyKgParsesSetsAndRPE() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("hevy_kg"), dialect: .hevy)
        XCTAssertGreaterThanOrEqual(history.sessions.count, 2)
        let piernas = try XCTUnwrap(history.sessions.first { $0.title == "Piernas A" })
        XCTAssertEqual(piernas.source, "hevy")
        XCTAssertEqual(piernas.id, "hevy-\(piernas.startTs)")
        XCTAssertTrue(piernas.hasPerSetRPE)
        XCTAssertEqual(piernas.sets.filter { $0.kind == .warmup }.count, 3)
        let work = piernas.sets.filter { $0.kind == .work && $0.mode == .standard && $0.rpe == 8 }
        XCTAssertFalse(work.isEmpty)
        XCTAssertEqual(piernas.endTs! - piernas.startTs, 85 * 60)  // 07:48 → 09:13
    }

    func testHevyLbConvertsToKg() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("hevy_lb"), dialect: .hevy)
        let session = try XCTUnwrap(history.sessions.first)
        // 135 lb → 61.23 kg (×0.45359237, 2 dp)
        let work = session.sets.first { $0.weightKg != nil && $0.kind == .work && $0.mode == .standard }
        let kg = try XCTUnwrap(work?.weightKg)
        let expected = (135.0 * WorkoutWeightUnit.lbToKg * 100).rounded() / 100
        XCTAssertEqual(kg, expected, accuracy: 0.001)
    }

    func testHevyDateWithSpanishMonth() throws {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        "Piernas","15 septiembre 2025, 07:48","15 septiembre 2025, 08:48","","Squat (Barbell)",,"",0,normal,100,5,,,8
        """
        let history = try StrengthCSVImporter.parse(text: csv, dialect: .hevy)
        let session = try XCTUnwrap(history.sessions.first)
        var comps = DateComponents(); comps.year = 2025; comps.month = 9; comps.day = 15
        comps.hour = 7; comps.minute = 48
        let expected = Int(Calendar.current.date(from: comps)!.timeIntervalSince1970)
        XCTAssertEqual(session.startTs, expected)
    }

    func testFailureSetBecomesRPE10() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("hevy_kg"), dialect: .hevy)
        let failure = try XCTUnwrap(history.sessions.flatMap(\.sets).first { $0.exerciseName.contains("Leg Curl") && $0.setIndex == 4 })
        // set_index 3 in file (0-based) → 4 one-based; failure forces RPE 10 even when CSV RPE empty
        XCTAssertEqual(failure.kind, .work)
        XCTAssertEqual(failure.rpe, 10)
    }

    func testDropsetBecomesModeDrop() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("hevy_kg"), dialect: .hevy)
        let drops = history.sessions.flatMap(\.sets).filter { $0.mode == .drop }
        XCTAssertFalse(drops.isEmpty)
        XCTAssertTrue(drops.allSatisfy { $0.kind == .work })
    }

    func testUnknownSetTypeIsSkippedWithCount() throws {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        "X","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",0,normal,100,5,,,8
        "X","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",1,mystery,100,5,,,8
        """
        let history = try StrengthCSVImporter.parse(text: csv, dialect: .hevy)
        XCTAssertEqual(history.sessions.first?.sets.count, 1)
        XCTAssertEqual(history.skipped.filter { $0.reason.contains("unknown set_type") }.count, 1)
    }

    func testRPEBelow6IsNil() throws {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        "X","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",0,normal,100,5,,,5
        "X","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",1,normal,100,5,,,10.5
        "X","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",2,normal,100,5,,,8
        """
        let history = try StrengthCSVImporter.parse(text: csv, dialect: .hevy)
        let rpes = history.sessions.first!.sets.map(\.rpe)
        XCTAssertEqual(rpes, [nil, nil, 8])
    }

    func testMalformedRowIsSkippedNotFatal() throws {
        let csv = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        "X","not a date","1 Jan 2025, 10:00","","Squat (Barbell)",,"",0,normal,100,5,,,8
        "Y","1 Jan 2025, 09:00","1 Jan 2025, 10:00","","Squat (Barbell)",,"",0,normal,100,5,,,8
        """
        let history = try StrengthCSVImporter.parse(text: csv, dialect: .hevy)
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.sessions.first?.title, "Y")
        XCTAssertFalse(history.skipped.isEmpty)
    }

    // MARK: - Strong

    func testStrongParsesDurationToEndTs() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("strong_current"), dialect: .strong)
        let empuje = try XCTUnwrap(history.sessions.first { $0.title == "Empuje A" })
        XCTAssertEqual(empuje.endTs! - empuje.startTs, 35 * 60)
        let piernas = try XCTUnwrap(history.sessions.first { $0.title == "Piernas" })
        XCTAssertEqual(piernas.endTs! - piernas.startTs, 65 * 60)  // 1h 5m
    }

    func testStrongWarmupW() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("strong_current"), dialect: .strong)
        let warmups = history.sessions.flatMap(\.sets).filter { $0.kind == .warmup }
        XCTAssertFalse(warmups.isEmpty)
        XCTAssertTrue(warmups.allSatisfy { $0.exerciseName.contains("Bench") || $0.exerciseName.contains("Squat") })
    }

    func testStrongWithoutUnitRequiresUnit() throws {
        XCTAssertThrowsError(
            try StrengthCSVImporter.parse(text: fixture("strong_legacy"), dialect: .strong, weightUnit: nil)
        ) { err in
            XCTAssertEqual(err as? StrengthCSVImporter.ImportError, .unitRequired)
        }
        let ok = try StrengthCSVImporter.parse(text: fixture("strong_legacy"), dialect: .strong, weightUnit: .kg)
        XCTAssertFalse(ok.sessions.isEmpty)
    }

    func testSessionKeyIsSourcePlusStart() throws {
        let hevy = try StrengthCSVImporter.parse(text: fixture("hevy_kg"), dialect: .hevy)
        for s in hevy.sessions {
            XCTAssertEqual(s.id, "hevy-\(s.startTs)")
        }
        let strong = try StrengthCSVImporter.parse(text: fixture("strong_current"), dialect: .strong)
        for s in strong.sessions {
            XCTAssertEqual(s.id, "strong-\(s.startTs)")
        }
    }

    // MARK: - Cénit round-trip

    /// RFC 4180 / Excel / Windows line endings read exactly like LF — never a silent empty import.
    func testCRLFParsesLikeLF() throws {
        let lf = try fixture("hevy_kg")
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(StrengthCSVImporter.detectDialect(header: String(crlf.split(separator: "\r\n").first ?? "")), .hevy)
        let a = try StrengthCSVImporter.parse(text: lf, dialect: .hevy)
        let b = try StrengthCSVImporter.parse(text: crlf, dialect: .hevy)
        XCTAssertFalse(b.sessions.isEmpty, "a CRLF file must not vanish into zero sessions")
        XCTAssertEqual(a.sessions, b.sessions)
        XCTAssertEqual(a.skipped.count, b.skipped.count)
    }

    func testCenitRoundTripLossless() throws {
        let history = try StrengthCSVImporter.parse(text: fixture("cenit_roundtrip"), dialect: .cenit)
        let session = try XCTUnwrap(history.sessions.first)
        XCTAssertEqual(session.source, "cenit")
        XCTAssertEqual(session.sets.count, 6)
        XCTAssertEqual(session.sets.map(\.kind), [.warmup, .work, .work, .work, .work, .work])
        XCTAssertEqual(session.sets.map(\.mode), [.standard, .standard, .standard, .drop, .standard, .amrap])
        XCTAssertEqual(session.sets.map(\.rpe), [nil, 8, 9, 9, 7.5, 8])
        XCTAssertEqual(session.sets.map(\.restTakenS), [90, 120, 180, nil, 90, 0])
        XCTAssertEqual(session.sets.last?.notes, "nota de serie")

        // Re-emit via StrengthCSV and parse again — set_mode / rpe / rest_taken_s survive.
        let date = Date(timeIntervalSince1970: TimeInterval(session.startTs))
        let rows: [StrengthCSV.Row] = session.sets.map { s in
            StrengthCSV.Row(date: date, routineName: session.title, exerciseName: s.exerciseName,
                            setIndex: s.setIndex, setKind: s.kind, weightKg: s.weightKg, reps: s.reps,
                            timeS: s.timeS, distanceM: s.distanceM, rpe: s.rpe, restTakenS: s.restTakenS,
                            notes: s.notes, setMode: s.mode)
        }
        var out = StrengthCSV.header + "\n"
        StrengthCSV.appendRows(rows, to: &out)
        let again = try StrengthCSVImporter.parse(text: out, dialect: .cenit)
        let back = try XCTUnwrap(again.sessions.first)
        XCTAssertEqual(back.sets.map(\.mode), session.sets.map(\.mode))
        XCTAssertEqual(back.sets.map(\.rpe), session.sets.map(\.rpe))
        XCTAssertEqual(back.sets.map(\.restTakenS), session.sets.map(\.restTakenS))
        XCTAssertEqual(back.sets.map(\.kind), session.sets.map(\.kind))
    }

    // MARK: - Materialize prefill rule (director note)

    func testMaterializePrefillsOnlyWhenCSVHasRPE() throws {
        let withRPE = try StrengthCSVImporter.parse(text: fixture("hevy_kg"), dialect: .hevy)
        let session = try XCTUnwrap(withRPE.sessions.first { $0.hasPerSetRPE })
        let (strength, sets) = try XCTUnwrap(
            StrengthCSVImporter.materialize(session) { _ in "ex1" })
        XCTAssertNotNil(strength.sessionRpe)
        XCTAssertEqual(strength.sessionRpeSource, .prefill)
        XCTAssertNil(strength.strain)
        XCTAssertNil(strength.strainSource)
        XCTAssertTrue(sets.allSatisfy(\.done))

        // Strip RPE → prefill must stay nil (nothing invented).
        var noRPE = session
        noRPE.sets = session.sets.map {
            var s = $0; s.rpe = nil; return s
        }
        noRPE.hasPerSetRPE = false
        let (bare, _) = try XCTUnwrap(StrengthCSVImporter.materialize(noRPE) { _ in "ex1" })
        XCTAssertNil(bare.sessionRpe)
        XCTAssertNil(bare.sessionRpeSource)
    }

    func testAnnotateDuplicatesCrossOriginWithin30Min() {
        let imported = StrengthCSVImporter.ImportedSession(
            id: "hevy-1000", source: "hevy", startTs: 1000, endTs: 2000,
            title: "A", notes: nil, sets: [
                .init(exerciseName: "Squat", setIndex: 1, kind: .work, weightKg: 100, reps: 5)
            ], hasPerSetRPE: false)
        let history = StrengthCSVImporter.ImportedStrengthHistory(sessions: [imported])
        let annotated = StrengthCSVImporter.annotateDuplicates(history, existing: [
            (id: "strong-1100", source: "strong", title: "B", startTs: 1100),  // +100 s
        ])
        XCTAssertEqual(annotated.possibleDuplicates.count, 1)
        XCTAssertEqual(annotated.possibleDuplicates.first?.existingId, "strong-1100")

        let far = StrengthCSVImporter.annotateDuplicates(history, existing: [
            (id: "strong-100000", source: "strong", title: "B", startTs: 100_000),
        ])
        XCTAssertTrue(far.possibleDuplicates.isEmpty)
    }
}
