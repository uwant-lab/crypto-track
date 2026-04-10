import XCTest
@testable import CryptoTrack

final class KeychainServiceTests: XCTestCase {

    private let keychain = KeychainService.shared

    // Use a unique account prefix per test run to avoid conflicts
    private var testAccount: String {
        "com.cryptotrack.tests.\(UUID().uuidString)"
    }

    // MARK: - testSaveAndRead

    func testSaveAndRead() throws {
        let account = testAccount
        let key = "apiKey"
        let value = "test-secret-\(UUID().uuidString)"

        try keychain.save(key: key, value: value, account: account)
        let result = try keychain.read(key: key, account: account)

        XCTAssertEqual(result, value)

        // Cleanup
        try? keychain.delete(key: key, account: account)
    }

    // MARK: - testSaveOverwrite

    func testSaveOverwrite() throws {
        let account = testAccount
        let key = "apiKey"
        let firstValue = "first-value-\(UUID().uuidString)"
        let secondValue = "second-value-\(UUID().uuidString)"

        try keychain.save(key: key, value: firstValue, account: account)
        try keychain.save(key: key, value: secondValue, account: account)

        let result = try keychain.read(key: key, account: account)
        XCTAssertEqual(result, secondValue)

        // Cleanup
        try? keychain.delete(key: key, account: account)
    }

    // MARK: - testReadNonexistent

    func testReadNonexistent() {
        let account = testAccount
        let key = "nonexistent-\(UUID().uuidString)"

        XCTAssertThrowsError(try keychain.read(key: key, account: account)) { error in
            guard let keychainError = error as? KeychainError else {
                XCTFail("Expected KeychainError, got \(type(of: error))")
                return
            }
            if case .itemNotFound = keychainError {
                // Expected
            } else {
                XCTFail("Expected .itemNotFound, got \(keychainError)")
            }
        }
    }

    // MARK: - testDelete

    func testDelete() throws {
        let account = testAccount
        let key = "apiKey"
        let value = "delete-test-\(UUID().uuidString)"

        try keychain.save(key: key, value: value, account: account)
        try keychain.delete(key: key, account: account)

        XCTAssertThrowsError(try keychain.read(key: key, account: account)) { error in
            guard let keychainError = error as? KeychainError else {
                XCTFail("Expected KeychainError, got \(type(of: error))")
                return
            }
            if case .itemNotFound = keychainError {
                // Expected
            } else {
                XCTFail("Expected .itemNotFound, got \(keychainError)")
            }
        }
    }

    // MARK: - testDeleteNonexistent

    func testDeleteNonexistent() {
        let account = testAccount
        let key = "nonexistent-\(UUID().uuidString)"

        // Should not throw for a non-existent item
        XCTAssertNoThrow(try keychain.delete(key: key, account: account))
    }

    // MARK: - testInvalidData (edge cases)

    func testSaveEmptyValue() throws {
        let account = testAccount
        let key = "emptyKey"
        let value = ""

        try keychain.save(key: key, value: value, account: account)
        let result = try keychain.read(key: key, account: account)
        XCTAssertEqual(result, value)

        // Cleanup
        try? keychain.delete(key: key, account: account)
    }

    func testSaveSpecialCharacters() throws {
        let account = testAccount
        let key = "specialKey"
        let value = "특수문자!@#$%^&*()_+-=[]{}|;':\",./<>?"

        try keychain.save(key: key, value: value, account: account)
        let result = try keychain.read(key: key, account: account)
        XCTAssertEqual(result, value)

        // Cleanup
        try? keychain.delete(key: key, account: account)
    }

    func testSaveLongValue() throws {
        let account = testAccount
        let key = "longKey"
        let value = String(repeating: "a", count: 4096)

        try keychain.save(key: key, value: value, account: account)
        let result = try keychain.read(key: key, account: account)
        XCTAssertEqual(result, value)

        // Cleanup
        try? keychain.delete(key: key, account: account)
    }
}
