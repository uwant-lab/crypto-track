import Foundation

/// 거래소 종류를 정의합니다.
enum Exchange: String, CaseIterable, Sendable {
    case upbit = "Upbit"
    case binance = "Binance"
    case bithumb = "Bithumb"
    case bybit = "Bybit"
    case coinone = "Coinone"
    case korbit = "Korbit"
    case okx = "OKX"
}

/// 거래소별 API 인증 방식을 정의합니다.
enum AuthMethod: Sendable {
    /// 업비트: JWT 기반 인증
    case jwt
    /// 해외 거래소: HMAC-SHA256 서명
    case hmacSHA256
    /// 빗썸: HMAC-SHA512 서명
    case hmacSHA512
    /// 코빗: OAuth 2.0 Bearer 토큰 인증
    case oauth2
    /// OKX: HMAC-SHA256 + 패스프레이즈 서명
    case hmacSHA256WithPassphrase
}

/// 거래소 API 통신을 위한 프로토콜.
/// 각 거래소별 구현체는 이 프로토콜을 채택하여 공통 모델(`Asset`, `Ticker`)로 변환합니다.
protocol ExchangeService: Sendable {
    /// 거래소 식별자
    var exchange: Exchange { get }

    /// 인증 방식
    var authMethod: AuthMethod { get }

    /// 보유 자산 목록을 조회합니다.
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset]

    /// 특정 마켓의 현재 시세를 조회합니다.
    /// - Parameter symbols: 조회할 심볼 목록 (예: ["BTC", "ETH"])
    /// - Returns: 공통 Ticker 모델 배열
    func fetchTickers(symbols: [String]) async throws -> [Ticker]

    /// API 연결 상태를 확인합니다.
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool
}

extension ExchangeService {
    /// 단일 심볼의 시세를 조회하는 편의 메서드
    func fetchTicker(symbol: String) async throws -> Ticker? {
        let tickers = try await fetchTickers(symbols: [symbol])
        return tickers.first
    }
}
