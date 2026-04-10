import Foundation

// MARK: - Korbit OAuth 2.0 Authenticator

/// Korbit API OAuth 2.0 토큰을 관리합니다.
/// client_id, client_secret은 KeychainService에 저장하며, UserDefaults는 사용하지 않습니다.
actor KorbitAuthenticator: Sendable {

    // MARK: - Keychain Keys

    static let keychainAccount = "korbit"
    static let clientIDKeyName = "clientId"
    static let clientSecretKeyName = "clientSecret"
    static let accessTokenKeyName = "accessToken"
    static let refreshTokenKeyName = "refreshToken"
    static let tokenExpiryKeyName = "tokenExpiry"

    // MARK: - Private Properties

    private let baseURL = "https://api.korbit.co.kr"
    private let session: URLSession

    // MARK: - Initializer

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Interface

    /// 유효한 Bearer 토큰을 반환합니다. 만료된 경우 자동으로 갱신합니다.
    /// - Returns: "Bearer <access_token>" 형식의 Authorization 헤더 값
    func authorizationHeader() async throws -> String {
        let accessToken = try await validAccessToken()
        return "Bearer \(accessToken)"
    }

    // MARK: - Token Management

    /// 유효한 액세스 토큰을 반환합니다. 만료 시 refresh 토큰으로 갱신합니다.
    private func validAccessToken() async throws -> String {
        // 캐시된 토큰 확인
        if let cachedToken = try? KeychainService.shared.read(
            key: KorbitAuthenticator.accessTokenKeyName,
            account: KorbitAuthenticator.keychainAccount
        ), !cachedToken.isEmpty {
            // 만료 시각 확인
            if let expiryString = try? KeychainService.shared.read(
                key: KorbitAuthenticator.tokenExpiryKeyName,
                account: KorbitAuthenticator.keychainAccount
            ), let expiryTimestamp = Double(expiryString) {
                let expiryDate = Date(timeIntervalSince1970: expiryTimestamp)
                // 만료 60초 전까지 유효로 간주
                if expiryDate > Date().addingTimeInterval(60) {
                    return cachedToken
                }
            }
            // 만료됐거나 만료 정보 없음 → refresh 시도
            if let newToken = try? await refreshAccessToken() {
                return newToken
            }
        }

        // 신규 토큰 발급
        return try await fetchNewAccessToken()
    }

    /// client_id/client_secret으로 신규 액세스 토큰을 발급합니다.
    private func fetchNewAccessToken() async throws -> String {
        let clientID = try KeychainService.shared.read(
            key: KorbitAuthenticator.clientIDKeyName,
            account: KorbitAuthenticator.keychainAccount
        )
        let clientSecret = try KeychainService.shared.read(
            key: KorbitAuthenticator.clientSecretKeyName,
            account: KorbitAuthenticator.keychainAccount
        )

        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&grant_type=client_credentials"
        return try await requestToken(body: body)
    }

    /// refresh_token으로 액세스 토큰을 갱신합니다.
    private func refreshAccessToken() async throws -> String {
        let clientID = try KeychainService.shared.read(
            key: KorbitAuthenticator.clientIDKeyName,
            account: KorbitAuthenticator.keychainAccount
        )
        let clientSecret = try KeychainService.shared.read(
            key: KorbitAuthenticator.clientSecretKeyName,
            account: KorbitAuthenticator.keychainAccount
        )
        let refreshToken = try KeychainService.shared.read(
            key: KorbitAuthenticator.refreshTokenKeyName,
            account: KorbitAuthenticator.keychainAccount
        )

        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&grant_type=refresh_token&refresh_token=\(refreshToken)"
        return try await requestToken(body: body)
    }

    /// OAuth 2.0 토큰 엔드포인트에 요청하고 토큰을 Keychain에 저장합니다.
    private func requestToken(body: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/oauth2/access_token") else {
            throw KorbitAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw KorbitAuthError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw KorbitAuthError.httpError(httpResponse.statusCode)
            }
            data = responseData
        } catch let error as KorbitAuthError {
            throw error
        } catch {
            throw KorbitAuthError.networkError(error)
        }

        do {
            let tokenResponse = try JSONDecoder().decode(KorbitTokenResponse.self, from: data)
            try storeTokens(tokenResponse)
            return tokenResponse.accessToken
        } catch let error as KorbitAuthError {
            throw error
        } catch {
            throw KorbitAuthError.decodingFailed(error)
        }
    }

    /// 발급된 토큰을 Keychain에 저장합니다.
    private func storeTokens(_ response: KorbitTokenResponse) throws {
        try KeychainService.shared.save(
            key: KorbitAuthenticator.accessTokenKeyName,
            value: response.accessToken,
            account: KorbitAuthenticator.keychainAccount
        )
        if let refreshToken = response.refreshToken {
            try KeychainService.shared.save(
                key: KorbitAuthenticator.refreshTokenKeyName,
                value: refreshToken,
                account: KorbitAuthenticator.keychainAccount
            )
        }
        // 만료 시각 저장
        let expiryDate = Date().addingTimeInterval(Double(response.expiresIn))
        try KeychainService.shared.save(
            key: KorbitAuthenticator.tokenExpiryKeyName,
            value: String(expiryDate.timeIntervalSince1970),
            account: KorbitAuthenticator.keychainAccount
        )
    }
}

// MARK: - Auth Errors

enum KorbitAuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case networkError(Error)
    case decodingFailed(Error)
    case missingAPIKeys

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다."
        case .invalidResponse:
            return "서버로부터 올바르지 않은 응답을 받았습니다."
        case .httpError(let code):
            return "인증 서버 오류가 발생했습니다. (HTTP \(code))"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "토큰 파싱에 실패했습니다: \(error.localizedDescription)"
        case .missingAPIKeys:
            return "Korbit API 키가 설정되지 않았습니다. 설정 화면에서 Client ID와 Client Secret을 입력해 주세요."
        }
    }
}
