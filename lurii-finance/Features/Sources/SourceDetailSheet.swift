import SwiftUI

struct SourceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: SourceDTO
    let fields: [SourceTypeField]
    let supportedApyRules: [SupportedApyRule]
    var onSaved: (() -> Void)?

    @State private var enabled: Bool
    @State private var credentials: [String: String] = [:]
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var apyRules: [ApyRuleDTO] = []
    @State private var isLoadingRules = false
    @State private var ruleEditorItem: RuleEditorItem?

    init(source: SourceDTO, fields: [SourceTypeField], supportedApyRules: [SupportedApyRule] = [], onSaved: (() -> Void)? = nil) {
        self.source = source
        self.fields = fields
        self.supportedApyRules = supportedApyRules
        self.onSaved = onSaved
        _enabled = State(initialValue: source.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source.name)
                .font(.title2)

            Text("Type: \(source.type)")
                .foregroundStyle(.secondary)

            Toggle("Enabled", isOn: $enabled)

            if !fields.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(.headline)
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.prompt)
                                .font(.caption)
                            if field.secret {
                                SecureField(field.name, text: Binding(
                                    get: { credentials[field.name, default: ""] },
                                    set: { credentials[field.name] = $0 }
                                ))
                            } else {
                                TextField(field.name, text: Binding(
                                    get: { credentials[field.name, default: ""] },
                                    set: { credentials[field.name] = $0 }
                                ))
                            }
                        }
                    }
                }
            }

            if !supportedApyRules.isEmpty {
                Divider()
                apyRulesSection
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            credentials = source.credentials
            if !supportedApyRules.isEmpty {
                loadRules()
            }
        }
        .sheet(item: $ruleEditorItem) { item in
            ApyRuleEditorSheet(
                sourceName: source.name,
                supportedApyRules: supportedApyRules,
                existingRule: item.rule,
                onSaved: { loadRules() }
            )
        }
    }

    private var apyRulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("APY Rules")
                    .font(.headline)
                Spacer()
                Button {
                    ruleEditorItem = RuleEditorItem(rule: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isLoadingRules {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if apyRules.isEmpty {
                Text("No rules configured")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(apyRules) { rule in
                    ApyRuleRow(rule: rule, onEdit: {
                        ruleEditorItem = RuleEditorItem(rule: rule)
                    }, onDelete: {
                        deleteRule(rule)
                    })
                }
            }
        }
    }

    private func loadRules() {
        isLoadingRules = true
        Task {
            do {
                apyRules = try await APIClient.shared.getApyRules(sourceName: source.name)
            } catch {
                // Silent — rules section just stays empty
            }
            isLoadingRules = false
        }
    }

    private func deleteRule(_ rule: ApyRuleDTO) {
        Task {
            do {
                try await APIClient.shared.deleteApyRule(sourceName: source.name, ruleId: rule.id)
                apyRules.removeAll { $0.id == rule.id }
            } catch {
                errorMessage = "Unable to delete rule."
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let changed = credentials.filter { key, value in
            source.credentials[key] != value && !value.isEmpty
        }

        Task {
            do {
                try await APIClient.shared.patchSource(
                    name: source.name,
                    body: SourcePatchRequest(
                        credentials: changed.isEmpty ? nil : changed,
                        enabled: enabled
                    )
                )
                onSaved?()
                dismiss()
            } catch {
                errorMessage = "Unable to update source."
            }
            isSaving = false
        }
    }
}

private struct ApyRuleRow: View {
    let rule: ApyRuleDTO
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(rule.protocolName) / \(rule.coin.uppercased())")
                    .font(.subheadline)
                Text("\(rule.type) · \(rule.startedAt) → \(rule.finishedAt) · \(rule.limits.count) tier(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { onEdit() } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RuleEditorItem: Identifiable {
    let id = UUID()
    let rule: ApyRuleDTO?
}

#Preview {
    SourceDetailSheet(
        source: SourceDTO(name: "Coinbase", type: "exchange", credentials: ["apiKey": "••••"], enabled: true),
        fields: [SourceTypeField(name: "apiKey", prompt: "API Key", required: true, secret: true, tip: nil)]
    )
}
