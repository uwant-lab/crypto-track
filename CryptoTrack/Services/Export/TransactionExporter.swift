import Foundation

// MARK: - TransactionExporter

/// Converts Order/Deposit arrays into .xlsx Data grouped by exchange.
enum TransactionExporter {

    // MARK: - Public API

    /// Exports orders to .xlsx Data, grouping by exchange into separate sheets.
    static func exportOrders(_ orders: [Order]) throws -> Data {
        let writer = XLSXWriter()
        let headers = ["체결일시", "코인", "구분", "체결가격", "체결수량", "체결금액", "수수료"]

        if orders.isEmpty {
            writer.addSheet(name: "체결 내역", headers: headers, rows: [])
            return try writer.finalize()
        }

        let grouped = Dictionary(grouping: orders, by: { $0.exchange })
        let sortedExchanges = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        for exchange in sortedExchanges {
            let exchangeOrders = grouped[exchange]!.sorted { $0.executedAt > $1.executedAt }
            let rows: [[String]] = exchangeOrders.map { order in
                [
                    dateFormatter.string(from: order.executedAt),
                    order.symbol,
                    order.side == .buy ? "매수" : "매도",
                    formatNumber(order.price),
                    formatNumber(order.amount),
                    formatNumber(order.totalValue),
                    formatNumber(order.fee),
                ]
            }
            writer.addSheet(name: exchange.rawValue, headers: headers, rows: rows)
        }

        return try writer.finalize()
    }

    /// Exports deposits to .xlsx Data, grouping by exchange into separate sheets.
    static func exportDeposits(_ deposits: [Deposit]) throws -> Data {
        let writer = XLSXWriter()
        let headers = ["입금일시", "코인", "유형", "수량", "수수료", "상태", "TxID"]

        if deposits.isEmpty {
            writer.addSheet(name: "입금 내역", headers: headers, rows: [])
            return try writer.finalize()
        }

        let grouped = Dictionary(grouping: deposits, by: { $0.exchange })
        let sortedExchanges = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        for exchange in sortedExchanges {
            let exchangeDeposits = grouped[exchange]!.sorted { $0.completedAt > $1.completedAt }
            let rows: [[String]] = exchangeDeposits.map { deposit in
                [
                    dateFormatter.string(from: deposit.completedAt),
                    deposit.symbol,
                    deposit.type == .crypto ? "암호화폐" : "원화",
                    formatNumber(deposit.amount),
                    formatNumber(deposit.fee),
                    statusLabel(deposit.status),
                    deposit.txId ?? "",
                ]
            }
            writer.addSheet(name: exchange.rawValue, headers: headers, rows: rows)
        }

        return try writer.finalize()
    }

    // MARK: - Private Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// Formats a number: whole numbers < 1 billion use 0 decimal places;
    /// otherwise up to 8 decimal places with trailing zeros stripped.
    static func formatNumber(_ value: Double) -> String {
        let isWholeNumber = value == value.rounded(.towardZero) && value == Double(Int64(value))
        if isWholeNumber && value < 1_000_000_000 {
            return numberFormatterZeroDecimals.string(from: NSNumber(value: value))
                ?? String(format: "%.0f", value)
        }
        let formatted = numberFormatterEightDecimals.string(from: NSNumber(value: value))
            ?? String(format: "%.8f", value)
        return stripTrailingZeros(formatted)
    }

    private static let numberFormatterZeroDecimals: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter
    }()

    private static let numberFormatterEightDecimals: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 1
        formatter.groupingSeparator = ","
        return formatter
    }()

    private static func stripTrailingZeros(_ string: String) -> String {
        guard string.contains(".") else { return string }
        var result = string
        while result.hasSuffix("0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }
        return result
    }

    private static func statusLabel(_ status: DepositStatus) -> String {
        switch status {
        case .completed: return "완료"
        case .pending: return "대기"
        case .cancelled: return "취소"
        }
    }
}
