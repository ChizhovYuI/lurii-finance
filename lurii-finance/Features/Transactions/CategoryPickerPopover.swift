import SwiftUI

/// Popover for 2-click category selection in the transaction list.
struct CategoryPickerPopover: View {
    let tx: TransactionDTO
    let categories: [TransactionCategoryDTO]
    let displayName: (String?) -> String
    let onSelect: (String) -> Void
    var onCreateCategory: ((String, String) -> Void)?

    @State private var rawFields: [String: String]?
    @State private var matchedRule: CategoryRuleDTO?
    @State private var isLoadingDetail = false
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var isCreatingRule = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left: category list.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Context header: description and source.
                    if let desc = tx.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(desc)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(tx.sourceName) · \(tx.resolvedType)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider()
                    }

                    // Category buttons.
                    ForEach(categories, id: \.category) { (cat: TransactionCategoryDTO) in
                        let isSelected = tx.metadata?.category == cat.category
                        Button {
                            onSelect(cat.category)
                        } label: {
                            HStack {
                                Text(cat.displayName)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    if isAddingCategory {
                        HStack(spacing: 6) {
                            TextField("Category name", text: $newCategoryName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                            Button {
                                let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                onCreateCategory?(tx.resolvedType, name)
                                let key = name.lowercased().replacingOccurrences(of: " ", with: "_")
                                onSelect(key)
                                isAddingCategory = false
                                newCategoryName = ""
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    } else {
                        Button {
                            isAddingCategory = true
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Add Category")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    if isCreatingRule {
                        Divider()
                        InlineRuleForm(
                            txType: tx.resolvedType,
                            category: tx.metadata?.category ?? "",
                            source: tx.source,
                            rawFields: rawFields,
                            onSaved: { isCreatingRule = false }
                        )
                    } else if tx.metadata?.category != nil {
                        Button {
                            isCreatingRule = true
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Create Rule")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 220)

            // Right: raw fields panel.
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let matchedRule {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Matched Rule")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(matchedRule.resultCategory) ← \(matchedRule.typeMatch)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)

                        Divider()
                    }

                    if isLoadingDetail {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    } else if let rawFields, !rawFields.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(rawFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(key)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Text(value)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    } else {
                        Text("No raw fields")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                }
            }
            .frame(minWidth: 200, idealWidth: 280)
        }
        .frame(minWidth: 400, maxWidth: 600, minHeight: 120, maxHeight: 600)
        .task { await loadDetail() }
    }

    init(
        tx: TransactionDTO,
        categories: [TransactionCategoryDTO],
        displayName: @escaping (String?) -> String,
        onSelect: @escaping (String) -> Void,
        onCreateCategory: ((String, String) -> Void)? = nil,
        previewRawFields: [String: String]? = nil,
        previewMatchedRule: CategoryRuleDTO? = nil
    ) {
        self.tx = tx
        self.categories = categories
        self.displayName = displayName
        self.onSelect = onSelect
        self.onCreateCategory = onCreateCategory
        self._rawFields = State(initialValue: previewRawFields)
        self._matchedRule = State(initialValue: previewMatchedRule)
        self._isLoadingDetail = State(initialValue: previewRawFields == nil && previewMatchedRule == nil)
    }

    private func loadDetail() async {
        guard tx.id > 0, rawFields == nil, matchedRule == nil else { return }
        isLoadingDetail = true
        do {
            let detail = try await APIClient.shared.getTransaction(id: tx.id)
            rawFields = detail.rawFields
            matchedRule = detail.matchedRule
        } catch {
            // Best-effort; popover still works without detail.
        }
        isLoadingDetail = false
    }
}

#Preview("Category Picker") {
    CategoryPickerPopover(
        tx: TransactionDTO(
            id: 0,
            date: "2026-03-15",
            time: "14:32",
            source: "wise",
            sourceName: "Wise",
            txType: "spend",
            effectiveType: nil,
            asset: "EUR",
            amount: "42.50",
            usdValue: "46.12",
            counterpartyAsset: nil,
            counterpartyAmount: nil,
            txId: nil,
            tradeSide: nil,
            description: "Lidl Berlin Alexanderplatz",
            metadata: TransactionMetadataDTO(
                category: "groceries",
                categorySource: "rule",
                categoryConfidence: nil,
                typeOverride: nil,
                isInternalTransfer: nil,
                transferPairId: nil,
                transferDetectedBy: nil,
                reviewed: true,
                notes: nil
            ),
            group: nil,
            rawFields: nil,
            matchedRule: nil,
            availableCategories: nil,
            availableTypes: nil
        ),
        categories: [
            TransactionCategoryDTO(id: 1, txType: "spend", category: "groceries", displayName: "Groceries", sortOrder: 1),
        ],
        displayName: { $0 ?? "Uncategorized" },
        onSelect: { _ in },
        previewRawFields: [
            "description": "LIDL SAGT DANKE  //Berlin/DE",
            "amount": "-42.50",
            "currency": "EUR",
            "date": "2026-03-15",
            "referenceNumber": "FT26074ABCD1234",
        ],
        previewMatchedRule: CategoryRuleDTO(
            id: 7,
            typeMatch: "spend",
            typeOperator: nil,
            fieldName: "description",
            fieldOperator: "contains",
            fieldValue: "LIDL",
            source: nil,
            resultCategory: "groceries",
            priority: 10,
            builtin: false,
            deleted: nil
        )
    )
    .padding(24)
}
