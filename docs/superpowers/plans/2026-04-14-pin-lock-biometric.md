# PIN 잠금 & 생체인증 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설정 화면에 4자리 PIN 잠금과 생체인증 편의 해제 기능을 추가한다.

**Architecture:** 기존 AppLockManager를 확장하고, 신규 PINService로 해싱/검증을 담당. 보안 설정은 모달로 분리. BiometricAuthService와 KeychainService는 변경 없이 기존 API를 그대로 사용한다.

**Tech Stack:** SwiftUI, CryptoKit (SHA-256), LocalAuthentication, Keychain Services

**Spec:** `docs/superpowers/specs/2026-04-14-pin-lock-biometric-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `CryptoTrack/Services/Auth/PINService.swift` | PIN 해싱(SHA-256+salt), Keychain 저장/검증, PIN 존재 확인 |
| `CryptoTrack/Views/Auth/PINPadView.swift` | 재사용 숫자 패드 + 점 인디케이터 컴포넌트 |
| `CryptoTrack/Views/Auth/PINInputView.swift` | PIN 설정/변경/해제 플로우 화면 |
| `CryptoTrack/Views/Settings/SecuritySettingsModal.swift` | 보안 설정 전용 모달 (NavigationStack 포함) |
| `CryptoTrackTests/PINServiceTests.swift` | PINService 단위 테스트 |

### Modified Files

| File | Changes |
|------|---------|
| `CryptoTrack/Models/AppSettings.swift` | `isAppLockEnabled` 제거, `isBiometricEnabled` 추가, 하위호환 디코딩 |
| `CryptoTrack/Services/Auth/AppLockManager.swift` | `isPINSet`/`isBiometricEnabled`/`refreshPINState()` 추가, unlock 분기 |
| `CryptoTrack/Views/Auth/LockScreenView.swift` | PIN 패드 + 생체인증 바로가기 통합 |
| `CryptoTrack/Views/Settings/SettingsView.swift` | SecuritySectionView를 모달 트리거로 교체 |

### Unchanged Files

| File | Reason |
|------|--------|
| `BiometricAuthService.swift` | 기존 API 그대로 사용 |
| `KeychainService.swift` | 기존 API 그대로 사용 |
| `CryptoTrackApp.swift` | LockScreenView 내부에서 분기 처리 |

---

## Task 1: PINService 생성 및 테스트

**Files:**
- Create: `CryptoTrack/Services/Auth/PINService.swift`
- Create: `CryptoTrackTests/PINServiceTests.swift`

- [ ] **Step 1: PINServiceTests 작성 (실패하는 테스트)**

```swift
// CryptoTrackTests/PINServiceTests.swift
import XCTest
@testable import CryptoTrack

final class PINServiceTests: XCTestCase {

    private let pinService = PINService.shared

    override func setUp() {
        super.setUp()
        try? pinService.deletePIN()
    }

    override func tearDown() {
        try? pinService.deletePIN()
        super.tearDown()
    }

    func testInitiallyNoPINSet() {
        XCTAssertFalse(pinService.isPINSet)
    }

    func testSetAndVerifyPIN() throws {
        try pinService.setPIN("1234")
        XCTAssertTrue(pinService.isPINSet)
        XCTAssertTrue(pinService.verifyPIN("1234"))
    }

    func testWrongPINFails() throws {
        try pinService.setPIN("1234")
        XCTAssertFalse(pinService.verifyPIN("5678"))
        XCTAssertFalse(pinService.verifyPIN("0000"))
    }

    func testDeletePIN() throws {
        try pinService.setPIN("1234")
        XCTAssertTrue(pinService.isPINSet)
        try pinService.deletePIN()
        XCTAssertFalse(pinService.isPINSet)
    }

    func testChangePIN() throws {
        try pinService.setPIN("1234")
        try pinService.setPIN("5678")
        XCTAssertFalse(pinService.verifyPIN("1234"))
        XCTAssertTrue(pinService.verifyPIN("5678"))
    }

