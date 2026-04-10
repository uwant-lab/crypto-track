import SwiftUI

/// 차트 드로잉 도구 선택 툴바입니다.
struct DrawingToolbarView: View {
    @Bindable var viewModel: DrawingViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Drawing tool buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(DrawingType.allCases, id: \.self) { tool in
                        Button {
                            if viewModel.selectedTool == tool {
                                viewModel.cancelDrawing()
                            } else {
                                viewModel.startDrawing(type: tool)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: tool.systemImage)
                                    .font(.system(size: 14))
                                    .frame(width: 24, height: 24)
                                Text(tool.rawValue)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                viewModel.selectedTool == tool
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.clear
                            )
                            .foregroundStyle(
                                viewModel.selectedTool == tool
                                    ? Color.accentColor
                                    : Color.primary
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 4)

            // Action buttons
            HStack(spacing: 8) {
                // Show/hide all toggle
                Button {
                    viewModel.toggleAllVisibility()
                } label: {
                    Image(systemName: viewModel.showAllDrawings ? "eye" : "eye.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(viewModel.showAllDrawings ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(viewModel.showAllDrawings ? "모두 숨기기" : "모두 표시")

                // Delete selected drawing
                if viewModel.selectedDrawingId != nil {
                    Button {
                        viewModel.deleteSelectedDrawing()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .help("선택한 드로잉 삭제")
                }

                // Done button
                Button {
                    viewModel.exitDrawingMode()
                } label: {
                    Text("완료")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundStyle(Color.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
        }
        .frame(height: 52)
        .background(AppColor.secondaryBackground)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = DrawingViewModel()
    DrawingToolbarView(viewModel: vm)
        .frame(width: 600)
}
