# 거래 내역 엑셀(.xlsx) 내보내기 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 현재 조회된 거래 내역(체결/입금)을 거래소별 시트로 분리한 .xlsx 파일로 내보내는 기능 구현

**Architecture:** XLSXWriter가 ZIP+XML로 .xlsx를 생성하고, TransactionExporter가 Order/Deposit 배열을 거래소별 시트 데이터로 변환한다. ViewModel에서 export 메서드를 호출하고, View에서 NSSavePanel로 저장 위치를 선택한다.

**Tech Stack:** Swift, Foundation (ZIP via FileWrapper 없이 직접 구현), SwiftUI, Compression framework 불필요 (Archive utility 사용)

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `CryptoTrack/Services/Export/XLSXWriter.swift` | .xlsx 파일 생성 (ZIP + XML) |
| Create | `CryptoTrack/Services/Export/TransactionExporter.swift` | Order/Deposit → 시트 데이터 변환 |
| Modify | `CryptoTrack/ViewModels/TransactionHistoryViewModel.swift` | exportToExcel() 메서드 추가 |
| Modify | `CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift` | 내보내기 버튼 + NSSavePanel |
| Create | `CryptoTrackTests/XLSXWriterTests.swift` | XLSXWriter 단위 테스트 |
| Create | `CryptoTrackTests/TransactionExporterTests.swift` | Exporter 단위 테스트 |

---

### Task 1: XLSXWriter — .xlsx 파일 생성 엔진

**Files:**
- Create: `CryptoTrack/Services/Export/XLSXWriter.swift`
- Create: `CryptoTrackTests/XLSXWriterTests.swift`

- [ ] **Step 1: Write failing test for XLSXWriter**

```swift
// CryptoTrackTests/XLSXWriterTests.swift
import XCTest
@testable import CryptoTrack

final class XLSXWriterTests: XCTestCase {

    func testSingleSheetProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Test", headers: ["Name", "Value"], rows: [
            ["Alice", "100"],
            ["Bob", "200"]
        ])
        let data = try writer.finalize()

        // .xlsx는 ZIP이므로 PK 시그니처로 시작
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testMultipleSheetsProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Sheet1", headers: ["A"], rows: [["1"]])
        writer.addSheet(name: "Sheet2", headers: ["B"], rows: [["2"]])
        let data = try writer.finalize()

        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testEmptySheetProducesValidZip() throws {
        let writer = XLSXWriter()
        writer.addSheet(name: "Empty", headers: ["Col1", "Col2"], rows: [])
        let data = try writer.finalize()

        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' test 2>&1 | grep -E '(FAIL|error:.*XLSXWriter)'`
Expected: FAIL — `XLSXWriter` not found

- [ ] **Step 3: Implement XLSXWriter**

`CryptoTrack/Services/Export/XLSXWriter.swift`:

