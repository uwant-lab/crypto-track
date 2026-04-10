import Foundation
import Observation

/// 차트 드로잉 도구의 상태와 비즈니스 로직을 관리합니다.
@Observable
@MainActor
final class DrawingViewModel {

    // MARK: - State

    var drawings: [ChartDrawing] = []
    var selectedTool: DrawingType? = nil
    var selectedDrawingId: String? = nil
    var isDrawingMode: Bool = false
    var showAllDrawings: Bool = true

    // MARK: - Private State

    private var currentDrawing: ChartDrawing? = nil
    private var symbol: String = ""
    private var exchange: Exchange = .binance
    private var timeframe: ChartTimeframe = .hour1
    private let storage = DrawingStorageService.shared

    // MARK: - Computed

    var visibleDrawings: [ChartDrawing] {
        showAllDrawings ? drawings.filter(\.isVisible) : []
    }

    var selectedDrawing: ChartDrawing? {
        guard let id = selectedDrawingId else { return nil }
        return drawings.first { $0.id == id }
    }

    var inProgressDrawing: ChartDrawing? { currentDrawing }

    // MARK: - Drawing Mode

    func startDrawing(type: DrawingType) {
        selectedTool = type
        isDrawingMode = true
        selectedDrawingId = nil
        currentDrawing = ChartDrawing(type: type)
    }

    func addPoint(price: Double, timestamp: Date) {
        guard isDrawingMode, var drawing = currentDrawing else { return }
        drawing.points.append(DrawingPoint(price: price, timestamp: timestamp))
        currentDrawing = drawing

        if drawing.isComplete {
            finishDrawing()
        }
    }

    func finishDrawing() {
        guard var drawing = currentDrawing, !drawing.points.isEmpty else {
            cancelDrawing()
            return
        }
        drawing.updatedAt = Date()
        drawings.append(drawing)
        currentDrawing = nil
        selectedDrawingId = drawing.id

        Task { await saveDrawings() }
    }

    func cancelDrawing() {
        currentDrawing = nil
        isDrawingMode = false
        selectedTool = nil
    }

    func exitDrawingMode() {
        if currentDrawing != nil { finishDrawing() }
        isDrawingMode = false
        selectedTool = nil
        currentDrawing = nil
    }

    // MARK: - Selection

    func selectDrawing(id: String) {
        selectedDrawingId = id
    }

    func deselectDrawing() {
        selectedDrawingId = nil
    }

    // MARK: - Mutation

    func deleteDrawing(id: String) {
        drawings.removeAll { $0.id == id }
        if selectedDrawingId == id { selectedDrawingId = nil }
        Task { await saveDrawings() }
    }

    func toggleVisibility(id: String) {
        guard let idx = drawings.firstIndex(where: { $0.id == id }) else { return }
        drawings[idx].isVisible.toggle()
        drawings[idx].updatedAt = Date()
        Task { await saveDrawings() }
    }

    func toggleAllVisibility() {
        showAllDrawings.toggle()
    }

    func deleteSelectedDrawing() {
        guard let id = selectedDrawingId else { return }
        deleteDrawing(id: id)
    }

    // MARK: - Persistence

    func loadDrawings(symbol: String, exchange: Exchange, timeframe: ChartTimeframe) async {
        self.symbol = symbol
        self.exchange = exchange
        self.timeframe = timeframe

        do {
            drawings = try storage.load(symbol: symbol, exchange: exchange, timeframe: timeframe)
        } catch {
            drawings = []
        }
    }

    func saveDrawings() async {
        guard !symbol.isEmpty else { return }
        do {
            try storage.save(drawings: drawings, symbol: symbol, exchange: exchange, timeframe: timeframe)
        } catch {
            // Silently fail — drawings are in-memory and will be retried on next save
        }
    }
}