    func testVerifyWithNoPINReturnsFalse() {
        XCTAssertFalse(pinService.verifyPIN("1234"))
    }
}
```

- [ ] **Step 2: 테스트 실행 — 컴파일 실패 확인**

Run: `xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -only-testing CryptoTrackTests_macOS/PINServiceTests 2>&1 | tail -5`
Expected: Compile error — `PINService` not found

- [ ] **Step 3: PINService 구현**

```swift
// CryptoTrack/Services/Auth/PINService.swift
import Foundation
import CryptoKit

final class PINService: @unchecked Sendable {
    static let shared = PINService()

    private let keychain = KeychainService.shared
    private static let account = "security"
    private static let hashKey = "pin.hash"
    private static let saltKey = "pin.salt"

    private init() {}

    /// PIN이 설정되어 있는지 확인합니다. KeychainService 캐시를 통해 조회합니다.
    var isPINSet: Bool {
        (try? keychain.read(key: Self.hashKey, account: Self.account)) != nil
    }

    /// 새 PIN을 해싱하여 Keychain에 저장합니다.
    func setPIN(_ pin: String) throws {
        let salt = generateSalt()
        let hash = hashPIN(pin, salt: salt)
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
```

- [ ] **Step 4: 테스트 실행 — 모두 통과 확인**

Run: `xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -only-testing CryptoTrackTests_macOS/PINServiceTests 2>&1 | tail -10`
Expected: All 6 tests PASS

- [ ] **Step 5: 커밋**

```bash
git add CryptoTrack/Services/Auth/PINService.swift CryptoTrackTests/PINServiceTests.swift
git commit -m "feat(auth): PINService 추가 — SHA-256+salt 해싱, Keychain 저장/검증"
```

---

## Task 2: AppSettings 모델 마이그레이션

**Files:**
- Modify: `CryptoTrack/Models/AppSettings.swift`

- [ ] **Step 1: AppSettings 수정 — isAppLockEnabled 제거, isBiometricEnabled 추가**

`CryptoTrack/Models/AppSettings.swift` 전체를 아래로 교체:

```swift
import Foundation

/// iCloud 동기화되는 앱 설정 모델입니다.
struct AppSettings: Codable, Sendable {
    var isBiometricEnabled: Bool
    var lastSyncDate: Date
    var priceColorMode: PriceColorMode

    init(
        isBiometricEnabled: Bool = false,
        lastSyncDate: Date = .distantPast,
        priceColorMode: PriceColorMode = .korean
    ) {
        self.isBiometricEnabled = isBiometricEnabled
        self.lastSyncDate = lastSyncDate
        self.priceColorMode = priceColorMode
    }

    enum CodingKeys: String, CodingKey {
        case isBiometricEnabled
        case lastSyncDate
        case priceColorMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isBiometricEnabled = try container.decodeIfPresent(Bool.self, forKey: .isBiometricEnabled) ?? false
        self.lastSyncDate = try container.decodeIfPresent(Date.self, forKey: .lastSyncDate) ?? .distantPast
        self.priceColorMode = try container.decodeIfPresent(PriceColorMode.self, forKey: .priceColorMode) ?? .korean
    }
}
```

- [ ] **Step 2: 빌드 확인 — 컴파일 에러 발생 예상**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep error: | head -10`
Expected: `AppLockManager.swift`에서 `isAppLockEnabled` 참조 에러. 이는 Task 3에서 해결한다.

- [ ] **Step 3: 커밋 (빌드 미통과 상태, Task 3과 atomic으로 묶을 수 있음)**

```bash
git add CryptoTrack/Models/AppSettings.swift
git commit -m "refactor(model): AppSettings에서 isAppLockEnabled 제거, isBiometricEnabled 추가"
```

---

## Task 3: AppLockManager 확장

**Files:**
- Modify: `CryptoTrack/Services/Auth/AppLockManager.swift`

- [ ] **Step 1: AppLockManager 전체 교체**

`CryptoTrack/Services/Auth/AppLockManager.swift` 전체를 아래로 교체:

```swift
import SwiftUI
import Observation

@Observable
@MainActor
final class AppLockManager {
    static let shared = AppLockManager()

    var isLocked: Bool = false
    private(set) var isPINSet: Bool = false

    var isBiometricEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometricEnabled, forKey: Self.biometricEnabledKey)
            let settings = AppSettings(isBiometricEnabled: isBiometricEnabled, lastSyncDate: Date())
            CloudSyncService.shared.syncSettings(settings)
        }
    }

    private static let biometricEnabledKey = "biometricEnabled"
    private let authService = BiometricAuthService.shared
    private let pinService = PINService.shared

    private init() {
        self.isBiometricEnabled = UserDefaults.standard.bool(forKey: Self.biometricEnabledKey)
        self.isPINSet = pinService.isPINSet
        if isPINSet {
            self.isLocked = true
        }
        syncFromCloud()
    }

    // MARK: - PIN State

    /// PINService의 상태를 읽어 isPINSet을 갱신합니다.
    /// PIN 설정/변경/해제 후 호출해야 SwiftUI가 변경을 감지합니다.
    func refreshPINState() {
        isPINSet = pinService.isPINSet
    }

    // MARK: - Cloud Sync

    func syncFromCloud() {
        guard let settings = CloudSyncService.shared.loadSettings() else { return }
        let cloudValue = settings.isBiometricEnabled
        guard cloudValue != isBiometricEnabled else { return }
        isBiometricEnabled = cloudValue
        UserDefaults.standard.set(isBiometricEnabled, forKey: Self.biometricEnabledKey)
    }

    // MARK: - Unlock

    /// PIN으로 잠금 해제를 시도합니다. 성공하면 true를 반환합니다.
    func unlockWithPIN(_ pin: String) -> Bool {
        guard pinService.verifyPIN(pin) else { return false }
        performUnlock()
        return true
    }

    /// 생체인증으로 잠금 해제를 시도합니다. 성공하면 true를 반환합니다.
    func unlockWithBiometrics() async -> Bool {
        guard isBiometricEnabled, authService.canUseBiometrics() else { return false }
        do {
            let success = try await authService.authenticate()
            if success {
                performUnlock()
                return true
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Lock

    func lock() {
        guard isPINSet else { return }
        isLocked = true
        KeychainService.shared.invalidateCache()
    }

    // MARK: - Private

    private func performUnlock() {
        isLocked = false
        ExchangeManager.shared.preloadKeychainCache()
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep error: | head -10`
Expected: `SettingsView.swift`에서 `isAppLockEnabled`/`toggleAppLock` 참조 에러. 이는 Task 7에서 해결한다. 그 외 에러 없어야 함.

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Services/Auth/AppLockManager.swift
git commit -m "refactor(auth): AppLockManager를 PIN 기반으로 전환 — unlockWithPIN/unlockWithBiometrics"
```

---

## Task 4: PINPadView & PINDotsView 생성

**Files:**
- Create: `CryptoTrack/Views/Auth/PINPadView.swift`

- [ ] **Step 1: PINPadView.swift 작성**

```swift
// CryptoTrack/Views/Auth/PINPadView.swift
import SwiftUI

// MARK: - PIN Dots Indicator

struct PINDotsView: View {
    let enteredCount: Int
    let totalDigits: Int
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<totalDigits, id: \.self) { index in
                Circle()
                    .fill(dotFill(at: index))
                    .frame(width: 14, height: 14)
                    .overlay {
                        if index >= enteredCount && !isError {
                            Circle()
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                        }
                    }
            }
        }
    }

    private func dotFill(at index: Int) -> Color {
        if isError { return .red }
        return index < enteredCount ? .accentColor : .clear
    }
}

