import SwiftUI

/// Root view. Holds prototype state (mock data) and routes between screens.
struct ContentView: View {
    @State private var currentView: String = "home"
    @State private var balances = Balance(usdc: 1234.56, btc: 0.0234, eth: 0.456)
    @State private var roundUpEnabled = true
    @State private var roundUpTotal = 127.43
    @State private var dcaSettings = DCASettings(
        enabled: true,
        amount: 100,
        frequency: "weekly",
        allocation: ["btc": 50, "eth": 30, "usdc": 20]
    )
    @State private var transactions: [Transaction] = [
        Transaction(id: 1, type: .purchase, merchant: "Starbucks", recipient: nil, amount: 4.25, roundUp: 0.75, date: "2025-11-13", crypto: "BTC"),
        Transaction(id: 2, type: .dca, merchant: nil, recipient: nil, amount: 100, roundUp: 0, date: "2025-11-11", crypto: "Mixed"),
        Transaction(id: 3, type: .purchase, merchant: "Amazon", recipient: nil, amount: 47.89, roundUp: 0.11, date: "2025-11-12", crypto: "ETH"),
        Transaction(id: 4, type: .deposit, merchant: nil, recipient: nil, amount: 2500, roundUp: 0, date: "2025-11-10", crypto: "USDC"),
        Transaction(id: 5, type: .p2pSent, merchant: nil, recipient: "Sarah K.", amount: 25, roundUp: 0, date: "2025-11-09", crypto: "USDC")
    ]

    /// Static mock prices. A real build would pull these from a market-data API.
    let prices: [String: Double] = ["btc": 92340, "eth": 3120, "usdc": 1.00]

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.13)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView()

                ScrollView {
                    VStack(spacing: 16) {
                        switch currentView {
                        case "roundup":
                            RoundUpView(roundUpEnabled: $roundUpEnabled, roundUpTotal: $roundUpTotal, transactions: $transactions, changeView: changeView)
                        case "dca":
                            DCAView(dcaSettings: $dcaSettings, changeView: changeView)
                        case "card":
                            CardView()
                        case "history":
                            TransactionHistoryView(transactions: transactions, changeView: changeView)
                        default:
                            HomeView(balances: $balances, roundUpTotal: $roundUpTotal, transactions: $transactions, prices: prices, simulatePurchase: simulatePurchase, changeView: changeView)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }

                BottomNavView(currentView: $currentView)
            }
        }
    }

    func changeView(to view: String) {
        currentView = view
    }

    /// Simulates a card purchase and its round-up so the flow can be demoed without a card issuer.
    func simulatePurchase() {
        let merchants = ["Whole Foods", "Gas Station", "Target", "Restaurant"]
        let merchant = merchants.randomElement()!
        let amount = Double.random(in: 5...55)
        let roundUp = ceil(amount) - amount

        let newTransaction = Transaction(
            id: transactions.count + 1,
            type: .purchase,
            merchant: merchant,
            recipient: nil,
            amount: amount,
            roundUp: roundUp,
            date: Date().formatted(.dateTime.year().month().day()),
            crypto: "BTC"
        )

        transactions.insert(newTransaction, at: 0)
        roundUpTotal += roundUp
        balances.usdc -= amount
    }
}

#Preview {
    ContentView()
}
