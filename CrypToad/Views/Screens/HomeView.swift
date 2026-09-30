import SwiftUI
import CrypToadCore

struct HomeView: View {
    @Environment(PortfolioStore.self) private var store
    let navigate: (Screen) -> Void
    let present: (ActiveSheet) -> Void

    var body: some View {
        VStack(spacing: 24) {
            portfolioCard
            holdings
            quickActions
            recentActivity
        }
    }

    // MARK: Sections

    private var portfolioCard: some View {
        ZStack {
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 8) {
                Text("Total Portfolio Value")
                    .font(.subheadline)
                    .opacity(0.8)

                Text(store.totalValue.usd)
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: store.totalValue)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("24h Change")
                            .font(.caption)
                            .opacity(0.8)
                        if let change = store.change24h {
                            Text("\(change.amount.signedUSD) (\(change.percent.signedPercent))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(change.amount >= 0 ? Color.green : Color(red: 1, green: 0.55, blue: 0.55))
                                .monospacedDigit()
                        } else {
                            Text("—")
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    PriceStatusBadge()
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var holdings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "wallet.pass", title: "Your Holdings")

            ForEach(Asset.allCases) { asset in
                BalanceRow(
                    asset: asset,
                    quantity: store.state.holdings[asset],
                    usdValue: store.value(of: asset),
                    price: store.prices.price(of: asset),
                    change24h: store.prices.change24h(of: asset)
                )
            }
        }
        .cardStyle()
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                QuickActionButton(icon: "creditcard", title: "Simulate Purchase", color: .blue) {
                    store.simulatePurchase()
                }
                QuickActionButton(icon: "arrow.up.circle", title: "Round-Ups: \(store.state.roundUpTotal.usd)", color: .green) {
                    navigate(.roundUp)
                }
            }
            HStack(spacing: 12) {
                QuickActionButton(icon: "bitcoinsign.circle", title: "Buy BTC / ETH", color: .orange) {
                    present(.trade)
                }
                QuickActionButton(icon: "banknote", title: "Add Paycheck", color: .indigo) {
                    store.simulatePaycheck()
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "clock", title: "Recent Activity")

            ForEach(store.state.transactions.prefix(3)) { tx in
                TransactionRow(transaction: tx)
            }

            Button(action: { navigate(.history) }) {
                Text("View All Transactions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .cardStyle()
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// "● Live · 12s ago" / "Updating…" / "Offline" indicator for market data.
struct PriceStatusBadge: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            label
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.25))
        .clipShape(Capsule())
    }

    private var dotColor: Color {
        switch store.priceStatus {
        case .live: return .green
        case .loading, .idle: return .yellow
        case .failed: return .red
        }
    }

    @ViewBuilder
    private var label: some View {
        switch store.priceStatus {
        case .live:
            Text("Live · \(Text(store.prices.fetchedAt, style: .relative)) ago")
        case .loading, .idle:
            Text("Updating prices…")
        case .failed:
            Text(store.prices.isPlaceholder ? "Offline · demo prices" : "Offline · last known")
        }
    }
}

#Preview {
    ScrollView {
        HomeView(navigate: { _ in }, present: { _ in })
            .padding()
    }
    .background(Theme.background)
    .environment(PortfolioStore.preview())
}
