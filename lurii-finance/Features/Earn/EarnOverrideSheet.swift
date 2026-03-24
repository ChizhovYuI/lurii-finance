import SwiftUI

struct EarnOverrideSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceName: String
    var existingOverride: EarnOverrideDTO?
    var onSaved: (() -> Void)?

    @State private var category: String = "Dual Asset"
    @State private var coin: String = ""
    @State private var aprPercent: String = ""
    @State private var settlementDate: Date = Date()
    @State private var hasSettlement: Bool = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { existingOverride != nil }

    private var isFormValid: Bool {
        !category.isEmpty && !coin.isEmpty && !aprPercent.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit Earn Override" : "Add Earn Override")
                .font(.title2)

            TextField("Category", text: $category)
                .textFieldStyle(.roundedBorder)

            TextField("Coin", text: $coin)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Text("APR %")
                    .frame(width: 50, alignment: .leading)
                TextField("102.75", text: $aprPercent)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Settlement date", isOn: $hasSettlement)

            if hasSettlement {
                DatePicker(
                    "Settlement",
                    selection: $settlementDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isSaving ? "Saving..." : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !isFormValid)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { populate() }
    }

    private func populate() {
        guard let ov = existingOverride else { return }
        category = ov.category
        coin = ov.coin
        aprPercent = ov.apr ?? ""
        if let settlement = ov.settlementAt {
            hasSettlement = true
            settlementDate = parseISO8601(settlement) ?? Date()
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let settlement: String? = hasSettlement ? formatISO8601(settlementDate) : nil
        let override = EarnOverrideDTO(
            category: category,
            coin: coin.uppercased(),
            apr: aprPercent,
            settlementAt: settlement
        )

        Task {
            do {
                // Load existing overrides, replace or append this one, then save all.
                let existing = try await APIClient.shared.getEarnOverrides(sourceName: sourceName)
                var overrides = existing.overrides.filter {
                    !($0.category == override.category && $0.coin == override.coin)
                }
                overrides.append(override)
                _ = try await APIClient.shared.setEarnOverrides(
                    sourceName: sourceName,
                    body: EarnOverridesSaveRequest(overrides: overrides)
                )
                // Trigger single-source collection so overrides take effect immediately.
                _ = try? await APIClient.shared.startCollect(source: sourceName)
                onSaved?()
                dismiss()
            } catch {
                errorMessage = "Unable to save override."
            }
            isSaving = false
        }
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

#Preview {
    EarnOverrideSheet(sourceName: "bybit-main")
}
