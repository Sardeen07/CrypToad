import SwiftUI
import CrypToadCore

/// Edit the recurring buy amount and frequency.
struct DCAScheduleSheet: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Decimal = 0
    @State private var frequency: DCAFrequency = .weekly
    @State private var loaded = false

    private let quickAmounts: [Decimal] = [25, 50, 100, 250]

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount per buy") {
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())

                    HStack {
                        ForEach(quickAmounts, id: \.self) { value in
                            Button(value.usd) { amount = value }
                                .buttonStyle(.bordered)
                                .tint(amount == value ? Color.blue : Color.gray)
                        }
                    }
                }

                Section("Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(DCAFrequency.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("Invests", value: store.state.dca.allocation.summary)
                    LabeledContent("Per month (approx.)", value: monthlyEstimate.usd)
                }
            }
            .navigationTitle("DCA Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setDCASchedule(amount: amount, frequency: frequency)
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
            .onAppear {
                guard !loaded else { return }
                amount = store.state.dca.amountUSD
                frequency = store.state.dca.frequency
                loaded = true
            }
        }
    }

    private var monthlyEstimate: Decimal {
        let perMonth: Decimal
        switch frequency {
        case .daily: perMonth = 30
        case .weekly: perMonth = Decimal.exact("4.33")
        case .biweekly: perMonth = Decimal.exact("2.17")
        case .monthly: perMonth = 1
        }
        return (amount * perMonth).cents
    }
}
