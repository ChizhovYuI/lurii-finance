import SwiftUI

struct NewCategoryRuleSheet: View {
    let categories: [TransactionCategoryDTO]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let txTypes = ["trade", "spend", "fee", "deposit", "withdrawal", "yield", "dividend", "interest", "transfer"]
    private let operators = ["eq", "contains"]

    @State private var typeMatch = "spend"
    @State private var resultCategory = ""
    @State private var source = "*"
    @State private var fieldName = ""
    @State private var fieldOperator = "eq"
    @State private var fieldValue = ""

    @State private var preview: RulePreviewResponse?
    @State private var isLoadingPreview = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var availableCategories: [TransactionCategoryDTO] {
        categories.filter { $0.txType == typeMatch }
    }

    private var isFormValid: Bool {
        !typeMatch.isEmpty && !resultCategory.isEmpty
    }

    private var hasFieldCondition: Bool {
        !fieldName.isEmpty && !fieldValue.isEmpty
    }

    private var requestBody: CategoryRuleCreateRequest {
        CategoryRuleCreateRequest(
            typeMatch: typeMatch,
            resultCategory: resultCategory,
            fieldName: hasFieldCondition ? fieldName : nil,
            fieldOperator: hasFieldCondition ? fieldOperator : nil,
            fieldValue: hasFieldCondition ? fieldValue : nil,
            source: source
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Category Rule")
                .font(.title2.bold())

            // Type match (required).
            Picker("Type", selection: $typeMatch) {
                ForEach(txTypes, id: \.self) { type in
                    Text(type.capitalized).tag(type)
                }
            }

            // Source filter.
            HStack {
                Text("Source")
                    .frame(width: 80, alignment: .leading)
                TextField("* (any)", text: $source)
                    .textFieldStyle(.roundedBorder)
            }

            // Field condition (optional).
            GroupBox("Field condition (optional)") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Field")
                            .frame(width: 60, alignment: .leading)
                        TextField("description, channel, asset...", text: $fieldName)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Operator")
                            .frame(width: 60, alignment: .leading)
                        Picker("", selection: $fieldOperator) {
                            ForEach(operators, id: \.self) { op in
                                Text(op).tag(op)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    HStack {
                        Text("Value")
                            .frame(width: 60, alignment: .leading)
                        TextField("Payment, Debit Card...", text: $fieldValue)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // Result category.
            Picker("Category", selection: $resultCategory) {
                Text("Select...").tag("")
                ForEach(availableCategories) { cat in
                    Text(cat.displayName).tag(cat.category)
                }
            }

            // Preview section.
            if isLoadingPreview {
                ProgressView("Running preview...")
                    .frame(maxWidth: .infinity)
            } else if let preview {
                GroupBox("Preview: \(preview.affectedCount) transactions affected") {
                    if preview.sample.isEmpty {
                        Text("No transactions match this rule.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(preview.sample) { item in
                                    HStack {
                                        Text(String(item.date.prefix(10)))
                                            .font(.system(size: 11, design: .monospaced))
                                        Text(item.source)
                                            .font(.system(size: 11))
                                            .frame(width: 60, alignment: .leading)
                                        Text(item.description ?? "—")
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(item.currentCategory ?? "—")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                        Text(item.newCategory)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // Actions.
            HStack {
                Button("Preview") { runPreview() }
                    .disabled(!isFormValid || isLoadingPreview)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)

                Button(isSaving ? "Saving..." : "Save Rule") { save() }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!isFormValid || isSaving)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onChange(of: typeMatch) { _, _ in
            resultCategory = availableCategories.first?.category ?? ""
            preview = nil
        }
    }

    private func runPreview() {
        isLoadingPreview = true
        preview = nil
        errorMessage = nil
        Task {
            do {
                preview = try await APIClient.shared.previewCategoryRule(body: requestBody)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingPreview = false
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await APIClient.shared.createCategoryRule(body: requestBody)
                onSaved()
                dismiss()
            } catch {
                errorMessage = "Unable to save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
