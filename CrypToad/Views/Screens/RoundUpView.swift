import SwiftUI

struct RoundUpView: View {
    @Binding var roundUpEnabled: Bool
    @Binding var roundUpTotal: Double
    @Binding var transactions: [Transaction]
    let changeView: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Button(action: { changeView("home") }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to Home")
                }
                .foregroundColor(.blue)
                .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Total Invested Card
            ZStack {
                LinearGradient(colors: [Color.green, Color.green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Invested via Round-Ups")
                        .font(.subheadline)
                        .opacity(0.8)

                    Text("$\(roundUpTotal, specifier: "%.2f")")
                        .font(.system(size: 40, weight: .bold))

                    Text("From \(transactions.filter { $0.roundUp > 0 }.count) purchases")
                        .font(.caption)
                        .opacity(0.9)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .cornerRadius(16)

            // Round-Up Status
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Round-Up Status")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $roundUpEnabled)
                        .labelsHidden()
                }

                Text(roundUpEnabled ? "Round-ups are active. Every purchase will be rounded up and invested automatically." : "Round-ups are paused. Turn on to start investing spare change.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )

            // Allocation Settings
            VStack(alignment: .leading, spacing: 16) {
                Text("Allocation Settings")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                AllocationBar(label: "Bitcoin (BTC)", percentage: 50, color: .orange)
                AllocationBar(label: "Ethereum (ETH)", percentage: 30, color: .purple)
                AllocationBar(label: "USDC (Stable)", percentage: 20, color: .blue)

                Button(action: {}) {
                    Text("Customize Allocation")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )

            // Round-Up History
            VStack(alignment: .leading, spacing: 12) {
                Text("Round-Up History")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                ForEach(transactions.filter { $0.roundUp > 0 }) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.merchant ?? "Purchase")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            Text(tx.date)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("+$\(tx.roundUp, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            Text("to \(tx.crypto)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(12)
                    .background(Color(red: 0.26, green: 0.26, blue: 0.28))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.36, green: 0.36, blue: 0.38), lineWidth: 1)
                    )
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
