import SwiftUI

struct TransactionsListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: TransactionsViewModel

    init() {
        _viewModel = StateObject(wrappedValue: TransactionsViewModel())
    }

    fileprivate init(viewModel: TransactionsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    @AppStorage("transactions.searchQuery") private var searchQuery = ""
    @AppStorage("transactions.selectedType") private var selectedType = "all"
    @AppStorage("transactions.selectedCategory") private var selectedCategory = "all"
    @State private var selectedTransaction: TransactionDTO?
    @State private var categoryPickerTxId: Int?
    @State private var typePickerTxId: Int?
    @State private var hoverTypeTxId: Int?
    @State private var hoverCategoryTxId: Int?
    @State private var showRulesSheet = false

    private let txTypes = ["all", "deposit", "withdrawal", "spend", "trade", "yield", "dividend", "interest", "fee", "transfer"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transactions")
                    .font(DesignTokens.titleFont)
                    .padding(.horizontal, DesignTokens.pageContentPadding)

                if viewModel.isLoading && viewModel.transactions.isEmpty {
                    ProgressView("Loading transactions...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(
                        title: "Unable to load",
                        message: errorMessage,
                        systemImage: "exclamationmark.triangle",
                        actionTitle: "Retry"
                    ) {
                        reload()
                    }
                } else if viewModel.transactions.isEmpty {
                    EmptyStateView(
                        title: "No transactions",
                        message: "No transactions match your filters.",
                        systemImage: "list.bullet.rectangle"
                    )
                } else {
                    transactionTable
                        .frame(maxWidth: .infinity)
                }

                if let msg = viewModel.categorizationMessage {
                    Text(msg)
                        .font(DesignTokens.captionFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignTokens.pageContentPadding)
                }
            }
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, 24)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                txTypeMenu
            }
            ToolbarItem(placement: .automatic) {
                categoryMenu
            }
            ToolbarItem(placement: .automatic) {
                searchField
            }
            ToolbarItem(placement: .automatic) {
                Button { showRulesSheet = true } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .help("Category rules")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    viewModel.runCategorization()
                } label: {
                    if viewModel.isCategorizing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(viewModel.isCategorizing)
                .help("Auto-categorize transactions")
            }
            ToolbarItem(placement: .automatic) {
                pageControls
            }
        }
        .onAppear {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == nil else { return }
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionCompleted)) { _ in
            reload()
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            guard newValue == .transactions else { return }
            reload()
        }
        .sheet(isPresented: $showRulesSheet) {
            CategoryRulesView()
                .frame(width: 700, height: 500)
        }
        .sheet(item: $selectedTransaction) { tx in
            TransactionDetailSheet(
                transaction: tx,
                categories: viewModel.categories,
                onSave: { category, reviewed, notes in
                    viewModel.updateMetadata(id: tx.id, category: category, reviewed: reviewed, notes: notes)
                    reload()
                }
            )
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .onSubmit { reload() }
            if !searchQuery.isEmpty {
                Button { searchQuery = ""; reload() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 200, height: 24)
        .glassEffect(.regular, in: Capsule())
    }

    private var pageControls: some View {
        HStack(spacing: 6) {
            Button { viewModel.goNextPage() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!viewModel.hasNextPage || viewModel.isLoading)

            if let label = viewModel.windowLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button { viewModel.goPreviousPage() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!viewModel.hasPreviousPage || viewModel.isLoading)
        }
    }

    private var txTypeMenu: some View {
        Menu {
            ForEach(txTypes, id: \.self) { type in
                Button {
                    selectedType = type
                    selectedCategory = "all"
                    reload()
                } label: {
                    if type == selectedType {
                        Label(type == "all" ? "All Types" : type.capitalized, systemImage: "checkmark")
                    } else {
                        Text(type == "all" ? "All Types" : type.capitalized)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(selectedType == "all" ? "All" : selectedType.capitalized)
                    .font(.subheadline)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    private var filteredCategories: [TransactionCategoryDTO] {
        if selectedType == "all" {
            return viewModel.categories
        }
        return viewModel.categoriesForType(selectedType)
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                selectedCategory = "all"
                reload()
            } label: {
                if selectedCategory == "all" {
                    Label("All Categories", systemImage: "checkmark")
                } else {
                    Text("All Categories")
                }
            }
            ForEach(filteredCategories, id: \.category) { cat in
                Button {
                    selectedCategory = cat.category
                    reload()
                } label: {
                    if cat.category == selectedCategory {
                        Label(cat.displayName, systemImage: "checkmark")
                    } else {
                        Text(cat.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                Text(selectedCategory == "all" ? "Category" : viewModel.categoryDisplayName(for: selectedCategory))
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }

    // MARK: - Date-grouped table

    private var groupedTransactions: [(key: String, label: String, txs: [TransactionDTO])] {
        let grouped = Dictionary(grouping: viewModel.transactions) { tx in
            String(tx.date.prefix(10))
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { section in
                let sorted = section.value.sorted { a, b in
                    (a.time ?? "") < (b.time ?? "")
                }
                return (key: section.key, label: formatDateSubtitle(section.key), txs: sorted)
            }
    }

    private var tableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("Time", width: 50)
                headerCell("Source", width: 50)
                headerCell("Type", width: 100)
                headerCell("Amount", width: 100, alignment: .trailing)
                Spacer().frame(width: 12)
                headerCell("Asset", width: 100)
                headerCell("USD Value", width: 100, alignment: .trailing)
                Spacer().frame(width: 12)
                headerCell("Category", width: 140, alignment: .trailing)
            }
            .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
            .padding(.vertical, 6)
            .background(DesignTokens.cardBackground.opacity(0.4))

            Divider()
        }
    }

    private var transactionTable: some View {
        VStack(spacing: 12) {
            ForEach(groupedTransactions, id: \.key) { section in
                VStack(spacing: 0) {
                    // Date subtitle
                    Text(section.label)
                        .font(DesignTokens.captionFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
                        .padding(.vertical, 6)

                    tableHeader

                    // Rows
                    ForEach(section.txs) { tx in
                        Button {
                            if tx.id > 0 { selectedTransaction = tx }
                        } label: {
                            HStack(spacing: 0) {
                                rowCell(tx.time ?? "—", width: 50)
                                sourceIconCell(tx: tx, width: 50)
                                txTypeBadge(tx, width: 100)
                                amountCell(tx: tx, width: 100)
                                Spacer().frame(width: 12)
                                assetCell(tx: tx, width: 100)
                                rowCell(
                                    appState.hideBalance ? "••••" : (ValueFormatters.currency(from: tx.usdValue, code: "USD") ?? tx.usdValue),
                                    width: 100,
                                    alignment: .trailing
                                )
                                Spacer().frame(width: 12)
                                categoryBadge(tx, width: 140)
                            }
                            .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

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

        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Cells

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(DesignTokens.captionFont)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func rowCell(_ text: some StringProtocol, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(DesignTokens.bodyFont)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    private func sourceIconCell(tx: TransactionDTO, width: CGFloat) -> some View {
        HStack(spacing: 2) {
            if let group = tx.group, group.type == "internal_transfer" {
                if let fromIcon = (group.fromSourceType ?? group.fromSource).sourceIconName() {
                    Image(fromIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                if let toIcon = (group.toSourceType ?? group.toSource).sourceIconName() {
                    Image(toIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                }
            } else {
                let iconKey = tx.group?.fromSourceType ?? tx.source
                if let iconName = iconKey.sourceIconName() {
                    Image(iconName)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func assetCell(tx: TransactionDTO, width: CGFloat) -> some View {
        Group {
            if let group = tx.group, group.fromAsset != group.toAsset {
                HStack(spacing: 4) {
                    Text(group.fromAsset)
                        .font(DesignTokens.bodyFont)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(group.toAsset)
                        .font(DesignTokens.bodyFont)
                        .lineLimit(1)
                }
            } else {
                Text(tx.asset)
                    .font(DesignTokens.bodyFont)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func amountCell(tx: TransactionDTO, width: CGFloat) -> some View {
        Group {
            if appState.hideBalance {
                Text("••••")
                    .font(DesignTokens.bodyFont)
            } else if let group = tx.group, group.type == "trade_pair" {
                Text(formatAmount(group.toAmount))
                    .font(DesignTokens.bodyFont)
            } else {
                Text(formatAmount(tx.amount))
                    .font(DesignTokens.bodyFont)
            }
        }
        .lineLimit(1)
        .frame(width: width, alignment: .trailing)
    }

    private func txTypeBadge(_ tx: TransactionDTO, width: CGFloat) -> some View {
        let type = tx.resolvedType
        let isPickerOpen = typePickerTxId == tx.id
        let isHovered = hoverTypeTxId == tx.id
        return HStack(spacing: 4) {
            Text(type)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(txTypeColor(type).opacity(isPickerOpen ? 0.3 : 0.15), in: Capsule())
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .medium))
                .opacity(isHovered || isPickerOpen ? 1 : 0)
        }
        .foregroundStyle(txTypeColor(type))
        .frame(width: width, alignment: .leading)
        .onHover { hoverTypeTxId = $0 ? tx.id : nil }
            .onTapGesture {
                typePickerTxId = isPickerOpen ? nil : tx.id
            }
            .popover(isPresented: Binding(
                get: { typePickerTxId == tx.id },
                set: { if !$0 { typePickerTxId = nil } }
            ), arrowEdge: .bottom) {
                TransactionEditPopover(
                    tx: tx,
                    types: txTypes.filter { $0 != "all" },
                    categories: viewModel.categories,
                    color: txTypeColor,
                    onSetType: { newType in
                        viewModel.setType(txId: tx.id, type: newType)
                    },
                    onSetCategory: { category in
                        viewModel.setCategory(txId: tx.id, category: category)
                    },
                    onCreateCategory: { txType, name in
                        viewModel.createCategory(txType: txType, name: name)
                    },
                    onLinkTransfer: { partnerId in
                        viewModel.linkTransfer(txIdA: tx.id, txIdB: partnerId)
                        typePickerTxId = nil
                    },
                    onDone: {
                        typePickerTxId = nil
                    }
                )
            }
    }

    private func categoryBadge(_ tx: TransactionDTO, width: CGFloat) -> some View {
        let isPickerOpen = categoryPickerTxId == tx.id
        let isUncategorized = tx.metadata?.category == nil
        let isHovered = hoverCategoryTxId == tx.id
        return HStack(spacing: 4) {
            Image(systemName: "pencil")
                .font(.system(size: 10))
                .opacity(isHovered || isPickerOpen ? 1 : 0)
            HStack(spacing: 4) {
                if tx.metadata?.isInternalTransfer == true || tx.group?.type == "internal_transfer" {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
                    if isHovered {
                        if let group = tx.group, group.type == "internal_transfer", let firstChild = group.childIds.first {
                            Button {
                                viewModel.unlinkTransfer(txId: firstChild)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Unlink transfer")
                        } else if tx.id > 0 {
                            Button {
                                viewModel.unlinkTransfer(txId: tx.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Unlink transfer")
                        }
                    }
                }
                Text(viewModel.categoryDisplayName(for: tx.metadata?.category))
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isUncategorized ? DesignTokens.error.opacity(0.12) : (isPickerOpen ? Color.accentColor.opacity(0.1) : Color.clear), in: Capsule())
        }
        .foregroundStyle(isUncategorized ? DesignTokens.error : .primary)
        .onHover { hoverCategoryTxId = $0 ? tx.id : nil }
        .frame(width: width, alignment: .trailing)
        .onTapGesture {
            categoryPickerTxId = isPickerOpen ? nil : tx.id
        }
        .popover(isPresented: Binding(
            get: { categoryPickerTxId == tx.id },
            set: { if !$0 { categoryPickerTxId = nil } }
        ), arrowEdge: .trailing) {
            CategoryPickerPopover(
                tx: tx,
                categories: viewModel.categoriesForType(tx.resolvedType),
                displayName: viewModel.categoryDisplayName(for:),
                onSelect: { category in
                    viewModel.setCategory(txId: tx.id, category: category)
                },
                onCreateCategory: { txType, name in
                    viewModel.createCategory(txType: txType, name: name)
                },
                onDone: {
                    categoryPickerTxId = nil
                }
            )
        }
    }

    // MARK: - Helpers

    private func txTypeColor(_ type: String) -> Color {
        switch type {
        case "deposit": return .green
        case "withdrawal": return .red
        case "spend": return .teal
        case "trade": return .blue
        case "yield", "interest", "dividend": return .orange
        case "fee": return .pink
        case "transfer": return .purple
        default: return .gray
        }
    }

    private func formatAmount(_ value: String) -> String {
        guard let number = Double(value) else { return value }
        let rounded2 = (number * 100).rounded() / 100
        let rounded4 = (number * 10_000).rounded() / 10_000
        let digits = rounded4 != rounded2 ? 4 : 2
        return String(format: "%.\(digits)f", number)
    }

    private func formatDateSubtitle(_ isoDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: isoDate) else { return isoDate }

        let calendar = Calendar.current
        let isCurrentYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())

        let display = DateFormatter()
        display.dateFormat = isCurrentYear ? "EEE d MMM" : "EEE d MMM yyyy"
        return display.string(from: date)
    }

    private func reload() {
        viewModel.load(
            sourceName: nil,
            txType: selectedType == "all" ? nil : selectedType,
            category: selectedCategory == "all" ? nil : selectedCategory,
            search: searchQuery.isEmpty ? nil : searchQuery
        )
    }
}

private struct TransactionEditPopover: View {
    let tx: TransactionDTO
    let types: [String]
    let categories: [TransactionCategoryDTO]
    let color: (String) -> Color
    let onSetType: (String) -> Void
    let onSetCategory: (String) -> Void
    let onCreateCategory: (String, String) -> Void
    let onLinkTransfer: (Int) -> Void
    let onDone: () -> Void

    private enum Step { case type, category, source, linkTransaction }

    @State private var step: Step = .type
    @State private var selectedType: String?
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var isCreatingRule = false
    @State private var ruleCategoryForForm: String?
    @State private var transferSources: [String] = []
    @State private var transferCandidates: [TransferCandidate] = []
    @State private var isLoadingCandidates = false
    @State private var rawFields: [String: String]?
    @State private var matchedRule: CategoryRuleDTO?
    @State private var isLoadingDetail = false

    private var effectiveType: String { selectedType ?? tx.resolvedType }

    private var filteredCategories: [TransactionCategoryDTO] {
        categories.filter { $0.txType == effectiveType }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                leftPanel
            }
            .frame(minWidth: 180, idealWidth: 220)

            Divider()

            ScrollView {
                rightPanel
            }
            .frame(minWidth: 200, idealWidth: 280)
        }
        .frame(minWidth: 400, maxWidth: 600, minHeight: 120, maxHeight: 600)
        .task { await loadDetail() }
    }

    @ViewBuilder
    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with transaction context.
            if let desc = tx.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(desc)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                    Text("\(tx.sourceName) · \(tx.asset)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
            }

            // Step indicator.
            stepHeader

            Divider()

            // Step content.
            switch step {
            case .type:
                typeList
            case .category:
                categoryList
            case .source:
                sourceList
            case .linkTransaction:
                candidateList
            }
        }
    }

    private var stepHeader: some View {
        HStack(spacing: 6) {
            if step != .type {
                Button {
                    switch step {
                    case .category: step = .type
                    case .source: step = .category
                    case .linkTransaction: step = .source
                    case .type: break
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            Text(stepTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if step == .source || step == .linkTransaction {
                Button("Skip") { onDone() }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var stepTitle: String {
        switch step {
        case .type: return "Type"
        case .category: return "Category"
        case .source: return "Source"
        case .linkTransaction: return "Link Transfer"
        }
    }

    // MARK: - Step 1: Type

    private var typeList: some View {
        ForEach(types, id: \.self) { type in
            let isSelected = type == effectiveType
            Button {
                selectedType = type
                onSetType(type)
                advanceAfterType(type)
            } label: {
                HStack {
                    Text(type)
                        .font(.system(size: 12))
                        .foregroundStyle(color(type))
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
                .background(isSelected ? color(type).opacity(0.08) : Color.clear)
            }
            .buttonStyle(.plain)
        }
    }

    private func advanceAfterType(_ type: String) {
        let cats = categories.filter { $0.txType == type }
        if cats.count == 1 {
            onSetCategory(cats[0].category)
            if cats[0].category == "transfer" {
                Task { await loadCandidates() }
                step = .source
            } else {
                onDone()
            }
        } else if cats.isEmpty {
            onDone()
        } else {
            step = .category
        }
    }

    // MARK: - Step 2: Category

    private var categoryList: some View {
        Group {
            if filteredCategories.isEmpty {
                Text("No categories for \(effectiveType)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ForEach(filteredCategories) { cat in
                    let isSelected = isCreatingRule
                        ? (cat.category == ruleCategoryForForm)
                        : (cat.category == tx.metadata?.category)
                    Button {
                        onSetCategory(cat.category)
                        if cat.category == "transfer" {
                            Task { await loadCandidates() }
                            step = .source
                        } else {
                            ruleCategoryForForm = cat.category
                            isCreatingRule = true
                        }
                    } label: {
                        HStack {
                            Text(cat.displayName)
                                .font(.system(size: 12))
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
                            onCreateCategory(effectiveType, name)
                            let key = name.lowercased().replacingOccurrences(of: " ", with: "_")
                            onSetCategory(key)
                            isAddingCategory = false
                            newCategoryName = ""
                            onDone()
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

                if isCreatingRule, let ruleCat = ruleCategoryForForm {
                    Divider()
                    InlineRuleForm(
                        txType: effectiveType,
                        category: ruleCat,
                        source: tx.source,
                        rawFields: rawFields,
                        onSaved: {
                            isCreatingRule = false
                            ruleCategoryForForm = nil
                            onDone()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Step 3: Source selection

    private var sourceList: some View {
        Group {
            if isLoadingCandidates {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(12)
            } else if transferSources.isEmpty {
                VStack(spacing: 8) {
                    Text("No matching transfers found")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button("Done") { onDone() }
                        .font(.system(size: 12))
                }
                .padding(12)
            } else {
                ForEach(transferSources, id: \.self) { source in
                    Button {
                        let filtered = transferCandidates.filter { $0.sourceName == source }
                        transferCandidates = filtered
                        step = .linkTransaction
                    } label: {
                        HStack {
                            if let iconName = source.sourceIconName() {
                                Image(iconName)
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                            }
                            Text(source)
                                .font(.system(size: 12))
                            Spacer()
                            let count = transferCandidates.filter { $0.sourceName == source }.count
                            Text("\(count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 4: Link transaction

    private var candidateList: some View {
        Group {
            if transferCandidates.isEmpty {
                VStack(spacing: 8) {
                    Text("No candidates from this source")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button("Done") { onDone() }
                        .font(.system(size: 12))
                }
                .padding(12)
            } else {
                ForEach(transferCandidates) { candidate in
                    Button {
                        onLinkTransfer(candidate.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(candidate.asset)
                                    .font(.system(size: 12, weight: .medium))
                                Text(candidate.amount)
                                    .font(.system(size: 12, design: .monospaced))
                                Spacer()
                                Text("$\(candidate.usdValue)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text(candidate.date)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Right panel (raw fields)

    @ViewBuilder
    private var rightPanel: some View {
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

    // MARK: - Data loading

    private func loadDetail() async {
        guard tx.id > 0, rawFields == nil, matchedRule == nil else { return }
        isLoadingDetail = true
        do {
            let detail = try await APIClient.shared.getTransaction(id: tx.id)
            rawFields = detail.rawFields
            matchedRule = detail.matchedRule
        } catch {}
        isLoadingDetail = false
    }

    private func loadCandidates() async {
        isLoadingCandidates = true
        do {
            let response = try await APIClient.shared.getTransferCandidates(id: tx.id)
            transferSources = response.sources
            transferCandidates = response.candidates
        } catch {}
        isLoadingCandidates = false
    }
}

#Preview {
    let vm = TransactionsViewModel()
    vm.transactions = [
        TransactionDTO(
            id: 1, date: "2026-03-15", time: "14:32", source: "wise", sourceName: "Wise",
            txType: "spend", effectiveType: nil, asset: "EUR", amount: "42.50", usdValue: "46.12",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: nil,
            description: "Lidl Berlin",
            metadata: TransactionMetadataDTO(
                category: "groceries", categorySource: "rule", categoryConfidence: nil,
                typeOverride: nil, isInternalTransfer: nil, transferPairId: nil,
                transferDetectedBy: nil, reviewed: true, notes: nil
            ),
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
        TransactionDTO(
            id: 2, date: "2026-03-15", time: "10:15", source: "wise", sourceName: "Wise",
            txType: "spend", effectiveType: nil, asset: "EUR", amount: "8.90", usdValue: "9.66",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: nil,
            description: "BVG Monthly",
            metadata: TransactionMetadataDTO(
                category: "transport", categorySource: "rule", categoryConfidence: nil,
                typeOverride: nil, isInternalTransfer: nil, transferPairId: nil,
                transferDetectedBy: nil, reviewed: false, notes: nil
            ),
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
        TransactionDTO(
            id: 3, date: "2026-03-15", time: "09:00", source: "wise", sourceName: "Wise",
            txType: "deposit", effectiveType: nil, asset: "EUR", amount: "3200.00", usdValue: "3472.00",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: nil,
            description: "Salary Mar 2026",
            metadata: TransactionMetadataDTO(
                category: "salary", categorySource: "rule", categoryConfidence: nil,
                typeOverride: nil, isInternalTransfer: nil, transferPairId: nil,
                transferDetectedBy: nil, reviewed: true, notes: nil
            ),
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
        TransactionDTO(
            id: 4, date: "2026-03-15", time: "16:45", source: "okx", sourceName: "OKX",
            txType: "trade", effectiveType: nil, asset: "BTC", amount: "0.015", usdValue: "975.00",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: "buy",
            description: nil,
            metadata: nil,
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
        TransactionDTO(
            id: 5, date: "2026-03-15", time: "11:20", source: "wise", sourceName: "Wise",
            txType: "transfer", effectiveType: nil, asset: "EUR", amount: "500.00", usdValue: "542.50",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: nil,
            description: "To OKX",
            metadata: TransactionMetadataDTO(
                category: nil, categorySource: nil, categoryConfidence: nil,
                typeOverride: nil, isInternalTransfer: true, transferPairId: 6,
                transferDetectedBy: "auto", reviewed: nil, notes: nil
            ),
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
        TransactionDTO(
            id: 6, date: "2026-03-15", time: "16:00", source: "wise", sourceName: "Wise",
            txType: "withdrawal", effectiveType: nil, asset: "EUR", amount: "200.00", usdValue: "217.00",
            counterpartyAsset: nil, counterpartyAmount: nil, txId: nil, tradeSide: nil,
            description: "ATM Berlin Alexanderplatz",
            metadata: TransactionMetadataDTO(
                category: "cash", categorySource: "rule", categoryConfidence: nil,
                typeOverride: nil, isInternalTransfer: nil, transferPairId: nil,
                transferDetectedBy: nil, reviewed: false, notes: nil
            ),
            group: nil, rawFields: nil, matchedRule: nil, availableCategories: nil, availableTypes: nil
        ),
    ]
    vm.categories = [
        TransactionCategoryDTO(id: 1, txType: "spend", category: "groceries", displayName: "Groceries", sortOrder: 1),
        TransactionCategoryDTO(id: 2, txType: "spend", category: "transport", displayName: "Transport", sortOrder: 2),
        TransactionCategoryDTO(id: 3, txType: "deposit", category: "salary", displayName: "Salary", sortOrder: 1),
    ]
    vm.total = 6
    return TransactionsListView(viewModel: vm)
        .environmentObject(AppState())
}
