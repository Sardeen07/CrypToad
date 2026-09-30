import SwiftUI
import CrypToadCore

/// Shared colors and styles so every screen looks consistent.
enum Theme {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let surface = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let surfaceRaised = Color(red: 0.26, green: 0.26, blue: 0.28)
    static let border = Color(red: 0.26, green: 0.26, blue: 0.28)
    static let borderRaised = Color(red: 0.36, green: 0.36, blue: 0.38)

    static func color(for asset: Asset) -> Color {
        switch asset {
        case .btc: return .orange
        case .eth: return .purple
        case .usdc: return .blue
        }
    }
}

extension View {
    /// Standard section container.
    func cardStyle() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    /// Row inside a card.
    func rowStyle() -> some View {
        self
            .padding(12)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderRaised, lineWidth: 1))
    }
}

/// Section title with an SF Symbol.
struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .font(.headline)
    }
}

/// "‹ Back to Home" link used by secondary screens.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.left")
                Text("Back to Home")
            }
            .foregroundStyle(.blue)
            .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
