import SwiftUI

@main
struct CrypToadApp: App {
    @State private var store: PortfolioStore
    @State private var lock: AppLock

    init() {
        // UI tests launch with -ui-testing: fresh in-memory data and fixed prices, no saved session.
        let store = ProcessInfo.processInfo.arguments.contains("-ui-testing") ? PortfolioStore.uiTesting() : PortfolioStore.live()
        _store = State(initialValue: store)
        // Start locked if the user turned on Face ID, so content never flashes before auth.
        _lock = State(initialValue: AppLock(startLocked: store.state.requireBiometricUnlock))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .tint(Theme.brand)
                // UI tests pass -force-dark to check dark mode (the headless simulator ignores its own setting).
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-force-dark") ? .dark : nil)
        }
    }
}
