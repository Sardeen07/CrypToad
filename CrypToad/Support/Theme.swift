import SwiftUI
import UIKit
import CrypToadCore

/// CrypToad's design tokens. Every color, radius, and spacing value in the app comes from here.
///
/// Neutrals are iOS's semantic system colors, so screens and native sheets/forms match exactly
/// and light/dark mode come for free. There is one brand color, and the financial colors
/// (positive / negative / warning) are reserved for meaning, never decoration.
enum Theme {
    // MARK: Color

    /// Page background behind cards.
    static let canvas = Color(uiColor: .systemGroupedBackground)
    /// Cards and rows.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    /// Fills inside a surface: icon tiles, tracks, inactive controls.
    static let fill = Color(uiColor: .tertiarySystemFill)
    /// 1px hairline around cards and between rows.
    static let border = Color.dynamic(light: 0xE3E3E8, dark: 0x2C2C2F)

    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)

    /// The one brand color, for text and tint: links, selected states, the active tab, icons.
    static let brand = Color.dynamic(light: 0x2D5BE3, dark: 0x6B8CFF)
    /// The brand color behind white text (primary buttons). Darker in dark mode so white
    /// text keeps at least 4.5:1 contrast (WCAG AA).
    static let brandFill = Color.dynamic(light: 0x2D5BE3, dark: 0x3558E0)
    /// Money in, gains.
    static let positive = Color.dynamic(light: 0x167A37, dark: 0x3DD06C)
    /// Losses, failures, destructive actions. Use sparingly.
    static let negative = Color.dynamic(light: 0xD1352B, dark: 0xFF6259)
    /// Pending or skipped items.
    static let warning = Color.dynamic(light: 0xA86400, dark: 0xF2A93B)

    /// Official asset brand colors, used only to identify an asset.
    static func color(for asset: Asset) -> Color {
        switch asset {
        case .btc: return Color(hex: 0xF7931A)
        case .eth: return Color(hex: 0x627EEA)
        case .usdc: return Color(hex: 0x2775CA)
        }
    }

    // MARK: Shape & spacing

    enum Radius {
        /// Cards and grouped containers.
        static let card: CGFloat = 12
        /// Buttons, inputs, the payment card art.
        static let control: CGFloat = 10
        /// Icon tiles and small elements.
        static let small: CGFloat = 8
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Height of every full-width button.
    static let buttonHeight: CGFloat = 48
    /// Content never stretches wider than this (iPad, landscape).
    static let readableWidth: CGFloat = 640
    /// Standard duration for state changes.
    static let quick = Animation.easeOut(duration: 0.18)
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Layout

extension View {
    /// Centers content at a comfortable reading width on iPad and landscape.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.readableWidth).frame(maxWidth: .infinity)
    }

    /// The standard container: surface background, 12pt corners, 1px hairline. No shadow.
    func surfaceCard(padding: CGFloat? = Theme.Space.l) -> some View {
        self
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// A titled group: a quiet header above a card. Rows inside are separated by `RowDivider`.
struct CardSection<Content: View, Accessory: View>: View {
    let title: String?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    accessory
                }
                .padding(.horizontal, Theme.Space.xs)
            }
            VStack(spacing: 0) { content }
                .surfaceCard(padding: 0)
        }
    }
}

extension CardSection where Accessory == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, accessory: { EmptyView() }, content: content)
    }
}

/// Hairline between rows in a card, inset to line up with row text.
struct RowDivider: View {
    var inset: CGFloat = Theme.Space.l

    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Footnote under a card, like a Form section footer.
struct SectionNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Space.xs)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Icons

/// A small neutral tile holding an SF Symbol. All row icons use it, so icons are uniform.
struct IconTile: View {
    let systemName: String
    var tint: Color = Theme.textSecondary
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An asset's mark: its glyph on its official color.
struct AssetIcon: View {
    let asset: Asset
    var size: CGFloat = 36

    var body: some View {
        Text(asset.glyph)
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.color(for: asset), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Filled brand button. One per screen at most.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .background(Theme.brandFill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Quiet button for secondary actions: neutral fill, brand text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity, minHeight: Theme.buttonHeight)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Full-width tappable row inside a card (highlights while pressed).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Theme.fill : Color.clear)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == RowButtonStyle {
    static var row: RowButtonStyle { RowButtonStyle() }
}

// MARK: - Rows

/// Standard row: optional leading icon, title + subtitle, trailing content. 56pt minimum.
struct InfoRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleColor: Color = Theme.textSecondary
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        subtitleColor: Color = Theme.textSecondary,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.leading = leading()
        self.trailing = trailing()
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Very large text: stack the trailing value under the title so neither truncates.
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.m) {
                        leading
                        labels
                    }
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.Space.m) {
                    leading
                    labels
                    Spacer(minLength: Theme.Space.s)
                    trailing
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(minHeight: 56)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
        }
    }
}

extension InfoRow where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, subtitleColor: Color = Theme.textSecondary, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: subtitle, subtitleColor: subtitleColor, leading: { EmptyView() }, trailing: trailing)
    }
}

/// Trailing chevron for rows that open something.
struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Toolbar

extension View {
    /// The settings gear every tab shows in its navigation bar.
    func settingsToolbar(_ open: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: open) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}
