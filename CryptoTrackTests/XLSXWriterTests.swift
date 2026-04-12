import XCTest
@testable import CryptoTrack

final class XLSXWriterTests: XCTestCase {
    func testSingleSheetProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Test", headers: ["Name", "Value"], rows: [
            ["Alice", "100"],
            ["Bob", "200"]
        ])
        let data = try writer.finalize()
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testMultipleSheetsProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Sheet1", headers: ["A"], rows: [["1"]])
        writer.addSheet(name: "Sheet2", headers: ["B"], rows: [["2"]])
        let data = try writer.finalize()
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testEmptySheetProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Empty", headers: ["Col1", "Col2"], rows: [])
        let data = try writer.finalize()
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }
}