// MARK: - Number Pad

struct PINPadView: View {
    let onNumberTap: (Int) -> Void
    let onDeleteTap: () -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
            spacing: 10
        ) {
            ForEach(1...9, id: \.self) { number in
                numberButton(number)
            }
            Color.clear.frame(height: 52)
            numberButton(0)
            deleteButton
        }
        .frame(maxWidth: 240)
    }

    private func numberButton(_ number: Int) -> some View {
        Button {
            onNumberTap(number)
        } label: {
            Text("\(number)")
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppColor.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button {
            onDeleteTap()
        } label: {
            Image(systemName: "delete.backward")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("PINPad") {
    VStack(spacing: 32) {
        PINDotsView(enteredCount: 2, totalDigits: 4)
        PINPadView(onNumberTap: { _ in }, onDeleteTap: {})
    }
    .padding()
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep 'PINPadView\|PINDotsView' | head -5`
Expected: SettingsView 에러만 남아있고 PINPadView 관련 에러는 없어야 함

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Auth/PINPadView.swift
git commit -m "feat(ui): PINPadView & PINDotsView 컴포넌트 추가"
```

---

## Task 5: PINInputView 생성

**Files:**
- Create: `CryptoTrack/Views/Auth/PINInputView.swift`

- [ ] **Step 1: PINInputView.swift 작성**

```swift
// CryptoTrack/Views/Auth/PINInputView.swift
import SwiftUI

enum PINFlowMode: Hashable {
    case setup
    case change
    case remove
}

struct PINInputView: View {
    let mode: PINFlowMode
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: String = ""
    @State private var step: Step = .initial
    @State private var newPIN: String = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var alertMessage: String?
    @State private var showAlert = false

    private let pinService = PINService.shared
    private let pinLength = 4

    private enum Step {
        case initial
        case enterNew
        case confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            instructionSection
                .padding(.bottom, 24)

            PINDotsView(
                enteredCount: pin.count,
                totalDigits: pinLength,
                isError: errorMessage != nil
            )
            .offset(x: shakeOffset)
            .padding(.bottom, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Spacer()

            PINPadView(
                onNumberTap: { handleNumberInput($0) },
                onDeleteTap: { handleDelete() }
            )
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
        .navigationTitle(titleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
        }
        .alert("오류", isPresented: $showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Text

    private var titleText: String {
        switch mode {
        case .setup: "PIN 설정"
        case .change: "PIN 변경"
        case .remove: "PIN 해제"
        }
    }

    private var instructionText: String {
        switch (mode, step) {
        case (.setup, .initial): "새로운 PIN을 입력하세요"
        case (.setup, .confirm): "PIN을 다시 입력하세요"
        case (.change, .initial): "현재 PIN을 입력하세요"
        case (.change, .enterNew): "새로운 PIN을 입력하세요"
        case (.change, .confirm): "PIN을 다시 입력하세요"
        case (.remove, .initial): "현재 PIN을 입력하세요"
        default: ""
        }
    }

    private var subtitleText: String {
        switch (mode, step) {
        case (.setup, .initial): "4자리 숫자"
        case (.setup, .confirm): "확인을 위해 한 번 더 입력해주세요"
        case (.change, .initial): "변경을 위해 현재 PIN을 입력해주세요"
        case (.change, .enterNew): "4자리 숫자"
        case (.change, .confirm): "확인을 위해 한 번 더 입력해주세요"
        case (.remove, .initial): "해제를 위해 현재 PIN을 입력해주세요"
        default: ""
        }
    }

    private var instructionSection: some View {
        VStack(spacing: 8) {
            Text(instructionText)
                .font(.headline)
            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Input

    private func handleNumberInput(_ number: Int) {
        guard pin.count < pinLength else { return }
        withAnimation { errorMessage = nil }
        pin += "\(number)"

        if pin.count == pinLength {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                processPIN()
            }
        }
    }

    private func handleDelete() {
        guard !pin.isEmpty else { return }
        withAnimation { errorMessage = nil }
        pin.removeLast()
    }

    // MARK: - Flow Logic

    private func processPIN() {
        switch (mode, step) {
        case (.setup, .initial):
            newPIN = pin
            pin = ""
            step = .confirm

        case (.setup, .confirm):
            if pin == newPIN {
                savePIN(pin)
            } else {
                showError("PIN이 일치하지 않습니다")
                newPIN = ""
                step = .initial
            }

        case (.change, .initial):
            if pinService.verifyPIN(pin) {
                pin = ""
                step = .enterNew
            } else {
                showError("PIN이 일치하지 않습니다")
            }

        case (.change, .enterNew):
            newPIN = pin
            pin = ""
            step = .confirm

        case (.change, .confirm):
            if pin == newPIN {
                savePIN(pin)
            } else {
                showError("PIN이 일치하지 않습니다")
                newPIN = ""
                step = .enterNew
            }

        case (.remove, .initial):
            if pinService.verifyPIN(pin) {
                do {
                    try pinService.deletePIN()
                    onComplete()
                } catch {
                    alertMessage = "PIN 해제에 실패했습니다. 다시 시도해주세요."
                    showAlert = true
                    pin = ""
                }
            } else {
                showError("PIN이 일치하지 않습니다")
            }

        default:
            break
        }
    }

    private func savePIN(_ value: String) {
        do {
            try pinService.setPIN(value)
            onComplete()
        } catch {
            let action = mode == .setup ? "설정" : "변경"
            alertMessage = "PIN \(action)에 실패했습니다. 다시 시도해주세요."
            showAlert = true
            resetFlow()
        }
    }

    private func showError(_ message: String) {
        pin = ""
        withAnimation { errorMessage = message }
        withAnimation(.default.speed(6).repeatCount(4, autoreverses: true)) {
            shakeOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { shakeOffset = 0 }
        }
    }

    private func resetFlow() {
        pin = ""
        newPIN = ""
        step = .initial
        errorMessage = nil
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep 'PINInputView' | head -5`
Expected: PINInputView 관련 에러 없음

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Auth/PINInputView.swift
git commit -m "feat(ui): PINInputView 추가 — 설정/변경/해제 플로우 지원"
```

---

## Task 6: SecuritySettingsModal 생성

**Files:**
- Create: `CryptoTrack/Views/Settings/SecuritySettingsModal.swift`

- [ ] **Step 1: SecuritySettingsModal.swift 작성**

```swift
// CryptoTrack/Views/Settings/SecuritySettingsModal.swift
import SwiftUI

struct SecuritySettingsModal: View {
    @State private var lockManager = AppLockManager.shared
    @State private var navigationPath = NavigationPath()
    @Environment(\.dismiss) private var dismiss

    private let authService = BiometricAuthService.shared

    var body: some View {
        NavigationStack(path: $navigationPath) {
            settingsContent
                .navigationTitle("보안 설정")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("완료") { dismiss() }
                    }
                }
                .navigationDestination(for: PINFlowMode.self) { mode in
                    PINInputView(mode: mode) {
                        navigationPath = NavigationPath()
                        lockManager.refreshPINState()
                        if mode == .remove {
                            lockManager.isBiometricEnabled = false
                        }
                    }
                }
        }
        .frame(idealWidth: 420, idealHeight: 500)
    }

    // MARK: - Content

    private var settingsContent: some View {
        List {
            appLockSection
            convenienceSection
            if lockManager.isPINSet {
                dangerZoneSection
            }
            Section {} footer: {
                Text("앱이 백그라운드로 전환되면 자동으로 잠깁니다.")
            }
        }
    }

    // MARK: - App Lock Section

    private var appLockSection: some View {
        Section {
            if lockManager.isPINSet {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN 잠금")
                            .font(.body)
                        Text("활성화됨")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }

                Button {
                    navigationPath.append(PINFlowMode.change)
                } label: {
                    HStack {
                        Text("PIN 변경")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    navigationPath.append(PINFlowMode.setup)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.badge.plus")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PIN 잠금 설정")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("4자리 PIN으로 앱을 보호합니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("설정")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("앱 잠금")
        }
    }

    // MARK: - Convenience Section

    private var convenienceSection: some View {
        Section {
            if lockManager.isPINSet && authService.canUseBiometrics() {
                Toggle(isOn: Binding(
                    get: { lockManager.isBiometricEnabled },
                    set: { lockManager.isBiometricEnabled = $0 }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(authService.biometricType.rawValue)로 잠금 해제")
                                .font(.body)
                            Text("PIN 대신 생체인증으로 빠르게 해제")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if lockManager.isPINSet {
                HStack(spacing: 12) {
                    Image(systemName: "lock.slash")
                        .foregroundStyle(.secondary)
                    Text("이 기기에서는 생체 인증을 사용할 수 없습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: biometricIcon)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("생체 인증으로 잠금 해제")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("PIN 설정 후 사용할 수 있습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(0.5)
            }
        } header: {
            Text("편의 기능")
        }
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        Section {
            Button {
                navigationPath.append(PINFlowMode.remove)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN 해제")
                            .font(.body)
                            .foregroundStyle(.red)
                        Text("현재 PIN 입력 후 잠금을 해제합니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("위험 영역")
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .none: "lock.fill"
        }
    }
}

#Preview {
    SecuritySettingsModal()
}
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep 'SecuritySettingsModal' | head -5`
Expected: SecuritySettingsModal 관련 에러 없음

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Settings/SecuritySettingsModal.swift
git commit -m "feat(ui): SecuritySettingsModal 추가 — 보안 설정 전용 모달"
```

---

## Task 7: SettingsView 업데이트

**Files:**
- Modify: `CryptoTrack/Views/Settings/SettingsView.swift`

- [ ] **Step 1: SecuritySectionView를 모달 트리거로 교체**

`SettingsView.swift`에서 기존 `SecuritySectionView(lockManager: lockManager)` 호출부와 `SecuritySectionView` struct 전체를 교체한다.

SettingsView의 body에서 변경:

```swift
// 기존 코드 (삭제):
SecuritySectionView(lockManager: lockManager)

// 새 코드 (교체):
SecuritySettingsTriggerView(lockManager: lockManager)
```

SettingsView에 `@State private var showSecuritySettings = false` 추가는 불필요 — 별도 View로 분리.

기존 `SecuritySectionView` 전체(line 119~171)를 아래로 교체:

```swift
// MARK: - Security Section (Modal Trigger)

private struct SecuritySettingsTriggerView: View {
    var lockManager: AppLockManager
    @State private var showModal = false

    var body: some View {
        Section {
            Button {
                showModal = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("보안")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text(lockManager.isPINSet ? "PIN 잠금 활성화됨" : "잠금 미설정")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showModal) {
                SecuritySettingsModal()
            }
        } header: {
            Text("보안")
        } footer: {
            if lockManager.isPINSet {
                Text("앱이 백그라운드로 이동하면 자동으로 잠깁니다.")
            }
        }
    }
}
```

- [ ] **Step 2: 빌드 확인 — 에러 없음**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep error: | head -10`
Expected: 에러 없음 (warning은 무시)

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Settings/SettingsView.swift
git commit -m "refactor(settings): 보안 섹션을 SecuritySettingsModal 트리거로 교체"
```

---

## Task 8: LockScreenView 업데이트

**Files:**
- Modify: `CryptoTrack/Views/Auth/LockScreenView.swift`

- [ ] **Step 1: LockScreenView 전체 교체**

`CryptoTrack/Views/Auth/LockScreenView.swift` 전체를 아래로 교체:

```swift
import SwiftUI

struct LockScreenView: View {
    @State private var lockManager = AppLockManager.shared
    @State private var pin: String = ""
    @State private var errorMessage: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var isAuthenticating = false

    private let authService = BiometricAuthService.shared
    private let pinLength = 4

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                appIconSection
                    .padding(.bottom, 24)

                Text("PIN을 입력하세요")
                    .font(.headline)
                    .padding(.bottom, 24)

                PINDotsView(
                    enteredCount: pin.count,
                    totalDigits: pinLength,
                    isError: errorMessage != nil
                )
                .offset(x: shakeOffset)
                .padding(.bottom, 8)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity)
                }

                Spacer()

                PINPadView(
                    onNumberTap: { handleNumberInput($0) },
                    onDeleteTap: { handleDelete() }
                )

                if lockManager.isBiometricEnabled && authService.canUseBiometrics() {
                    Button {
                        Task { await attemptBiometric() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: biometricIcon)
                            Text("\(authService.biometricType.rawValue)로 해제")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                    }
                    .disabled(isAuthenticating)
                    .padding(.top, 20)
                }

                Spacer()
            }
            .padding(.horizontal, 40)
        }
        .task {
            if lockManager.isBiometricEnabled && authService.canUseBiometrics() {
                await attemptBiometric()
            }
        }
    }

    // MARK: - Subviews

    private var appIconSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)

            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white)
        }
        .shadow(color: .blue.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    // MARK: - Input

    private func handleNumberInput(_ number: Int) {
        guard pin.count < pinLength else { return }
        withAnimation { errorMessage = nil }
        pin += "\(number)"

        if pin.count == pinLength {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                verifyPIN()
            }
        }
    }

    private func handleDelete() {
        guard !pin.isEmpty else { return }
        withAnimation { errorMessage = nil }
        pin.removeLast()
    }

    // MARK: - Auth

    private func verifyPIN() {
        if lockManager.unlockWithPIN(pin) {
            // Success — AppLockManager sets isLocked = false
        } else {
            pin = ""
            withAnimation { errorMessage = "PIN이 일치하지 않습니다" }
            withAnimation(.default.speed(6).repeatCount(4, autoreverses: true)) {
                shakeOffset = 8
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation { shakeOffset = 0 }
            }
        }
    }

    private func attemptBiometric() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        _ = await lockManager.unlockWithBiometrics()
    }

    private var biometricIcon: String {
        switch authService.biometricType {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .none: "lock.open.fill"
        }
    }
}

#Preview {
    LockScreenView()
}
```

- [ ] **Step 2: 전체 빌드 확인**

Run: `xcodebuild build -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | grep error: | head -10`
Expected: 빌드 성공 (에러 없음)

- [ ] **Step 3: 커밋**

```bash
git add CryptoTrack/Views/Auth/LockScreenView.swift
git commit -m "feat(ui): LockScreenView에 PIN 패드 + 생체인증 바로가기 통합"
```

---

## Task 9: 전체 테스트 실행 및 최종 검증

**Files:** None (검증만)

- [ ] **Step 1: 전체 테스트 실행**

Run: `xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS 2>&1 | tail -20`
Expected: 모든 테스트 통과 (PINServiceTests 포함)

- [ ] **Step 2: 기존 테스트 회귀 확인**

Run: `xcodebuild test -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -only-testing CryptoTrackTests_macOS 2>&1 | grep -E '(Test Suite|Executed|FAIL)'`
Expected: 모든 기존 테스트 통과. `ModelTests`에서 `AppSettings` 관련 테스트가 있다면 `isAppLockEnabled` 제거로 인해 실패할 수 있음 — 해당 테스트를 `isBiometricEnabled`로 업데이트해야 함.

- [ ] **Step 3: 앱 실행 후 수동 검증**

앱을 빌드하고 실행하여 다음 플로우를 검증:

1. 설정 > 보안 클릭 → SecuritySettingsModal 열림
2. "PIN 잠금 설정" 클릭 → PINInputView로 이동
3. 4자리 입력 → 확인 입력 → PIN 설정 완료
4. 생체인증 토글 켜기
5. 앱 백그라운드 → 잠금 화면 표시
6. 생체인증으로 해제 시도
7. PIN으로 해제 시도 (올바른 PIN)
8. PIN으로 해제 시도 (틀린 PIN → 에러 표시)
9. 설정 > 보안 > PIN 변경 → 현재 PIN → 새 PIN → 확인
10. 설정 > 보안 > PIN 해제 → 현재 PIN → 잠금 해제됨

- [ ] **Step 4: 최종 커밋 (필요시)**

테스트 수정이 있었다면:

```bash
git add -A
git commit -m "test: AppSettings 모델 변경에 따른 기존 테스트 업데이트"
```
