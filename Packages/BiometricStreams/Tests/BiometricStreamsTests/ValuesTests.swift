import XCTest
@testable import BiometricStreams

final class ValuesTests: XCTestCase {
    func testAccessors() {
        XCTAssertEqual(ParsedValue.int(60).intValue, 60)
        XCTAssertEqual(ParsedValue.double(25.5).doubleValue, 25.5)
        XCTAssertEqual(ParsedValue.string("hi").stringValue, "hi")
        XCTAssertEqual(ParsedValue.intArray([1, 2, 3]).intArrayValue, [1, 2, 3])
        XCTAssertNil(ParsedValue.string("x").intValue)
        XCTAssertNil(ParsedValue.int(1).stringValue)
    }

    func testDecodeBareScalarsFromJSON() throws {
        let dec = JSONDecoder()
        // A JSON object whose values are bare scalars/arrays, like golden.json's parsed.
        let json = """
        {"heart_rate": 60, "battery_pct": 25.5, "log": "hello",
         "rr_intervals": [800, 810], "flag": true, "nothing": null}
        """.data(using: .utf8)!
        let map = try dec.decode([String: ParsedValue].self, from: json)
        XCTAssertEqual(map["heart_rate"], .int(60))
        XCTAssertEqual(map["battery_pct"], .double(25.5))
        XCTAssertEqual(map["log"], .string("hello"))
        XCTAssertEqual(map["rr_intervals"], .intArray([800, 810]))
        XCTAssertEqual(map["flag"], .bool(true))
        XCTAssertEqual(map["nothing"], .null)
    }

    func testEncodeProducesBareScalars() throws {
        let enc = JSONEncoder()
        let data = try enc.encode(ParsedValue.int(7))
        XCTAssertEqual(String(data: data, encoding: .utf8), "7")
        let arr = try enc.encode(ParsedValue.intArray([1, 2]))
        XCTAssertEqual(String(data: arr, encoding: .utf8), "[1,2]")
    }

    func testEmptyArrayDecodesAsIntArray() throws {
        let json = "{\"rr_intervals\": []}".data(using: .utf8)!
        let map = try JSONDecoder().decode([String: ParsedValue].self, from: json)
        XCTAssertEqual(map["rr_intervals"], .intArray([]))
    }
}
