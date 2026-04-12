# 체결 내역 UI 개선 설계

## 목적
체결 내역 조회 결과에 매수/매도 필터링과 심볼별 요약 테이블을 추가하여 사용자가 거래 현황을 한눈에 파악할 수 있도록 한다.

## 설계

### 1. 매수/매도 필터 — 토글 칩

**위치**: 조회 결과 리스트 상단 (OrderListView 내부)

**동작**:
- `✓ 매수` `✓ 매도` 두 개의 토글 칩 배치
- 기본값: 둘 다 선택 (전체 표시)
- 하나를 끄면 해당 유형 숨김
- 최소 하나는 항상 선택된 상태 유지 (둘 다 끌 수 없음)
- 칩 옆에 필터링 후 건수 표시: `총 N건`
- 클라이언트 사이드 필터링 (재조회 불필요)

**ViewModel 변경**:
- `showBuy: Bool = true` 추가
- `showSell: Bool = true` 추가
- `filteredOrders: [Order]` computed property 추가 (showBuy/showSell 기반)
- `filteredGroupedOrders` computed property 추가 (filteredOrders 기반 그룹핑)

### 2. 접이식 요약 섹션

**위치**: 토글 칩 바로 아래, 리스트 위

**접힌 상태** (기본):
- 한 줄 요약 바: `▶ 요약 | 매수 ₩총매수금액 | 매도 ₩총매도금액 | 수수료 ₩총수수료 | N건`
- 클릭하면 펼침

**펼친 상태**:
- 심볼별 테이블:
  | 심볼 | 매수 수량 | 매수 금액 | 매도 수량 | 매도 금액 | 수수료 |
  |------|----------|----------|----------|----------|--------|
  | BTC  | 0.1523   | ₩12.5M   | 0.0382   | ₩3.2M    | ₩15.7K |
  | ETH  | 1.82     | ₩5.8M    | 0.35     | ₩1.1M    | ₩6.9K  |
  | **합계** |      | **₩18.3M** |        | **₩4.3M** | **₩22.6K** |
- 매수/매도 필터에 연동 (매수만 보기 시 요약도 매수 컬럼만 표시)

**ViewModel 변경**:
- `OrderSymbolSummary` 구조체: symbol, buyAmount, buyTotal, sellAmount, sellTotal, fee
- `orderSummary: [OrderSymbolSummary]` computed property 추가
- `totalBuyValue`, `totalSellValue`, `totalFee` computed properties

### 3. 수정 파일

| 파일 | 변경 내용 |
|------|----------|
| `TransactionHistoryViewModel` | showBuy, showSell, filteredOrders, orderSummary 추가 |
| `OrderListView` | 토글 칩 UI, 접이식 요약 섹션 추가, groupedOrders → filteredGroupedOrders |
| `TransactionHistoryView` | 새 프로퍼티(showBuy, showSell, summary) 전달 |

새 파일 생성 없음. 기존 파일만 수정.
