import SwiftUI
import UniformTypeIdentifiers

struct TransactionHistoryView: View {
    @State private var viewModel = TransactionHistoryViewModel()
    @State private var showOrdersFromPicker = false
    @State private var showOrdersToPicker = false
    @State private var showDepositsFromPicker = false
    @State private var showDepositsToPicker = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                tabContent
            }
            .navigationTitle("거래 내역")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        exportToFile()
                    } label: {
                        Label("엑셀로 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isCurrentTabLoading || !hasData)
                    .help("현재 조회된 데이터를 엑셀 파일로 내보냅니다")
                }
            }
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

            switch viewModel.selectedTab {
            case .orders:
                ordersFilterRow
            case .deposits:
                depositsFilterRow
            }
        }
        .padding()
    }

    private var ordersFilterRow: some View {
        HStack(spacing: 12) {
            Picker("거래소", selection: $viewModel.ordersExchange) {
                Text("전체").tag(Exchange?.none)
                ForEach(Exchange.allCases, id: \.self) { exchange in
                    Text(exchange.rawValue).tag(Exchange?.some(exchange))
                }
            }
            .frame(width: 120)

            dateButton(date: $viewModel.ordersDateFrom, showPicker: $showOrdersFromPicker)
            Text("~")
            dateButton(date: $viewModel.ordersDateTo, showPicker: $showOrdersToPicker)

            if viewModel.isLoadingOrders {
                Button("중지") {
                    viewModel.cancelOrders()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("조회") {
                    viewModel.fetchOrders()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var depositsFilterRow: some View {
        HStack(spacing: 12) {
            Picker("거래소", selection: $viewModel.depositsExchange) {
                Text("전체").tag(Exchange?.none)
                ForEach(Exchange.allCases, id: \.self) { exchange in
                    Text(exchange.rawValue).tag(Exchange?.some(exchange))
                }
            }
            .frame(width: 120)

            dateButton(date: $viewModel.depositsDateFrom, showPicker: $showDepositsFromPicker)
            Text("~")
            dateButton(date: $viewModel.depositsDateTo, showPicker: $showDepositsToPicker)

            if viewModel.isLoadingDeposits {
                Button("중지") {
                    viewModel.cancelDeposits()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("조회") {
                    viewModel.fetchDeposits()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func dateButton(date: Binding<Date>, showPicker: Binding<Bool>) -> some View {
        Button(dateFormatter.string(from: date.wrappedValue)) {
            showPicker.wrappedValue.toggle()
        }
        .monospacedDigit()
        .popover(isPresented: showPicker) {
            VStack(spacing: 12) {
                DatePicker("", selection: date, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ko_KR"))
                DatePicker("", selection: date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "ko_KR"))
            }
            .padding()
        }
    }

    private var isCurrentTabLoading: Bool {
        switch viewModel.selectedTab {
        case .orders: return viewModel.isLoadingOrders
        case .deposits: return viewModel.isLoadingDeposits
        }
    }

    private var hasData: Bool {
        switch viewModel.selectedTab {
        case .orders: return !viewModel.filteredOrders.isEmpty
        case .deposits: return !viewModel.filteredDeposits.isEmpty
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .orders:
            OrderListView(
                groupedOrders: viewModel.groupedOrders,
                isLoading: viewModel.isLoadingOrders,
                progress: viewModel.ordersProgress,
                loadedCount: viewModel.ordersLoadedCount,
                progressMessage: viewModel.ordersProgressMessage,
                errorMessage: viewModel.ordersErrorMessage,
                summary: viewModel.orderSummary,
                totalBuyValue: viewModel.totalBuyValue,
                totalSellValue: viewModel.totalSellValue,
                totalFee: viewModel.totalFee,
                filteredCount: viewModel.filteredOrders.count,
                showBuy: viewModel.showBuy,
                showSell: viewModel.showSell,
                isSummaryExpanded: $viewModel.isSummaryExpanded,
                onToggleSide: viewModel.toggleSide
            )
        case .deposits:
            DepositListView(
                groupedDeposits: viewModel.groupedDeposits,
                isLoading: viewModel.isLoadingDeposits,
                progress: viewModel.depositsProgress,
                loadedCount: viewModel.depositsLoadedCount,
                progressMessage: viewModel.depositsProgressMessage,
                errorMessage: viewModel.depositsErrorMessage,
                summary: viewModel.depositSummary,
                totalFiatAmount: viewModel.totalDepositFiatAmount,
                totalCryptoCount: viewModel.totalDepositCryptoCount,
                totalFee: viewModel.totalDepositFee,
                filteredCount: viewModel.filteredDeposits.count,
                showFiat: viewModel.showFiat,
                showCrypto: viewModel.showCrypto,
                isDepositSummaryExpanded: $viewModel.isDepositSummaryExpanded,
                onToggleType: viewModel.toggleDepositType
            )
        }
    }

    private func exportToFile() {
        guard let tempURL = viewModel.exportToExcel() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = tempURL.lastPathComponent
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destURL = panel.url else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destURL)
        } catch {
            viewModel.ordersErrorMessage = "파일 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }
}

#Preview {
    TransactionHistoryView()
}
