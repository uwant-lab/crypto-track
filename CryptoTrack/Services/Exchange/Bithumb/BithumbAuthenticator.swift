import Foundation
import CryptoKit

// MARK: - Bithumb HMAC-SHA512 Authenticator

/// Bithumb API 인증을 위한 HMAC-SHA512 서명을 생성합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 직접 저장하지 않습니다.
struct BithumbAuthenticator: Sendable {

    // MARK: - Keychain Keys

    static let keychainAccount = "bithumb"
    static let accessKeyName = "accessKey"
    static let secretKeyName = "secretKey"

    // MARK: - Auth Headers

    /// Bithumb API 요청에 필요한 인증 헤더를 생성합니다.
    /// - Parameters:
    ///   - endpoint: API 엔드포인트 (예: "/info/balance")
    ///   - parameters: POST 파라미터 딕셔너리
    /// - Returns: 인증 헤더 딕셔너리 (Api-Key, Api-Sign, Api-Timestamp, Api-Nonce)
    func generateAuthHeaders(endpoint: String, parameters: [String: String]) throws -> [String: String] {
        let accessKey = try KeychainService.shared.read(
            key: BithumbAuthenticator.accessKeyName,
            account: BithumbAuthenticator.keychainAccount
        )
        let secretKey = try KeychainService.shared.read(
            key: BithumbAuthenticator.secretKeyName,
            account: BithumbAuthenticator.keychainAccount
        )

        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
        let nonce = UUID().uuidString

        // 파라미터를 쿼리 문자열 형태로 인코딩
        var allParams = parameters
        allParams["endpoint"] = endpoint
        let encodedPayload = encodePayload(allParams)

        // 서명 원문: endpoint + chr(0) + encodedPayload + chr(0) + timestamp
        let signingMessage = "\(endpoint)\0\(encodedPayload)\0\(timestamp)"

        guard let signingData = signingMessage.data(using: .utf8),
              let secretData = secretKey.data(using: .utf8) else {
            throw BithumbAuthError.signingFailed
        }

        // HMAC-SHA512 서명
        let symmetricKey = SymmetricKey(data: secretData)
        let hmac = HMAC<SHA512>.authenticationCode(for: signingData, using: symmetricKey)
        let signature = Data(hmac).map { String(format: "%02x", $0) }.joined()

        return [
            "Api-Key": accessKey,
            "Api-Sign": signature,
            "Api-Timestamp": timestamp,
            "Api-Nonce": nonce,
            "Content-Type": "application/x-www-form-urlencoded"
        ]
    }

    // MARK: - Private Helpers

    private func encodePayload(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}

// MARK: - Auth Errors

enum BithumbAuthError: LocalizedError {
    case signingFailed
    case missingAPIKeys

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return "HMAC-SHA512 서명 생성에 실패했습니다."
        case .missingAPIKeys:
            return "빗썸 API 키가 설정되지 않았습니다. 설정 화면에서 키를 입력해 주세요."
        }
    }
}
