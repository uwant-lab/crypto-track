import Foundation
import Observation

// MARK: - Connection Status

/// 거래소 API 연결 상태를 나타냅니다.
enum ConnectionStatus: Equatable {
    case untested
    case testing
    case success
    case failed(String)

    var displayText: String {
        switch self {
        case .untested:
            return "미테스트"
        case .testing:
            return "테스트 중…"
        case .success:
            return "연결 성공"
        case .failed(let message):
            return "실패: \(message)"
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - SettingsViewModel

/// 설정 화면의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - State

    /// 저장된 API 키가 있는 거래소 집합
    var savedExchanges: Set<Exchange> = []

    /// 거래소별 연결 테스트 상태
    var connectionStatus: [Exchange: ConnectionStatus] = [:]

    // MARK: - Computed Properties

    /// 모든 지원 거래소 목록
    var allExchanges: [Exchange] {
        Exchange.allCases
    }

    // MARK: - Initializer

    init() {
        refreshSavedExchanges()
    }

    // MARK: - Keychain State

    /// Keychain에서 저장된 API 키 여부를 새로고침합니다.
    func refreshSavedExchanges() {
        savedExchanges = Set(Exchange.allCases.filter { hasAPIKeys(for: $0) })
    }

    /// 해당 거래소의 API 키가 Keychain에 저장되어 있는지 확인합니다.
    func hasAPIKeys(for exchange: Exchange) -> Bool {
        let account = exchange.rawValue.lowercased()
        let primaryKey = exchange == .korbit ? "clientId" : "accessKey"
        return (try? KeychainService.shared.read(key: primaryKey, account: account)) != nil
    }

    // MARK: - Save

    /// API 키를 Keychain에 저장합니다.
    func saveAPIKeys(
        exchange: Exchange,
        accessKey: String,
        secretKey: String,
        passphrase: String?
    ) throws {
        let account = exchange.rawValue.lowercased()

        if exchange == .korbit {
            // Korbit: clientId / clientSecret
            try KeychainService.shared.save(key: "clientId", value: accessKey, account: account)
            try KeychainService.shared.save(key: "clientSecret", value: secretKey, account: account)
        } else if exchange == .okx {
            // OKX: apiKey / secretKey / passphrase
            try KeychainService.shared.save(key: "apiKey", value: accessKey, account: account)
            try KeychainService.shared.save(key: "secretKey", value: secretKey, account: account)
            if let passphrase, !passphrase.isEmpty {
                try KeychainService.shared.save(key: "passphrase", value: passphrase, account: account)
            }
        } else {
            // 나머지 거래소: accessKey / secretKey
            try KeychainService.shared.save(key: "accessKey", value: accessKey, account: account)
            try KeychainService.shared.save(key: "secretKey", value: secretKey, account: account)
        }

        savedExchanges.insert(exchange)
    }

    // MARK: - Delete

    /// Keychain에서 해당 거래소의 API 키를 삭제합니다.
    func deleteAPIKeys(exchange: Exchange) throws {
        let account = exchange.rawValue.lowercased()

        if exchange == .korbit {
            try KeychainService.shared.delete(key: "clientId", account: account)
            try KeychainService.shared.delete(key: "clientSecret", account: account)
            // 토큰 캐시도 삭제
            try KeychainService.shared.delete(key: "accessToken", account: account)
            try KeychainService.shared.delete(key: "refreshToken", account: account)
            try KeychainService.shared.delete(key: "tokenExpiry", account: account)
        } else if exchange == .okx {
            try KeychainService.shared.delete(key: "apiKey", account: account)
            try KeychainService.shared.delete(key: "secretKey", account: account)
            try KeychainService.shared.delete(key: "passphrase", account: account)
        } else {
            try KeychainService.shared.delete(key: "accessKey", account: account)
            try KeychainService.shared.delete(key: "secretKey", account: account)
        }

        savedExchanges.remove(exchange)
        connectionStatus.removeValue(forKey: exchange)
    }

    // MARK: - Test Connection

    /// 거래소 API 연결 상태를 테스트합니다.
    func testConnection(exchange: Exchange) async {
        connectionStatus[exchange] = .testing

        do {
            let service = makeService(for: exchange)
            let isValid = try await service.validateConnection()
            connectionStatus[exchange] = isValid ? .success : .failed("인증 실패")
        } catch {
            connectionStatus[exchange] = .failed(error.localizedDescription)
        }
    }

    /// 저장된 모든 거래소의 연결 상태를 병렬로 재검증합니다.
    /// 앱 재시작 시 메모리에서 사라진 `connectionStatus`를 복원하기 위해 사용합니다.
    /// 이미 테스트 중이거나 성공 상태인 거래소는 건너뜁니다.
    func refreshConnectionStatuses() async {
        let targets = savedExchanges.filter { exchange in
            switch connectionStatus[exchange] {
            case .testing, .success:
                return false
            default:
                return true
            }
        }
        guard !targets.isEmpty else { return }

        for exchange in targets {
            connectionStatus[exchange] = .testing
        }

        await withTaskGroup(of: (Exchange, ConnectionStatus).self) { group in
            for exchange in targets {
                group.addTask { [weak self] in
                    guard let self else { return (exchange, .failed("취소됨")) }
                    let service = await self.makeService(for: exchange)
                    do {
                        let isValid = try await service.validateConnection()
                        return (exchange, isValid ? .success : .failed("인증 실패"))
                    } catch {
                        return (exchange, .failed(error.localizedDescription))
                    }
                }
            }
            for await (exchange, status) in group {
                connectionStatus[exchange] = status
            }
        }
    }

    // MARK: - Private Factory

    /// 거래소에 맞는 ExchangeService 인스턴스를 생성합니다.
    private func makeService(for exchange: Exchange) -> any ExchangeService {
        switch exchange {
        case .upbit:
            return UpbitService()
        case .binance:
            return BinanceService()
        case .bithumb:
            return BithumbService()
        case .bybit:
            return BybitService()
        case .coinone:
            return CoinoneService()
        case .korbit:
            return KorbitService()
        case .okx:
            return OKXService()
        }
    }
}
