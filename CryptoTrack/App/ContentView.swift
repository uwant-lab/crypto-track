import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("CryptoTrack")
                    .font(.largeTitle.bold())
                Text("포트폴리오 관리")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("CryptoTrack")
        }
    }
}

#Preview {
    ContentView()
}
