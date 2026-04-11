import SwiftUI

/// 포트폴리오 대시보드 메인 화면입니다.
struct DashboardView: View {
    @State private var viewModel = DashboardViewModel()
    @State private var settingsManager = AppSettingsManager.shared

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("대시보드")
                .task {
                    await viewModel.runAutoRefreshLoop()
                }
                .refreshable {
                    await viewModel.refresh()
                }
        }
    }

    // MARK: - Content States

    private var hasNoExchanges: Bool {
        ExchangeManager.shared.registeredExchanges.isEmpty
    }

    private var registeredExchanges: [Exchange] {
        ExchangeManager.shared.registeredExchanges
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.assets.isEmpty {
            loadingView
        } else if hasNoExchanges {
            emptyStateView
        } else if let error = viewModel.errorMessage, viewModel.assets.isEmpty {
            errorView(message: error)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            AssetFilterTabBar(
                selected: $viewModel.selectedFilter,
                available: registeredExchanges
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            PortfolioSummaryCard(
                krw: viewModel.krwSummary,
                usd: viewModel.usdSummary,
                colorMode: settingsManager.priceColorMode
            )
            .padding(.horizontal, 16)

            ExchangeStatusBanner(statuses: viewModel.exchangeStatuses)
                .padding(.horizontal, 16)

            DashboardToolbar(
                hideDust: $viewModel.hideDust,
                lastRefresh: viewModel.lastRefreshDate,
                isRefreshing: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } },
                needsCostBasisSync: !viewModel.foreignCostBasisPairs.isEmpty,
                isCostBasisSyncing: viewModel.costBasisProvider.isComputing,
                onCostBasisSync: { Task { await viewModel.syncForeignCostBasis() } }
            )
            .padding(.horizontal, 16)

            assetsList
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var assetsList: some View {
        if viewModel.displayedSections.isEmpty {
            emptyFilterView
        } else {
            #if os(macOS)
            AssetTableSections(
                sections: viewModel.displayedSections,
                krwSortOrder: $viewModel.krwSortOrder,
                usdSortOrder: $viewModel.usdSortOrder,
                showHeaders: viewModel.selectedFilter == .all,
                colorMode: settingsManager.priceColorMode,
                sparkline: { viewModel.sparkline(for: $0) }
            )
            .padding(.horizontal, 16)
            #else
            AssetCardList(
                sections: viewModel.displayedSections,
                showSectionHeaders: viewModel.selectedFilter == .all,
                colorMode: settingsManager.priceColorMode,
                sparkline: { viewModel.sparkline(for: $0) }
            )
            #endif
        }
    }

    // MARK: - Empty/Loading/Error states

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("연결된 거래소가 없습니다")
                .font(.title3.bold())
            Text("설정 탭에서 거래소 API를 등록하면\n자산 현황을 확인할 수 있습니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
            if viewModel.hideDust && hasOnlyDust {
                Text("표시할 자산이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("소액 숨김 해제") {
                    viewModel.hideDust = false
                }
                .buttonStyle(.borderless)
            } else {
                Text("선택한 거래소에 보유 자산이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Dust-only short-circuit: some rows were filtered, but flipping the dust
    /// toggle would bring them back.
    private var hasOnlyDust: Bool {
        let unfilteredCount = viewModel.assets.filter { asset in
            switch viewModel.selectedFilter {
            case .all: return true
            case .exchange(let ex): return asset.exchange == ex
            }
        }.count
        return unfilteredCount > 0 && viewModel.displayedSections.allSatisfy(\.rows.isEmpty)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                #if os(macOS)
                .controlSize(.large)
                #else
                .scaleEffect(1.5)
                #endif
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
