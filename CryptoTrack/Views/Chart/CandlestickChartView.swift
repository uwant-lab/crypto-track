import SwiftUI

// MARK: - Platform Background Color Helper

private extension Color {
    /// iOS의 systemBackground / macOS의 windowBackgroundColor에 해당하는 배경색
    static var platformBackground: Color {
        #if os(iOS)
        Color.platformBackground
        #else
        Color(NSColor.windowBackgroundColor)
        #endif
    }
}

/// 캔들스틱 차트 메인 컨테이너 화면입니다.
struct CandlestickChartView: View {
    @State private var viewModel: ChartViewModel
    @State private var crosshairPosition: CGPoint? = nil

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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.loadData() }
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        VStack(spacing: 0) {
            // 타임프레임 선택
            TimeframePickerView(
                selectedTimeframe: viewModel.selectedTimeframe,
                onSelect: { timeframe in
                    await viewModel.changeTimeframe(timeframe)
                }
            )
            .background(Color.platformBackground)

            Divider()

            // 캔들스틱 + 크로스헤어
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

                if let pos = crosshairPosition, let kline = viewModel.crosshairKline {
                    GeometryReader { geo in
                        CrosshairOverlayView(
                            position: pos,
                            kline: kline,
                            chartSize: geo.size
                        )
                    }
                    .allowsHitTesting(false)
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
        .background(Color.platformBackground)
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
