import SwiftUI
import UniformTypeIdentifiers

struct TransactionHistoryView: View {
    @State private var viewModel = TransactionHistoryViewModel()
    @State private var showFromPicker = false
    @State private var showToPicker = false

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
                    .disabled(viewModel.isLoading || !hasData)
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

            HStack(spacing: 12) {
                Picker("거래소", selection: $viewModel.selectedExchange) {
                    Text("전체").tag(Exchange?.none)
                    ForEach(Exchange.allCases, id: \.self) { exchange in
                        Text(exchange.rawValue).tag(Exchange?.some(exchange))
                    }
                }
                .frame(width: 120)

                dateButton(date: $viewModel.dateFrom, showPicker: $showFromPicker)
                Text("~")
                dateButton(date: $viewModel.dateTo, showPicker: $showToPicker)

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

    private var hasData: Bool {
        switch viewModel.selectedTab {
        case .orders: return !viewModel.filteredOrders.isEmpty
        case .deposits: return !viewModel.deposits.isEmpty
        }
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
                progressMessage: viewModel.progressMessage,
                errorMessage: viewModel.errorMessage,
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
                isLoading: viewModel.isLoading,
                progress: viewModel.progress,
                loadedCount: viewModel.loadedCount,
                progressMessage: viewModel.progressMessage,
                errorMessage: viewModel.errorMessage
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
            viewModel.errorMessage = "파일 저장에 실패했습니다: \(error.localizedDescription)"
        }
    }
}

#Preview {
    TransactionHistoryView()
}
