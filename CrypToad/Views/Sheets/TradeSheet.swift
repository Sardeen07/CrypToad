import SwiftUI
import CrypToadCore

/// Buy BTC or ETH with USDC: enter an amount, review a quote, confirm.
///
/// Signed in, the quote comes from the server and its rate is locked for 45 seconds;
/// Buy executes exactly that quote. In the on-device demo the quote is computed locally.
struct TradeSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var asset: Asset = .btc
    @State private var amount: Decimal = 50
    @State private var serverQuote: ServerQuote?
    @State private var quoteError: String?
    @State private var isLoadingQuote = false
    @State private var isBuying = false

    private var available: Decimal { store.state.holdings[.usdc] }

    private var quote: TradeQuote? {
        store.isSignedIn ? serverQuote?.quote : store.quote(spending: amount, on: asset)
    }

    private var validationMessage: String? {
        if amount < Trading.minimumTradeUSD { return "Minimum trade is \(Trading.minimumTradeUSD.usd)." }
        if amount > available { return "You only have \(available.usd) in USDC." }
        return nil
    }

    /// Changing either input fetches a fresh server quote.
    private struct QuoteRequest: Hashable {
        var asset: Asset
        var amount: Decimal
        var refresh: Int
    }

    @State private var refreshCount = 0

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

                if let quote, validationMessage == nil {
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
                        quoteFooter
                    }
                } else if store.isSignedIn && isLoadingQuote && validationMessage == nil {
                    Section("Quote") { ProgressView("Getting a quote…") }
                }

                if let message = validationMessage ?? quoteError {
                    Section {
                        Text(message)
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
                    if isBuying {
                        ProgressView()
                    } else {
                        Button("Buy", action: buy)
                            .fontWeight(.semibold)
                            .disabled(quote == nil || validationMessage != nil)
                    }
                }
            }
            .task(id: QuoteRequest(asset: asset, amount: amount, refresh: refreshCount)) {
                await loadServerQuote()
            }
        }
    }

    @ViewBuilder
    private var quoteFooter: some View {
        if let serverQuote, store.isSignedIn {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(serverQuote.expiresAt.timeIntervalSince(context.date).rounded(.down)))
                Text(seconds > 0 ? "Rate locked by the server for \(seconds)s." : "Quote expired. Tap Buy to get a fresh one.")
            }
        } else {
            Text(store.isUsingLivePrices
                 ? "Live CoinGecko price. Quotes refresh every minute."
                 : "Prices are not live right now; this quote uses the last known price.")
        }
    }

    private func loadServerQuote() async {
        guard store.isSignedIn else { return }
        serverQuote = nil
        quoteError = nil
        guard validationMessage == nil else { return }
        // Debounce typing: only ask the server once the amount settles.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isLoadingQuote = true
        defer { isLoadingQuote = false }
        do {
            let fresh = try await store.serverQuote(spending: amount, on: asset)
            if !Task.isCancelled { serverQuote = fresh }
        } catch {
            if !Task.isCancelled { quoteError = error.localizedDescription }
        }
    }

    private func buy() {
        if !store.isSignedIn {
            if let quote, store.executeTrade(quote) { dismiss() }
            return
        }
        guard let serverQuote else { return }
        if serverQuote.isExpired() {
            refreshCount += 1  // fetch a new rate instead of failing on the server
            return
        }
        isBuying = true
        Task {
            let ok = await store.execute(serverQuote)
            isBuying = false
            if ok { dismiss() } else { refreshCount += 1 }
        }
    }
}
