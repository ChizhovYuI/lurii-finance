import SwiftUI

struct TransactionDetailSheet: View {
    let transaction: TransactionDTO
    let categories: [TransactionCategoryDTO]
    let onSave: (String?, Bool?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String?
    @State private var notes: String
    @State private var isReviewed: Bool
    @State private var detail: TransactionDTO?
    @State private var isLoadingDetail = false

    init(transaction: TransactionDTO, categories: [TransactionCategoryDTO], onSave: @escaping (String?, Bool?, String?) -> Void) {
        self.transaction = transaction
        self.categories = categories
        self.onSave = onSave
        _selectedCategory = State(initialValue: transaction.metadata?.category)
        _notes = State(initialValue: transaction.metadata?.notes ?? "")
        _isReviewed = State(initialValue: transaction.metadata?.reviewed ?? false)
    }

    private var applicableCategories: [TransactionCategoryDTO] {
        categories.filter { $0.txType == transaction.txType }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transaction Detail")
                    .font(.title2.bold())

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Date", value: String(transaction.date.prefix(10)))
                        detailRow("Source", value: transaction.sourceName)
                        detailRow("Type", value: transaction.txType)
                        detailRow("Asset", value: transaction.asset)
                        detailRow("Amount", value: transaction.amount)
                        detailRow("USD Value", value: ValueFormatters.currency(from: transaction.usdValue, code: "USD") ?? transaction.usdValue)
                        if let desc = transaction.description, !desc.isEmpty {
                            detailRow("Description", value: desc)
                        }
                        if let side = transaction.tradeSide, !side.isEmpty {
                            detailRow("Side", value: side)
                        }
                        if transaction.metadata?.isInternalTransfer == true {
                            detailRow("Transfer", value: "Internal transfer detected")
                        }
                        if let group = transaction.group {
                            Divider()
                            detailRow("Group", value: group.type.replacingOccurrences(of: "_", with: " ").capitalized)
                            detailRow("Items", value: "\(group.childCount) transactions")
                            if group.fromAsset != group.toAsset {
                                detailRow("From", value: "\(group.fromAmount) \(group.fromAsset)")
                                detailRow("To", value: "\(group.toAmount) \(group.toAsset)")
                            }
                            if group.fromSource != group.toSource {
                                detailRow("Route", value: "\(group.fromSource) \u{2192} \(group.toSource)")
                            }
                        }
                    }
                }

                // Matched rule and raw fields.
                if let detail {
                    if let rule = detail.matchedRule {
                        GroupBox("Matched Rule") {
                            matchedRuleView(rule)
                        }
                    }

                    if let rawFields = detail.rawFields, !rawFields.isEmpty {
                        GroupBox("Raw Fields") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(rawFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                    rawFieldRow(key, value: value)
                                }
                            }
                        }
                    }
                } else if isLoadingDetail {
                    GroupBox("Loading details...") {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(8)
                    }
                }

                GroupBox("Category") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Uncategorized").tag(nil as String?)
                            ForEach(applicableCategories) { cat in
                                Text(cat.displayName).tag(cat.category as String?)
                            }
                        }
                        .pickerStyle(.menu)

                        if let source = transaction.metadata?.categorySource {
                            Text("Source: \(source)")
                                .font(DesignTokens.captionFont)
                                .foregroundStyle(.secondary)
                        }
                        if let confidence = transaction.metadata?.categoryConfidence {
                            Text("Confidence: \(String(format: "%.0f%%", confidence * 100))")
                                .font(DesignTokens.captionFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox("Notes") {
                    TextEditor(text: $notes)
                        .font(DesignTokens.bodyFont)
                        .frame(minHeight: 60, maxHeight: 100)
                }

                Toggle("Reviewed", isOn: $isReviewed)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    Button("Save") {
                        onSave(selectedCategory, isReviewed, notes)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(24)
        }
        .frame(width: 620)
        .frame(maxHeight: 700)
        .task { await loadDetail() }
    }

    private func loadDetail() async {
        guard transaction.id > 0 else { return }
        isLoadingDetail = true
        do {
            detail = try await APIClient.shared.getTransaction(id: transaction.id)
        } catch {
            // Detail fetch is best-effort; the sheet still works without it.
        }
        isLoadingDetail = false
    }

    // MARK: - Matched rule display

    private func matchedRuleView(_ rule: CategoryRuleDTO) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(rule.resultCategory)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.green)

            Text("if type =")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("\"\(rule.typeMatch)\"")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.purple)

            if let field = rule.fieldName, !field.isEmpty,
               let op = rule.fieldOperator, let val = rule.fieldValue {
                Text("AND \(field) \(op)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\"\(val)\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.purple)
            }

            if let source = rule.source, source != "*" {
                Text("[\(source)]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            Spacer()

            if rule.builtin == true {
                Text("builtin")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.1), in: Capsule())
            }
        }
    }

    // MARK: - Detail rows

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(DesignTokens.bodyFont)
        }
    }

    private func rawFieldRow(_ key: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}
