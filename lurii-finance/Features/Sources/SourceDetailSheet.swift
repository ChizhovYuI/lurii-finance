import SwiftUI

struct SourceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: SourceDTO
    let fields: [SourceTypeField]
    let supportedApyRules: [SupportedApyRule]
    var onSaved: (() -> Void)?
    @ObservedObject var viewModel: SourcesViewModel

    @State private var enabled: Bool
    @State private var credentials: [String: String] = [:]
    @State private var isSaving = false
    @State private var isCheckingConnection = false
    @State private var isDeletingSource = false
    @State private var errorMessage: String?
    @State private var validationMessage: String?
    @State private var validationSucceeded: Bool?
    @State private var showDeleteConfirmation = false

    @State private var apyRules: [ApyRuleDTO] = []
    @State private var isLoadingRules = false
    @State private var ruleEditorItem: RuleEditorItem?

    init(
        source: SourceDTO,
        fields: [SourceTypeField],
        supportedApyRules: [SupportedApyRule] = [],
        onSaved: (() -> Void)? = nil,
        viewModel: SourcesViewModel
    ) {
        self.source = source
        self.fields = fields
        self.supportedApyRules = supportedApyRules
        self.onSaved = onSaved
        self.viewModel = viewModel
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
                                SecureField(field.name, text: binding(for: field.name))
                            } else {
                                TextField(field.name, text: binding(for: field.name))
                            }
                        }
                    }
                }
            }

            if !supportedApyRules.isEmpty {
                Divider()
                apyRulesSection
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(validationSucceeded == true ? .green : .red)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(isDeletingSource ? "Deleting..." : "Delete Source") {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(isSaving || isCheckingConnection || isDeletingSource)
                Spacer()
                Button(isCheckingConnection ? "Checking..." : "Check Connection") {
                    validateConnection()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || isCheckingConnection || isDeletingSource)
                Button("Cancel") { dismiss() }
                .disabled(isDeletingSource)
                Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isCheckingConnection || isDeletingSource)
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
        .alert("Delete Source?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSource()
            }
            .disabled(isDeletingSource)
        } message: {
            Text(
                """
                Delete '\(source.name)' permanently?

                Historical snapshots and transactions for this source will be removed. APY rules for this source will be removed. Cached report and commentary data for affected dates will be cleared. Portfolio and Earn summaries will update after deletion.
                """
            )
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

        Task {
            do {
                try await APIClient.shared.patchSource(
                    name: source.name,
                    body: SourcePatchRequest(
                        credentials: changedCredentials.isEmpty ? nil : changedCredentials,
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

    private func deleteSource() {
        guard !isDeletingSource else { return }
        isDeletingSource = true
        errorMessage = nil

        Task {
            let result = await viewModel.deleteSource(source)
            switch result {
            case .success:
                onSaved?()
                dismiss()
            case let .failure(error):
                errorMessage = error.errorDescription ?? "Unable to delete source."
            }
            isDeletingSource = false
        }
    }

    private var changedCredentials: [String: String] {
        credentials.filter { key, value in
            source.credentials[key] != value && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func validateConnection() {
        guard !isCheckingConnection else { return }
        isCheckingConnection = true
        errorMessage = nil
        validationMessage = nil

        Task {
            let result = await viewModel.validateSource(name: source.name, credentials: changedCredentials)
            switch result {
            case let .success(message):
                validationSucceeded = true
                validationMessage = message
            case let .failure(error):
                validationSucceeded = false
                validationMessage = error.errorDescription ?? "Connection check failed."
            }
            isCheckingConnection = false
        }
    }

    private func binding(for fieldName: String) -> Binding<String> {
        Binding(
            get: { credentials[fieldName, default: ""] },
            set: {
                credentials[fieldName] = $0
                clearValidationState()
            }
        )
    }

    private func clearValidationState() {
        validationMessage = nil
        validationSucceeded = nil
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
        fields: [SourceTypeField(name: "apiKey", prompt: "API Key", required: true, secret: true, tip: nil)],
        viewModel: SourcesViewModel()
    )
}
