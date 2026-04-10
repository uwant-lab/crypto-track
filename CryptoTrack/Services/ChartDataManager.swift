import Foundation
import Observation

/// 차트 데이터를 관리하고 캐싱하는 매니저.
/// 거래소별 캔들스틱 데이터를 조회하고 메모리 캐시에 저장합니다.
@Observable
@MainActor
final class ChartDataManager {

    // MARK: - Singleton

    static let shared = ChartDataManager()

    // MARK: - Private Properties

    /// 메모리 캐시: 키 = "{exchange}-{symbol}-{timeframe}"
    private var cache: [String: [Kline]] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Public Methods

    /// 캔들스틱 데이터를 조회합니다. 캐시가 있으면 캐시를 반환합니다.
    /// - Parameters:
    ///   - symbol: 심볼 (예: "BTC")
    ///   - exchange: 거래소
    ///   - timeframe: 봉 간격
    ///   - limit: 최대 조회 개수
    /// - Returns: 시간순 정렬된 Kline 배열
    func fetchKlines(
        symbol: String,
        exchange: Exchange,
        timeframe: ChartTimeframe,
        limit: Int
    ) async throws -> [Kline] {
        let cacheKey = "\(exchange.rawValue)-\(symbol)-\(timeframe.rawValue)"
        if let cached = cache[cacheKey] {
            return cached
        }

        let service = resolveService(for: exchange)
        let klines = try await service.fetchKlines(symbol: symbol, timeframe: timeframe, limit: limit)
        cache[cacheKey] = klines
        return klines
    }

    /// 전체 캐시를 초기화합니다.
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Helpers

    /// 거래소에 해당하는 서비스 인스턴스를 반환합니다.
    /// 등록된 거래소는 ExchangeManager에서, 미등록 거래소는 임시 인스턴스를 생성합니다.
    private func resolveService(for exchange: Exchange) -> any ExchangeService {
        if let service = ExchangeManager.shared.services[exchange] {
            return service
        }
        // 공개 API 전용 임시 인스턴스 생성
        switch exchange {
        case .upbit:
            return UpbitService()
        case .binance:
            return BinanceService()
        case .bithumb:
            return BithumbService()
        case .bybit:
            return BybitService()
        case .coinone:
            return CoinoneService()
        case .korbit:
            return KorbitService()
        case .okx:
            return OKXService()
        }
    }
}
