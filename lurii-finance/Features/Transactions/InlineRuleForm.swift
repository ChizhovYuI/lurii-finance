import SwiftUI

struct InlineRuleForm: View {
    let txType: String
    let category: String
    let source: String
    let rawFields: [String: String]?
    let onSaved: () -> Void

    @State private var ruleSource: String
    @State private var fieldName: String
    @State private var fieldOperator: String = "contains"
    @State private var fieldValue: String
    @State private var previewCount: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var fieldNames: [String] {
        var names = ["description", "asset"]
        if let rawFields {
            for key in rawFields.keys.sorted() where !names.contains(key) {
                names.append(key)
            }
        }
        return names
    }

    private var isTypeRule: Bool { category.isEmpty }

    private var isValid: Bool {
        !fieldValue.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(txType: String, category: String, source: String, rawFields: [String: String]?, onSaved: @escaping () -> Void) {
        self.txType = txType
        self.category = category
        self.source = source
        self.rawFields = rawFields
        self.onSaved = onSaved
        _ruleSource = State(initialValue: source)
        _fieldName = State(initialValue: "description")
        let desc = rawFields?["description"] ?? ""
        _fieldValue = State(initialValue: desc)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Create Rule")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let previewCount {
                    Text("\(previewCount) match\(previewCount == 1 ? "" : "es")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text(isTypeRule ? "Type rule" : "Category rule")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(txType)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                if !isTypeRule {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(category)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }

            HStack(spacing: 4) {
                Text("Source")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("*", text: $ruleSource)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
            }

            HStack(spacing: 4) {
                Text("Field")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: $fieldName) {
                    ForEach(fieldNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .onChange(of: fieldName) { _, newName in
                    fieldValue = rawFields?[newName] ?? ""
                    previewCount = nil
                }

                Picker("", selection: $fieldOperator) {
                    Text("contains").tag("contains")
                    Text("equals").tag("eq")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 80)
            }

            HStack(spacing: 4) {
                Text("Value")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                TextField("match value", text: $fieldValue)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                if !isTypeRule {
                    Button("Preview") {
                        Task { await preview() }
                    }
                    .controlSize(.small)
                    .disabled(!isValid || isSaving)
                }

                Button("Save Rule") {
                    Task { await save() }
                }
                .controlSize(.small)
                .disabled(!isValid || isSaving)

                Spacer()

                Button("Skip") {
                    onSaved()
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func buildRequest() -> CategoryRuleCreateRequest {
        let trimmedValue = fieldValue.trimmingCharacters(in: .whitespaces)
        return CategoryRuleCreateRequest(
            typeMatch: txType,
            resultCategory: category,
            fieldName: trimmedValue.isEmpty ? nil : fieldName,
            fieldOperator: trimmedValue.isEmpty ? nil : fieldOperator,
            fieldValue: trimmedValue.isEmpty ? nil : trimmedValue,
            source: ruleSource.trimmingCharacters(in: .whitespaces)
        )
    }

    private func preview() async {
        errorMessage = nil
        do {
            let response = try await APIClient.shared.previewCategoryRule(body: buildRequest())
            previewCount = response.affectedCount
        } catch {
            errorMessage = "Preview failed"
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            if isTypeRule {
                try await APIClient.shared.createTypeRule(body: buildTypeRuleRequest())
            } else {
                _ = try await APIClient.shared.createCategoryRule(body: buildRequest())
            }
            onSaved()
        } catch {
            errorMessage = "Save failed"
        }
        isSaving = false
    }

    private func buildTypeRuleRequest() -> TypeRuleCreateRequest {
        let trimmedValue = fieldValue.trimmingCharacters(in: .whitespaces)
        return TypeRuleCreateRequest(
            resultType: txType,
            fieldName: trimmedValue.isEmpty ? nil : fieldName,
            fieldOperator: trimmedValue.isEmpty ? nil : fieldOperator,
            fieldValue: trimmedValue.isEmpty ? nil : trimmedValue,
            source: ruleSource.trimmingCharacters(in: .whitespaces)
        )
    }
}
