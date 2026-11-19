import SwiftUI
import CrypToadCore

/// The dashboard. Hierarchy, top to bottom: total balance → actions → holdings →
/// this month's money in and out → recent activity. On iPad it becomes two columns:
/// what you have on the left, what happened on the right.
struct HomeView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    let present: (ActiveSheet) -> Void

    var body: some View {
        ScreenScroll(wide: sizeClass == .regular) {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        balance
                        actions
                        holdings
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        thisMonth
                        recentActivity
                    }
                }
            } else {
                balance
                actions
                holdings
                thisMonth
                recentActivity
            }
        }
    }

    // MARK: Balance

    private var balance: some View {
        HeroFigure("Total balance", amount: store.totalValue) {
            if let change = store.change24h {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: change.amount >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.footnote.weight(.bold))
                    Text("\(change.amount.signedUSD) (\(change.percent.signedPercent)) today")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(change.amount >= 0 ? Theme.positive : Theme.negative)
            }
            StatusLine()
                .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            ActionButton(title: "Buy", systemImage: "plus", accessibilityLabel: "Buy") {
                present(.trade)
            }
            ActionButton(title: "Deposit", systemImage: "arrow.down", accessibilityLabel: "Simulate paycheck") {
                store.simulatePaycheck()
            }
            ActionButton(title: "Purchase", systemImage: "creditcard", accessibilityLabel: "Simulate purchase") {
                store.simulatePurchase()
            }
            if store.bank.linked {
                ActionButton(title: "Bank Sync", systemImage: "building.columns", accessibilityLabel: "Round up bank purchases") {
                    Task { await store.syncBank() }
                }
            }
        }
        .disabled(store.isWorking)
    }

    // MARK: Holdings

    private var holdings: some View {
        CardSection("Holdings") {
            AllocationStrip(weights: values)
                .padding([.horizontal, .top], Theme.Space.l)
                .padding(.bottom, Theme.Space.xs)

            ForEach(Array(Asset.allCases.enumerated()), id: \.element) { index, asset in
                if index > 0 { RowDivider(inset: 64) }
                HoldingRow(
                    asset: asset,
                    quantity: store.state.holdings[asset],
                    usdValue: store.value(of: asset),
                    share: share(of: asset),
                    change24h: store.prices.change24h(of: asset)
                )
            }
        }
    }

    private var values: [Asset: Decimal] {
        Dictionary(uniqueKeysWithValues: Asset.allCases.map { ($0, store.value(of: $0)) })
    }

    private func share(of asset: Asset) -> Decimal? {
        let total = store.totalValue
        guard total > 0 else { return nil }
        return store.value(of: asset) / total * 100
    }

    // MARK: This month

    @Environment(\.dynamicTypeSize) private var typeSize

    private var thisMonth: some View {
        let summary = MonthSummary(store.state.transactions)
        return CardSection("This month") {
            if typeSize.isAccessibilitySize {
                stat("Spent", summary.spent)
                RowDivider()
                stat("Invested", summary.invested)
                RowDivider()
                stat("Deposited", summary.deposited)
            } else {
                HStack(spacing: 0) {
                    stat("Spent", summary.spent)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    stat("Invested", summary.invested)
                    Rectangle().fill(Theme.border).frame(width: 1)
                    stat("Deposited", summary.deposited)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func stat(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.usd)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.l)
        .accessibilityElement(children: .combine)
    }

    // MARK: Activity

    private var recentActivity: some View {
        CardSection("Recent activity") {
            NavigationLink("See All") { TransactionHistoryView() }
                .font(.subheadline.weight(.medium))
        } content: {
            let recent = store.state.transactions.prefix(4)
            if recent.isEmpty {
                EmptyRow(text: "No activity yet.")
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 { RowDivider(inset: 64) }
                    TransactionRow(transaction: tx)
                }
            }
        }
    }
}

/// One quiet line under the balance: where the data lives and how fresh prices are.
struct StatusLine: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        Group {
            switch store.priceStatus {
            case .live:
                Text("\(mode) · Prices updated ") + Text(store.prices.fetchedAt, style: .relative) + Text(" ago")
            case .loading, .idle:
                Text("\(mode) · Updating prices…")
            case .failed:
                Text("\(mode) · Offline, showing \(store.prices.isPlaceholder ? "sample" : "last known") prices")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textTertiary)
        .lineLimit(2)
    }

    private var mode: String {
        store.isSignedIn ? "Synced" : "On-device demo"
    }
}

/// Money in and out during the current calendar month.
struct MonthSummary {
    var spent: Decimal = 0
    var invested: Decimal = 0
    var deposited: Decimal = 0

    init(_ transactions: [TransactionRecord], now: Date = Date(), calendar: Calendar = .current) {
        for tx in transactions where calendar.isDate(tx.date, equalTo: now, toGranularity: .month) {
            switch tx.kind {
            case .purchase, .p2pSent: spent += tx.amountUSD
            case .deposit: deposited += tx.amountUSD
            case .dcaBuy, .trade: invested += tx.amountUSD
            }
            invested += tx.roundUpUSD
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(present: { _ in })
            .navigationTitle("Portfolio")
    }
    .environment(PortfolioStore.preview())
    .tint(Theme.brand)
}
