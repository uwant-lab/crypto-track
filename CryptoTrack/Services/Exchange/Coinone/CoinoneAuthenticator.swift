import Foundation
import CryptoKit

// MARK: - Coinone HMAC-SHA512 Authenticator

/// Coinone API 인증을 위한 HMAC-SHA512 서명을 생성합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 직접 저장하지 않습니다.
struct CoinoneAuthenticator: Sendable {

    // MARK: - Keychain Keys

    static let keychainAccount = "coinone"
    static let accessKeyName = "accessKey"
    static let secretKeyName = "secretKey"

    // MARK: - Auth Result

    /// 인증 결과: 헤더 및 서명된 페이로드 데이터
    struct AuthResult: Sendable {
        /// X-COINONE-PAYLOAD, X-COINONE-SIGNATURE 헤더 딕셔너리
        let headers: [String: String]
        /// HTTP body로 사용할 서명된 페이로드 JSON 데이터
        let bodyData: Data
    }

    // MARK: - Header Generation

    /// Coinone API 요청에 필요한 인증 헤더와 HTTP body 데이터를 생성합니다.
    /// - Parameter payload: 요청 페이로드 딕셔너리 (access_token 제외)
    /// - Returns: 인증 헤더 및 body 데이터
    func generateAuth(payload: [String: Any]) throws -> AuthResult {
        let accessKey = try KeychainService.shared.read(
            key: CoinoneAuthenticator.accessKeyName,
            account: CoinoneAuthenticator.keychainAccount
        )
        let secretKey = try KeychainService.shared.read(
            key: CoinoneAuthenticator.secretKeyName,
            account: CoinoneAuthenticator.keychainAccount
        )

        var fullPayload = payload
        fullPayload["access_token"] = accessKey

        let bodyData = try JSONSerialization.data(withJSONObject: fullPayload, options: [.sortedKeys])
        let payloadBase64 = bodyData.base64EncodedString()
        let signature = try generateSignature(payloadBase64: payloadBase64, secretKey: secretKey)

        let headers: [String: String] = [
            "X-COINONE-PAYLOAD": payloadBase64,
            "X-COINONE-SIGNATURE": signature
        ]

        return AuthResult(headers: headers, bodyData: bodyData)
    }

    // MARK: - Private Helpers

    private func generateSignature(payloadBase64: String, secretKey: String) throws -> String {
        guard let payloadData = payloadBase64.data(using: .utf8),
              let keyData = secretKey.uppercased().data(using: .utf8) else {
            throw CoinoneAuthError.signingFailed
        }

        let symmetricKey = SymmetricKey(data: keyData)
        let signature = HMAC<SHA512>.authenticationCode(for: payloadData, using: symmetricKey)
        return Data(signature).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Auth Errors

enum CoinoneAuthError: LocalizedError {
    case signingFailed
    case missingAPIKeys

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return "Coinone HMAC-SHA512 서명 생성에 실패했습니다."
        case .missingAPIKeys:
            return "Coinone API 키가 설정되지 않았습니다. 설정 화면에서 키를 입력해 주세요."
        }
    }
}
