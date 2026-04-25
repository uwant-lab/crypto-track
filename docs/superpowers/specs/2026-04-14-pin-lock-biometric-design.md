# PIN 잠금 & 생체인증 설계 문서

> 날짜: 2026-04-14
> 상태: 승인됨

## 개요

설정 화면에 **4자리 숫자 PIN 잠금**과 **생체인증(Face ID/Touch ID) 편의 해제** 기능을 추가한다. PIN이 기본 인증 수단이고, 생체인증은 PIN 설정 후 선택적으로 활성화할 수 있는 편의 바로가기다.

## 요구사항

### 핵심 요구사항
- 4자리 고정 숫자 PIN으로 앱 잠금
- PIN이 기본, 생체인증은 PIN 대신 쓸 수 있는 편의 옵션
- 보안 설정 전체를 하나의 모달로 관리
- 데스크탑에서도 모달 UI 사용
- 기존 코드의 사이드 이펙트 최소화

### 세부 정책
- PIN 틀렸을 때 횟수 제한 없음 (에러 피드백만 표시)
- 앱이 백그라운드로 전환되면 즉시 잠금 (기존 동작 유지)
- PIN 변경은 현재 PIN 입력 후에만 가능
- PIN 분실 시 별도 복구 수단 없음 (앱 재설치로 초기화)

## 아키텍처

### 접근 방식: 기존 AppLockManager 확장

기존 검증된 코드를 유지하면서 필요한 만큼만 확장한다.

### 서비스 레이어

| 서비스 | 역할 | 변경 |
|--------|------|------|
| **PINService** | PIN 해싱, Keychain 저장/검증, PIN 설정 여부 확인 | 신규 생성 |
| **AppLockManager** | 잠금 상태 관리, PIN/생체인증 흐름 분기 | 확장 수정 |
| **BiometricAuthService** | Face ID / Touch ID 인증 실행 | 변경 없음 |
| **KeychainService** | Keychain 읽기/쓰기 | 변경 없음 |

### 잠금 해제 흐름

```
앱 진입 → PIN 설정됨?
  ├─ 생체인증 ON → 생체인증 시도 → 성공 → 잠금 해제
  │                              → 실패 → PIN 패드
  └─ 생체인증 OFF → PIN 패드 → 성공 → 잠금 해제
```

### 설정 흐름

```
설정 > 보안 클릭 → 보안 모달 열기
  ├─ PIN 설정 / 변경 / 해제
  └─ 생체인증 ON/OFF 토글
```

## PIN 보안

