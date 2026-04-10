import Foundation
import CryptoKit

/// Bybit HMAC-SHA256 서명 인증을 담당합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 파일이나 UserDefaults에 저장하지 않습니다.
struct BybitAuthenticator: Sendable {

    // MARK: - Keychain Keys

    private static let keychainAccount = "bybit"
    private static let apiKeyName = "apiKey"
    private static let secretKeyName = "secretKey"

    // MARK: - Constants

    private static let recvWindow = "5000"

    // MARK: - API Key Access

    /// Keychain에서 API Key를 조회합니다.
    func apiKey() throws -> String {
        try KeychainService.shared.read(
            key: BybitAuthenticator.apiKeyName,
            account: BybitAuthenticator.keychainAccount
        )
    }

    /// Keychain에서 Secret Key를 조회합니다.
    func secretKey() throws -> String {
        try KeychainService.shared.read(
            key: BybitAuthenticator.secretKeyName,
            account: BybitAuthenticator.keychainAccount
        )
    }

    /// API Key와 Secret Key를 Keychain에 저장합니다.
    func saveCredentials(apiKey: String, secretKey: String) throws {
        try KeychainService.shared.save(
            key: BybitAuthenticator.apiKeyName,
            value: apiKey,
            account: BybitAuthenticator.keychainAccount
        )
        try KeychainService.shared.save(
            key: BybitAuthenticator.secretKeyName,
            value: secretKey,
            account: BybitAuthenticator.keychainAccount
        )
    }

    // MARK: - Auth Headers

    /// Bybit V5 API 인증 헤더를 생성합니다.
    /// 서명 문자열: timestamp + apiKey + recvWindow + queryString
    /// - Parameter queryString: 서명할 쿼리 스트링 (예: "accountType=UNIFIED")
    /// - Returns: 인증 헤더 딕셔너리
    func authHeaders(queryString: String) throws -> [String: String] {
        let key = try apiKey()
        let secret = try secretKey()
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let recvWindow = BybitAuthenticator.recvWindow

        let signPayload = timestamp + key + recvWindow + queryString
        let signature = hmacSHA256(message: signPayload, secret: secret)

        return [
            "X-BAPI-API-KEY": key,
            "X-BAPI-SIGN": signature,
            "X-BAPI-TIMESTAMP": timestamp,
            "X-BAPI-RECV-WINDOW": recvWindow
        ]
    }

    // MARK: - HMAC-SHA256

    /// HMAC-SHA256 서명을 생성합니다.
    /// - Parameters:
    ///   - message: 서명할 메시지
    ///   - secret: Bybit Secret Key
    /// - Returns: 16진수 문자열 서명
    private func hmacSHA256(message: String, secret: String) -> String {
        let keyData = Data(secret.utf8)
        let messageData = Data(message.utf8)

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)

        return Data(mac).map { String(format: "%02hhx", $0) }.joined()
    }
}
