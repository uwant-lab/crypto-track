# ExchangeSetupView macOS 리디자인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ExchangeSetupView를 macOS 시스템 환경설정 스타일로 리디자인하여, Grid 기반 레이블-필드 정렬, GroupBox 섹션 구분, 적절한 너비 제한을 적용한다.

**Architecture:** 기존 `ExchangeSetupView.swift`를 전면 교체한다. ViewModel과 비즈니스 로직은 변경 없이 View 레이어만 교체한다. macOS에서는 `Form` 대신 `ScrollView` + `GroupBox` + `Grid`를 사용하고, iOS에서는 기존 `Form` 레이아웃을 유지하기 위해 `#if os(macOS)` 분기를 사용한다.

**Tech Stack:** SwiftUI, Grid, GroupBox, `#if os(macOS)` conditional compilation

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `CryptoTrack/Views/Settings/ExchangeSetupView.swift` | macOS용 전체 UI 리디자인 |

기존 파일 1개만 수정한다. 새 파일 생성 없음.

---

### Task 1: macOS용 헤더 섹션 구현

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift:80-98`

- [ ] **Step 1: 기존 guideSection을 exchangeHeader로 교체**

`ExchangeSetupView`의 `guideSection`을 거래소 아이콘 + 이름 + 상태 뱃지를 표시하는 헤더로 교체한다. macOS 전용 `body`를 새로 작성하기 위해, 먼저 macOS용 헤더 컴포넌트를 추가한다.

`ExchangeSetupView.swift`의 `// MARK: - Sections` 아래, 기존 `guideSection` 바로 위에 macOS 전용 헤더를 추가한다:

```swift
// MARK: - macOS Components

#if os(macOS)
private var macHeader: some View {
    HStack(spacing: 14) {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColor.exchange(exchange).opacity(0.15))
                .frame(width: 48, height: 48)
            Text(String(exchange.rawValue.prefix(1)))
                .font(.title2.bold())
                .foregroundStyle(AppColor.exchange(exchange))
        }

        VStack(alignment: .leading, spacing: 4) {
            Text(exchange.rawValue)
                .font(.title2.bold())
            Text("API 키 설정")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Spacer()

        if isSaved {
            statusBadge
        }
    }
}

private var statusBadge: some View {
    HStack(spacing: 6) {
        switch connectionStatus {
        case .untested:
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            Text("미테스트")
                .foregroundStyle(.orange)
        case .testing:
            ProgressView()
                .scaleEffect(0.7)
            Text("테스트 중")
                .foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("연결됨")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text("연결 실패")
                .foregroundStyle(.red)
        }
    }
    .font(.subheadline.weight(.medium))
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.5))
    .clipShape(Capsule())
}
#endif
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "feat: add macOS header component for ExchangeSetupView"
```

---

