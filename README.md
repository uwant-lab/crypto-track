# CryptoTrack (가제) - macOS & iOS Portfolio Manager

개인 정보와 자산 데이터를 서버에 저장하지 않고, 기기 로컬의 **Apple Keychain**을 사용하여 보안을 극대화한 가상화폐 포트폴리오 관리 앱입니다.

## 🚀 주요 기능

### 포트폴리오 관리
- **거래소 API 연동:** 업비트, 바이낸스, 빗썸, 바이빗, 코인원, 코빗, OKX (7개 거래소)
- **실시간 자산 추적:** 각 코인별 평단가, 보유량, 총 자산 현황 조회
- **손익 자동 계산:** 현재 시세와 연동하여 실시간 수익률(P&L) 및 평가 손익 산출
- **로컬 보안 저장소:** API Key를 서버가 아닌 Apple Keychain에 암호화하여 저장
- **서버리스 아키텍처:** 모든 데이터 요청은 기기에서 거래소로 직접 전달 (No Middle-man)

### 차트 & 분석 (Planned)
TradingView 수준의 인터랙티브 차트를 앱 내에서 제공합니다.

#### 차트 뷰어
- **캔들스틱 차트:** OHLCV(시가/고가/저가/종가/거래량) 캔들 차트
- **다중 타임프레임:** 1분, 5분, 15분, 1시간, 4시간, 1일, 1주, 1개월
- **확대/축소 & 스크롤:** 제스처 기반 차트 네비게이션
- **크로스헤어:** 터치/호버 시 해당 캔들의 상세 정보 표시

#### 기술적 지표 (Technical Indicators)
- **추세 지표:** MA(이동평균), EMA, 볼린저 밴드
- **모멘텀 지표:** RSI, MACD, Stochastic
- **거래량 지표:** Volume, OBV
- **지표 커스터마이징:** 파라미터 조정 (기간, 색상 등)

#### 드로잉 도구
- **라인 도구:** 추세선, 수평선, 수직선, 레이(Ray)
- **피보나치:** 되돌림(Retracement), 확장(Extension)
- **영역 도구:** 사각형, 평행 채널
- **텍스트 & 마커:** 메모, 가격 라벨, 아이콘 마커
- **드로잉 저장:** 심볼+타임프레임별로 드로잉을 로컬에 영구 저장
- **드로잉 관리:** 개별 편집(이동, 크기 조절), 삭제, 표시/숨기기

#### 데이터 소스
- 연동된 거래소의 Kline/Candlestick API를 직접 호출
- 차트 데이터도 서버를 거치지 않는 클라이언트 직접 통신 유지

### iCloud 동기화 (Planned)
모든 Apple 기기(macOS, iOS, iPadOS)에서 동일한 환경을 유지합니다.

- **API Key 동기화:** iCloud Keychain을 통한 자동 동기화 (추가 구현 불필요)
- **거래소 등록 상태:** NSUbiquitousKeyValueStore로 기기 간 실시간 동기화
- **차트 드로잉 데이터:** CloudKit 기반 동기화 (심볼별 드로잉 보존)
- **앱 설정:** 테마, 잠금 설정 등 NSUbiquitousKeyValueStore로 동기화
- **충돌 해결:** 최신 타임스탬프 우선 (last-write-wins) 전략

## 🛠 기술 스택
- **Language:** Swift 6.0+ (Swift Concurrency 활용)
- **UI Framework:** SwiftUI (macOS/iOS 공용)
- **Chart Rendering:** Canvas / Metal (고성능 차트 렌더링)
- **Security:** Security Framework (Keychain), Local Authentication (FaceID/TouchID)
- **Networking:** URLSession
- **Data Persistence:** UserDefaults (설정), Keychain (API Key), FileManager (드로잉 데이터)
- **Architecture:** MVVM (Model-View-ViewModel)

## 🔒 보안 원칙 (Security Policy)
1. **Zero-Server Policy:** 사용자의 API Key나 자산 정보를 수집하는 외부 서버를 절대 운영하지 않음.
2. **Encrypted Storage:** API Key는 반드시 `Keychain`에 저장하며, `UserDefaults`나 평문 파일 저장을 금지함.
3. **Minimal Permission:** 사용자에게 API 발급 시 '조회(Read)' 권한만 허용하도록 안내함.

## 🛠 개발 프로세스 (Git Workflow)
이 프로젝트는 안정적인 개발을 위해 다음 브랜치 전략을 따릅니다:
- **main:** 프로덕션 릴리스용 브랜치.
- **develop:** 개발 통합 브랜치. 모든 기능은 여기서 시작됩니다.
- **feature/*:** 개별 기능 구현 브랜치. 완료 후 `develop`으로 머지됩니다.

## 🚀 개발 시작하기
1. `develop` 브랜치에서 새로운 기능 브랜치를 생성합니다.
2. 기능 구현 후 테스트를 완료합니다.
3. `develop` 브랜치로 Pull Request를 생성합니다.

## Third-Party Trademarks

Exchange logos displayed in this app (Upbit, Binance, Bithumb, Bybit,
Coinone, Korbit, OKX) are trademarks of their respective owners and are
used solely for nominative identification — to help users see which
exchange a given asset resides in. No affiliation with or endorsement
by any listed exchange is implied.

Logos can be removed at any time by deleting the corresponding imageset
under `CryptoTrack/Assets.xcassets/Logo/`. The UI automatically falls
back to a brand-colored monogram circle in that case.