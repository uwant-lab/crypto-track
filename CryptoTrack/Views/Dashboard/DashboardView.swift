import SwiftUI

/// 포트폴리오 대시보드 메인 화면입니다.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("대시보드")
                .task { await viewModel.refresh() }
                .refreshable { await viewModel.refresh() }
        }
    }

    // MARK: - Content States

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.assets.isEmpty {
            loadingView
        } else if let errorMessage = viewModel.errorMessage, viewModel.assets.isEmpty {
            errorView(message: errorMessage)
        } else {
            portfolioList
        }
    }

    // MARK: - Subviews

    private var portfolioList: some View {
        List {
            Section {
                PortfolioSummaryView(
                    totalValue: viewModel.totalValue,
                    totalProfit: viewModel.totalProfit,
                    totalProfitRate: viewModel.totalProfitRate
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section("보유 자산") {
                if viewModel.assets.isEmpty {
                    Text("보유 자산이 없습니다.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(viewModel.assets) { asset in
                        AssetRowView(
                            asset: asset,
                            currentValue: viewModel.currentValue(for: asset),
                            profit: viewModel.profit(for: asset),
                            profitRate: viewModel.profitRate(for: asset)
                        )
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("불러오는 중…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("오류가 발생했습니다")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("다시 시도") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
}

#Preview("샘플 데이터") {
    // Inject pre-populated viewModel via a wrapper
    _DashboardPreviewWrapper()
}

private struct _DashboardPreviewWrapper: View {
    @State private var viewModel = DashboardViewModel.preview

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PortfolioSummaryView(
                        totalValue: viewModel.totalValue,
                        totalProfit: viewModel.totalProfit,
                        totalProfitRate: viewModel.totalProfitRate
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                Section("보유 자산") {
                    ForEach(viewModel.assets) { asset in
                        AssetRowView(
                            asset: asset,
                            currentValue: viewModel.currentValue(for: asset),
                            profit: viewModel.profit(for: asset),
                            profitRate: viewModel.profitRate(for: asset)
                        )
                    }
                }
            }
            .navigationTitle("대시보드")
        }
    }
}
