import Foundation

// MARK: - Bithumb Service

/// 빗썸 거래소 API와 통신하는 서비스 구현체.
/// `ExchangeService` 프로토콜을 채택하며, HMAC-SHA512 인증을 사용합니다.
/// API 키는 KeychainService를 통해서만 접근합니다.
final class BithumbService: ExchangeService, Sendable {

    // MARK: - ExchangeService Properties

    let exchange: Exchange = .bithumb
    let authMethod: AuthMethod = .hmacSHA512

    // MARK: - Private Properties

    private let baseURL = "https://api.bithumb.com"
    private let authenticator = BithumbAuthenticator()
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ExchangeService Methods

    /// 빗썸 계좌의 보유 자산 목록을 조회합니다.
    /// - Throws: `BithumbServiceError` 또는 `KeychainError`
    /// - Returns: 공통 Asset 모델 배열
    func fetchAssets() async throws -> [Asset] {
        guard let url = URL(string: "\(baseURL)/info/balance") else {
            throw BithumbServiceError.invalidURL
        }

        let parameters = ["currency": "ALL"]
        let authHeaders: [String: String]
        do {
            authHeaders = try authenticator.generateAuthHeaders(endpoint: "/info/balance", parameters: parameters)
        } catch let error as KeychainError {
            throw error
        } catch {
            throw BithumbServiceError.authenticationFailed(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        // POST body: application/x-www-form-urlencoded
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let decoded = try JSONDecoder().decode(BithumbResponse<BithumbBalanceData>.self, from: data)
            guard decoded.isSuccess else {
                throw BithumbServiceError.apiError(decoded.status, decoded.message)
            }
            guard let balanceData = decoded.data else {
                return []
            }
            return balanceData.currencies
                .compactMap { symbol, balance -> Asset? in
                    let amount = Double(balance.available) ?? 0
                    guard amount > 0 else { return nil }
                    return balance.toAsset(symbol: symbol)
                }
                .sorted { $0.symbol < $1.symbol }
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    /// 특정 심볼의 KRW 마켓 현재 시세를 조회합니다.
    /// - Parameter symbols: 심볼 목록 (예: ["BTC", "ETH"])
    /// - Throws: `BithumbServiceError`
    /// - Returns: 공통 Ticker 모델 배열
    func fetchTickers(symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }

        var tickers: [Ticker] = []
        for symbol in symbols {
            let ticker = try await fetchSingleTicker(symbol: symbol)
            tickers.append(ticker)
        }
        return tickers
    }

    /// API 키의 유효성을 검증합니다.
    /// - Throws: `BithumbServiceError` 또는 `KeychainError`
    /// - Returns: 연결 성공 여부
    func validateConnection() async throws -> Bool {
        do {
            _ = try await fetchAssets()
            return true
        } catch KeychainError.itemNotFound {
            throw BithumbAuthError.missingAPIKeys
        } catch let error as BithumbServiceError {
            switch error {
            case .httpError(let statusCode) where statusCode == 401:
                return false
            case .apiError(let status, _) where status == "5100":
                // 빗썸 오류 코드 5100: Bad Request (인증 실패)
                return false
            default:
                throw error
            }
        }
    }

    // MARK: - Private Helpers

    private func fetchSingleTicker(symbol: String) async throws -> Ticker {
        guard let url = URL(string: "\(baseURL)/public/ticker/\(symbol)_KRW") else {
            throw BithumbServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            try validateHTTPResponse(response)
            data = responseData
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.networkError(error)
        }

        do {
            let decoded = try JSONDecoder().decode(BithumbResponse<BithumbTickerData>.self, from: data)
            guard decoded.isSuccess else {
                throw BithumbServiceError.apiError(decoded.status, decoded.message)
            }
            guard let tickerData = decoded.data else {
                throw BithumbServiceError.emptyResponse
            }
            return tickerData.toTicker(symbol: symbol)
        } catch let error as BithumbServiceError {
            throw error
        } catch {
            throw BithumbServiceError.decodingFailed(error)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BithumbServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BithumbServiceError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Service Errors

enum BithumbServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingFailed(Error)
    case authenticationFailed(Error)
    case apiError(String, String?)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버로부터 올바르지 않은 응답을 받았습니다."
        case .httpError(let code):
            return "서버 오류가 발생했습니다. (HTTP \(code))"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "데이터 파싱에 실패했습니다: \(error.localizedDescription)"
        case .authenticationFailed(let error):
            return "인증 처리 중 오류가 발생했습니다: \(error.localizedDescription)"
        case .apiError(let status, let message):
            return "빗썸 API 오류 (코드: \(status))\(message.map { ": \($0)" } ?? "")"
        case .emptyResponse:
            return "서버로부터 빈 응답을 받았습니다."
        }
    }
}
