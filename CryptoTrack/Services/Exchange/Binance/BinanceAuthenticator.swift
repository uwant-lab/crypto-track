import Foundation
import CryptoKit

/// Binance HMAC-SHA256 서명 인증을 담당합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 파일이나 UserDefaults에 저장하지 않습니다.
struct BinanceAuthenticator: Sendable {

    // MARK: - Keychain Keys

    private static let keychainAccount = "binance"
    private static let apiKeyName = "apiKey"
    private static let secretKeyName = "secretKey"

    // MARK: - API Key Access

    /// Keychain에서 API Key를 조회합니다.
    func apiKey() throws -> String {
        try KeychainService.shared.read(
            key: BinanceAuthenticator.apiKeyName,
            account: BinanceAuthenticator.keychainAccount
        )
    }

    /// Keychain에서 Secret Key를 조회합니다.
    func secretKey() throws -> String {
        try KeychainService.shared.read(
            key: BinanceAuthenticator.secretKeyName,
            account: BinanceAuthenticator.keychainAccount
        )
    }

    /// API Key와 Secret Key를 Keychain에 저장합니다.
    func saveCredentials(apiKey: String, secretKey: String) throws {
        try KeychainService.shared.save(
            key: BinanceAuthenticator.apiKeyName,
            value: apiKey,
            account: BinanceAuthenticator.keychainAccount
        )
        try KeychainService.shared.save(
            key: BinanceAuthenticator.secretKeyName,
            value: secretKey,
            account: BinanceAuthenticator.keychainAccount
        )
    }

    // MARK: - Signature Generation

    /// 쿼리 스트링에 timestamp와 HMAC-SHA256 서명을 추가합니다.
    /// - Parameter queryItems: 서명할 쿼리 파라미터 배열
    /// - Returns: timestamp와 signature가 추가된 쿼리 파라미터 배열
    func signedQueryItems(from queryItems: [URLQueryItem]) throws -> [URLQueryItem] {
        let secret = try secretKey()
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))

        var items = queryItems
        items.append(URLQueryItem(name: "timestamp", value: timestamp))

        let queryString = items
            .compactMap { item in
                guard let value = item.value else { return nil }
                return "\(item.name)=\(value)"
            }
            .joined(separator: "&")

        let signature = hmacSHA256(message: queryString, secret: secret)
        items.append(URLQueryItem(name: "signature", value: signature))

        return items
    }

    // MARK: - HMAC-SHA256

    /// HMAC-SHA256 서명을 생성합니다.
    /// - Parameters:
    ///   - message: 서명할 메시지 (쿼리 스트링)
    ///   - secret: Binance Secret Key
    /// - Returns: 16진수 문자열 서명
    private func hmacSHA256(message: String, secret: String) -> String {
        let keyData = Data(secret.utf8)
        let messageData = Data(message.utf8)

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)

        return Data(mac).map { String(format: "%02hhx", $0) }.joined()
    }
}
