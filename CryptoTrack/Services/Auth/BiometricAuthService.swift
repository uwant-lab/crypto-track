import LocalAuthentication
import Foundation

enum BiometricType: String {
    case faceID = "Face ID"
    case touchID = "Touch ID"
    case none = "없음"
}

enum BiometricAuthError: LocalizedError {
    case notAvailable
    case notEnrolled
    case authenticationFailed
    case userCancelled
    case systemCancelled
    case lockout
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "이 기기에서는 생체 인증을 사용할 수 없습니다."
        case .notEnrolled:
            return "등록된 생체 인증 정보가 없습니다. 기기 설정에서 등록해 주세요."
        case .authenticationFailed:
            return "생체 인증에 실패했습니다. 다시 시도해 주세요."
        case .userCancelled:
            return "사용자가 인증을 취소했습니다."
        case .systemCancelled:
            return "시스템에 의해 인증이 취소되었습니다."
        case .lockout:
            return "인증 시도 횟수를 초과했습니다. 기기 잠금 해제 후 다시 시도해 주세요."
        case .unknown(let error):
            return "인증 오류: \(error.localizedDescription)"
        }
    }
}

final class BiometricAuthService: Sendable {
    static let shared = BiometricAuthService()

    private init() {}

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        default:
            return .none
        }
    }

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate() async throws -> Bool {
        let context = LAContext()
        var policyError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError) else {
            if let laError = policyError as? LAError {
                throw mapLAError(laError)
            }
            throw BiometricAuthError.notAvailable
        }

        let reason = "앱 잠금 해제를 위해 인증이 필요합니다."

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            throw mapLAError(error)
        } catch {
            throw BiometricAuthError.unknown(error)
        }
    }

    private func mapLAError(_ error: LAError) -> BiometricAuthError {
        switch error.code {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel, .appCancel:
            return .userCancelled
        case .systemCancel:
            return .systemCancelled
        case .biometryLockout:
            return .lockout
        default:
            return .unknown(error)
        }
    }
}
