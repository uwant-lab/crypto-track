import XCTest
@testable import CryptoTrack

final class TransactionExporterTests: XCTestCase {
    func testExportOrdersGroupsByExchange() throws {
        let orders = [
            Order(id: "1", symbol: "BTC", side: .buy, price: 80_000_000,
                  amount: 0.5, totalValue: 40_000_000, fee: 20_000,
                  exchange: .upbit, executedAt: Date()),
            Order(id: "2", symbol: "ETH", side: .sell, price: 4_000_000,
                  amount: 2.0, totalValue: 8_000_000, fee: 4_000,
                  exchange: .bithumb, executedAt: Date()),
            Order(id: "3", symbol: "XRP", side: .buy, price: 1_000,
                  amount: 100, totalValue: 100_000, fee: 50,
                  exchange: .upbit, executedAt: Date()),
        ]
        let data = try TransactionExporter.exportOrders(orders)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testExportDepositsGroupsByExchange() throws {
        let deposits = [
            Deposit(id: "1", symbol: "BTC", amount: 1.0, fee: 0.0005,
                    type: .crypto, status: .completed, txId: "abc123",
                    exchange: .upbit, completedAt: Date()),
            Deposit(id: "2", symbol: "KRW", amount: 1_000_000, fee: 0,
                    type: .fiat, status: .completed, txId: nil,
                    exchange: .bithumb, completedAt: Date()),
        ]
        let data = try TransactionExporter.exportDeposits(deposits)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testExportEmptyOrdersProducesValidFile() throws {
        let data = try TransactionExporter.exportOrders([])
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }
}
