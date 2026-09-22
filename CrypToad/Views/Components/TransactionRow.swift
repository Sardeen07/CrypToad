import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transactionTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text(transaction.date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(transaction.type == .deposit ? "+" : "-")$\(transaction.amount, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type == .deposit ? .green : .white)

                if transaction.roundUp > 0 {
                    Text("+$\(transaction.roundUp, specifier: "%.2f") invested")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(8)
    }

    var iconName: String {
        switch transaction.type {
        case .purchase: return "creditcard"
        case .deposit: return "arrow.up.circle"
        case .dca: return "chart.line.uptrend.xyaxis"
        case .p2pSent: return "paperplane"
        }
    }

    var iconColor: Color {
        switch transaction.type {
        case .purchase: return .red
        case .deposit: return .green
        case .dca: return .blue
        case .p2pSent: return .purple
        }
    }

    var iconBackground: Color {
        switch transaction.type {
        case .purchase: return Color.red.opacity(0.2)
        case .deposit: return Color.green.opacity(0.2)
        case .dca: return Color.blue.opacity(0.2)
        case .p2pSent: return Color.purple.opacity(0.2)
        }
    }

    var transactionTitle: String {
        switch transaction.type {
        case .purchase: return transaction.merchant ?? "Purchase"
        case .deposit: return "Paycheck Deposit"
        case .dca: return "Auto-Investment (DCA)"
        case .p2pSent: return "Sent to \(transaction.recipient ?? "User")"
        }
    }
}
