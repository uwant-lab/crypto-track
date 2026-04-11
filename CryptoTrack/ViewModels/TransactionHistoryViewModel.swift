import Foundation
import Observation

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

    private var currentTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var groupedOrders: [(Date, [Order])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: orders) { order in
            calendar.startOfDay(for: order.executedAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

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

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count
                guard totalExchanges > 0 else {
                    isLoading = false
                    return
                }

                for (index, service) in services.enumerated() {
                    var page = 0
                    while !Task.isCancelled {
                        let result = try await service.fetchOrders(from: dateFrom, to: dateTo, page: page)
                        orders.append(contentsOf: result.items)
                        loadedCount = orders.count
                        progress = (Double(index) + (result.progress ?? (result.hasMore ? 0.5 : 1.0))) / Double(totalExchanges)
                        if !result.hasMore { break }
                        page += 1
                    }
                }
                progress = 1.0
            } catch is CancellationError {
                // cancelled
            } catch {
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

        currentTask = Task {
            do {
                let services = targetServices()
                let totalExchanges = services.count
                guard totalExchanges > 0 else {
                    isLoading = false
                    return
                }

                for (index, service) in services.enumerated() {
                    var page = 0
                    while !Task.isCancelled {
                        let result = try await service.fetchDeposits(from: dateFrom, to: dateTo, page: page)
                        deposits.append(contentsOf: result.items)
                        loadedCount = deposits.count
                        progress = (Double(index) + (result.progress ?? (result.hasMore ? 0.5 : 1.0))) / Double(totalExchanges)
                        if !result.hasMore { break }
                        page += 1
                    }
                }
                progress = 1.0
            } catch is CancellationError {
                // cancelled
            } catch {
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
}