### 저장 방식
- PIN 원문은 절대 저장하지 않음
- SHA-256 + 랜덤 salt로 해싱
- Keychain에 저장 (account: `security`, keys: `pin.hash`, `pin.salt`)
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` 접근 레벨 (기존 KeychainService 정책)

### 검증 흐름
1. 사용자가 4자리 입력
2. Keychain에서 salt 읽기
3. 입력값 + salt로 SHA-256 해시 생성
4. Keychain에 저장된 해시와 비교
5. 일치하면 잠금 해제, 불일치하면 에러 피드백

## UI 설계

### 보안 설정 모달 (SecuritySettingsModal)

설정 > 보안 항목 클릭 시 `.sheet()`로 표시되는 모달. 가로 약 420px, 화면 중앙에 오버레이.

**PIN 미설정 상태:**
- 앱 잠금 섹션: "PIN 잠금 설정" + [설정] 버튼
- 편의 기능 섹션: "Touch ID로 잠금 해제" (비활성, PIN 먼저 설정 필요 안내)
- 하단 안내: "앱이 백그라운드로 전환되면 자동으로 잠깁니다"

**PIN 설정 완료 상태:**
- 앱 잠금 섹션: "PIN 잠금" 토글(ON) + "PIN 변경" 메뉴
- 편의 기능 섹션: "Touch ID로 잠금 해제" 토글 (활성화 가능)
- 위험 영역 섹션: "PIN 해제" (현재 PIN 입력 후 해제)

### PIN 입력 화면 (PINInputView)

보안 모달 내부의 NavigationStack에서 push되는 화면. 모달 콘텐츠가 PIN 입력 화면으로 전환되며, 뒤로가기로 보안 설정 목록으로 복귀한다. 320px 너비.

**구성 요소:**
- 뒤로가기 버튼 + 제목
- 안내 텍스트 (용도별 변경: "새 PIN 입력", "PIN 다시 입력", "현재 PIN 입력")
- 4개 점 인디케이터 (빈 원 → 채워진 원, 에러 시 빨간색)
- 3x4 숫자 패드 (1-9, 0, 백스페이스)

**사용 시나리오:**
- PIN 설정: 새 PIN 입력 → 확인 입력 (2단계)
- PIN 변경: 현재 PIN → 새 PIN → 확인 (3단계)
- PIN 해제: 현재 PIN 입력 (1단계)

### 숫자 패드 (PINPadView)

재사용 가능한 독립 컴포넌트. 숫자 버튼 탭 시 콜백으로 입력값 전달.

### 잠금 해제 화면 (LockScreenView 수정)

기존 LockScreenView를 확장하여 PIN 패드를 통합.

**구성 요소:**
- 앱 아이콘 (상단)
- "PIN을 입력하세요" 안내
- 4개 점 인디케이터
- 숫자 패드
- 하단: "Touch ID로 해제" 바로가기 (생체인증 ON인 경우에만 표시)

**에러 상태:**
- 점 인디케이터 빨간색 + shake 애니메이션
- "PIN이 일치하지 않습니다" 텍스트

## 상태 관리

### AppLockManager 확장

| 속성 | 타입 | 저장소 | 용도 |
|------|------|--------|------|
| `isLocked` | `Bool` | 메모리 | 현재 잠금 상태 |
| `isPINSet` | computed `Bool` | Keychain 조회 | PIN 설정 여부 |
| `isBiometricEnabled` | `Bool` | UserDefaults | 생체인증 사용 여부 |

기존 `isAppLockEnabled`는 `isPINSet`으로 대체한다. PIN이 설정되면 앱 잠금이 활성화된 것이며, PIN을 해제하면 앱 잠금도 해제된다. `isPINSet`은 KeychainService의 캐시를 통해 조회하므로 매번 Keychain I/O가 발생하지 않는다.

**마이그레이션:** 기존 `isAppLockEnabled` UserDefaults 키와 `AppSettings.isAppLockEnabled` 필드는 제거한다. PIN 존재 여부가 곧 앱 잠금 활성화 상태이므로 별도 플래그가 불필요하다.

### AppSettings 모델 변경

- `isAppLockEnabled` 필드 제거 (PIN 존재 여부로 대체)
- `isBiometricEnabled` 필드 추가
- iCloud 동기화는 `isBiometricEnabled`만 대상. PIN 해시는 동기화하지 않는다 (디바이스별 Keychain에만 저장).

## 에러 처리

| 상황 | 처리 |
|------|------|
| PIN 불일치 (잠금 해제) | 빨간 점 + shake 애니메이션 + "PIN이 일치하지 않습니다" |
| PIN 확인 불일치 (설정 시) | "PIN이 일치하지 않습니다. 다시 입력하세요" + 첫 단계로 복귀 |
| Keychain 저장 실패 | Alert "PIN 설정에 실패했습니다. 다시 시도해주세요" |
| 생체인증 실패 | PIN 패드로 자동 전환 |
| 생체인증 불가 기기 | 생체인증 토글 숨김, PIN만 표시 |

## 파일 변경 목록

### 신규 파일

| 파일 | 위치 | 역할 |
|------|------|------|
| `PINService.swift` | `Services/Auth/` | PIN 해싱, 저장, 검증 |
| `SecuritySettingsModal.swift` | `Views/Settings/` | 보안 설정 전용 모달 |
| `PINInputView.swift` | `Views/Auth/` | PIN 입력 화면 (설정/변경/해제) |
| `PINPadView.swift` | `Views/Auth/` | 재사용 가능한 숫자 패드 컴포넌트 |

### 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `AppLockManager.swift` | `isPINSet` computed property, `isBiometricEnabled` 상태, `unlock()` 분기 로직 |
| `LockScreenView.swift` | PIN 패드 통합, 생체인증 바로가기 버튼 추가 |
| `SettingsView.swift` | `SecuritySectionView`를 모달 트리거로 변경 |
| `AppSettings.swift` | `isBiometricEnabled` 필드 추가 |

### 변경 없는 파일

| 파일 | 이유 |
|------|------|
| `BiometricAuthService.swift` | 기존 API 그대로 사용 |
| `KeychainService.swift` | 기존 API 그대로 사용 |
| `CryptoTrackApp.swift` | LockScreenView가 내부적으로 분기 처리 |
