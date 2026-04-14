import Foundation
import CryptoKit

final class PINService: Sendable {
    static let shared = PINService()

    private let keychain = KeychainService.shared
    private static let account = "security"
    private static let hashKey = "pin.hash"
    private static let saltKey = "pin.salt"

    private init() {}

    /// 저장된 PIN이 있으면 true를 반환합니다.
    var isPINSet: Bool {
        (try? keychain.read(key: Self.hashKey, account: Self.account)) != nil
    }

    /// 새 PIN을 해싱하여 Keychain에 저장합니다.
    /// 기존 PIN 데이터를 먼저 제거하여 부분 쓰기 상태를 방지합니다.
    func setPIN(_ pin: String) throws {
        let salt = generateSalt()
        let hash = hashPIN(pin, salt: salt)
        try? keychain.delete(key: Self.hashKey, account: Self.account)
        try? keychain.delete(key: Self.saltKey, account: Self.account)
        try keychain.save(key: Self.saltKey, value: salt, account: Self.account)
        try keychain.save(key: Self.hashKey, value: hash, account: Self.account)
    }

    /// 입력된 PIN이 저장된 해시와 일치하는지 검증합니다.
    func verifyPIN(_ pin: String) -> Bool {
        guard let salt = try? keychain.read(key: Self.saltKey, account: Self.account),
              let storedHash = try? keychain.read(key: Self.hashKey, account: Self.account) else {
            return false
        }
        return hashPIN(pin, salt: salt) == storedHash
    }

    /// 저장된 PIN을 Keychain에서 삭제합니다.
    func deletePIN() throws {
        try keychain.delete(key: Self.hashKey, account: Self.account)
        try keychain.delete(key: Self.saltKey, account: Self.account)
    }

    // MARK: - Private

    private func generateSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func hashPIN(_ pin: String, salt: String) -> String {
        let input = Data((pin + salt).utf8)
        let hash = SHA256.hash(data: input)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
