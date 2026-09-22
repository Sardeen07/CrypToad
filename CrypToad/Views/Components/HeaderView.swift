import SwiftUI

struct HeaderView: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("🐸")
                        .font(.title3)
                }
                .frame(width: 32, height: 32)
                .cornerRadius(8)

                Text("CrypToad")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(red: 0.16, green: 0.16, blue: 0.18))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(red: 0.26, green: 0.26, blue: 0.28)),
            alignment: .bottom
        )
    }
}
