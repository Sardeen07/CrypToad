import SwiftUI

struct SettingsButton: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundColor(.white)
                        Text(title)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
            .padding()
            .background(Color(red: 0.26, green: 0.26, blue: 0.28))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.36, green: 0.36, blue: 0.38), lineWidth: 1)
            )
        }
    }
}
