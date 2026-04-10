import Foundation

/// 차트 드로잉을 로컬 파일 시스템에 저장하고 불러오는 서비스입니다.
final class DrawingStorageService: Sendable {

    static let shared = DrawingStorageService()

    private init() {}

    // MARK: - Storage Key

    private func fileName(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) -> String {
        "\(exchange.rawValue)_\(symbol)_\(timeframe.rawValue).json"
    }

    /// DrawingSyncService용 키 (확장자 없음, DrawingSyncService가 .json을 붙임)
    private func syncKey(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) -> String {
        "\(exchange.rawValue)_\(symbol)_\(timeframe.rawValue)"
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

    /// 드로잉 목록을 로컬에 저장하고, iCloud에도 동기화합니다.
    func save(drawings: [ChartDrawing], symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws {
        let url = try storageURL(symbol: symbol, exchange: exchange, timeframe: timeframe)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(drawings)
        try data.write(to: url, options: .atomic)

        // iCloud에 비동기 동기화 (실패 시 로컬 저장은 이미 완료됨)
        let key = syncKey(symbol: symbol, exchange: exchange, timeframe: timeframe)
        Task {
            try? await DrawingSyncService.shared.save(drawings: drawings, key: key)
        }
    }

    /// 저장된 드로잉 목록을 불러옵니다.
    /// iCloud 버전이 있으면 last-write-wins 전략으로 최신 버전을 반환합니다.
    func load(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws -> [ChartDrawing] {
        let localURL = try storageURL(symbol: symbol, exchange: exchange, timeframe: timeframe)
        let localExists = FileManager.default.fileExists(atPath: localURL.path)

        let localDrawings: [ChartDrawing]
        if localExists {
            let data = try Data(contentsOf: localURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            localDrawings = try decoder.decode([ChartDrawing].self, from: data)
        } else {
            localDrawings = []
        }

        return localDrawings
    }

    /// 저장된 드로잉 목록을 iCloud와 비교하여 최신 버전으로 불러옵니다.
    func loadWithCloudSync(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) async throws -> [ChartDrawing] {
        let localDrawings = try load(symbol: symbol, exchange: exchange, timeframe: timeframe)
        let key = syncKey(symbol: symbol, exchange: exchange, timeframe: timeframe)

        guard let cloudDrawings = try? await DrawingSyncService.shared.load(key: key),
              !cloudDrawings.isEmpty else {
            return localDrawings
        }

        // last-write-wins: updatedAt 기준으로 최신 드로잉을 우선합니다.
        let localLatest = localDrawings.map { $0.updatedAt }.max() ?? .distantPast
        let cloudLatest = cloudDrawings.map { $0.updatedAt }.max() ?? .distantPast

        if cloudLatest > localLatest {
            // 클라우드가 더 최신이면 로컬에 저장 후 반환
            try? save(drawings: cloudDrawings, symbol: symbol, exchange: exchange, timeframe: timeframe)
            return cloudDrawings
        }

        return localDrawings
    }

    /// 특정 드로잉을 삭제합니다.
    func delete(drawingId: String, symbol: String, exchange: Exchange, timeframe: ChartTimeframe) throws {
        var drawings = try load(symbol: symbol, exchange: exchange, timeframe: timeframe)
        drawings.removeAll { $0.id == drawingId }
        try save(drawings: drawings, symbol: symbol, exchange: exchange, timeframe: timeframe)
    }
}