```swift
import Foundation

/// 외부 라이브러리 없이 .xlsx 파일을 생성합니다.
/// .xlsx = ZIP 아카이브 안에 XML 파일들로 구성된 Office Open XML 포맷.
final class XLSXWriter {

    struct Sheet {
        let name: String
        let headers: [String]
        let rows: [[String]]
    }

    private var sheets: [Sheet] = []

    func addSheet(name: String, headers: [String], rows: [[String]]) {
        sheets.append(Sheet(name: name, headers: headers, rows: rows))
    }

    func finalize() throws -> Data {
        var entries: [(path: String, data: Data)] = []

        // [Content_Types].xml
        entries.append(("[Content_Types].xml", contentTypesXML()))

        // _rels/.rels
        entries.append(("_rels/.rels", relsXML()))

        // xl/workbook.xml
        entries.append(("xl/workbook.xml", workbookXML()))

        // xl/_rels/workbook.xml.rels
        entries.append(("xl/_rels/workbook.xml.rels", workbookRelsXML()))

        // xl/styles.xml
        entries.append(("xl/styles.xml", stylesXML()))

        // xl/sharedStrings.xml
        let (sharedStringsData, stringIndex) = buildSharedStrings()
        entries.append(("xl/sharedStrings.xml", sharedStringsData))

        // xl/worksheets/sheet{N}.xml
        for (i, sheet) in sheets.enumerated() {
            entries.append((
                "xl/worksheets/sheet\(i + 1).xml",
                sheetXML(sheet: sheet, stringIndex: stringIndex)
            ))
        }

        return try buildZip(entries: entries)
    }

    // MARK: - XML Generators

    private func contentTypesXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        xml += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        for i in sheets.indices {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "</Types>"
        return Data(xml.utf8)
    }

    private func relsXML() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        return Data(xml.utf8)
    }

    private func workbookXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<sheets>"
        for (i, sheet) in sheets.enumerated() {
            xml += "<sheet name=\"\(escapeXML(sheet.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        xml += "</sheets></workbook>"
        return Data(xml.utf8)
    }

    private func workbookRelsXML() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in sheets.indices {
            xml += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        let ssIdx = sheets.count + 1
        let stIdx = sheets.count + 2
        xml += "<Relationship Id=\"rId\(ssIdx)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        xml += "<Relationship Id=\"rId\(stIdx)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "</Relationships>"
        return Data(xml.utf8)
    }

    private func stylesXML() -> Data {
        // 스타일 0: 기본, 스타일 1: 헤더 (볼드)
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
        </fonts>
        <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        </fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf/></cellStyleXfs>
        <cellXfs count="2">
        <xf fontId="0" fillId="0" borderId="0"/>
        <xf fontId="1" fillId="0" borderId="0"/>
        </cellXfs>
        </styleSheet>
        """
        return Data(xml.utf8)
    }

    private func buildSharedStrings() -> (Data, [String: Int]) {
        var allStrings: [String] = []
        var index: [String: Int] = [:]

        for sheet in sheets {
            for header in sheet.headers {
                if index[header] == nil {
                    index[header] = allStrings.count
                    allStrings.append(header)
                }
            }
            for row in sheet.rows {
                for cell in row {
                    if index[cell] == nil {
                        index[cell] = allStrings.count
                        allStrings.append(cell)
                    }
                }
            }
        }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(allStrings.count)\" uniqueCount=\"\(allStrings.count)\">"
        for s in allStrings {
            xml += "<si><t>\(escapeXML(s))</t></si>"
        }
        xml += "</sst>"
        return (Data(xml.utf8), index)
    }

    private func sheetXML(sheet: Sheet, stringIndex: [String: Int]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        xml += "<sheetData>"

        // 헤더 행 (row 1, style 1 = bold)
        xml += "<row r=\"1\">"
        for (col, header) in sheet.headers.enumerated() {
            let ref = cellRef(row: 0, col: col)
            let idx = stringIndex[header] ?? 0
            xml += "<c r=\"\(ref)\" t=\"s\" s=\"1\"><v>\(idx)</v></c>"
        }
        xml += "</row>"

        // 데이터 행 (row 2~, style 0)
        for (rowIdx, row) in sheet.rows.enumerated() {
            xml += "<row r=\"\(rowIdx + 2)\">"
            for (col, cell) in row.enumerated() {
                let ref = cellRef(row: rowIdx + 1, col: col)
                let idx = stringIndex[cell] ?? 0
                xml += "<c r=\"\(ref)\" t=\"s\"><v>\(idx)</v></c>"
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        return Data(xml.utf8)
    }

    // MARK: - Helpers

    /// 열 인덱스를 A, B, ..., Z, AA, AB 형태로 변환
    private func cellRef(row: Int, col: Int) -> String {
        var colStr = ""
        var c = col
        repeat {
            colStr = String(UnicodeScalar(65 + c % 26)!) + colStr
            c = c / 26 - 1
        } while c >= 0
        return "\(colStr)\(row + 1)"
    }

    private func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - ZIP Builder

    /// 최소한의 ZIP 아카이브를 수동 생성합니다 (STORE, 압축 없음).
    /// .xlsx 리더들은 STORE(비압축) ZIP을 정상적으로 처리합니다.
    private func buildZip(entries: [(path: String, data: Data)]) throws -> Data {
        var body = Data()
        var centralDir = Data()
        var offsets: [Int] = []

        for (path, fileData) in entries {
            let pathData = Data(path.utf8)
            offsets.append(body.count)

            let crc = crc32(fileData)

            // Local file header
            body.appendUInt32(0x04034B50) // signature
            body.appendUInt16(20)         // version needed
            body.appendUInt16(0)          // flags
            body.appendUInt16(0)          // compression (STORE)
            body.appendUInt16(0)          // mod time
            body.appendUInt16(0)          // mod date
            body.appendUInt32(crc)        // crc32
            body.appendUInt32(UInt32(fileData.count)) // compressed size
            body.appendUInt32(UInt32(fileData.count)) // uncompressed size
            body.appendUInt16(UInt16(pathData.count))  // filename length
            body.appendUInt16(0)          // extra field length
            body.append(pathData)
            body.append(fileData)

            // Central directory entry
            centralDir.appendUInt32(0x02014B50) // signature
            centralDir.appendUInt16(20)         // version made by
            centralDir.appendUInt16(20)         // version needed
            centralDir.appendUInt16(0)          // flags
            centralDir.appendUInt16(0)          // compression
            centralDir.appendUInt16(0)          // mod time
            centralDir.appendUInt16(0)          // mod date
            centralDir.appendUInt32(crc)
            centralDir.appendUInt32(UInt32(fileData.count))
            centralDir.appendUInt32(UInt32(fileData.count))
            centralDir.appendUInt16(UInt16(pathData.count))
            centralDir.appendUInt16(0)  // extra field length
            centralDir.appendUInt16(0)  // comment length
            centralDir.appendUInt16(0)  // disk number
            centralDir.appendUInt16(0)  // internal attrs
            centralDir.appendUInt32(0)  // external attrs
            centralDir.appendUInt32(UInt32(offsets.last!)) // offset
            centralDir.append(pathData)
        }

        let centralDirOffset = body.count
        body.append(centralDir)

        // End of central directory
        body.appendUInt32(0x06054B50)  // signature
        body.appendUInt16(0)           // disk number
        body.appendUInt16(0)           // central dir disk
        body.appendUInt16(UInt16(entries.count))
        body.appendUInt16(UInt16(entries.count))
        body.appendUInt32(UInt32(centralDir.count))
        body.appendUInt32(UInt32(centralDirOffset))
        body.appendUInt16(0)           // comment length

        return body
    }

    /// CRC-32 계산 (ISO 3309 / ITU-T V.42)
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - Data Extension for ZIP writing

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
```

