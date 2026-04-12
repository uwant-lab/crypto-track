# 거래 내역 엑셀(.xlsx) 내보내기

## 목적
현재 조회된 거래 내역(체결/입금)을 거래소별 시트로 분리한 .xlsx 파일로 내보낸다.

## 내보내기 대상
- 현재 화면에 조회된 데이터만 내보냄 (API 재호출 없음)
- 선택된 탭에 따라 체결 내역 또는 입금 내역을 내보냄

## 시트 구조
- **거래소별로 시트 분리** (예: "Upbit", "Bithumb", "Binance")
- 데이터가 있는 거래소만 시트 생성
- 각 시트 내에서 `구분(side)` 컬럼으로 매수/매도 필터링 가능

### 체결 내역 컬럼

| 컬럼명 | 원본 필드 | 비고 |
|--------|----------|------|
| 체결일시 | `executedAt` | `yyyy-MM-dd HH:mm:ss` |
| 코인 | `symbol` | |
| 구분 | `side` | 매수/매도 |
| 체결가격 | `price` | |
| 체결수량 | `amount` | |
| 체결금액 | `totalValue` | |
| 수수료 | `fee` | |

### 입금 내역 컬럼

| 컬럼명 | 원본 필드 | 비고 |
|--------|----------|------|
| 입금일시 | `completedAt` | `yyyy-MM-dd HH:mm:ss` |
| 코인 | `symbol` | |
| 유형 | `type` | 암호화폐/원화 |
| 수량 | `amount` | |
| 상태 | `status` | 완료/대기/취소 |
| TxID | `txId` | |

## 구현 방식

### XLSXWriter (신규)
- 경로: `CryptoTrack/Services/Export/XLSXWriter.swift`
- .xlsx = ZIP 안에 XML 파일들로 구성
- Foundation만 사용, 외부 라이브러리 없음
- 필요한 XML 파일:
  - `[Content_Types].xml` - 콘텐츠 타입 정의
  - `_rels/.rels` - 관계 정의
  - `xl/workbook.xml` - 워크북 (시트 목록)
  - `xl/_rels/workbook.xml.rels` - 워크북 관계
  - `xl/styles.xml` - 기본 스타일 (헤더 볼드)
  - `xl/sharedStrings.xml` - 공유 문자열 테이블
  - `xl/worksheets/sheet{N}.xml` - 각 시트 데이터

### TransactionExporter (신규)
- 경로: `CryptoTrack/Services/Export/TransactionExporter.swift`
- `Order` / `Deposit` 배열을 거래소별로 그룹핑
- XLSXWriter를 사용해 .xlsx 데이터 생성
- `Data` 반환 (파일 저장은 호출자 책임)

### ViewModel 변경
- `TransactionHistoryViewModel`에 `exportToExcel() -> URL?` 메서드 추가
- 임시 디렉토리에 파일 저장 후 URL 반환

### UI 변경
- `TransactionHistoryView` 툴바에 내보내기 버튼 추가
- 조회된 데이터가 있을 때만 활성화
- macOS: `NSSavePanel`로 저장 위치 선택
- iOS: `ShareLink` 또는 `UIActivityViewController`

## 파일 명명 규칙
- `CryptoTrack_체결내역_2026-04-12.xlsx`
- `CryptoTrack_입금내역_2026-04-12.xlsx`
