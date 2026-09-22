import SwiftUI

struct DCAView: View {
    @Binding var dcaSettings: DCASettings
    let changeView: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Button(action: { changeView("home") }) {
                HStack {
                    Image(systemName: "chevron.left")
                    Text("Back to Home")
                }
                .foregroundColor(.blue)
                .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // DCA Card
            ZStack {
                LinearGradient(colors: [Color.blue, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-Investment (DCA)")
                        .font(.subheadline)
                        .opacity(0.8)

                    Text("$\(dcaSettings.amount, specifier: "%.0f")")
                        .font(.system(size: 40, weight: .bold))

                    Text("Every \(dcaSettings.frequency)")
                        .font(.caption)
                        .opacity(0.9)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .cornerRadius(16)

            // DCA Status
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DCA Status")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $dcaSettings.enabled)
                        .labelsHidden()
                }

                Text(dcaSettings.enabled ? "Automatic investments are active. Your crypto portfolio grows steadily." : "DCA is paused. Turn on to resume automatic investing.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )

            // Investment Strategy
            VStack(alignment: .leading, spacing: 12) {
                Text("Investment Strategy")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                StrategyCard(title: "Balanced Growth", description: "50% BTC, 30% ETH, 20% USDC", isActive: true)
                StrategyCard(title: "Aggressive Bitcoin", description: "80% BTC, 15% ETH, 5% USDC", isActive: false)
                StrategyCard(title: "Stablecoin Saver", description: "10% BTC, 10% ETH, 80% USDC", isActive: false)
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )
        }
    }
}
