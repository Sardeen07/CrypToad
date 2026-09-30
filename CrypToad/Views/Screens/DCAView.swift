import SwiftUI
import CrypToadCore

/// Dollar-cost averaging: recurring buys on a schedule.
struct DCAView: View {
    @Environment(PortfolioStore.self) private var store
    let navigate: (Screen) -> Void
    let present: (ActiveSheet) -> Void

    private var dca: DCASettings { store.state.dca }

    var body: some View {
        VStack(spacing: 24) {
            BackButton { navigate(.home) }
            scheduleCard
            statusCard
            strategyCard
        }
    }

    private var scheduleCard: some View {
        ZStack {
            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-Investment (DCA)")
                    .font(.subheadline)
                    .opacity(0.8)
                Text(dca.amountUSD.usd)
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                Text("Every \(dca.frequency.everyPhrase)")
                    .font(.caption)
                    .opacity(0.9)
                if dca.enabled {
                    Text("Next buy: \(dca.nextRun.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .opacity(0.9)
                }

                HStack(spacing: 12) {
                    Button("Edit Schedule") { present(.dcaSchedule) }
                    Button("Buy Now") { store.runDCANow() }
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { dca.enabled }, set: { store.setDCAEnabled($0) })) {
                Text("DCA Status")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            Text(dca.enabled
                 ? "Automatic investments are active. Missed buys run the next time prices load."
                 : "DCA is paused. Turn on to resume automatic investing.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .cardStyle()
    }

    private var strategyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Investment Strategy")
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            ForEach(Allocation.presets) { preset in
                StrategyCard(
                    title: preset.name,
                    description: preset.allocation.summary,
                    isActive: dca.allocation == preset.allocation
                ) {
                    store.setDCAAllocation(preset.allocation)
                }
            }

            StrategyCard(
                title: "Custom",
                description: dca.allocation.presetName == nil ? dca.allocation.summary : "Set your own split",
                isActive: dca.allocation.presetName == nil
            ) {
                present(.dcaAllocation)
            }
        }
        .cardStyle()
    }
}
