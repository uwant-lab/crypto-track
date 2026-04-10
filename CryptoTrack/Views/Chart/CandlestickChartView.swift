import SwiftUI

/// 캔들스틱 차트 메인 컨테이너 화면입니다.
struct CandlestickChartView: View {
    @State private var viewModel: ChartViewModel
    @State private var drawingViewModel: DrawingViewModel = DrawingViewModel()
    @State private var crosshairPosition: CGPoint? = nil
    @State private var showDrawingToolbar: Bool = false

    init(symbol: String, exchange: Exchange) {
        _viewModel = State(initialValue: ChartViewModel(symbol: symbol, exchange: exchange))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.klines.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.klines.isEmpty {
                errorView(message: error)
            } else {
                chartContent
            }
        }
        .navigationTitle("\(viewModel.symbol) (\(viewModel.exchange.rawValue))")
        .inlineNavigationTitle()
        .task {
            await viewModel.loadData()
            await drawingViewModel.loadDrawings(
                symbol: viewModel.symbol,
                exchange: viewModel.exchange,
                timeframe: viewModel.selectedTimeframe
            )
        }
        .onChange(of: viewModel.selectedTimeframe) { _, newTimeframe in
            Task {
                await drawingViewModel.loadDrawings(
                    symbol: viewModel.symbol,
                    exchange: viewModel.exchange,
                    timeframe: newTimeframe
                )
            }
        }
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        VStack(spacing: 0) {
            // 타임프레임 선택 + 드로잉 토글
            HStack(spacing: 0) {
                TimeframePickerView(
                    selectedTimeframe: viewModel.selectedTimeframe,
                    onSelect: { timeframe in
                        await viewModel.changeTimeframe(timeframe)
                    }
                )
                Spacer()
                Button {
                    showDrawingToolbar.toggle()
                    if !showDrawingToolbar {
                        drawingViewModel.exitDrawingMode()
                    }
                } label: {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(showDrawingToolbar ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("드로잉 도구")
            }
            .background(AppColor.background)

            // 드로잉 툴바
            if showDrawingToolbar {
                DrawingToolbarView(viewModel: drawingViewModel)
            }

            Divider()

            // 캔들스틱 + 드로잉 + 크로스헤어
            GeometryReader { geo in
                let yAxisWidth: CGFloat = 60
                let xAxisHeight: CGFloat = 24
                let chartRect = CGRect(
                    x: 0,
                    y: 0,
                    width: geo.size.width - yAxisWidth,
                    height: geo.size.height - xAxisHeight
                )
                let priceRange = computePriceRange(klines: viewModel.visibleKlines)

                ZStack {
                    CandlestickCanvas(
                        klines: viewModel.visibleKlines,
                        onZoom: { scale in viewModel.zoom(scale: scale) },
                        onScroll: { offset, width in viewModel.scroll(offset: offset, candleWidth: width) },
                        onCrosshairChanged: { position, kline in
                            crosshairPosition = position
                            viewModel.crosshairKline = kline
                        }
                    )

                    // Drawing canvas overlay
                    DrawingCanvas(
                        viewModel: drawingViewModel,
                        klines: viewModel.visibleKlines,
                        chartRect: chartRect,
                        priceRange: priceRange
                    )

                    // Tap gesture for adding drawing points
                    if drawingViewModel.isDrawingMode {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: chartRect.width, height: geo.size.height)
                            .onTapGesture { location in
                                let price = priceFromY(location.y, chartRect: chartRect, priceRange: priceRange)
                                let timestamp = timestampFromX(location.x, chartRect: chartRect, klines: viewModel.visibleKlines)
                                drawingViewModel.addPoint(price: price, timestamp: timestamp)
                            }
                    }

                    if let pos = crosshairPosition, let kline = viewModel.crosshairKline {
                        CrosshairOverlayView(
                            position: pos,
                            kline: kline,
                            chartSize: geo.size
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: chartHeight)

            Divider()

            // 거래량 바
            VolumeBarCanvas(klines: viewModel.visibleKlines)
                .frame(maxWidth: .infinity)
                .frame(height: 80)

            Divider()
        }
        .background(AppColor.background)
    }

    // MARK: - Drawing Coordinate Helpers

    private func computePriceRange(klines: [Kline]) -> ClosedRange<Double> {
        guard !klines.isEmpty else { return 0...1 }
        let low = klines.map(\.low).min()!
        let high = klines.map(\.high).max()!
        let padding = (high - low) * 0.05
        return (low - padding)...(high + padding)
    }

    private func priceFromY(_ y: CGFloat, chartRect: CGRect, priceRange: ClosedRange<Double>) -> Double {
        let span = priceRange.upperBound - priceRange.lowerBound
        let fraction = Double((y - chartRect.minY) / chartRect.height)
        return priceRange.upperBound - fraction * span
    }

    private func timestampFromX(_ x: CGFloat, chartRect: CGRect, klines: [Kline]) -> Date {
        guard klines.count > 1 else { return Date() }
        let fraction = Double((x - chartRect.minX) / chartRect.width)
        let first = klines.first!.timestamp.timeIntervalSinceReferenceDate
        let last = klines.last!.timestamp.timeIntervalSinceReferenceDate
        let t = first + fraction * (last - first)
        return Date(timeIntervalSinceReferenceDate: t)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("차트 데이터 불러오는 중…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("차트를 불러올 수 없습니다")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await viewModel.loadData() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout

    private var chartHeight: CGFloat {
        #if os(iOS)
        return 320
        #else
        return 400
        #endif
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CandlestickChartView(symbol: "BTC", exchange: .binance)
    }
}

#Preview("샘플 데이터") {
    _ChartPreviewWrapper()
}

private struct _ChartPreviewWrapper: View {
    @State private var viewModel = ChartViewModel.preview

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TimeframePickerView(
                    selectedTimeframe: viewModel.selectedTimeframe,
                    onSelect: { tf in await viewModel.changeTimeframe(tf) }
                )
                Divider()
                CandlestickCanvas(
                    klines: viewModel.visibleKlines,
                    onZoom: { scale in viewModel.zoom(scale: scale) },
                    onScroll: { offset, width in viewModel.scroll(offset: offset, candleWidth: width) },
                    onCrosshairChanged: { _, kline in viewModel.crosshairKline = kline }
                )
                .frame(height: 320)
                Divider()
                VolumeBarCanvas(klines: viewModel.visibleKlines)
                    .frame(height: 80)
            }
            .navigationTitle("BTC (Binance)")
            .inlineNavigationTitle()
        }
    }
}
