import Foundation

// MARK: - XLSXWriter

/// Generates .xlsx files from scratch using only Foundation.
/// .xlsx is a ZIP archive containing XML files. Uses STORE (no compression) for the ZIP layer.
final class XLSXWriter {

    // MARK: - Types

    private struct SheetData {
        let name: String
        let headers: [String]
        let rows: [[String]]
    }

    // MARK: - Properties

    private var sheets: [SheetData] = []

    // MARK: - Public API

    /// Adds a sheet with headers and row data. Call before `finalize()`.
    func addSheet(name: String, headers: [String], rows: [[String]]) {
        sheets.append(SheetData(name: name, headers: headers, rows: rows))
    }

    /// Builds the .xlsx ZIP archive and returns the raw bytes.
    func finalize() throws -> Data {
        guard !sheets.isEmpty else {
            throw XLSXWriterError.noSheets
        }

        // Collect every string into a shared-string table for the workbook.
        var sharedStrings: [String] = []
        var sharedStringIndex: [String: Int] = [:]

        func indexForString(_ s: String) -> Int {
            if let idx = sharedStringIndex[s] { return idx }
            let idx = sharedStrings.count
            sharedStrings.append(s)
            sharedStringIndex[s] = idx
            return idx
        }

        // Pre-populate shared strings (headers first, then rows).
        for sheet in sheets {
            for h in sheet.headers { _ = indexForString(h) }
            for row in sheet.rows {
                for cell in row { _ = indexForString(cell) }
            }
        }

        // Build XML files.
        var files: [(path: String, data: Data)] = []

        files.append(("[Content_Types].xml", buildContentTypes()))
        files.append(("_rels/.rels", buildRels()))
        files.append(("xl/workbook.xml", buildWorkbook()))
        files.append(("xl/_rels/workbook.xml.rels", buildWorkbookRels()))
        files.append(("xl/styles.xml", buildStyles()))
        files.append(("xl/sharedStrings.xml", buildSharedStrings(sharedStrings)))

        for (i, sheet) in sheets.enumerated() {
            let xml = buildSheet(sheet, index: i, stringIndex: sharedStringIndex)
            files.append(("xl/worksheets/sheet\(i + 1).xml", xml))
        }

        return buildZipArchive(files: files)
    }

    // MARK: - XML Builders

    private func buildContentTypes() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        xml += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        xml += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        xml += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        xml += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        xml += "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>"
        for i in 1...sheets.count {
            xml += "<Override PartName=\"/xl/worksheets/sheet\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        xml += "</Types>"
        return Data(xml.utf8)
    }

