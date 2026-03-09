import SwiftUI

struct CashManualSheet: View {
    @Environment(\.dismiss) private var dismiss

    let state: CashManualState
    let onSaved: () -> Void

    @State private var selectedCurrencies: Set<String>
    @State private var amounts: [String: String]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(state: CashManualState, onSaved: @escaping () -> Void) {
        self.state = state
        self.onSaved = onSaved
        _selectedCurrencies = State(initialValue: Set(state.selectedCurrencies))

        var initialAmounts: [String: String] = [:]
        for (currency, balance) in state.balances {
            initialAmounts[currency] = balance.amount
        }
        _amounts = State(initialValue: initialAmounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Cash Balances")
                .font(.title2)

            if let latest = state.latestSnapshotDate, !latest.isEmpty {
                Text("Latest snapshot: \(latest)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Currencies")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(state.supportedCurrencies, id: \.self) { currency in
                        Toggle(currency, isOn: toggleBinding(for: currency))
                            .toggleStyle(.checkbox)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Today’s Balances")
                    .font(.headline)

                if orderedSelectedCurrencies.isEmpty {
                    Text("Select at least one currency.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedSelectedCurrencies, id: \.self) { currency in
                        HStack(spacing: 12) {
                            Text(currency)
                                .frame(width: 48, alignment: .leading)
                            TextField("0", text: amountBinding(for: currency))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
                Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var orderedSelectedCurrencies: [String] {
        state.supportedCurrencies.filter { selectedCurrencies.contains($0) }
    }

    private func toggleBinding(for currency: String) -> Binding<Bool> {
        Binding(
            get: { selectedCurrencies.contains(currency) },
            set: { enabled in
                if enabled {
                    selectedCurrencies.insert(currency)
                    if amounts[currency] == nil {
                        amounts[currency] = "0"
                    }
                } else {
                    selectedCurrencies.remove(currency)
                }
            }
        )
    }

    private func amountBinding(for currency: String) -> Binding<String> {
        Binding(
            get: { amounts[currency, default: "0"] },
            set: { amounts[currency] = $0 }
        )
    }

    private func save() {
        guard !isSaving else { return }
        errorMessage = nil

        let selected = orderedSelectedCurrencies
        guard !selected.isEmpty else {
            errorMessage = "Select at least one currency."
            return
        }

        var payloadBalances: [String: String] = [:]
        for currency in selected {
            let raw = amounts[currency, default: "0"].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = raw.isEmpty ? "0" : raw
            guard let decimal = Decimal(string: value), decimal.isFinite else {
                errorMessage = "Invalid amount for \(currency)."
                return
            }
            guard decimal >= 0 else {
                errorMessage = "Amount for \(currency) must be non-negative."
                return
            }
            payloadBalances[currency] = NSDecimalNumber(decimal: decimal).stringValue
        }

        isSaving = true
        Task {
            do {
                _ = try await APIClient.shared.upsertCashManual(
                    CashManualUpsertRequest(
                        selectedCurrencies: selected,
                        balances: payloadBalances
                    )
                )
                onSaved()
                dismiss()
            } catch {
                errorMessage = "Unable to save cash balances: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
