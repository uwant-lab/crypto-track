# Project Context: CryptoTrack

이 문서는 Claude Code가 이 프로젝트의 코드를 생성하고 수정할 때 준수해야 할 규칙입니다.

## 🎯 프로젝트 목적
- 국내외 거래소 API를 통합하여 개인의 가상화폐 자산을 관리하는 데스크탑/모바일 앱 개발.

## 🛠 기술적 제약 사항
1. **Network:** 모든 네트워크 요청은 클라이언트 앱에서 직접 수행한다.
2. **Authentication:** - 업비트: JWT(JSON Web Token) 기반 인증 로직을 Swift로 구현한다.
   - 해외 거래소: HMAC-SHA256 서명 기반 인증을 사용한다.
3. **Data Persistence:**
   - 설정값(테마, 단위 등)은 `UserDefaults`를 사용한다.
   - **중요:** API Key(Access/Secret)는 반드시 `Keychain` 접근 로직을 거쳐야 한다. 직접적인 파일 저장은 금지한다.
4. **Concurrency:** `Completion Handler` 대신 Swift의 `async/await` 패턴을 우선 사용한다.

## 🏗 아키텍처 가이드라인
- **Model:** 거래소별 응답 형식을 공통 모델(`Asset`, `Ticker`)로 변환하는 `ExchangeAdapter` 패턴을 사용한다.
- **ViewModel:** 각 화면(Dashboard, Settings)은 독립적인 ViewModel을 가지며, 상태 관리는 `@Observable` (iOS 17+) 또는 `@Published`를 사용한다.
- **Service:** 거래소별 통신 로직은 `ExchangeService` 프로토콜을 구현하여 확장성을 확보한다.

## 📝 코드 작성 스타일
- 변수와 함수명은 Swift API Design Guidelines를 따른다.
- 모든 API 통신 코드에는 에러 핸들링(`do-catch`)과 사용자 피드백(Alert 메시지 등) 로직을 포함한다.
- SwiftUI View는 작은 단위로 컴포넌트화하여 재사용성을 높인다.

## 🌿 Git Workflow Rules
1. **Branching Root:** 모든 새로운 기능 개발(`feature/`)은 반드시 `develop` 브랜치에서 시작한다.
2. **Protected Branch:** `develop` 브랜치로의 직접적인 push는 지양하며, 반드시 기능 브랜치에서 작업 후 검증 과정을 거쳐 머지한다.
3. **Parallel Development:** 여러 기능을 동시 개발할 경우 `git-worktrees`를 사용하여 환경을 격리한다.
4. **Merge Process:** - 작업 완료 후 `verification-before-completion` 스킬로 검증한다.
   - 검증 완료 후 `finishing-a-development-branch` 스킬을 사용하여 `develop`에 머지한다.

## 🤖 Claude Code Skill Usage
- 병렬 작업 시: `dispatching-parallel-agents` 사용.
- 고속 구현 필요 시: `ultrawork` 또는 `autopilot` 모드 활용.
- 품질 검증 시: `ultraqa` 스킬로 테스트 사이클 반복.