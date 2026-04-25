import XCTest
@testable import CryptoTrack

final class PINServiceTests: XCTestCase {

    private let pinService = PINService.shared

    override func setUp() {
        super.setUp()
        try? pinService.deletePIN()
    }

    override func tearDown() {
        try? pinService.deletePIN()
        super.tearDown()
    }

    func testInitiallyNoPINSet() {
        XCTAssertFalse(pinService.isPINSet)
    }

    func testSetAndVerifyPIN() throws {
        try pinService.setPIN("1234")
        XCTAssertTrue(pinService.isPINSet)
        XCTAssertTrue(pinService.verifyPIN("1234"))
    }

    func testWrongPINFails() throws {
        try pinService.setPIN("1234")
        XCTAssertFalse(pinService.verifyPIN("5678"))
        XCTAssertFalse(pinService.verifyPIN("0000"))
    }

    func testDeletePIN() throws {
        try pinService.setPIN("1234")
        XCTAssertTrue(pinService.isPINSet)
        try pinService.deletePIN()
        XCTAssertFalse(pinService.isPINSet)
    }

    func testChangePIN() throws {
        try pinService.setPIN("1234")
        try pinService.setPIN("5678")
        XCTAssertFalse(pinService.verifyPIN("1234"))
        XCTAssertTrue(pinService.verifyPIN("5678"))
    }

    func testVerifyWithNoPINReturnsFalse() {
        XCTAssertFalse(pinService.verifyPIN("1234"))
    }
}
