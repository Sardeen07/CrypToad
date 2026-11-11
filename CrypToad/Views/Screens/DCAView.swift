import SwiftUI
import CrypToadCore

/// Dollar-cost averaging: a recurring buy on a schedule, split by a strategy.
struct DCAView: View {
    @Environment(PortfolioStore.self) private var store
    let present: (ActiveSheet) -> Void

    private var dca: DCASettings { store.state.dca }

    var body: some View {
        ScreenScroll {
            HeroFigure("Recurring buy", amount: dca.amountUSD) {
                Text(scheduleText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: Theme.Space.m) {
                Button("Buy Now") { store.runDCANow() }
                    .buttonStyle(.primary)
                Button("Edit Schedule") { present(.dcaSchedule) }
                    .buttonStyle(.secondary)
            }
            .disabled(store.isWorking)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                CardSection {
                    ToggleRow(
                        title: "Automatic investing",
                        isOn: Binding(get: { dca.enabled }, set: { store.setDCAEnabled($0) })
                    )
                }
                SectionNote(dca.enabled
                    ? "Buys run on schedule. Any missed while the app was closed run the next time prices load."
                    : "Turn on to resume automatic investing.")
            }

            CardSection("Strategy") {
                ForEach(Array(Allocation.presets.enumerated()), id: \.element.id) { index, preset in
                    if index > 0 { RowDivider() }
                    strategyRow(preset.name, detail: preset.allocation.summary, selected: dca.allocation == preset.allocation) {
                        store.setDCAAllocation(preset.allocation)
                    }
                }
                RowDivider()
                strategyRow(
                    "Custom",
                    detail: dca.allocation.presetName == nil ? dca.allocation.summary : "Set your own split",
                    selected: dca.allocation.presetName == nil,
                    opensEditor: true
                ) {
                    present(.dcaAllocation)
                }
            }
        }
    }

    private var scheduleText: String {
        let every = "Every \(dca.frequency.everyPhrase)"
        guard dca.enabled else { return "\(every) · Paused" }
        return "\(every) · Next buy \(dca.nextRun.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
    }

    private func strategyRow(_ title: String, detail: String, selected: Bool, opensEditor: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            InfoRow(title, subtitle: detail) {
                HStack(spacing: Theme.Space.m) {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                    if opensEditor { Chevron() }
                }
            }
        }
        .buttonStyle(.row)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { DCAView(present: { _ in }).navigationTitle("Invest") }
        .environment(PortfolioStore.preview())
}
