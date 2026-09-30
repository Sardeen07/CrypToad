import SwiftUI
import CrypToadCore

struct RoundUpView: View {
    @Environment(PortfolioStore.self) private var store
    let navigate: (Screen) -> Void
    let present: (ActiveSheet) -> Void

    private var settings: RoundUpSettings { store.state.roundUps }

    var body: some View {
        VStack(spacing: 24) {
            BackButton { navigate(.home) }
            totalCard
            statusCard
            allocationCard
            historyCard
        }
    }

    private var totalCard: some View {
        ZStack {
            LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 8) {
                Text("Total Invested via Round-Ups")
                    .font(.subheadline)
                    .opacity(0.8)
                Text(store.state.roundUpTotal.usd)
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: store.state.roundUpTotal)
                let count = store.state.roundUpTransactions.count
                Text("From \(count) purchase\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { settings.enabled }, set: { store.setRoundUpsEnabled($0) })) {
                Text("Round-Up Status")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Text(settings.enabled
                 ? "Round-ups are active. Every card purchase is rounded up and the spare change is invested automatically."
                 : "Round-ups are paused. Turn on to start investing spare change.")
                .font(.caption)
                .foregroundStyle(.gray)

            HStack {
                Text("Multiplier")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Picker("Multiplier", selection: Binding(get: { settings.multiplier }, set: { store.setRoundUpMultiplier($0) })) {
                    Text("1×").tag(1)
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                    Text("5×").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            .disabled(!settings.enabled)
        }
        .cardStyle()
    }

    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Allocation")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                if let name = settings.allocation.presetName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            ForEach(Asset.allCases) { asset in
                AllocationBar(label: "\(asset.displayName) (\(asset.ticker))", percentage: settings.allocation[asset], color: Theme.color(for: asset))
            }

            Button(action: { present(.roundUpAllocation) }) {
                Text("Customize Allocation")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .cardStyle()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Round-Up History")
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            if store.state.roundUpTransactions.isEmpty {
                Text("No round-ups yet. Tap Simulate Purchase on the Home tab.")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            ForEach(store.state.roundUpTransactions) { tx in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+" + tx.roundUpUSD.usd)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                        Text(fillSummary(tx))
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .rowStyle()
            }
        }
        .cardStyle()
    }

    /// "0.0000081 BTC" for a single fill, "to Mixed" for several.
    private func fillSummary(_ tx: TransactionRecord) -> String {
        let bought = tx.fills.filter { !$0.asset.isStablecoin && $0.quantity > 0 }
        if bought.count == 1, let fill = bought.first {
            return fill.asset.format(fill.quantity)
        }
        return "to \(tx.investedSummary ?? "USDC")"
    }
}
