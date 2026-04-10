# CryptoTrack (가제) - macOS & iOS Portfolio Manager

개인 정보와 자산 데이터를 서버에 저장하지 않고, 기기 로컬의 **Apple Keychain**을 사용하여 보안을 극대화한 가상화폐 포트폴리오 관리 앱입니다.

## 🚀 주요 기능
- **거래소 API 연동:** 업비트(Upbit), 바이낸스(Binance) 등 국내외 거래소 연동.
- **실시간 자산 추적:** 각 코인별 평단가, 보유량, 총 자산 현황 조회.
- **손익 자동 계산:** 현재 시세와 연동하여 실시간 수익률(P&L) 및 평가 손익 산출.
- **로컬 보안 저장소:** API Key를 서버가 아닌 Apple Keychain에 암호화하여 저장.
- **서버리스 아키텍처:** 모든 데이터 요청은 기기에서 거래소로 직접 전달 (No Middle-man).

## 🛠 기술 스택
- **Language:** Swift 6.0+ (Swift Concurrency 활용)
- **UI Framework:** SwiftUI (macOS/iOS 공용)
- **Security:** Security Framework (Keychain), Local Authentication (FaceID/TouchID)
- **Networking:** URLSession / Alamofire
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