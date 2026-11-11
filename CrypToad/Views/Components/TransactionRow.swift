import SwiftUI
import CrypToadCore

/// One line of account activity, styled like a bank statement:
/// uniform icon tile, merchant, status/time, and a right-aligned amount.
struct TransactionRow: View {
    let transaction: TransactionRecord
    /// Inside a list already grouped by day, show only the time.
    var timeOnly = false

    var body: some View {
        InfoRow(title, subtitle: subtitle, subtitleColor: skipped ? Theme.warning : Theme.textSecondary) {
            IconTile(systemName: Self.symbol(for: transaction))
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(transaction.isCredit ? Theme.positive : Theme.textPrimary)
                if let detail {
                    Text(detail.text)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(detail.color)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var skipped: Bool { transaction.roundUpSkipped == true }

    private var title: String {
        switch transaction.kind {
        case .p2pSent: return "Sent to \(transaction.title)"
        case .dcaBuy: return "Recurring buy"
        default: return transaction.title
        }
    }

    private var subtitle: String {
        let when = timeOnly
            ? transaction.date.formatted(date: .omitted, time: .shortened)
            : transaction.date.shortTimestamp
        if skipped { return "Round-up skipped · \(when)" }
        return "\(kindLabel) · \(when)"
    }

    private var kindLabel: String {
        switch transaction.kind {
        case .purchase: return "Purchase"
        case .deposit: return "Deposit"
        case .dcaBuy: return "Auto-invest"
        case .trade: return "Trade"
        case .p2pSent: return "Transfer"
        }
    }

    /// Money in shows "+", money out shows "−"; conversions (trades, DCA) show no sign.
    private var amountText: String {
        switch transaction.kind {
        case .deposit: return "+" + transaction.amountUSD.usd
        case .purchase, .p2pSent: return "\u{2212}" + transaction.amountUSD.usd
        case .trade, .dcaBuy: return transaction.amountUSD.usd
        }
    }

    /// Second line on the right: what was invested.
    private var detail: (text: String, color: Color)? {
        if transaction.roundUpUSD > 0 {
            return ("+\(transaction.roundUpUSD.usd) invested", Theme.positive)
        }
        switch transaction.kind {
        case .trade:
            guard let fill = transaction.fills.first else { return nil }
            return (fill.asset.format(fill.quantity), Theme.textSecondary)
        case .dcaBuy:
            return transaction.investedTickers.map { ($0, Theme.textSecondary) }
        default:
            return nil
        }
    }

    /// One symbol per kind of activity; purchases get a symbol for the merchant's category.
    static func symbol(for transaction: TransactionRecord) -> String {
        switch transaction.kind {
        case .deposit: return "arrow.down"
        case .dcaBuy: return "repeat"
        case .trade: return "arrow.left.arrow.right"
        case .p2pSent: return "person"
        case .purchase: return merchantSymbol(transaction.title)
        }
    }

    static func merchantSymbol(_ merchant: String) -> String {
        let name = merchant.lowercased()
        let categories: [(String, [String])] = [
            ("cup.and.saucer", ["starbucks", "coffee", "cafe", "dunkin"]),
            ("car", ["uber", "lyft", "taxi"]),
            ("fuelpump", ["shell", "chevron", "exxon", "gas station"]),
            ("cart", ["whole foods", "trader joe", "kroger", "safeway", "grocery", "market"]),
            ("fork.knife", ["chipotle", "mcdonald", "kfc", "restaurant", "pizza", "burger"]),
            ("airplane", ["airline", "airways"]),
            ("bag", ["amazon", "target", "walmart", "store", "shop", "apple"])
        ]
        return categories.first { $0.1.contains { name.contains($0) } }?.0 ?? "creditcard"
    }
}

extension TransactionRecord {
    /// "BTC · ETH · USDC": every asset this transaction bought, or nil if none.
    var investedTickers: String? {
        let tickers = fills.filter { $0.quantity > 0 }.map(\.asset.ticker)
        return tickers.isEmpty ? nil : tickers.joined(separator: " · ")
    }
}

extension Date {
    /// "8:00 AM" today, "Yesterday", otherwise "Nov 9". Short enough for one line.
    var shortTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Today", "Yesterday", "Monday, Nov 9", or "Nov 9, 2025" for section headers.
    var activitySectionTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}
