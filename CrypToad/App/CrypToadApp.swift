import SwiftUI

@main
struct CrypToadApp: App {
    @State private var store: PortfolioStore
    @State private var lock: AppLock

    init() {
        let store = PortfolioStore.live()
        _store = State(initialValue: store)
        // Start locked if the user turned on Face ID, so content never flashes before auth.
        _lock = State(initialValue: AppLock(startLocked: store.state.requireBiometricUnlock))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .preferredColorScheme(.dark)
        }
    }
}
