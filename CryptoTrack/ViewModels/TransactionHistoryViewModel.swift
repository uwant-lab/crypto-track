import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.cryptotrack", category: "TransactionHistory")

enum TransactionTab: String, CaseIterable {
    case orders = "체결 내역"
    case deposits = "입금 내역"
}

/// 거래 내역 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class TransactionHistoryViewModel {

    // MARK: - State

    var selectedTab: TransactionTab = .orders
    var selectedExchange: Exchange? = nil
    var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var dateTo: Date = Date()
    var orders: [Order] = []
    var deposits: [Deposit] = []
    var isLoading = false
    var progress: Double = 0.0
    var loadedCount = 0
    var errorMessage: String?
    var progressMessage: String = ""
    var showBuy: Bool = true
    var showSell: Bool = true
    var isSummaryExpanded: Bool = false

    private var currentTask: Task<Void, Never>?

    /// API 호출 간 딜레이 (나노초). 속도 제한(429) 방지용.
    private let requestDelayNs: UInt64 = 200_000_000 // 200ms
    /// 429 에러 시 최대 재시도 횟수
    private let maxRetries = 3

    // MARK: - Computed Properties

    var filteredOrders: [Order] {
        orders.filter { order in
            switch order.side {
            case .buy: return showBuy
            case .sell: return showSell
            }
        }
    }

    var groupedOrders: [(Date, [Order])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredOrders) { order in
            calendar.startOfDay(for: order.executedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var orderSummary: [OrderSymbolSummary] {
        let target = filteredOrders
        let grouped = Dictionary(grouping: target) { $0.symbol }
        return grouped.map { symbol, orders in
            let buys = orders.filter { $0.side == .buy }
            let sells = orders.filter { $0.side == .sell }
            return OrderSymbolSummary(
                symbol: symbol,
                buyAmount: buys.reduce(0) { $0 + $1.amount },
                buyTotal: buys.reduce(0) { $0 + $1.totalValue },
                sellAmount: sells.reduce(0) { $0 + $1.amount },
                sellTotal: sells.reduce(0) { $0 + $1.totalValue },
                fee: orders.reduce(0) { $0 + $1.fee }
            )
        }.sorted { $0.buyTotal + $0.sellTotal > $1.buyTotal + $1.sellTotal }
    }

    var totalBuyValue: Double { orderSummary.reduce(0) { $0 + $1.buyTotal } }
    var totalSellValue: Double { orderSummary.reduce(0) { $0 + $1.sellTotal } }
    var totalFee: Double { orderSummary.reduce(0) { $0 + $1.fee } }

    var groupedDeposits: [(Date, [Deposit])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: deposits) { deposit in
            calendar.startOfDay(for: deposit.completedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Actions

    func fetchOrders() {
        cancel()
        orders = []
        loadedCount = 0
        progress = 0.0
        isLoading = true
        errorMessage = nil
        progressMessage = ""

        logger.info("📋 체결내역 조회 시작: \(self.formatDate(self.dateFrom)) ~ \(self.formatDate(self.dateTo))")

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count
                logger.info("  대상 거래소: \(totalExchanges)개")
                guard totalExchanges > 0 else {
                    logger.warning("  등록된 거래소 없음 — 조회 중단")
                    isLoading = false
                    return
                }

                for (index, service) in services.enumerated() {
                    let chunks = generateDateChunks(
                        from: dateFrom, to: dateTo,
                        maxDays: service.maxQueryRangeDays
                    )
                    let totalChunks = chunks.count
                    logger.info("  [\(service.exchange.rawValue)] 청크 \(totalChunks)개 (maxDays: \(service.maxQueryRangeDays ?? -1))")

                    for (chunkIndex, chunk) in chunks.enumerated() {
                        guard !Task.isCancelled else { break }

                        if totalChunks > 1 {
                            progressMessage = "\(formatChunkRange(chunk)) 조회중..."
                        }
                        logger.info("  [\(service.exchange.rawValue)] 청크 \(chunkIndex + 1)/\(totalChunks): \(self.formatDate(chunk.from)) ~ \(self.formatDate(chunk.to))")

                        var page = 0
                        while !Task.isCancelled {
                            let currentPage = page
                            let result: PagedResult<Order> = try await requestWithRetry {
                                try await service.fetchOrders(
                                    from: chunk.from, to: chunk.to, page: currentPage
                                )
                            }
                            orders.append(contentsOf: result.items)
                            loadedCount = orders.count

                            logger.info("    page \(page): \(result.items.count)건 (hasMore: \(result.hasMore), 총 \(self.loadedCount)건)")

                            let pageProgress = result.progress
                                ?? (result.hasMore ? 0.5 : 1.0)
                            let chunkProgress = (Double(chunkIndex) + pageProgress)
                                / Double(totalChunks)
                            progress = (Double(index) + chunkProgress)
                                / Double(totalExchanges)

                            if !result.hasMore { break }
                            page += 1
                            try await Task.sleep(nanoseconds: requestDelayNs)
                        }
                    }
                }
                progressMessage = ""
                progress = 1.0
                logger.info("📋 체결내역 조회 완료: 총 \(self.orders.count)건")
            } catch is CancellationError {
                logger.info("📋 체결내역 조회 취소됨")
            } catch {
                logger.error("📋 체결내역 조회 실패: \(error)")
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func fetchDeposits() {
        cancel()
        deposits = []
        loadedCount = 0
        progress = 0.0
        isLoading = true
        errorMessage = nil
        progressMessage = ""

        logger.info("💰 입금내역 조회 시작: \(self.formatDate(self.dateFrom)) ~ \(self.formatDate(self.dateTo))")

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count
                logger.info("  대상 거래소: \(totalExchanges)개")
                guard totalExchanges > 0 else {
                    logger.warning("  등록된 거래소 없음 — 조회 중단")
                    isLoading = false
                    return
                }

                for (index, service) in services.enumerated() {
                    let chunks = generateDateChunks(
                        from: dateFrom, to: dateTo,
                        maxDays: service.maxQueryRangeDays
                    )
                    let totalChunks = chunks.count
                    logger.info("  [\(service.exchange.rawValue)] 청크 \(totalChunks)개 (maxDays: \(service.maxQueryRangeDays ?? -1))")

                    for (chunkIndex, chunk) in chunks.enumerated() {
                        guard !Task.isCancelled else { break }

                        if totalChunks > 1 {
                            progressMessage = "\(formatChunkRange(chunk)) 조회중..."
                        }
                        logger.info("  [\(service.exchange.rawValue)] 청크 \(chunkIndex + 1)/\(totalChunks): \(self.formatDate(chunk.from)) ~ \(self.formatDate(chunk.to))")

                        var page = 0
                        while !Task.isCancelled {
                            let currentPage = page
                            let result: PagedResult<Deposit> = try await requestWithRetry {
                                try await service.fetchDeposits(
                                    from: chunk.from, to: chunk.to, page: currentPage
                                )
                            }
                            deposits.append(contentsOf: result.items)
                            loadedCount = deposits.count

                            logger.info("    page \(page): \(result.items.count)건 (hasMore: \(result.hasMore), 총 \(self.loadedCount)건)")

                            let pageProgress = result.progress
                                ?? (result.hasMore ? 0.5 : 1.0)
                            let chunkProgress = (Double(chunkIndex) + pageProgress)
                                / Double(totalChunks)
                            progress = (Double(index) + chunkProgress)
                                / Double(totalExchanges)

                            if !result.hasMore { break }
                            page += 1
                            try await Task.sleep(nanoseconds: requestDelayNs)
                        }
                    }
                }
                progressMessage = ""
                progress = 1.0
                logger.info("💰 입금내역 조회 완료: 총 \(self.deposits.count)건")
            } catch is CancellationError {
                logger.info("💰 입금내역 조회 취소됨")
            } catch {
                logger.error("💰 입금내역 조회 실패: \(error)")
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Private

    /// 현재 필터에 해당하는 서비스 목록. `ExchangeManager.shared.services`에서
    /// 꺼내 쓴다 — 매번 `UpbitService()` 같은 fresh 인스턴스를 만들면 앱
    /// 시작 시 preload해 둔 Keychain 캐시를 재사용하지 못해 조회마다 로그인
    /// 프롬프트가 반복 뜬다.
    private func targetServices() -> [any ExchangeService] {
        let manager = ExchangeManager.shared
        let candidates: [Exchange]
        if let selected = selectedExchange {
            candidates = manager.registeredExchanges.contains(selected) ? [selected] : []
        } else {
            candidates = manager.registeredExchanges
        }
        return candidates.compactMap { manager.services[$0] }
    }

    /// 429(Too Many Requests) 에러 시 지수 백오프로 재시도합니다.
    /// 1초 → 2초 → 4초 대기 후 재시도, 최대 3회.
    private func requestWithRetry<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                let isRateLimited = isHTTP429(error)
                if isRateLimited && attempt < maxRetries {
                    let delaySec = pow(2.0, Double(attempt)) // 1, 2, 4초
                    logger.warning("  ⏳ 429 속도 제한 — \(delaySec)초 후 재시도 (\(attempt + 1)/\(self.maxRetries))")
                    progressMessage = "속도 제한 — \(Int(delaySec))초 대기중..."
                    try await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
                    continue
                }
                throw error
            }
        }
        fatalError("unreachable")
    }

    /// 에러가 HTTP 429인지 판별합니다.
    private func isHTTP429(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("httpError(429)")
    }

    /// 날짜 범위를 `maxDays` 단위로 분할합니다 (최신 → 과거 순).
    /// `maxDays`가 nil이면 전체 범위를 하나의 청크로 반환합니다.
    private func generateDateChunks(
        from startDate: Date, to endDate: Date, maxDays: Int?
    ) -> [(from: Date, to: Date)] {
        guard let maxDays else {
            return [(from: startDate, to: endDate)]
        }

        let calendar = Calendar.current
        var chunks: [(from: Date, to: Date)] = []
        var chunkTo = endDate

        while chunkTo >= startDate {
            guard let rawStart = calendar.date(
                byAdding: .day, value: -(maxDays - 1), to: chunkTo
            ) else { break }

            let chunkFrom = max(startDate, rawStart)
            chunks.append((from: chunkFrom, to: chunkTo))

            guard let prevDay = calendar.date(
                byAdding: .day, value: -1, to: chunkFrom
            ) else { break }
            chunkTo = prevDay
        }

        return chunks
    }

    private func formatChunkRange(_ chunk: (from: Date, to: Date)) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return "\(formatter.string(from: chunk.from)) ~ \(formatter.string(from: chunk.to))"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    /// 매수/매도 토글. 최소 하나는 항상 선택된 상태를 유지합니다.
    func toggleSide(_ side: OrderSide) {
        switch side {
        case .buy:
            if showBuy && !showSell { return }
            showBuy.toggle()
        case .sell:
            if showSell && !showBuy { return }
            showSell.toggle()
        }
    }

    // MARK: - Export

    /// 현재 조회된 데이터를 .xlsx 파일로 내보냅니다.
    /// - Returns: 임시 디렉토리에 저장된 파일 URL, 실패 시 nil
    func exportToExcel() -> URL? {
        do {
            let data: Data
            let prefix: String
            switch selectedTab {
            case .orders:
                data = try TransactionExporter.exportOrders(filteredOrders)
                prefix = "CryptoTrack_체결내역"
            case .deposits:
                data = try TransactionExporter.exportDeposits(deposits)
                prefix = "CryptoTrack_입금내역"
            }

            let dateStr = Self.fileDateFormatter.string(from: Date())
            let filename = "\(prefix)_\(dateStr).xlsx"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            return url
        } catch {
            logger.error("엑셀 내보내기 실패: \(error)")
            errorMessage = "내보내기에 실패했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Summary Model

struct OrderSymbolSummary: Identifiable {
    var id: String { symbol }
    let symbol: String
    let buyAmount: Double
    let buyTotal: Double
    let sellAmount: Double
    let sellTotal: Double
    let fee: Double
}
