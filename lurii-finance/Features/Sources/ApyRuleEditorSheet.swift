import SwiftUI

struct ApyRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sourceName: String
    let supportedApyRules: [SupportedApyRule]
    let existingRule: ApyRuleDTO?
    var onSaved: (() -> Void)?

    @State private var selectedProtocol: String = ""
    @State private var selectedCoin: String = ""
    @State private var selectedType: String = "base"
    @State private var startedAt: Date = Date()
    @State private var finishedAt: Date = Date()
    @State private var limits: [LimitTier] = [LimitTier()]
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var availableCoins: [String] {
        supportedApyRules.first(where: { $0.protocolName == selectedProtocol })?.coins ?? []
    }

    private var isEditing: Bool {
        existingRule != nil
    }

    private var isFormValid: Bool {
        !selectedProtocol.isEmpty &&
        !selectedCoin.isEmpty &&
        !limits.isEmpty &&
        limits.allSatisfy { !$0.fromAmount.isEmpty && !$0.apy.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit APY Rule" : "Add APY Rule")
                .font(.title2)

            Picker("Protocol", selection: $selectedProtocol) {
                ForEach(supportedApyRules) { rule in
                    Text(rule.protocolName).tag(rule.protocolName)
                }
            }

            Picker("Coin", selection: $selectedCoin) {
                ForEach(availableCoins, id: \.self) { coin in
                    Text(coin.uppercased()).tag(coin)
                }
            }

            Picker("Type", selection: $selectedType) {
                Text("Base").tag("base")
                Text("Bonus").tag("bonus")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                DatePicker("From", selection: $startedAt, displayedComponents: .date)
                DatePicker("To", selection: $finishedAt, displayedComponents: .date)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tiers")
                        .font(.headline)
                    Spacer()
                    Button {
                        limits.append(LimitTier())
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(spacing: 8) {
                    Text("From")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("To (empty=∞)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("APY %")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Spacer for delete button column
                    Text("")
                        .frame(width: 24)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach($limits) { $tier in
                    HStack(spacing: 8) {
                        TextField("0", text: $tier.fromAmount)
                            .frame(maxWidth: .infinity)
                        TextField("∞", text: $tier.toAmount)
                            .frame(maxWidth: .infinity)
                        TextField("10", text: $tier.apy)
                            .frame(maxWidth: .infinity)
                        Button {
                            limits.removeAll { $0.id == tier.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .disabled(limits.count <= 1)
                    }
                }
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
        .frame(width: 520)
        .onAppear { populate() }
        .onChange(of: selectedProtocol) { _, _ in
            if !isEditing {
                selectedCoin = availableCoins.first ?? ""
            }
        }
    }

    private func populate() {
        if let rule = existingRule {
            selectedProtocol = rule.protocolName
            selectedCoin = rule.coin
            selectedType = rule.type
            startedAt = dateFromISO(rule.startedAt) ?? Date()
            finishedAt = dateFromISO(rule.finishedAt) ?? Date()
            limits = rule.limits.map { limit in
                LimitTier(
                    fromAmount: limit.fromAmount,
                    toAmount: limit.toAmount ?? "",
                    apy: apyToPercent(limit.apy)
                )
            }
        } else {
            selectedProtocol = supportedApyRules.first?.protocolName ?? ""
            selectedCoin = availableCoins.first ?? ""
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let limitDTOs = limits.map { tier in
            RuleLimitDTO(
                fromAmount: tier.fromAmount,
                toAmount: tier.toAmount.isEmpty ? nil : tier.toAmount,
                apy: percentToApy(tier.apy)
            )
        }

        let body = ApyRuleCreateRequest(
            protocolName: selectedProtocol,
            coin: selectedCoin,
            type: selectedType,
            limits: limitDTOs,
            startedAt: isoString(from: startedAt),
            finishedAt: isoString(from: finishedAt)
        )

        Task {
            do {
                if let existingRule {
                    _ = try await APIClient.shared.updateApyRule(
                        sourceName: sourceName,
                        ruleId: existingRule.id,
                        body: body
                    )
                } else {
                    _ = try await APIClient.shared.createApyRule(
                        sourceName: sourceName,
                        body: body
                    )
                }
                onSaved?()
                dismiss()
            } catch {
                errorMessage = "Unable to save rule."
            }
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func dateFromISO(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private func isoString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func apyToPercent(_ apy: String) -> String {
        guard let decimal = Decimal(string: apy) else { return apy }
        return "\(decimal * 100)"
    }

    private func percentToApy(_ percent: String) -> String {
        guard let decimal = Decimal(string: percent) else { return percent }
        return "\(decimal / 100)"
    }
}

private struct LimitTier: Identifiable {
    let id = UUID()
    var fromAmount: String = ""
    var toAmount: String = ""
    var apy: String = ""
}

#Preview {
    ApyRuleEditorSheet(
        sourceName: "bitget_wallet",
        supportedApyRules: [
            SupportedApyRule(protocolName: "aave", coins: ["usdc", "usdt"])
        ],
        existingRule: nil
    )
}
