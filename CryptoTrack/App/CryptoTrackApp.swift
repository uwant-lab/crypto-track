import SwiftUI

@main
struct CryptoTrackApp: App {
    @State private var lockManager = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CloudSyncService.shared.startObserving()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    if lockManager.isLocked {
                        LockScreenView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: lockManager.isLocked)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        lockManager.lock()
                    }
                }
        }
    }
}
