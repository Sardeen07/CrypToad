import SwiftUI
import CrypToadCore

/// One holding: asset, quantity, dollar value, and 24h price change.
struct BalanceRow: View {
    let asset: Asset
    let quantity: Decimal
    let usdValue: Decimal
    let price: Decimal?
    let change24h: Decimal?

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.color(for: asset))
                        .frame(width: 40, height: 40)
                    Text(asset.glyph)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.displayName)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(asset.format(quantity))
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(usdValue.usd)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                changeLabel
            }
        }
        .rowStyle()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var changeLabel: some View {
        if asset.isStablecoin {
            Text("Stablecoin")
                .font(.caption)
                .foregroundStyle(.gray)
        } else if let change = change24h {
            Text("\(change.signedPercent) · \(price?.usd ?? "—")")
                .font(.caption)
                .foregroundStyle(change >= 0 ? Color.green : Color.red)
                .monospacedDigit()
        } else {
            Text(price?.usd ?? "—")
                .font(.caption)
                .foregroundStyle(.gray)
        }
    }
}
