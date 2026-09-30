import SwiftUI
import CrypToadCore

/// Debit card screen. No real card is issued; the card number and PIN are placeholders.
struct CardView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppLock.self) private var lock

    @State private var revealedPIN = false
    @State private var showWalletInfo = false

    private var frozen: Bool { store.state.cardFrozen }

    var body: some View {
        VStack(spacing: 24) {
            card
            settings
            notice
        }
        .alert("Apple Wallet", isPresented: $showWalletInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Adding a card to Apple Wallet requires a licensed card issuer and Apple's In-App Provisioning entitlement (PassKit). This prototype doesn't issue real cards.")
        }
    }

    private var card: some View {
        ZStack {
            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                .saturation(frozen ? 0 : 1)

            VStack {
                HStack {
                    Text("CrypToad")
                        .font(.title3)
                        .fontWeight(.bold)
                    Spacer()
                    Text(frozen ? "FROZEN" : "Debit")
                        .font(.caption)
                        .fontWeight(frozen ? .bold : .regular)
                        .opacity(0.8)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Card Number")
                        .font(.caption2)
                        .opacity(0.8)
                    Text("•••• •••• •••• 8734")
                        .font(.title3)
                        .tracking(2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Valid Thru")
                                .font(.caption2)
                                .opacity(0.8)
                            Text("12/29")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Spendable")
                                .font(.caption2)
                                .opacity(0.8)
                            Text(store.state.holdings[.usdc].usd)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(24)

            if frozen {
                Image(systemName: "snowflake")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut, value: frozen)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Card Settings")
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            SettingsButton(icon: "wallet.pass", title: "Add to Apple Wallet", subtitle: "Tap to pay anywhere") {
                showWalletInfo = true
            }

            Toggle(isOn: Binding(get: { frozen }, set: { store.setCardFrozen($0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Freeze Card", systemImage: frozen ? "lock.fill" : "lock")
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                    Text(frozen ? "Purchases are blocked until you unfreeze." : "Temporarily disable spending")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .rowStyle()

            SettingsButton(
                icon: revealedPIN ? "eye.slash" : "eye",
                title: revealedPIN ? "PIN: 2468 (demo)" : "View PIN",
                subtitle: revealedPIN ? "Hides automatically in 5 seconds" : "Requires \(lock.biometryName)"
            ) {
                Task { await revealPIN() }
            }
        }
        .cardStyle()
    }

    private var notice: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Real-time Notifications")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(red: 0.4, green: 0.6, blue: 1.0))
                Text("Get instant alerts for every transaction on your card")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.5, green: 0.7, blue: 1.0))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.3), lineWidth: 1))
    }

    private func revealPIN() async {
        if revealedPIN {
            revealedPIN = false
            return
        }
        guard await lock.authenticate(reason: "View your card PIN") else { return }
        revealedPIN = true
        try? await Task.sleep(for: .seconds(5))
        revealedPIN = false
    }
}
