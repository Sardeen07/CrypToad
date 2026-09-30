import SwiftUI
import CrypToadCore

struct SettingsSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.dismiss) private var dismiss

    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: biometricBinding) {
                        Label("Require \(lock.biometryName)", systemImage: lock.biometryIcon)
                    }
                    if let error = lock.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Locks CrypToad whenever it leaves the screen. Biometric data stays in the Secure Enclave and never reaches the app.")
                }

                Section("Market data") {
                    LabeledContent("Source", value: "CoinGecko")
                    LabeledContent("Status", value: statusText)
                    if !store.prices.isPlaceholder {
                        LabeledContent("Last updated") {
                            Text(store.prices.fetchedAt.formatted(date: .omitted, time: .standard))
                        }
                    }
                    Button("Refresh now") {
                        Task { await store.refreshPrices() }
                    }
                }

                Section {
                    Button("Reset demo data", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Restores the starting balances and transactions.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Source code on GitHub", destination: URL(string: "https://github.com/Sardeen07/CrypToad")!)
                    Text("CrypToad is a personal project. It does not hold real funds or issue real cards, and nothing in it is financial advice. Crypto is not FDIC insured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.resetDemoData() }
            }
        }
    }

    /// Turning the lock on or off requires authenticating first.
    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { store.state.requireBiometricUnlock },
            set: { newValue in
                Task { @MainActor in
                    let reason = newValue ? "Turn on app lock" : "Turn off app lock"
                    if await lock.authenticate(reason: reason) {
                        store.setRequireBiometricUnlock(newValue)
                    }
                }
            }
        )
    }

    private var statusText: String {
        switch store.priceStatus {
        case .idle: return "Waiting"
        case .loading: return "Updating…"
        case .live: return "Live"
        case .failed(let message): return message
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
