import SwiftUI
import CrypToadCore

/// Round-ups: spare change from every purchase, invested by allocation.
struct RoundUpView: View {
    @Environment(PortfolioStore.self) private var store
    let present: (ActiveSheet) -> Void

    private var settings: RoundUpSettings { store.state.roundUps }

    var body: some View {
        ScreenScroll {
            HeroFigure("Invested from round-ups", amount: store.state.roundUpTotal) {
                let count = store.state.roundUpTransactions.count
                Text("From \(count) purchase\(count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardSection {
                    ToggleRow(
                        title: "Round up purchases",
                        subtitle: settings.enabled ? "Spare change is invested automatically" : "Paused",
                        isOn: Binding(get: { settings.enabled }, set: { store.setRoundUpsEnabled($0) })
                    )
                    RowDivider()
                    HStack {
                        Text("Multiplier")
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
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
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .disabled(!settings.enabled)
                    .opacity(settings.enabled ? 1 : 0.5)
                }
                SectionNote("A $4.25 purchase rounds up to $5.00 and invests $0.75. A 2× multiplier invests $1.50.")
            }

            CardSection(settings.allocation.presetName ?? "Allocation") {
                Button("Edit") { present(.roundUpAllocation) }
                    .font(.subheadline.weight(.medium))
            } content: {
                AllocationStrip(weights: Dictionary(uniqueKeysWithValues: Asset.allCases.map { ($0, Decimal(settings.allocation[$0])) }))
                    .padding([.horizontal, .top], Theme.Space.l)
                    .padding(.bottom, Theme.Space.xs)
                ForEach(Array(Asset.allCases.enumerated()), id: \.element) { index, asset in
                    if index > 0 { RowDivider(inset: 56) }
                    InfoRow(asset.displayName) {
                        AssetIcon(asset: asset, size: 28)
                    } trailing: {
                        Text("\(settings.allocation[asset])%")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            CardSection("History") {
                let roundUps = store.state.roundUpTransactions
                if roundUps.isEmpty {
                    EmptyRow(text: "No round-ups yet. Make a purchase from Home to see one here.")
                }
                ForEach(Array(roundUps.enumerated()), id: \.element.id) { index, tx in
                    if index > 0 { RowDivider(inset: 64) }
                    InfoRow(tx.title, subtitle: tx.date.formatted(.dateTime.month(.abbreviated).day())) {
                        IconTile(systemName: TransactionRow.symbol(for: tx))
                    } trailing: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("+" + tx.roundUpUSD.usd)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.positive)
                            Text(fillSummary(tx))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "0.0000081 BTC" for a single fill, "BTC · ETH · USDC" for several.
    private func fillSummary(_ tx: TransactionRecord) -> String {
        let bought = tx.fills.filter { !$0.asset.isStablecoin && $0.quantity > 0 }
        if bought.count == 1, let fill = bought.first {
            return fill.asset.format(fill.quantity)
        }
        return tx.investedTickers ?? "USDC"
    }
}

#Preview {
    NavigationStack { RoundUpView(present: { _ in }).navigationTitle("Round-Ups") }
        .environment(PortfolioStore.preview())
}
