import SwiftUI

struct TransactionHistoryView: View {
    @State private var viewModel = TransactionHistoryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                tabContent
            }
            .navigationTitle("거래 내역")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 12) {
            Picker("탭", selection: $viewModel.selectedTab) {
                ForEach(TransactionTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Picker("거래소", selection: $viewModel.selectedExchange) {
                    Text("전체").tag(Exchange?.none)
                    ForEach(Exchange.allCases, id: \.self) { exchange in
                        Text(exchange.rawValue).tag(Exchange?.some(exchange))
                    }
                }
                .frame(width: 120)

                DatePicker("시작일", selection: $viewModel.dateFrom, displayedComponents: .date)
                    .labelsHidden()
                Text("~")
                DatePicker("종료일", selection: $viewModel.dateTo, displayedComponents: .date)
                    .labelsHidden()

                Button("조회") {
                    if viewModel.selectedTab == .orders {
                        viewModel.fetchOrders()
                    } else {
                        viewModel.fetchDeposits()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .orders:
            OrderListView(
                groupedOrders: viewModel.groupedOrders,
                isLoading: viewModel.isLoading,
                progress: viewModel.progress,
                loadedCount: viewModel.loadedCount,
                errorMessage: viewModel.errorMessage
            )
        case .deposits:
            DepositListView(
                groupedDeposits: viewModel.groupedDeposits,
                isLoading: viewModel.isLoading,
                progress: viewModel.progress,
                loadedCount: viewModel.loadedCount,
                errorMessage: viewModel.errorMessage
            )
        }
    }
}

#Preview {
    TransactionHistoryView()
}
