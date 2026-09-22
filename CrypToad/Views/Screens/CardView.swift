import SwiftUI

/// Mock debit card screen. No real card is issued; card number is a placeholder.
struct CardView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Debit Card
            ZStack {
                LinearGradient(colors: [Color.purple, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack {
                    HStack {
                        Text("CrypToad")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                        Text("Debit")
                            .font(.caption)
                            .opacity(0.8)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Card Number")
                            .font(.caption2)
                            .opacity(0.8)
                        Text("•••• •••• •••• 8734")
                            .font(.title3)
                            .tracking(2)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Valid Thru")
                                    .font(.caption2)
                                    .opacity(0.8)
                                Text("12/27")
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            Text("Apple Pay Ready")
                                .font(.caption)
                                .opacity(0.9)
                        }
                    }
                }
                .foregroundColor(.white)
                .padding(24)
            }
            .frame(height: 200)
            .cornerRadius(16)

            // Card Settings
            VStack(alignment: .leading, spacing: 12) {
                Text("Card Settings")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                SettingsButton(icon: "wallet.pass", title: "Add to Apple Wallet", subtitle: "Tap to pay anywhere")
                SettingsButton(icon: "lock", title: "Freeze Card", subtitle: "Temporarily disable spending")
                SettingsButton(icon: "eye", title: "View PIN", subtitle: "Requires Face ID")
            }
            .padding()
            .background(Color(red: 0.16, green: 0.16, blue: 0.18))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.26, green: 0.26, blue: 0.28), lineWidth: 1)
            )

            // Notification Info
            HStack(spacing: 12) {
                Image(systemName: "bell")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Real-time Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                    Text("Get instant alerts for every transaction on your card")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.5, green: 0.7, blue: 1.0))
                }
            }
            .padding()
            .background(Color.blue.opacity(0.15))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