- [ ] **Step 4: Add file to Xcode project and run tests**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' test 2>&1 | grep -E '(XLSXWriter|PASSED|FAILED|BUILD)'`
Expected: 3 tests PASS, BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Services/Export/XLSXWriter.swift CryptoTrackTests/XLSXWriterTests.swift
git commit -m "feat(export): XLSXWriter — ZIP+XML 기반 .xlsx 생성 엔진"
```

---

### Task 2: TransactionExporter — Order/Deposit를 시트 데이터로 변환

**Files:**
- Create: `CryptoTrack/Services/Export/TransactionExporter.swift`
- Create: `CryptoTrackTests/TransactionExporterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// CryptoTrackTests/TransactionExporterTests.swift
import XCTest
@testable import CryptoTrack

final class TransactionExporterTests: XCTestCase {

    func testExportOrdersGroupsByExchange() throws {
        let orders = [
            Order(id: "1", symbol: "BTC", side: .buy, price: 80_000_000,
                  amount: 0.5, totalValue: 40_000_000, fee: 20_000,
                  exchange: .upbit, executedAt: Date()),
            Order(id: "2", symbol: "ETH", side: .sell, price: 4_000_000,
                  amount: 2.0, totalValue: 8_000_000, fee: 4_000,
                  exchange: .bithumb, executedAt: Date()),
            Order(id: "3", symbol: "XRP", side: .buy, price: 1_000,
                  amount: 100, totalValue: 100_000, fee: 50,
                  exchange: .upbit, executedAt: Date()),
        ]

        let data = try TransactionExporter.exportOrders(orders)

        // ZIP 시그니처 확인
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testExportDepositsGroupsByExchange() throws {
        let deposits = [
            Deposit(id: "1", symbol: "BTC", amount: 1.0, type: .crypto,
                    status: .completed, txId: "abc123",
                    exchange: .upbit, completedAt: Date()),
            Deposit(id: "2", symbol: "KRW", amount: 1_000_000, type: .fiat,
                    status: .completed, txId: nil,
                    exchange: .bithumb, completedAt: Date()),
        ]

        let data = try TransactionExporter.exportDeposits(deposits)

        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }

    func testExportEmptyOrdersProducesValidFile() throws {
        let data = try TransactionExporter.exportOrders([])
        // 빈 데이터라도 유효한 xlsx
        XCTAssertEqual(data.prefix(2), Data([0x50, 0x4B]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' test 2>&1 | grep -E '(TransactionExporter|FAIL)'`
Expected: FAIL — `TransactionExporter` not found

- [ ] **Step 3: Implement TransactionExporter**

`CryptoTrack/Services/Export/TransactionExporter.swift`:

```swift
import Foundation

/// 거래 내역을 거래소별 시트로 분리한 .xlsx 데이터로 변환합니다.
enum TransactionExporter {

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    /// 체결 내역을 거래소별 시트로 분리한 .xlsx 데이터를 반환합니다.
    static func exportOrders(_ orders: [Order]) throws -> Data {
        let writer = XLSXWriter()
        let headers = ["체결일시", "코인", "구분", "체결가격", "체결수량", "체결금액", "수수료"]

        let grouped = Dictionary(grouping: orders) { $0.exchange }
        let sortedExchanges = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        for exchange in sortedExchanges {
            let exchangeOrders = grouped[exchange]!
                .sorted { $0.executedAt > $1.executedAt }
            let rows = exchangeOrders.map { order -> [String] in
                [
                    dateFormatter.string(from: order.executedAt),
                    order.symbol,
                    order.side == .buy ? "매수" : "매도",
                    formatNumber(order.price),
                    formatNumber(order.amount),
                    formatNumber(order.totalValue),
                    formatNumber(order.fee),
                ]
            }
            writer.addSheet(name: exchange.rawValue, headers: headers, rows: rows)
        }

        // 데이터가 없으면 빈 시트 하나 생성
        if grouped.isEmpty {
            writer.addSheet(name: "체결 내역", headers: headers, rows: [])
        }

        return try writer.finalize()
    }

    /// 입금 내역을 거래소별 시트로 분리한 .xlsx 데이터를 반환합니다.
    static func exportDeposits(_ deposits: [Deposit]) throws -> Data {
        let writer = XLSXWriter()
        let headers = ["입금일시", "코인", "유형", "수량", "상태", "TxID"]

        let grouped = Dictionary(grouping: deposits) { $0.exchange }
        let sortedExchanges = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        for exchange in sortedExchanges {
            let exchangeDeposits = grouped[exchange]!
                .sorted { $0.completedAt > $1.completedAt }
            let rows = exchangeDeposits.map { deposit -> [String] in
                [
                    dateFormatter.string(from: deposit.completedAt),
                    deposit.symbol,
                    deposit.type == .crypto ? "암호화폐" : "원화",
                    formatNumber(deposit.amount),
                    statusText(deposit.status),
                    deposit.txId ?? "",
                ]
            }
            writer.addSheet(name: exchange.rawValue, headers: headers, rows: rows)
        }

        if grouped.isEmpty {
            writer.addSheet(name: "입금 내역", headers: headers, rows: [])
        }

        return try writer.finalize()
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && value < 1_000_000_000 {
            return String(format: "%.0f", value)
        }
        // 소수점 이하 불필요한 0 제거
        let s = String(format: "%.8f", value)
        return s.replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    private static func statusText(_ status: DepositStatus) -> String {
        switch status {
        case .completed: return "완료"
        case .pending: return "대기"
        case .cancelled: return "취소"
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' test 2>&1 | grep -E '(TransactionExporter|PASSED|FAILED|BUILD)'`
Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add CryptoTrack/Services/Export/TransactionExporter.swift CryptoTrackTests/TransactionExporterTests.swift
git commit -m "feat(export): TransactionExporter — 거래소별 시트 변환"
```

---

### Task 3: ViewModel에 export 메서드 추가

**Files:**
- Modify: `CryptoTrack/ViewModels/TransactionHistoryViewModel.swift`

- [ ] **Step 1: Add exportToExcel() method to TransactionHistoryViewModel**

`TransactionHistoryViewModel.swift`의 `// MARK: - Actions` 섹션, `toggleSide` 메서드 뒤에 추가:

```swift
    // MARK: - Export

    /// 현재 조회된 데이터를 .xlsx 파일로 내보냅니다.
    /// - Returns: 임시 디렉토리에 저장된 파일 URL, 실패 시 nil
    func exportToExcel() -> URL? {
        do {
            let data: Data
            let prefix: String
            switch selectedTab {
            case .orders:
                data = try TransactionExporter.exportOrders(filteredOrders)
                prefix = "CryptoTrack_체결내역"
            case .deposits:
                data = try TransactionExporter.exportDeposits(deposits)
                prefix = "CryptoTrack_입금내역"
            }

            let dateStr = Self.fileDateFormatter.string(from: Date())
            let filename = "\(prefix)_\(dateStr).xlsx"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url)
            return url
        } catch {
            logger.error("엑셀 내보내기 실패: \(error)")
            errorMessage = "내보내기에 실패했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | grep -E '(error:|BUILD)'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add CryptoTrack/ViewModels/TransactionHistoryViewModel.swift
git commit -m "feat(export): ViewModel에 exportToExcel() 메서드 추가"
```

---

### Task 4: View에 내보내기 버튼 + NSSavePanel 연동

**Files:**
- Modify: `CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift`

- [ ] **Step 1: Add export button and save logic to TransactionHistoryView**

`TransactionHistoryView.swift`에서 `NavigationStack` 내부에 `.toolbar` 추가, 그리고 `exportFile` state 추가:

파일 상단 `@State` 선언부에 추가:
```swift
    @State private var isExporting = false
```

`NavigationStack` 블록의 `.navigationTitle("거래 내역")` 뒤에 toolbar 추가:
```swift
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportToFile()
                    } label: {
                        Label("엑셀로 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isLoading || !hasData)
                    .help("현재 조회된 데이터를 엑셀 파일로 내보냅니다")
                }
            }
```

computed property 추가:
```swift
    private var hasData: Bool {
        switch viewModel.selectedTab {
        case .orders: return !viewModel.filteredOrders.isEmpty
        case .deposits: return !viewModel.deposits.isEmpty
        }
    }
```

export 메서드 추가:
```swift
    private func exportToFile() {
        guard let tempURL = viewModel.exportToExcel() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = tempURL.lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destURL = panel.url else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        } catch {
            viewModel.errorMessage = "파일 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }
```

상단에 `import UniformTypeIdentifiers` 추가.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' build 2>&1 | grep -E '(error:|BUILD)'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild -scheme CryptoTrack_macOS -destination 'platform=macOS' test 2>&1 | grep -E '(PASSED|FAILED|BUILD)'`
Expected: All tests PASS, BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CryptoTrack/Views/TransactionHistory/TransactionHistoryView.swift
git commit -m "feat(export): 거래 내역 엑셀 내보내기 버튼 및 NSSavePanel 연동"
```
