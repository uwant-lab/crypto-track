# 보유 비중 도넛 차트

## 개요
대시보드의 `PortfolioSummaryCard` 안에 자산 보유 비중을 도넛 차트로 시각화한다.
각 통화 그룹(KRW, USD) 별로 독립된 도넛 차트를 표시하여 해당 통화 내 코인 비중을 보여준다.

## 레이아웃

### iOS (모바일)
- 각 `SummaryBlock`(KRW/USD) 하단에 도넛 차트를 세로 배치
- Divider 아래 "보유 비중" 헤더를 탭하면 접기/펼치기 토글
- 접기 상태는 `@AppStorage`로 영속 저장
- 접힌 상태에서는 차트 영역만 숨기고 요약 정보는 유지

### macOS (데스크탑)
- `SummaryBlock` 왼쪽에 금액 정보, 오른쪽에 도넛 차트를 가로 배치
- 접기 기능 없음 (항상 표시)

## 도넛 차트 구성

### 차트 영역
- SwiftUI Shape 기반 커스텀 도넛 (Swift Charts에 도넛 타입 없음)
- 중앙 텍스트: "비중" 라벨 + 코인 종 수 (예: "5종")
- 세그먼트: 코인 개수 제한 없이 전부 표시
- 세그먼트 간 약간의 갭(1~2pt)으로 구분감 부여

### 범례
- 차트 우측(데스크탑) 또는 우측(모바일)에 세로 배치
- 각 항목: 색상 점 + 코인 심볼 + 퍼센트(%)
- `currentValue` 내림차순 정렬

### 색상
- 사전 정의된 색상 팔레트 배열에서 순서대로 할당
- iOS/macOS 다크/라이트 모드 모두에서 구분 가능한 색상 선택

## 데이터 소스

### 비중 계산
- `displayedSections`의 `PortfolioRow.currentValue` 기준
- 비중(%) = (해당 코인 currentValue / 해당 통화 그룹 총 currentValue) × 100
- dust 필터 연동: `hideDust` 적용된 행만 차트에 포함

### 통화 그룹 분리
- KRW 자산과 USD 자산이 모두 있을 때 각각 독립된 도넛 차트 표시
- 한쪽 통화 자산만 있으면 해당 차트만 표시

## 컴포넌트 구조

### 새로 생성할 파일
- `CryptoTrack/Views/Dashboard/Components/DonutChartView.swift`
  - `DonutSegment`: Shape 기반 개별 세그먼트
  - `DonutChartView`: 도넛 + 중앙 텍스트 + 범례 조합
  - `DonutLegend`: 범례 리스트

### 수정할 파일
- `CryptoTrack/Views/Dashboard/PortfolioSummaryCard.swift`
  - `SummaryBlock` 하단에 `DonutChartView` 삽입
  - iOS: 접기/펼치기 토글 추가
  - macOS: 가로 레이아웃으로 차트 배치

## 접기/펼치기 동작 (iOS만)

- `@AppStorage("donutChartExpanded")` Bool (기본값: true)
- KRW/USD 차트의 접기 상태를 공유 (하나의 토글로 모두 제어)
- "보유 비중" 텍스트 + 셰브론(▼/▶) 탭 영역
- `withAnimation` 으로 부드러운 전환

## 엣지 케이스

- 자산이 1개일 때: 도넛이 완전 원형, 범례 1줄
- 자산이 0개일 때: 차트 영역 자체를 숨김
- ticker 없는 자산(currentValue == 0): 비중 0%로 표시하되, 모든 자산이 0이면 차트 숨김
