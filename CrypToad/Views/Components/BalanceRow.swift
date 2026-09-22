import SwiftUI

struct BalanceRow: View {
    let symbol: String
    let name: String
    let amount: Double
    let crypto: String
    let usdValue: Double
    let change: String
    let isPositive: Bool?
    let color: Color

    var body: some View {
        HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 40, height: 40)
                    Text(symbol)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("\(amount, specifier: "%.4f") \(crypto)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(usdValue, specifier: "%.2f")")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                if let positive = isPositive {
                    Text(change)
                        .font(.caption)
                        .foregroundColor(positive ? .green : .red)
                } else {
                    Text(change)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(red: 0.26, green: 0.26, blue: 0.28))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.36, green: 0.36, blue: 0.38), lineWidth: 1)
        )
    }
}
