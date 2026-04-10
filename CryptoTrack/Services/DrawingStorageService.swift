import Foundation

/// 차트 드로잉을 로컬 파일 시스템에 저장하고 불러오는 서비스입니다.
final class DrawingStorageService: Sendable {

    static let shared = DrawingStorageService()

    private init() {}

    // MARK: - Storage Key

    private func fileName(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) -> String {
        "\(exchange.rawValue)_\(symbol)_\(timeframe.rawValue).json"
    }

    private func storageURL(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let drawingsDir = documents.appendingPathComponent("Drawings", isDirectory: true)

        if !FileManager.default.fileExists(atPath: drawingsDir.path) {
            try FileManager.default.createDirectory(at: drawingsDir, withIntermediateDirectories: true)
        }

        return drawingsDir.appendingPathComponent(fileName(symbol: symbol, exchange: exchange, timeframe: timeframe))
    }

    // MARK: - CRUD

    /// 드로잉 목록을 저장합니다.
    func save(drawings: [ChartDrawing], symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws {
        let url = try storageURL(symbol: symbol, exchange: exchange, timeframe: timeframe)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(drawings)
        try data.write(to: url, options: .atomic)
    }

    /// 저장된 드로잉 목록을 불러옵니다.
    func load(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws -> [ChartDrawing] {
        let url = try storageURL(symbol: symbol, exchange: exchange, timeframe: timeframe)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ChartDrawing].self, from: data)
    }

    /// 특정 드로잉을 삭제합니다.
    func delete(drawingId: String, symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws {
        var drawings = try load(symbol: symbol, exchange: exchange, timeframe: timeframe)
        drawings.removeAll { $0.id == drawingId }
        try save(drawings: drawings, symbol: symbol, exchange: exchange, timeframe: timeframe)
    }
}
