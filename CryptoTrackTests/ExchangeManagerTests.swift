import XCTest
@testable import CryptoTrack

@MainActor
final class ExchangeManagerTests: XCTestCase {

    // Each test gets a fresh instance; we do NOT use .shared to avoid side effects
    private var manager: ExchangeManager!

    // Unique UserDefaults key per test to avoid state leakage
    private var testDefaultsKey: String!

    override func setUp() async throws {
        try await super.setUp()
        manager = ExchangeManager()
        // Clear any UserDefaults state that might have been loaded from shared storage
        UserDefaults.standard.removeObject(forKey: "registeredExchanges")
        // Re-create a clean manager after clearing defaults
        manager = ExchangeManager()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "registeredExchanges")
        manager = nil
        try await super.tearDown()
    }

    // MARK: - testInitialState

    func testInitialState() {
        XCTAssertTrue(manager.registeredExchanges.isEmpty, "Fresh instance should have no registered exchanges")
        XCTAssertTrue(manager.services.isEmpty, "Fresh instance should have no active services")
    }

    // MARK: - testRegisterExchange

    func testRegisterExchange() {
        manager.register(exchange: .upbit)

        XCTAssertTrue(manager.registeredExchanges.contains(.upbit))
        XCTAssertEqual(manager.registeredExchanges.count, 1)
    }

    // MARK: - testUnregisterExchange

    func testUnregisterExchange() {
        manager.register(exchange: .binance)
        XCTAssertTrue(manager.isRegistered(.binance))

        manager.unregister(exchange: .binance)
        XCTAssertFalse(manager.isRegistered(.binance))
        XCTAssertTrue(manager.registeredExchanges.isEmpty)
    }

    // MARK: - testDuplicateRegistration

    func testDuplicateRegistration() {
        manager.register(exchange: .upbit)
        manager.register(exchange: .upbit)

        XCTAssertEqual(manager.registeredExchanges.count, 1, "Duplicate registration should result in only one entry")
    }

    // MARK: - testIsRegistered

    func testIsRegistered() {
        XCTAssertFalse(manager.isRegistered(.korbit), "Should be false before registration")

        manager.register(exchange: .korbit)
        XCTAssertTrue(manager.isRegistered(.korbit), "Should be true after registration")

        manager.unregister(exchange: .korbit)
        XCTAssertFalse(manager.isRegistered(.korbit), "Should be false after unregistration")
    }

    // MARK: - testFetchAllAssetsEmpty

    func testFetchAllAssetsEmpty() async throws {
        XCTAssertTrue(manager.registeredExchanges.isEmpty)

        let assets = try await manager.fetchAllAssets()
        XCTAssertTrue(assets.isEmpty, "No registered exchanges should return empty asset array")
    }

    // MARK: - testCreateServiceFactory

    func testCreateServiceFactory() {
        // Register all exchanges and verify a service was created for each
        for exchange in Exchange.allCases {
            manager.register(exchange: exchange)
        }

        for exchange in Exchange.allCases {
            XCTAssertNotNil(manager.services[exchange], "Service should be created for \(exchange.rawValue)")
        }

        XCTAssertEqual(manager.services.count, Exchange.allCases.count,
                       "Should have one service per exchange")
    }

    // MARK: - testRegisterMultipleExchanges

    func testRegisterMultipleExchanges() {
        manager.register(exchange: .upbit)
        manager.register(exchange: .binance)
        manager.register(exchange: .bithumb)

        XCTAssertEqual(manager.registeredExchanges.count, 3)
        XCTAssertTrue(manager.isRegistered(.upbit))
        XCTAssertTrue(manager.isRegistered(.binance))
        XCTAssertTrue(manager.isRegistered(.bithumb))
    }

    // MARK: - testUnregisterOneOfMultiple

    func testUnregisterOneOfMultiple() {
        manager.register(exchange: .upbit)
        manager.register(exchange: .binance)

        manager.unregister(exchange: .upbit)

        XCTAssertFalse(manager.isRegistered(.upbit))
        XCTAssertTrue(manager.isRegistered(.binance))
        XCTAssertEqual(manager.registeredExchanges.count, 1)
    }
}
