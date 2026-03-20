import SwiftUI

struct CategoryRulesView: View {
    @StateObject private var viewModel = CategoryRulesViewModel()
    @State private var showNewRuleSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Category Rules")
                    .font(DesignTokens.titleFont)
                    .padding(.horizontal, DesignTokens.pageContentPadding)

                if viewModel.isLoading && viewModel.rules.isEmpty {
                    ProgressView("Loading rules...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let err = viewModel.errorMessage {
                    EmptyStateView(
                        title: "Unable to load",
                        message: err,
                        systemImage: "exclamationmark.triangle",
                        actionTitle: "Retry"
                    ) { viewModel.load() }
                } else {
                    rulesContent
                }
            }
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showNewRuleSheet = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Add category rule")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Reset all rules") { viewModel.resetRules(source: nil) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Reset rules")
            }
        }
        .onAppear { viewModel.load() }
        .sheet(isPresented: $showNewRuleSheet) {
            NewCategoryRuleSheet(categories: viewModel.categories) {
                viewModel.load()
            }
        }
    }

    private var rulesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.customRules.isEmpty {
                rulesSection("Custom Rules", rules: viewModel.customRules, canDelete: true)
            }
            rulesSection("Default Rules", rules: viewModel.builtinRules, canDelete: true)
        }
        .padding(.horizontal, DesignTokens.pageContentPadding)
    }

    private func rulesSection(_ title: String, rules: [CategoryRuleDTO], canDelete: Bool) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
                .padding(.vertical, 6)

            // Header
            HStack(spacing: 0) {
                Text("Priority")
                    .frame(width: 60, alignment: .leading)
                Text("Category")
                    .frame(width: 120, alignment: .leading)
                Text("Conditions")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("")
                    .frame(width: 30)
            }
            .font(DesignTokens.captionFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.05))

            Divider()

            ForEach(rules, id: \.id) { (rule: CategoryRuleDTO) in
                ruleRow(rule, canDelete: canDelete)
                Divider().padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
            }
        }
        .padding(DesignTokens.blockPadding)
        .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }

    private func ruleRow(_ rule: CategoryRuleDTO, canDelete: Bool) -> some View {
        HStack(spacing: 0) {
            Text("\(rule.priority ?? 300)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(viewModel.categoryDisplayName(for: rule.resultCategory))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            ruleConditionsText(rule)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canDelete {
                Button {
                    viewModel.deleteRule(rule)
                } label: {
                    Image(systemName: rule.builtin == true ? "eye.slash" : "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(rule.deleted == true ? Color.secondary : Color.red)
                }
                .buttonStyle(.plain)
                .frame(width: 30)
                .help(rule.builtin == true ? "Disable builtin rule" : "Delete rule")
                .disabled(rule.deleted == true)
            }
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .padding(.vertical, 5)
        .opacity(rule.deleted == true ? 0.4 : 1.0)
    }

    private func ruleConditionsText(_ rule: CategoryRuleDTO) -> some View {
        HStack(spacing: 3) {
            Text("type =")
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
                    .lineLimit(1)
            }

            if let source = rule.source, source != "*" {
                Text("[\(source)]")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.blue)
            }
        }
    }
}
