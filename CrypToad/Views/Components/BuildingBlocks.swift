import SwiftUI
import CrypToadCore

/// Every tab's scrolling page: canvas background, standard padding and spacing, and pull to refresh.
/// Single-column pages center at a readable width on iPad; `wide` pages (multi-column layouts)
/// use the full width, aligned with the large navigation title.
struct ScreenScroll<Content: View>: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    var wide = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            let column = VStack(alignment: .leading, spacing: Theme.Space.xl) {
                content
            }
            .padding(.horizontal, sizeClass == .regular ? 20 : Theme.Space.l)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xxl)

            if wide {
                column.frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                column.readableWidth()
            }
        }
        .background(Theme.canvas)
        .refreshable { await store.refreshAll() }
    }
}

extension View {
    /// Large titles on iPhone; on iPad, a centered inline title that lines up with centered content.
    func adaptiveTitleDisplayMode() -> some View {
        modifier(AdaptiveTitleDisplayMode())
    }
}

private struct AdaptiveTitleDisplayMode: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
    }
}

/// The one big number on a screen (balance, recurring amount, total invested).
struct HeroFigure<Detail: View>: View {
    let label: String
    let amount: Decimal
    @ViewBuilder var detail: Detail
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    init(_ label: String, amount: Decimal, @ViewBuilder detail: () -> Detail) {
        self.label = label
        self.amount = amount
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text(amount.usd)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(Theme.quick, value: amount)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

extension HeroFigure where Detail == EmptyView {
    init(_ label: String, amount: Decimal) {
        self.init(label, amount: amount) { EmptyView() }
    }
}

/// Circular quick action under the balance (Apple Wallet style).
struct ActionButton: View {
    let title: String
    let systemImage: String
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 52, height: 52)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.border, lineWidth: 1))
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeStyle())
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// Dims slightly while pressed; nothing else moves.
struct PressFadeStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// A switch with a title and an explanation, inside a card.
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(minHeight: 56)
    }
}

/// A thin stacked bar showing how money is split across assets.
struct AllocationStrip: View {
    /// Share of each asset, in any unit (dollars or percent).
    let weights: [Asset: Decimal]

    private var total: Decimal { weights.values.reduce(0, +) }

    var body: some View {
        GeometryReader { geometry in
            let assets = Asset.allCases.filter { (weights[$0] ?? 0) > 0 }
            let gaps = CGFloat(max(assets.count - 1, 0)) * 2
            HStack(spacing: 2) {
                if total <= 0 {
                    Theme.fill
                } else {
                    ForEach(assets) { asset in
                        Theme.color(for: asset)
                            .frame(width: max(0, (geometry.size.width - gaps) * CGFloat(((weights[asset] ?? 0) / total).doubleValue)))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .animation(Theme.quick, value: weights)
        .accessibilityHidden(true)
    }
}

/// One holding: asset, quantity and share, value, and 24h change.
struct HoldingRow: View {
    let asset: Asset
    let quantity: Decimal
    let usdValue: Decimal
    let share: Decimal?
    let change24h: Decimal?

    var body: some View {
        InfoRow(asset.displayName, subtitle: subtitle) {
            AssetIcon(asset: asset)
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(usdValue.usd)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                changeText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let amount = asset.format(quantity)
        guard let share else { return amount }
        return "\(amount) · \(share.formatted(.number.precision(.fractionLength(0))))%"
    }

    @ViewBuilder
    private var changeText: some View {
        if asset.isStablecoin {
            Text("Stable")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } else if let change = change24h {
            Text(change.signedPercent)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
        } else {
            Text("—")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// Centered message for an empty card.
struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xl)
    }
}
