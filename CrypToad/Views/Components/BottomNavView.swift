import SwiftUI

struct BottomNavView: View {
    @Binding var currentView: String

    var body: some View {
        HStack(spacing: 0) {
            NavButton(icon: "wallet.pass", label: "Home", isSelected: currentView == "home") {
                currentView = "home"
            }
            NavButton(icon: "chart.line.uptrend.xyaxis", label: "Invest", isSelected: currentView == "dca") {
                currentView = "dca"
            }
            NavButton(icon: "creditcard", label: "Card", isSelected: currentView == "card") {
                currentView = "card"
            }
            NavButton(icon: "arrow.up.circle", label: "Round-Up", isSelected: currentView == "roundup") {
                currentView = "roundup"
            }
        }
        .padding(.vertical, 8)
        .background(Color(red: 0.16, green: 0.16, blue: 0.18))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(red: 0.26, green: 0.26, blue: 0.28)),
            alignment: .top
        )
    }
}

struct NavButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .blue : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(8)
        }
        .padding(.horizontal, 4)
    }
}
