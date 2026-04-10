import Foundation
import CryptoKit

// MARK: - Upbit JWT Authenticator

/// Upbit API 인증을 위한 JWT 토큰을 생성합니다.
/// API 키는 반드시 KeychainService를 통해 조회하며, 직접 저장하지 않습니다.
struct UpbitAuthenticator: Sendable {

    // MARK: - Keychain Keys

    static let keychainAccount = "upbit"
    static let accessKeyName = "accessKey"
    static let secretKeyName = "secretKey"

    // MARK: - JWT Generation

    /// Upbit API 요청에 필요한 Bearer JWT 토큰을 생성합니다.
    /// - Parameters:
    ///   - queryHash: 요청 파라미터의 SHA-512 해시 (파라미터 없는 요청은 nil)
    /// - Returns: "Bearer <jwt>" 형식의 Authorization 헤더 값
    func generateAuthorizationHeader(queryHash: String? = nil) throws -> String {
        let accessKey = try KeychainService.shared.read(
            key: UpbitAuthenticator.accessKeyName,
            account: UpbitAuthenticator.keychainAccount
        )
        let secretKey = try KeychainService.shared.read(
            key: UpbitAuthenticator.secretKeyName,
            account: UpbitAuthenticator.keychainAccount
        )

        let token = try createJWT(accessKey: accessKey, secretKey: secretKey, queryHash: queryHash)
        return "Bearer \(token)"
    }

    // MARK: - Private JWT Builder

    private func createJWT(accessKey: String, secretKey: String, queryHash: String?) throws -> String {
        // Header
        let header = base64URLEncode(try JSONEncoder().encode(JWTHeader(alg: "HS256", typ: "JWT")))

        // Payload
        let payload = JWTPayload(
            accessKey: accessKey,
            nonce: UUID().uuidString,
            queryHash: queryHash,
            queryHashAlg: queryHash != nil ? "SHA512" : nil
        )
        let payloadData = try JSONEncoder().encode(payload)
        let encodedPayload = base64URLEncode(payloadData)

        // Signing input
        let signingInput = "\(header).\(encodedPayload)"
        guard let signingData = signingInput.data(using: .utf8),
              let secretData = secretKey.data(using: .utf8) else {
            throw UpbitAuthError.jwtEncodingFailed
        }

        // HMAC-SHA256 signature via CryptoKit
        let symmetricKey = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: signingData, using: symmetricKey)
        let encodedSignature = base64URLEncode(Data(signature))

        return "\(signingInput).\(encodedSignature)"
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - JWT Structures (private encoding helpers)

private struct JWTHeader: Encodable {
    let alg: String
    let typ: String
}

private struct JWTPayload: Encodable {
    let accessKey: String
    let nonce: String
    let queryHash: String?
    let queryHashAlg: String?

    enum CodingKeys: String, CodingKey {
        case accessKey = "access_key"
        case nonce
        case queryHash = "query_hash"
        case queryHashAlg = "query_hash_alg"
    }
}

// MARK: - Auth Errors

enum UpbitAuthError: LocalizedError {
    case jwtEncodingFailed
    case missingAPIKeys

    var errorDescription: String? {
        switch self {
        case .jwtEncodingFailed:
            return "JWT 토큰 생성에 실패했습니다."
        case .missingAPIKeys:
            return "Upbit API 키가 설정되지 않았습니다. 설정 화면에서 키를 입력해 주세요."
        }
    }
}
