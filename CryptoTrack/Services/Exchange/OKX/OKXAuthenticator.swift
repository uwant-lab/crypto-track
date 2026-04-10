import Foundation
import CryptoKit

/// OKX HMAC-SHA256 + 패스프레이즈 서명 인증을 담당합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 파일이나 UserDefaults에 저장하지 않습니다.
struct OKXAuthenticator: Sendable {

    // MARK: - Keychain Keys

    private static let keychainAccount = "okx"
    private static let apiKeyName = "apiKey"
    private static let secretKeyName = "secretKey"
    private static let passphraseKeyName = "passphrase"

    // MARK: - API Key Access

    /// Keychain에서 API Key를 조회합니다.
    func apiKey() throws -> String {
        try KeychainService.shared.read(
            key: OKXAuthenticator.apiKeyName,
            account: OKXAuthenticator.keychainAccount
        )
    }

    /// Keychain에서 Secret Key를 조회합니다.
    func secretKey() throws -> String {
        try KeychainService.shared.read(
            key: OKXAuthenticator.secretKeyName,
            account: OKXAuthenticator.keychainAccount
        )
    }

    /// Keychain에서 패스프레이즈를 조회합니다.
    func passphrase() throws -> String {
        try KeychainService.shared.read(
            key: OKXAuthenticator.passphraseKeyName,
            account: OKXAuthenticator.keychainAccount
        )
    }

    /// API Key, Secret Key, 패스프레이즈를 Keychain에 저장합니다.
    func saveCredentials(apiKey: String, secretKey: String, passphrase: String) throws {
        try KeychainService.shared.save(
            key: OKXAuthenticator.apiKeyName,
            value: apiKey,
            account: OKXAuthenticator.keychainAccount
        )
        try KeychainService.shared.save(
            key: OKXAuthenticator.secretKeyName,
            value: secretKey,
            account: OKXAuthenticator.keychainAccount
        )
        try KeychainService.shared.save(
            key: OKXAuthenticator.passphraseKeyName,
            value: passphrase,
            account: OKXAuthenticator.keychainAccount
        )
    }

    // MARK: - Auth Headers

    /// OKX 인증 헤더를 생성합니다.
    /// - Parameters:
    ///   - method: HTTP 메서드 (예: "GET", "POST")
    ///   - requestPath: 요청 경로 (예: "/api/v5/account/balance")
    ///   - body: 요청 바디 (GET 요청의 경우 빈 문자열)
    /// - Returns: OKX 인증에 필요한 헤더 딕셔너리
    func authHeaders(method: String, requestPath: String, body: String = "") throws -> [String: String] {
        let secret = try secretKey()
        let key = try apiKey()
        let pass = try passphrase()
        let timestamp = iso8601Timestamp()

        let message = timestamp + method.uppercased() + requestPath + body
        let signature = hmacSHA256Base64(message: message, secret: secret)

        return [
            "OK-ACCESS-KEY": key,
            "OK-ACCESS-SIGN": signature,
            "OK-ACCESS-TIMESTAMP": timestamp,
            "OK-ACCESS-PASSPHRASE": pass,
            "Content-Type": "application/json"
        ]
    }

    // MARK: - Private Helpers

    /// ISO 8601 형식의 현재 타임스탬프를 반환합니다.
    /// OKX는 소수점 3자리 밀리초가 포함된 형식을 요구합니다. (예: 2024-01-01T00:00:00.000Z)
    private func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// HMAC-SHA256 서명을 Base64 인코딩하여 반환합니다.
    /// - Parameters:
    ///   - message: 서명할 메시지 (timestamp + method + requestPath + body)
    ///   - secret: OKX Secret Key
    /// - Returns: Base64 인코딩된 서명 문자열
    private func hmacSHA256Base64(message: String, secret: String) -> String {
        let keyData = Data(secret.utf8)
        let messageData = Data(message.utf8)

        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)

        return Data(mac).base64EncodedString()
    }
}
