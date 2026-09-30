import SwiftUI
import CrypToadCore

/// Buy BTC or ETH with USDC: enter an amount, review a live quote, confirm.
struct TradeSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var asset: Asset = .btc
    @State private var amount: Decimal = 50

    private var available: Decimal { store.state.holdings[.usdc] }
    private var quote: TradeQuote? { store.quote(spending: amount, on: asset) }

    private var validationMessage: String? {
        if amount < Trading.minimumTradeUSD { return "Minimum trade is \(Trading.minimumTradeUSD.usd)." }
        if amount > available { return "You only have \(available.usd) in USDC." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Asset", selection: $asset) {
                        Text("Bitcoin").tag(Asset.btc)
                        Text("Ethereum").tag(Asset.eth)
                    }
                    .pickerStyle(.segmented)

                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())

                    HStack {
                        Text("Available: \(available.usd) USDC")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Max") { amount = available.rounded(2, .down) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Pay with USDC")
                }

                if let quote {
                    Section {
                        LabeledContent("Price", value: "\(quote.priceUSD.usd) / \(asset.ticker)")
                        LabeledContent("Fee (1%)", value: quote.feeUSD.usd)
                        LabeledContent("Converted", value: quote.netUSD.usd)
                        LabeledContent("You receive") {
                            Text(asset.format(quote.quantity))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    } header: {
                        Text("Quote")
                    } footer: {
                        Text(priceFooter)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Buy \(asset.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Buy") {
                        if let quote, store.executeTrade(quote) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(quote == nil || validationMessage != nil)
                }
            }
        }
    }

    private var priceFooter: String {
        if store.isUsingLivePrices {
            return "Live CoinGecko price. Quotes refresh every minute."
        }
        return "Prices are not live right now; this quote uses the last known price."
    }
}
