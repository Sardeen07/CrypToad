import SwiftUI
import CrypToadCore

/// Full transaction list with a type filter.
struct TransactionHistoryView: View {
    @Environment(PortfolioStore.self) private var store
    let navigate: (Screen) -> Void

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

    private var filtered: [TransactionRecord] {
        store.state.transactions.filter(filter.includes)
    }

    var body: some View {
        VStack(spacing: 24) {
            BackButton { navigate(.home) }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(icon: "list.bullet", title: "All Transactions")

                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if filtered.isEmpty {
                    Text("No transactions yet.")
                        .font(.caption)
                        .foregroundStyle(.gray)
                } else {
                    ForEach(filtered) { tx in
                        TransactionRow(transaction: tx)
                    }
                }
            }
            .cardStyle()
        }
    }
}
