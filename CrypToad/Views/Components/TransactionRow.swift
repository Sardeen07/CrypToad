import SwiftUI
import CrypToadCore

struct TransactionRow: View {
    let transaction: TransactionRecord

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((transaction.isCredit ? "+" : "-") + transaction.amountUSD.usd)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(transaction.isCredit ? Color.green : Color.white)
                    .monospacedDigit()

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(8)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch transaction.kind {
        case .p2pSent: return "Sent to \(transaction.title)"
        default: return transaction.title
        }
    }

    /// Secondary line, e.g. "+$0.75 → BTC" for a round-up or "0.0005 BTC" for a trade.
    private var detail: String? {
        if transaction.roundUpUSD > 0 {
            return "+\(transaction.roundUpUSD.usd) → \(transaction.investedSummary ?? "USDC")"
        }
        switch transaction.kind {
        case .trade:
            guard let fill = transaction.fills.first else { return nil }
            return "+" + fill.asset.format(fill.quantity)
        case .dcaBuy:
            return transaction.investedSummary.map { "→ \($0)" }
        default:
            return nil
        }
    }

    private var iconName: String {
        switch transaction.kind {
        case .purchase: return "creditcard"
        case .deposit: return "arrow.down.circle"
        case .dcaBuy: return "chart.line.uptrend.xyaxis"
        case .trade: return "arrow.left.arrow.right"
        case .p2pSent: return "paperplane"
        }
    }

    private var iconColor: Color {
        switch transaction.kind {
        case .purchase: return .red
        case .deposit: return .green
        case .dcaBuy: return .blue
        case .trade: return .orange
        case .p2pSent: return .purple
        }
    }
}
