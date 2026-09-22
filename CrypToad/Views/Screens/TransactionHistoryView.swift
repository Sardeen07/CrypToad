import SwiftUI

/// Full transaction list, reached from "View All Transactions" on the home screen.
struct TransactionHistoryView: View {
    let transactions: [Transaction]
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

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.blue)
                    Text("All Transactions")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .font(.headline)

                if transactions.isEmpty {
                    Text("No transactions yet.")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    ForEach(transactions) { tx in
                        TransactionRow(transaction: tx)
                    }
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
