import SwiftUI

struct HomeView: View {
    @Binding var balances: Balance
    @Binding var roundUpTotal: Double
    @Binding var transactions: [Transaction]
    let prices: [String: Double]
    let simulatePurchase: () -> Void
    let changeView: (String) -> Void

    var totalUSDValue: Double {
        balances.usdc * prices["usdc"]! +
        balances.btc * prices["btc"]! +
        balances.eth * prices["eth"]!
    }

    var body: some View {
        VStack(spacing: 24) {
            // Total Balance Card
            ZStack {
                LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Portfolio Value")
                        .font(.subheadline)
                        .opacity(0.8)

                    Text("$\(totalUSDValue, specifier: "%.2f")")
                        .font(.system(size: 40, weight: .bold))

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("24h Change")
                                .font(.caption)
                                .opacity(0.8)
                            Text("+$127.43 (+5.2%)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(Color.green.opacity(0.8))
                        }
                    }
                    .font(.caption)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .cornerRadius(16)

            // Crypto Balances
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass")
                        .foregroundColor(.blue)
                    Text("Your Holdings")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .font(.headline)

                BalanceRow(symbol: "$", name: "USDC", amount: balances.usdc, crypto: "USDC", usdValue: balances.usdc * prices["usdc"]!, change: "Stablecoin", isPositive: nil, color: .blue)

                BalanceRow(symbol: "₿", name: "Bitcoin", amount: balances.btc, crypto: "BTC", usdValue: balances.btc * prices["btc"]!, change: "+12.4%", isPositive: true, color: .orange)

                BalanceRow(symbol: "Ξ", name: "Ethereum", amount: balances.eth, crypto: "ETH", usdValue: balances.eth * prices["eth"]!, change: "+8.7%", isPositive: true, color: .purple)
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )

            // Quick Actions
            HStack(spacing: 12) {
                Button(action: simulatePurchase) {
                    VStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .font(.title2)
                        Text("Simulate Purchase")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }

                Button(action: { changeView("roundup") }) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.circle")
                            .font(.title2)
                        Text("Round-Ups: $\(roundUpTotal, specifier: "%.2f")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }

            // Recent Activity
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    Text("Recent Activity")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .font(.headline)

                ForEach(Array(transactions.prefix(3))) { tx in
                    TransactionRow(transaction: tx)
                }

                Button(action: { changeView("history") }) {
                    Text("View All Transactions")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )
        }
    }
}
