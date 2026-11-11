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
        ScreenScroll {
            PaymentCard(frozen: frozen)

            CardSection {
                InfoRow("Available to spend", subtitle: "USDC balance") {
                    Text(store.state.holdings[.usdc].usd)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardSection("Controls") {
                    ToggleRow(
                        title: "Freeze card",
                        subtitle: frozen ? "Purchases are declined until you unfreeze" : "Temporarily block new purchases",
                        isOn: Binding(get: { frozen }, set: { store.setCardFrozen($0) })
                    )
                    RowDivider(inset: 64)
                    Button {
                        Task { await revealPIN() }
                    } label: {
                        InfoRow(revealedPIN ? "PIN 2468" : "Show PIN", subtitle: revealedPIN ? "Hides in 5 seconds" : "Requires \(lock.biometryName)") {
                            IconTile(systemName: revealedPIN ? "eye.slash" : "eye")
                        } trailing: {
                            Chevron()
                        }
                    }
                    .buttonStyle(.row)
                    RowDivider(inset: 64)
                    Button {
                        showWalletInfo = true
                    } label: {
                        InfoRow("Add to Apple Wallet") {
                            IconTile(systemName: "wallet.pass")
                        } trailing: {
                            Chevron()
                        }
                    }
                    .buttonStyle(.row)
                }
                SectionNote("This is a demo card. No real card is issued and the PIN is a placeholder.")
            }
        }
        .alert("Apple Wallet", isPresented: $showWalletInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Adding a card to Apple Wallet requires a licensed card issuer and Apple's In-App Provisioning entitlement (PassKit). This prototype doesn't issue real cards.")
        }
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

/// The card itself: a flat graphite card, the same in light and dark mode, like a physical card.
struct PaymentCard: View {
    let frozen: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text("CrypToad")
                    .font(.headline)
                Spacer()
                if frozen {
                    Label("Frozen", systemImage: "snowflake")
                        .font(.footnote.weight(.semibold))
                } else {
                    Text("Debit")
                        .font(.footnote.weight(.medium))
                        .opacity(0.7)
                }
            }
            Spacer()
            Text("•••• 8734")
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .tracking(1.5)
            HStack {
                Text("Valid thru 12/29")
                    .font(.footnote)
                    .opacity(0.7)
                Spacer()
                Text("USDC")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .aspectRatio(1.586, contentMode: .fit)  // ISO/IEC 7810 ID-1, a real card's proportions
        .background(Color(hex: 0x1B1D22), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .opacity(frozen ? 0.55 : 1)
        .frame(maxWidth: .infinity)
        .animation(Theme.quick, value: frozen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(frozen ? "CrypToad debit card ending in 8734, frozen" : "CrypToad debit card ending in 8734")
    }
}

#Preview {
    NavigationStack { CardView().navigationTitle("Card") }
        .environment(PortfolioStore.preview())
        .environment(AppLock())
}
