import Foundation

/// 거래소별 API 키 발급 안내 정보
struct ExchangeGuide {
    let exchange: Exchange
    let displayName: String
    let apiKeyLabels: APIKeyLabels
    let steps: [String]
    let importantNotes: [String]
    let guideURL: URL?

    struct APIKeyLabels {
        let accessKey: String
        let secretKey: String
        let passphrase: String?
    }
}

extension ExchangeGuide {
    static let all: [Exchange: ExchangeGuide] = [
        .upbit: upbit,
        .binance: binance,
        .bithumb: bithumb,
        .bybit: bybit,
        .coinone: coinone,
        .korbit: korbit,
        .okx: okx
    ]

    // MARK: - 업비트

    static let upbit = ExchangeGuide(
        exchange: .upbit,
        displayName: "업비트 (Upbit)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "Access Key",
            secretKey: "Secret Key",
            passphrase: nil
        ),
        steps: [
            "업비트(upbit.com)에 로그인합니다.",
            "마이페이지 → Open API 관리로 이동합니다.",
            "'Open API Key 발급하기'를 클릭합니다.",
            "자산조회 권한만 체크합니다. (주문, 출금 권한 절대 비활성화)",
            "허용 IP 주소를 설정합니다. (선택사항, 보안 강화)",
            "Access Key와 Secret Key를 복사하여 저장합니다."
        ],
        importantNotes: [
            "반드시 '자산조회(Read)' 권한만 부여하세요.",
            "주문/출금 권한은 절대 활성화하지 마세요.",
            "Secret Key는 발급 시 한 번만 표시됩니다."
        ],
        guideURL: URL(string: "https://upbit.com/mypage/open_api_management")
    )

    // MARK: - 바이낸스

    static let binance = ExchangeGuide(
        exchange: .binance,
        displayName: "바이낸스 (Binance)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "API Key",
            secretKey: "Secret Key",
            passphrase: nil
        ),
        steps: [
            "바이낸스(binance.com)에 로그인합니다.",
            "프로필 아이콘 → API Management로 이동합니다.",
            "'Create API'를 클릭하고 라벨을 입력합니다.",
            "보안 인증(2FA)을 완료합니다.",
            "API restrictions에서 'Enable Reading'만 체크합니다.",
            "IP 접근 제한을 설정합니다. (권장)",
            "API Key와 Secret Key를 복사하여 저장합니다."
        ],
        importantNotes: [
            "'Enable Reading' 권한만 활성화하세요.",
            "'Enable Spot & Margin Trading' 등 거래 권한은 비활성화하세요.",
            "Secret Key는 생성 시 한 번만 표시됩니다."
        ],
        guideURL: URL(string: "https://www.binance.com/en/my/settings/api-management")
    )

    // MARK: - 빗썸

    static let bithumb = ExchangeGuide(
        exchange: .bithumb,
        displayName: "빗썸 (Bithumb)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "API Key (Connect Key)",
            secretKey: "Secret Key",
            passphrase: nil
        ),
        steps: [
            "빗썸(bithumb.com)에 로그인합니다.",
            "마이페이지 → API 관리로 이동합니다.",
            "'API Key 발급'을 클릭합니다.",
            "보안 인증(SMS/OTP)을 완료합니다.",
            "'입출금 조회' 권한만 선택합니다.",
            "Connect Key(API Key)와 Secret Key를 복사합니다."
        ],
        importantNotes: [
            "'입출금 조회' 권한만 부여하세요.",
            "거래(주문) 및 출금 권한은 절대 부여하지 마세요.",
            "API Key는 최대 3개까지 발급 가능합니다."
        ],
        guideURL: URL(string: "https://www.bithumb.com/mypage/api")
    )

    // MARK: - 바이빗

    static let bybit = ExchangeGuide(
        exchange: .bybit,
        displayName: "바이빗 (Bybit)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "API Key",
            secretKey: "API Secret",
            passphrase: nil
        ),
        steps: [
            "바이빗(bybit.com)에 로그인합니다.",
            "프로필 → API로 이동합니다.",
            "'새 키 만들기'를 클릭합니다.",
            "API 키 유형: 'API 트랜잭션'을 선택합니다.",
            "권한: '읽기 전용'으로 설정합니다.",
            "IP 접근 제한을 설정합니다. (권장)",
            "API Key와 API Secret을 복사합니다."
        ],
        importantNotes: [
            "'읽기 전용(Read-Only)' 권한만 설정하세요.",
            "거래/출금 권한은 부여하지 마세요.",
            "API Secret은 생성 시 한 번만 확인 가능합니다."
        ],
        guideURL: URL(string: "https://www.bybit.com/app/user/api-management")
    )

    // MARK: - 코인원

    static let coinone = ExchangeGuide(
        exchange: .coinone,
        displayName: "코인원 (Coinone)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "Access Token",
            secretKey: "Secret Key",
            passphrase: nil
        ),
        steps: [
            "코인원(coinone.co.kr)에 로그인합니다.",
            "마이페이지 → API 키 관리로 이동합니다.",
            "'API 키 발급'을 클릭합니다.",
            "보안 인증을 완료합니다.",
            "'잔고 조회' 권한만 선택합니다.",
            "Access Token과 Secret Key를 복사합니다."
        ],
        importantNotes: [
            "'잔고 조회' 권한만 부여하세요.",
            "매수/매도/출금 권한은 절대 활성화하지 마세요.",
            "API 키는 분실 시 재발급 받아야 합니다."
        ],
        guideURL: URL(string: "https://coinone.co.kr/mypage/api")
    )

    // MARK: - 코빗

    static let korbit = ExchangeGuide(
        exchange: .korbit,
        displayName: "코빗 (Korbit)",
        apiKeyLabels: APIKeyLabels(
            accessKey: "Client ID",
            secretKey: "Client Secret",
            passphrase: nil
        ),
        steps: [
            "코빗(korbit.co.kr)에 로그인합니다.",
            "설정 → API 관리로 이동합니다.",
            "'API 키 발급'을 클릭합니다.",
            "보안 인증을 완료합니다.",
            "Client ID와 Client Secret이 발급됩니다.",
            "OAuth 2.0 방식이므로 별도 권한 설정은 없습니다."
        ],
        importantNotes: [
            "코빗은 OAuth 2.0 인증을 사용합니다.",
            "Client Secret은 발급 시 한 번만 표시됩니다.",
            "토큰 갱신은 앱에서 자동으로 처리됩니다."
        ],
        guideURL: URL(string: "https://www.korbit.co.kr/settings/api")
    )

    // MARK: - OKX

    static let okx = ExchangeGuide(
        exchange: .okx,
        displayName: "OKX",
        apiKeyLabels: APIKeyLabels(
            accessKey: "API Key",
            secretKey: "Secret Key",
            passphrase: "Passphrase"
        ),
        steps: [
            "OKX(okx.com)에 로그인합니다.",
            "프로필 → API로 이동합니다.",
            "'API 키 생성'을 클릭합니다.",
            "API 키 이름과 Passphrase를 입력합니다.",
            "권한: '읽기(Read)' 전용으로 설정합니다.",
            "IP 화이트리스트를 설정합니다. (권장)",
            "API Key, Secret Key, Passphrase를 모두 저장합니다."
        ],
        importantNotes: [
            "'읽기(Read)' 권한만 활성화하세요.",
            "OKX는 Passphrase가 반드시 필요합니다. 분실 시 재발급해야 합니다.",
            "거래/출금 권한은 절대 활성화하지 마세요.",
            "API Key, Secret Key, Passphrase 세 가지를 모두 안전하게 보관하세요."
        ],
        guideURL: URL(string: "https://www.okx.com/account/my-api")
    )
}
