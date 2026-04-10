import SwiftUI

/// 플랫폼에 따라 macOS에서는 NavigationSplitView 사이드바,
/// iOS에서는 TabView를 사용하는 최상위 레이아웃입니다.
struct AdaptiveRootView: View {
    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List {
                NavigationLink {
                    DashboardView()
                } label: {
                    Label("대시보드", systemImage: "chart.pie.fill")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("설정", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("CryptoTrack")
        } detail: {
            DashboardView()
        }
        #else
        TabView {
            DashboardView()
                .tabItem {
                    Label("대시보드", systemImage: "chart.pie.fill")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
        }
        #endif
    }
}

#Preview {
    AdaptiveRootView()
}
