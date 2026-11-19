import SwiftUI
import CrypToadCore

/// Full account activity, grouped by day like a bank statement, with a type filter.
struct TransactionHistoryView: View {
    @Environment(PortfolioStore.self) private var store

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case spending = "Spending"
        case investing = "Investing"
        case deposits = "Deposits"
        var id: String { rawValue }

        func includes(_ tx: TransactionRecord) -> Bool {
            switch self {
            case .all: return true
            case .spending: return tx.kind == .purchase || tx.kind == .p2pSent
            case .investing: return tx.kind == .dcaBuy || tx.kind == .trade || tx.roundUpUSD > 0
            case .deposits: return tx.kind == .deposit
            }
        }
    }

    @State private var filter: Filter = .all

    /// Newest day first; within a day, newest first.
    private var days: [(day: Date, transactions: [TransactionRecord])] {
        let calendar = Calendar.current
        let filtered = store.state.transactions.filter(filter.includes)
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (day: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        ScreenScroll {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if days.isEmpty {
                CardSection {
                    EmptyRow(text: filter == .all ? "No activity yet." : "No \(filter.rawValue.lowercased()) activity yet.")
                }
            }

            ForEach(days, id: \.day) { group in
                CardSection(group.day.activitySectionTitle) {
                    Text(dayTotal(group.transactions))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                } content: {
                    ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, tx in
                        if index > 0 { RowDivider(inset: 64) }
                        TransactionRow(transaction: tx, timeOnly: true)
                    }
                }
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Theme.quick, value: filter)
    }

    /// Net cash for the day: deposits in, purchases out. Conversions don't change it.
    private func dayTotal(_ transactions: [TransactionRecord]) -> String {
        let net = transactions.reduce(Decimal(0)) { total, tx in
            switch tx.kind {
            case .deposit: return total + tx.amountUSD
            case .purchase, .p2pSent: return total - tx.amountUSD
            case .trade, .dcaBuy: return total
            }
        }
        if net == 0 { return "" }
        return net > 0 ? "+" + net.usd : "\u{2212}" + (-net).usd
    }
}

#Preview {
    NavigationStack { TransactionHistoryView() }
        .environment(PortfolioStore.preview())
}