### Task 2: macOS용 Grid 기반 키 입력 섹션 구현

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift`

- [ ] **Step 1: macOS용 credentials GroupBox 추가**

기존 `credentialsSection` 아래에 macOS 전용 Grid 기반 입력 섹션을 추가한다:

```swift
#if os(macOS)
private var macCredentialsBox: some View {
    GroupBox {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text(accessKeyLabel)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                SecureField("키를 입력하세요", text: $accessKey)
                    .textFieldStyle(.roundedBorder)
                    .gridColumnAlignment(.leading)
            }
            GridRow {
                Text(secretKeyLabel)
                    .foregroundStyle(.secondary)
                SecureField("키를 입력하세요", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
            }
            if showPassphraseField {
                GridRow {
                    Text("Passphrase")
                        .foregroundStyle(.secondary)
                    SecureField("Passphrase를 입력하세요", text: $passphrase)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(4)
    } label: {
        Label("API 키 정보", systemImage: "key.fill")
    }
}
#endif
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "feat: add macOS Grid-based credentials input section"
```

---

### Task 3: macOS용 액션 영역 구현

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift`

- [ ] **Step 1: macOS용 액션 버튼 + 연결 상태 추가**

```swift
#if os(macOS)
private var macActionArea: some View {
    VStack(spacing: 12) {
        HStack(spacing: 12) {
            Button {
                Task { await settingsViewModel.testConnection(exchange: exchange) }
            } label: {
                HStack(spacing: 6) {
                    if isTestingConnection {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text("연결 테스트")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isTestingConnection || !isSaved)

            Button {
                saveKeys()
            } label: {
                Text("저장")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(accessKey.isEmpty || secretKey.isEmpty)
        }

        if isSaved {
            macConnectionStatus
        }
    }
}

private var macConnectionStatus: some View {
    HStack(spacing: 8) {
        switch connectionStatus {
        case .untested:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
            Text("연결 테스트를 실행하세요")
                .foregroundStyle(.secondary)
        case .testing:
            ProgressView()
                .scaleEffect(0.7)
            Text("연결 확인 중...")
                .foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("연결 성공")
                .foregroundStyle(.green)
        case .failed(let message):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
        Spacer()
    }
    .font(.subheadline)
    .padding(12)
    .background(.quaternary.opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: 8))
}
#endif
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "feat: add macOS action buttons and connection status"
```

---

### Task 4: macOS용 위험 영역 + 하단 안내 구현

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift`

- [ ] **Step 1: macOS용 삭제 GroupBox + 하단 안내 추가**

```swift
#if os(macOS)
private var macDangerZone: some View {
    GroupBox {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("API 키 삭제")
                    .font(.body.weight(.medium))
                Text("Keychain에서 이 거래소의 모든 인증 정보를 제거합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("삭제")
            }
        }
        .padding(4)
    } label: {
        Label("위험 영역", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    }
}

private var macFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
        Button {
            showGuide = true
        } label: {
            Label("API 키 발급 방법 안내", systemImage: "questionmark.circle")
                .font(.subheadline)
        }
        .buttonStyle(.link)

        Label("API 키는 기기의 Keychain에 안전하게 저장됩니다.", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
#endif
```

- [ ] **Step 2: 빌드 확인**

Run: `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "feat: add macOS danger zone and footer components"
```

---

### Task 5: macOS용 body 조합 및 iOS body 분기

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift:47-78`

- [ ] **Step 1: body를 플랫폼별로 분기**

기존 `body`를 교체한다. macOS에서는 새로 만든 컴포넌트들을 조합하고, iOS에서는 기존 Form 레이아웃을 유지한다:

```swift
var body: some View {
    #if os(macOS)
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            macHeader
            macCredentialsBox
            macActionArea
            if isSaved {
                macDangerZone
            }
            macFooter
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }
    .sheet(isPresented: $showGuide) {
        if let guide = ExchangeGuide.all[exchange] {
            APIKeyGuideView(guide: guide)
        }
    }
    .navigationTitle(exchange.rawValue)
    .alert("알림", isPresented: $showAlert) {
        Button("확인", role: .cancel) {}
    } message: {
        Text(alertMessage ?? "")
    }
    .confirmationDialog(
        "\(exchange.rawValue) API 키를 삭제하시겠습니까?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
    ) {
        Button("삭제", role: .destructive) {
            deleteKeys()
        }
        Button("취소", role: .cancel) {}
    }
    #else
    Form {
        guideSection
        credentialsSection
        actionSection
        if isSaved {
            deleteSection
        }
    }
    .sheet(isPresented: $showGuide) {
        if let guide = ExchangeGuide.all[exchange] {
            APIKeyGuideView(guide: guide)
        }
    }
    .navigationTitle(exchange.rawValue)
    .inlineNavigationTitle()
    .alert("알림", isPresented: $showAlert) {
        Button("확인", role: .cancel) {}
    } message: {
        Text(alertMessage ?? "")
    }
    .confirmationDialog(
        "\(exchange.rawValue) API 키를 삭제하시겠습니까?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
    ) {
        Button("삭제", role: .destructive) {
            deleteKeys()
        }
        Button("취소", role: .cancel) {}
    }
    #endif
}
```

- [ ] **Step 2: 빌드 확인 (macOS + iOS)**

Run (macOS): `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Run (iOS): `xcodebuild -project CryptoTrack.xcodeproj -scheme CryptoTrack_iOS -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "feat: wire up macOS layout with platform-conditional body"
```

---

### Task 6: 시각 확인 및 미세 조정

**Files:**
- Modify: `CryptoTrack/Views/Settings/ExchangeSetupView.swift`

- [ ] **Step 1: macOS에서 앱을 실행하여 시각적으로 확인**

`CryptoTrack_macOS` 스킴으로 빌드/실행하여 다음을 확인한다:
- 헤더의 거래소 아이콘, 이름, 상태 뱃지 표시
- Grid 레이블이 오른쪽 정렬, 필드가 왼쪽 정렬
- 저장/연결 테스트 버튼이 나란히 배치
- 삭제 GroupBox가 빨간색 톤
- 전체 콘텐츠 너비가 480px 제한, 중앙 정렬
- ScrollView로 콘텐츠 넘칠 때 스크롤 가능

- [ ] **Step 2: 필요 시 여백/간격 미세 조정**

시각 확인 결과에 따라 padding, spacing 값을 조정한다.

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/Views/Settings/ExchangeSetupView.swift
git commit -m "style: fine-tune macOS ExchangeSetupView layout spacing"
```
