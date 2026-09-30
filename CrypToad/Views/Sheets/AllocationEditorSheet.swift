import SwiftUI
import CrypToadCore

/// Sliders for splitting investments across assets. Moving one slider rebalances
/// the others so the total always stays at 100%.
struct AllocationEditorSheet: View {
    let title: String
    let onSave: (Allocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Allocation

    init(title: String, initial: Allocation, onSave: @escaping (Allocation) -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Asset.allCases) { asset in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Circle()
                                    .fill(Theme.color(for: asset))
                                    .frame(width: 10, height: 10)
                                Text(asset.displayName)
                                Spacer()
                                Text("\(draft[asset])%")
                                    .monospacedDigit()
                                    .fontWeight(.semibold)
                            }
                            Slider(value: binding(for: asset), in: 0...100, step: 1)
                                .tint(Theme.color(for: asset))
                                .accessibilityLabel("\(asset.displayName) percentage")
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Split")
                } footer: {
                    Text("Total: \(draft.total)%. Adjusting one asset rebalances the others proportionally.")
                }

                Section("Presets") {
                    ForEach(Allocation.presets) { preset in
                        Button {
                            withAnimation { draft = preset.allocation }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                    Text(preset.allocation.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if draft == preset.allocation {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }

    private func binding(for asset: Asset) -> Binding<Double> {
        Binding(
            get: { Double(draft[asset]) },
            set: { draft = draft.adjusting(asset, to: Int($0.rounded())) }
        )
    }
}

#Preview {
    AllocationEditorSheet(title: "Round-Up Allocation", initial: .balanced) { _ in }
}
