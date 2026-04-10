import Foundation
import Observation

/// 대시보드 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class DashboardViewModel {
    // MARK: - State

    var assets: [Asset] = []
    var tickers: [Ticker] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: - Computed Properties

    /// 각 자산의 현재 평가액 합계
    var totalValue: Double {
        assets.reduce(0) { sum, asset in
            sum + currentValue(for: asset)
        }
    }

    /// 총 매수 금액
    var totalCost: Double {
        assets.reduce(0) { $0 + $1.totalCost }
    }

    /// 총 평가 손익
    var totalProfit: Double {
        totalValue - totalCost
    }

    /// 총 수익률 (%)
    var totalProfitRate: Double {
        guard totalCost > 0 else { return 0 }
        return (totalProfit / totalCost) * 100
    }

    // MARK: - Per-Asset Calculations

    /// 특정 자산의 현재 시세를 반환합니다.
    func ticker(for asset: Asset) -> Ticker? {
        tickers.first { $0.symbol == asset.symbol && $0.exchange == asset.exchange }
            ?? tickers.first { $0.symbol == asset.symbol }
    }

    /// 특정 자산의 현재 평가액을 반환합니다.
    func currentValue(for asset: Asset) -> Double {
        guard let ticker = ticker(for: asset) else { return asset.totalCost }
        return asset.balance * ticker.currentPrice
    }

    /// 특정 자산의 평가 손익을 반환합니다.
    func profit(for asset: Asset) -> Double {
        currentValue(for: asset) - asset.totalCost
    }

    /// 특정 자산의 수익률(%)을 반환합니다.
    func profitRate(for asset: Asset) -> Double {
        guard asset.totalCost > 0 else { return 0 }
        return (profit(for: asset) / asset.totalCost) * 100
    }

    // MARK: - Dependencies

    private let exchangeManager: ExchangeManager

    init(exchangeManager: ExchangeManager = .shared) {
        self.exchangeManager = exchangeManager
    }

    // MARK: - Data Loading

    /// 등록된 거래소에서 자산 및 시세 데이터를 새로고침합니다.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetchedAssets = try await exchangeManager.fetchAllAssets()
            let symbols = Array(Set(fetchedAssets.map { $0.symbol }))
            let fetchedTickers = try await exchangeManager.fetchAllTickers(symbols: symbols)

            assets = fetchedAssets
            tickers = fetchedTickers

            if assets.isEmpty && !exchangeManager.registeredExchanges.isEmpty {
                errorMessage = "자산 데이터를 불러오지 못했습니다."
            } else if exchangeManager.registeredExchanges.isEmpty {
                errorMessage = "설정에서 거래소를 등록해주세요."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sample Data

    static let sampleAssets: [Asset] = [
        Asset(
            id: "upbit-BTC",
            symbol: "BTC",
            balance: 0.5,
            averageBuyPrice: 55_000_000,
            exchange: .upbit,
            lastUpdated: Date()
        ),
        Asset(
            id: "upbit-ETH",
            symbol: "ETH",
            balance: 3.2,
            averageBuyPrice: 2_800_000,
            exchange: .upbit,
            lastUpdated: Date()
        ),
        Asset(
            id: "binance-BTC",
            symbol: "BTC",
            balance: 0.25,
            averageBuyPrice: 42_000,
            exchange: .binance,
            lastUpdated: Date()
        ),
        Asset(
            id: "binance-ETH",
            symbol: "ETH",
            balance: 1.8,
            averageBuyPrice: 2_200,
            exchange: .binance,
            lastUpdated: Date()
        ),
    ]

    static let sampleTickers: [Ticker] = [
        Ticker(
            id: "upbit-BTC-ticker",
            symbol: "BTC",
            currentPrice: 62_000_000,
            changeRate24h: 2.35,
            volume24h: 1_500_000_000,
            exchange: .upbit,
            timestamp: Date()
        ),
        Ticker(
            id: "upbit-ETH-ticker",
            symbol: "ETH",
            currentPrice: 3_100_000,
            changeRate24h: -1.12,
            volume24h: 800_000_000,
            exchange: .upbit,
            timestamp: Date()
        ),
        Ticker(
            id: "binance-BTC-ticker",
            symbol: "BTC",
            currentPrice: 47_500,
            changeRate24h: 2.41,
            volume24h: 25_000,
            exchange: .binance,
            timestamp: Date()
        ),
        Ticker(
            id: "binance-ETH-ticker",
            symbol: "ETH",
            currentPrice: 2_380,
            changeRate24h: -0.98,
            volume24h: 18_000,
            exchange: .binance,
            timestamp: Date()
        ),
    ]

    /// 프리뷰용 샘플 ViewModel
    static var preview: DashboardViewModel {
        let vm = DashboardViewModel(exchangeManager: ExchangeManager())
        vm.assets = sampleAssets
        vm.tickers = sampleTickers
        return vm
    }
}
