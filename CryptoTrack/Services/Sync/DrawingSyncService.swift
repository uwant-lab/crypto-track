import Foundation

/// iCloud Documents를 사용하여 차트 드로잉을 동기화하는 서비스입니다.
/// iCloud를 사용할 수 없는 경우 로컬 저장소로 폴백합니다.
final class DrawingSyncService: Sendable {

    // MARK: - Singleton

    static let shared = DrawingSyncService()

    // MARK: - Constants

    private let containerIdentifier = "iCloud.com.cryptotrack.app"
    private let drawingsSubdirectory = "Drawings"

    // MARK: - Init

    private init() {}

    // MARK: - iCloud Availability

    /// iCloud 사용 가능 여부를 확인합니다.
    func isICloudAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Save

    /// 드로잉 목록을 iCloud Documents에 저장합니다.
    /// iCloud를 사용할 수 없으면 로컬 저장소에 저장합니다.
    func save(drawings: [ChartDrawing], key: String) async throws {
        let url = try await storageURL(for: key)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(drawings)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    /// iCloud Documents에서 드로잉 목록을 불러옵니다.
    /// iCloud를 사용할 수 없으면 로컬 저장소에서 불러옵니다.
    func load(key: String) async throws -> [ChartDrawing]? {
        let url = try await storageURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ChartDrawing].self, from: data)
    }

    // MARK: - Private

    private func storageURL(for key: String) async throws -> URL {
        if isICloudAvailable(), let iCloudURL = iCloudDrawingsDirectory() {
            return iCloudURL.appendingPathComponent("\(key).json")
        }
        return try localDrawingsURL(for: key)
    }

    private func iCloudDrawingsDirectory() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) else { return nil }

        let drawingsURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(drawingsSubdirectory, isDirectory: true)

        if !FileManager.default.fileExists(atPath: drawingsURL.path) {
            try? FileManager.default.createDirectory(
                at: drawingsURL,
                withIntermediateDirectories: true
            )
        }

        return drawingsURL
    }

    private func localDrawingsURL(for key: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let drawingsDir = documents.appendingPathComponent(drawingsSubdirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: drawingsDir.path) {
            try FileManager.default.createDirectory(at: drawingsDir, withIntermediateDirectories: true)
        }
        return drawingsDir.appendingPathComponent("\(key).json")
    }
}