    private func buildRels() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """
        return Data(xml.utf8)
    }

    private func buildWorkbook() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">"
        xml += "<sheets>"
        for (i, sheet) in sheets.enumerated() {
            xml += "<sheet name=\"\(escapeXML(sheet.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        xml += "</sheets>"
        xml += "</workbook>"
        return Data(xml.utf8)
    }

    private func buildWorkbookRels() -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        for i in 1...sheets.count {
            xml += "<Relationship Id=\"rId\(i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i).xml\"/>"
        }
        xml += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "<Relationship Id=\"rId\(sheets.count + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>"
        xml += "</Relationships>"
        return Data(xml.utf8)
    }

    private func buildStyles() -> Data {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <fonts count="2">\
        <font><sz val="11"/><name val="Calibri"/></font>\
        <font><b/><sz val="11"/><name val="Calibri"/></font>\
        </fonts>\
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
        <cellXfs count="2">\
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
        </cellXfs>\
        </styleSheet>
        """
        return Data(xml.utf8)
    }

    private func buildSharedStrings(_ strings: [String]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
        for s in strings {
            xml += "<si><t>\(escapeXML(s))</t></si>"
        }
        xml += "</sst>"
        return Data(xml.utf8)
    }

    private func buildSheet(_ sheet: SheetData, index: Int, stringIndex: [String: Int]) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        xml += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        xml += "<sheetData>"

        // Header row (row 1), style 1 = bold
        if !sheet.headers.isEmpty {
            xml += "<row r=\"1\">"
            for (col, header) in sheet.headers.enumerated() {
                let ref = cellReference(row: 0, col: col)
                let idx = stringIndex[header]!
                xml += "<c r=\"\(ref)\" t=\"s\" s=\"1\"><v>\(idx)</v></c>"
            }
            xml += "</row>"
        }

        // Data rows (starting at row 2), style 0 = normal
        for (rowIdx, row) in sheet.rows.enumerated() {
            let rowNum = rowIdx + 2
            xml += "<row r=\"\(rowNum)\">"
            for (col, cell) in row.enumerated() {
                let ref = cellReference(row: rowIdx + 1, col: col)
                let idx = stringIndex[cell]!
                xml += "<c r=\"\(ref)\" t=\"s\" s=\"0\"><v>\(idx)</v></c>"
            }
            xml += "</row>"
        }

        xml += "</sheetData>"
        xml += "</worksheet>"
        return Data(xml.utf8)
    }

    // MARK: - Cell Reference Helper

    /// Converts (row, col) to Excel-style reference like "A1", "B2", "AA3".
    private func cellReference(row: Int, col: Int) -> String {
        var columnName = ""
        var c = col
        repeat {
            columnName = String(UnicodeScalar(65 + (c % 26))!) + columnName
            c = c / 26 - 1
        } while c >= 0
        return "\(columnName)\(row + 1)"
    }

    // MARK: - XML Escaping

    private func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }

    // MARK: - ZIP Archive Builder

    /// Builds a minimal ZIP archive (STORE method, no compression) from named file entries.
    private func buildZipArchive(files: [(path: String, data: Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localHeaderOffsets: [UInt32] = []

        for (path, fileData) in files {
            let crc = crc32(fileData)
            let pathBytes = Data(path.utf8)
            let offset = UInt32(archive.count)
            localHeaderOffsets.append(offset)

            // Local file header
            archive.appendUInt32(0x04034B50)        // signature
            archive.appendUInt16(20)                 // version needed
            archive.appendUInt16(0)                  // general purpose bit flag
            archive.appendUInt16(0)                  // compression method (STORE)
            archive.appendUInt16(0)                  // last mod file time
            archive.appendUInt16(0)                  // last mod file date
            archive.appendUInt32(crc)                // crc-32
            archive.appendUInt32(UInt32(fileData.count)) // compressed size
            archive.appendUInt32(UInt32(fileData.count)) // uncompressed size
            archive.appendUInt16(UInt16(pathBytes.count)) // file name length
            archive.appendUInt16(0)                  // extra field length
            archive.append(pathBytes)                // file name
            archive.append(fileData)                 // file data

            // Central directory entry
            centralDirectory.appendUInt32(0x02014B50) // signature
            centralDirectory.appendUInt16(20)         // version made by
            centralDirectory.appendUInt16(20)         // version needed
            centralDirectory.appendUInt16(0)          // general purpose bit flag
            centralDirectory.appendUInt16(0)          // compression method (STORE)
            centralDirectory.appendUInt16(0)          // last mod file time
            centralDirectory.appendUInt16(0)          // last mod file date
            centralDirectory.appendUInt32(crc)        // crc-32
            centralDirectory.appendUInt32(UInt32(fileData.count)) // compressed size
            centralDirectory.appendUInt32(UInt32(fileData.count)) // uncompressed size
            centralDirectory.appendUInt16(UInt16(pathBytes.count)) // file name length
            centralDirectory.appendUInt16(0)          // extra field length
            centralDirectory.appendUInt16(0)          // file comment length
            centralDirectory.appendUInt16(0)          // disk number start
            centralDirectory.appendUInt16(0)          // internal file attributes
            centralDirectory.appendUInt32(0)          // external file attributes
            centralDirectory.appendUInt32(offset)     // relative offset of local header
            centralDirectory.append(pathBytes)        // file name
        }

        let centralDirOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory record
        archive.appendUInt32(0x06054B50)              // signature
        archive.appendUInt16(0)                       // disk number
        archive.appendUInt16(0)                       // disk with central directory
        archive.appendUInt16(UInt16(files.count))     // entries on this disk
        archive.appendUInt16(UInt16(files.count))     // total entries
        archive.appendUInt32(UInt32(centralDirectory.count)) // central directory size
        archive.appendUInt32(centralDirOffset)        // offset of central directory
        archive.appendUInt16(0)                       // comment length

        return archive
    }

    // MARK: - CRC-32 (ISO 3309)

    /// CRC-32 lookup table, generated once.
    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ Self.crc32Table[index]
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Error

enum XLSXWriterError: Error, LocalizedError {
    case noSheets

    var errorDescription: String? {
        switch self {
        case .noSheets:
            return "XLSXWriter requires at least one sheet before finalizing."
        }
    }
}

// MARK: - Data Extension for ZIP Writing

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }
}
