import SwiftUI

struct StrategyCard: View {
    let title: String
    let description: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                if isActive {
                    Text("Active")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.2) : Color(red: 0.26, green: 0.26, blue: 0.28))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.blue : Color(red: 0.36, green: 0.36, blue: 0.38), lineWidth: isActive ? 2 : 1)
        )
    }
}
