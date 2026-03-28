import SwiftUI

struct AllocationView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AllocationViewModel()
    @Namespace private var glassNamespace

    @AppStorage("allocation.searchQuery") private var searchQuery = ""
    @AppStorage("allocation.selectedType") private var selectedType = "all"
    @AppStorage("allocation.hideSmallAmounts") private var hideSmallAmounts = true
    @AppStorage("allocation.sortKey") private var sortKeyRaw = AllocationSortKey.value.rawValue
    @AppStorage("allocation.sortAscending") private var sortAscending = false
    @AppStorage("allocation.visibleColumns") private var visibleColumnsRaw = AllocationColumn.defaultStorage
    @AppStorage("allocation.groupBy") private var groupByRaw = GroupByMode.none.rawValue

    @State private var expandedSections: Set<String> = []

    private var groupBy: GroupByMode {
        get { GroupByMode(rawValue: groupByRaw) ?? .none }
        set { groupByRaw = newValue.rawValue }
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var sortKey: AllocationSortKey {
        get { AllocationSortKey(rawValue: sortKeyRaw) ?? .value }
        set { sortKeyRaw = newValue.rawValue }
    }

    private var visibleColumns: Set<AllocationColumn> {
        get {
            let parsed = Set(
                visibleColumnsRaw
                    .split(separator: ",")
                    .compactMap { AllocationColumn(rawValue: String($0)) }
            )
            if parsed.isEmpty {
                return Set(AllocationColumn.allCases)
            }
            return parsed
        }
        set {
            let ordered = AllocationColumn.allCases.filter(newValue.contains).map(\.rawValue)
            visibleColumnsRaw = ordered.joined(separator: ",")
        }
    }

    private var typeTabs: [String] {
        ["all", "crypto", "defi", "fiat", "other", "stocks", "deposit"]
    }

    private var filteredRows: [AllocationGroupRow] {
        groupedAllocationRows()
    }

    private let controlSize: CGFloat = 24
    private let tableRightScrollPadding: CGFloat = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allocation")
                    .font(.title)
                contentContainer
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.leading, DesignTokens.pageContentPadding)
        .padding(.trailing, DesignTokens.pageContentTrailingPadding)
        .padding(.top, DesignTokens.pageContentPadding)
        .padding(.bottom, 8)
        }
        .navigationTitle("Allocation")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                searchField
                    .frame(width: 200)
            }
            ToolbarItem(placement: .automatic) {
                groupByPicker
            }
            if groupBy != .none {
                ToolbarItem(placement: .automatic) {
                    expandAllToggle
                }
            }
            if groupBy != .type {
                ToolbarItem(placement: .automatic) {
                    typeTabsBar
                }
            }
            ToolbarItem(placement: .automatic) {
                controlsMenu
            }
        }
        .onAppear {
            sanitizePersistedState()
            guard !isPreview else { return }
            viewModel.load()
        }
        .onChange(of: typeTabs) { _, _ in
            ensureSelectedTypeIsValid()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated)) { _ in
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionCompleted)) { _ in
            viewModel.load()
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            if newValue == .allocation {
                viewModel.load()
            }
        }
        .onChange(of: groupByRaw) { _, newValue in
            expandedSections = []
            if GroupByMode(rawValue: newValue) == .type {
                selectedType = "all"
            }
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        if viewModel.isLoading {
            ProgressView("Loading allocation...")
        } else if let errorMessage = viewModel.errorMessage {
            EmptyStateView(title: "Allocation unavailable", message: errorMessage, actionTitle: "Retry") {
                viewModel.load()
            }
        } else if groupBy == .none {
            ScrollView(.vertical) {
                allocationTable
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, DesignTokens.blockPadding)
            .padding(.trailing, 8)
            .padding(.top, 16)
            .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .stroke(DesignTokens.border)
            )
        } else {
            allocationTable
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controlsMenu: some View {
        Menu {
            controlsMenuItems
        } label: {
            Label("Allocation options", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: controlSize, height: controlSize)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .frame(height: controlSize)
        .accessibilityLabel("Allocation options")
        .glassEffectID("allocation-controls-menu", in: glassNamespace)
    }

    private var controlsMenuItems: some View {
        Group {
            Button {
                hideSmallAmounts.toggle()
            } label: {
                Text(menuItemTitle("Hide small amounts", checked: hideSmallAmounts))
            }

            Menu("Sort options") {
                ForEach(AllocationSortKey.allCases, id: \.self) { key in
                    Button {
                        sortKeyRaw = key.rawValue
                    } label: {
                        Text(menuItemTitle(key.title, checked: sortKey == key))
                    }
                }

                Divider()

                Button {
                    sortAscending = true
                } label: {
                    Text(menuItemTitle("Ascending", checked: sortAscending))
                }

                Button {
                    sortAscending = false
                } label: {
                    Text(menuItemTitle("Descending", checked: !sortAscending))
                }
            }

            Menu("Columns options") {
                ForEach(AllocationColumn.allCases, id: \.self) { column in
                    Button {
                        toggleColumn(column)
                    } label: {
                        Text(menuItemTitle(column.title, checked: isColumnVisible(column)))
                    }
                }
            }

        }
    }

    private var typeTabsBar: some View {
        Picker("", selection: $selectedType) {
            ForEach(typeTabs, id: \.self) { type in
                Image(systemName: typeSymbol(for: type))
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityLabel(Text(typeTitle(for: type)))
                    .help(typeTitle(for: type))
                    .tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .tint(.clear)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: controlSize)
        .glassEffectID("allocation-type-tabs", in: glassNamespace)
    }

    private var groupByPicker: some View {
        Picker("Group by", selection: $groupByRaw) {
            ForEach(GroupByMode.allCases) { mode in
                Image(systemName: mode.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityLabel(Text(mode.title))
                    .help("Group by \(mode.title)")
                    .tag(mode.rawValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: controlSize)
        .glassEffectID("allocation-group-by", in: glassNamespace)
    }

    private var expandAllToggle: some View {
        Toggle(
            isOn: Binding(
                get: { !expandedSections.isEmpty },
                set: { expand in
                    if expand {
                        expandedSections = Set(allocationSections().map(\.id))
                    } else {
                        expandedSections = []
                    }
                }
            )
        ) {
            Label("Expand all", systemImage: "rectangle.expand.vertical")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: controlSize)
        .allocationGlassBackground(in: Capsule())
        .glassEffectID("allocation-search", in: glassNamespace)
    }

    private var allocationTable: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if groupBy == .none {
                allocationHeader

                if filteredRows.isEmpty {
                    Text("No allocation data yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredRows) { row in
                        allocationRow(row)
                    }
                }
            } else {
                let sections = allocationSections()
                if sections.isEmpty {
                    Text("No allocation data yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sections) { section in
                        allocationSectionView(section)
                    }
                }
            }
        }
    }

    private func allocationSectionView(_ section: AllocationSection) -> some View {
        let expanded = expandedSections.contains(section.id)
        return VStack(alignment: .leading, spacing: 8) {
            CollapsibleSectionHeader(
                title: section.title,
                iconName: section.iconName,
                iconIsSystemSymbol: section.iconIsSystemSymbol,
                totalUsdValue: ValueFormatters.currency(
                    from: NSDecimalNumber(decimal: section.totalUsdValue).stringValue,
                    code: "usd"
                ),
                percentage: section.percentage.flatMap {
                    ValueFormatters.percentFromPercentValue(
                        NSDecimalNumber(decimal: $0).stringValue
                    )
                },
                isExpanded: Binding(
                    get: { expandedSections.contains(section.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedSections.insert(section.id)
                        } else {
                            expandedSections.remove(section.id)
                        }
                    }
                ),
                hideBalance: appState.hideBalance
            )

            if expanded {
                Divider()

                allocationHeader

                ForEach(section.rows) { row in
                    allocationRow(row)
                }
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

    private var allocationHeader: some View {
        HStack(spacing: 12) {
            headerCell("Asset")
            if isColumnVisible(.source) {
                headerCell("Source")
            }
            if isColumnVisible(.amount) {
                headerCell("Amount", alignment: .trailing)
            }
            if isColumnVisible(.price) {
                headerCell("Price", alignment: .trailing)
            }
            if isColumnVisible(.value) {
                headerCell("Value", alignment: .trailing)
            }
            if isColumnVisible(.percentage) {
                headerCell("% Of Net Value", alignment: .trailing)
            }
            if isColumnVisible(.type) {
                headerCell("Type", alignment: .trailing)
            }
        }
        .padding(.leading, DesignTokens.blockRowHorizontalPadding)
        .padding(.trailing, tableRightScrollPadding)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func allocationRow(_ row: AllocationGroupRow) -> some View {
        let hidden = appState.hideBalance
        return HStack(spacing: 12) {
            rowCell(row.asset)

            if isColumnVisible(.source) {
                sourceCell(sources: row.sources, asset: row.asset)
            }

            if isColumnVisible(.amount) {
                let amountText = hidden ? "••••" : (ValueFormatters.number(from: row.amount) ?? row.amount ?? "—")
                rowCell(amountText, alignment: .trailing)
            }

            if isColumnVisible(.price) {
                let priceText = ValueFormatters.currency(from: row.price, code: "usd") ?? row.price ?? "—"
                rowCell(priceText, alignment: .trailing)
            }

            if isColumnVisible(.value) {
                let valueText = hidden ? "••••" : (ValueFormatters.currency(from: row.usdValue, code: "usd") ?? row.usdValue ?? "—")
                rowCell(valueText, alignment: .trailing)
            }

            if isColumnVisible(.percentage) {
                let percentText = hidden ? "••••" : (ValueFormatters.percentFromPercentValue(row.percentage) ?? row.percentage ?? "—")
                rowCell(percentText, alignment: .trailing)
            }

            if isColumnVisible(.type) {
                typeIconCell(row.assetType)
            }
        }
        .padding(.leading, DesignTokens.blockRowHorizontalPadding)
        .padding(.trailing, tableRightScrollPadding)
        .font(.subheadline)
    }

    @ViewBuilder
    private func sourceCell(sources: [SourceAllocation], asset: String) -> some View {
        let items: [SourceIconItem] = sources.compactMap { source in
            guard let iconName = source.source.sourceIconName() else { return nil }
            let displayName = source.sourceName ?? source.source
            let valueText = ValueFormatters.currency(from: source.usdValue, code: "usd") ?? source.usdValue ?? "—"
            let amountText = ValueFormatters.number(from: source.amount) ?? source.amount ?? "—"
            let tooltip = "\(displayName)\n\(asset) \(amountText)\n\(valueText)"
            return SourceIconItem(iconName: iconName, tooltip: tooltip)
        }

        if items.isEmpty {
            rowCell(sourcesText(sources))
        } else {
            SourceIconsPopover(items: items)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourcesText(_ sources: [SourceAllocation]) -> String {
        let joined = sources.map { $0.sourceName ?? $0.source }.joined(separator: ", ")
        return joined.isEmpty ? "—" : joined
    }

    private func headerCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func rowCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func typeIconCell(_ rawType: String?) -> some View {
        Image(systemName: typeSymbol(for: rawType))
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(Text(typeTitle(for: rawType)))
    }

    private func filteredHoldings() -> [AllocationRow] {
        var holdings = viewModel.summary?.holdings ?? []

        if hideSmallAmounts {
            holdings = holdings.filter { holding in
                guard let usd = holding.usdValue, let value = Decimal(string: usd) else { return true }
                return value >= 1
            }
        }

        if selectedType != "all" {
            holdings = holdings.filter { normalizeType($0.assetType) == selectedType }
        }

        let localTokens = searchQuery
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let globalTokens = appState.globalSearchQuery
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        if !localTokens.isEmpty || !globalTokens.isEmpty {
            holdings = holdings.filter { holding in
                let haystack = holdingHaystack(for: holding)
                let localMatches = localTokens.allSatisfy { token in
                    haystack.contains { $0.contains(token) }
                }
                let globalMatches = globalTokens.allSatisfy { token in
                    haystack.contains { $0.contains(token) }
                }
                return localMatches && globalMatches
            }
        }

        return holdings
    }

    private func groupedAllocationRows() -> [AllocationGroupRow] {
        let holdings = filteredHoldings()
        let netWorthDecimal = netWorthUSD()
        var groups: [String: AllocationGroupAccumulator] = [:]

        for holding in holdings {
            let key = "\(holding.asset)|\(holding.assetType ?? "")"
            var group = groups[key] ?? AllocationGroupAccumulator(asset: holding.asset, assetType: holding.assetType)
            group.append(holding)
            groups[key] = group
        }

        return groups.values
            .map { $0.build(netWorth: netWorthDecimal) }
            .sorted(by: sortRows)
    }

    private func allocationSections() -> [AllocationSection] {
        let netWorth = netWorthUSD()

        switch groupBy {
        case .none:
            return []

        case .source:
            let holdings = filteredHoldings()
            var sourceGroups: [String: [AllocationRow]] = [:]
            for holding in holdings {
                let key = holding.sourceName ?? holding.sources.first ?? "Unknown"
                sourceGroups[key, default: []].append(holding)
            }

            return sourceGroups.compactMap { sourceName, sourceHoldings in
                var assetGroups: [String: AllocationGroupAccumulator] = [:]
                for holding in sourceHoldings {
                    let key = "\(holding.asset)|\(holding.assetType ?? "")"
                    var group = assetGroups[key] ?? AllocationGroupAccumulator(
                        asset: holding.asset, assetType: holding.assetType
                    )
                    group.append(holding)
                    assetGroups[key] = group
                }
                let rows = assetGroups.values
                    .map { $0.build(netWorth: netWorth) }
                    .sorted(by: sortRows)

                guard !rows.isEmpty else { return nil }

                let sectionTotal = rows.reduce(Decimal.zero) { sum, row in
                    sum + (Decimal(string: row.usdValue ?? "") ?? 0)
                }
                let pct = netWorth.flatMap { $0 > 0 ? (sectionTotal / $0) * 100 : nil }
                let sourceKey = sourceHoldings.first?.sources.first ?? sourceName

                return AllocationSection(
                    id: sourceName,
                    title: sourceName,
                    iconName: sourceKey.sourceIconName(),
                    iconIsSystemSymbol: false,
                    totalUsdValue: sectionTotal,
                    percentage: pct,
                    rows: rows
                )
            }
            .sorted { $0.totalUsdValue > $1.totalUsdValue }

        case .type:
            let rows = groupedAllocationRows()
            var typeGroups: [String: [AllocationGroupRow]] = [:]
            for row in rows {
                let key = normalizeType(row.assetType) ?? "other"
                typeGroups[key, default: []].append(row)
            }

            return typeGroups.compactMap { key, groupRows in
                guard !groupRows.isEmpty else { return nil }

                let sectionTotal = groupRows.reduce(Decimal.zero) { sum, row in
                    sum + (Decimal(string: row.usdValue ?? "") ?? 0)
                }
                let pct = netWorth.flatMap { $0 > 0 ? (sectionTotal / $0) * 100 : nil }

                return AllocationSection(
                    id: key,
                    title: typeTitle(for: key),
                    iconName: typeSymbol(for: key),
                    iconIsSystemSymbol: true,
                    totalUsdValue: sectionTotal,
                    percentage: pct,
                    rows: groupRows
                )
            }
            .sorted { $0.totalUsdValue > $1.totalUsdValue }
        }
    }

    private func sortRows(_ lhs: AllocationGroupRow, _ rhs: AllocationGroupRow) -> Bool {
        switch sortKey {
        case .value:
            return compareDecimals(
                decimal(from: lhs.usdValue),
                decimal(from: rhs.usdValue),
                lhs: lhs,
                rhs: rhs
            )
        case .asset:
            let cmp = lhs.asset.localizedCaseInsensitiveCompare(rhs.asset)
            if cmp == .orderedSame {
                return compareDecimals(
                    decimal(from: lhs.usdValue),
                    decimal(from: rhs.usdValue),
                    lhs: lhs,
                    rhs: rhs
                )
            }
            return sortAscending ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
        case .amount:
            return compareDecimals(
                decimal(from: lhs.amount),
                decimal(from: rhs.amount),
                lhs: lhs,
                rhs: rhs
            )
        case .price:
            return compareDecimals(
                decimal(from: lhs.price),
                decimal(from: rhs.price),
                lhs: lhs,
                rhs: rhs
            )
        case .percentage:
            return compareDecimals(
                decimal(from: lhs.percentage),
                decimal(from: rhs.percentage),
                lhs: lhs,
                rhs: rhs
            )
        }
    }

    private func compareDecimals(_ left: Decimal, _ right: Decimal, lhs: AllocationGroupRow, rhs: AllocationGroupRow) -> Bool {
        if left == right {
            return lhs.asset.localizedCaseInsensitiveCompare(rhs.asset) == .orderedAscending
        }
        return sortAscending ? (left < right) : (left > right)
    }

    private func decimal(from value: String?) -> Decimal {
        Decimal(string: value ?? "") ?? 0
    }

    private func holdingHaystack(for holding: AllocationRow) -> [String] {
        var values: [String] = [holding.asset.lowercased()]
        values.append(contentsOf: holding.sources.map { $0.lowercased() })
        if let name = holding.sourceName?.lowercased(), !name.isEmpty {
            values.append(name)
        }
        return values
    }

    private func netWorthUSD() -> Decimal? {
        guard let summary = viewModel.summary else { return nil }
        if let usdValue = summary.netWorth?["usd"], let decimal = Decimal(string: usdValue) {
            return decimal
        }
        if let firstValue = summary.netWorth?.values.first, let decimal = Decimal(string: firstValue) {
            return decimal
        }
        return nil
    }

    private func normalizeType(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func typeSymbol(for rawType: String?) -> String {
        switch normalizeType(rawType) {
        case "all":
            return "square.grid.2x2"
        case "crypto":
            return "bitcoinsign.circle"
        case "defi":
            return "link.circle"
        case "fiat":
            return "banknote"
        case "other":
            return "questionmark.circle"
        case "stocks":
            return "chart.line.uptrend.xyaxis"
        case "deposit":
            return "building.columns.circle"
        default:
            return "questionmark.circle"
        }
    }

    private func typeTitle(for rawType: String?) -> String {
        switch normalizeType(rawType) {
        case "all":
            return "All"
        case "crypto":
            return "Crypto"
        case "defi":
            return "DeFi"
        case "fiat":
            return "Fiat"
        case "other":
            return "Other"
        case "stocks":
            return "Stocks"
        case "deposit":
            return "Deposit"
        default:
            return "Unknown type"
        }
    }

    private func menuItemTitle(_ title: String, checked: Bool) -> String {
        checked ? "✓ \(title)" : title
    }

    private func toggleColumn(_ column: AllocationColumn) {
        var current = Set(
            visibleColumnsRaw
                .split(separator: ",")
                .compactMap { AllocationColumn(rawValue: String($0)) }
        )
        if current.isEmpty {
            current = Set(AllocationColumn.allCases)
        }
        if current.contains(column) {
            current.remove(column)
        } else {
            current.insert(column)
        }
        let ordered = AllocationColumn.allCases.filter(current.contains).map(\.rawValue)
        visibleColumnsRaw = ordered.joined(separator: ",")
    }

    private func isColumnVisible(_ column: AllocationColumn) -> Bool {
        visibleColumns.contains(column)
    }

    private func sanitizePersistedState() {
        if AllocationSortKey(rawValue: sortKeyRaw) == nil {
            sortKeyRaw = AllocationSortKey.value.rawValue
        }
        if GroupByMode(rawValue: groupByRaw) == nil {
            groupByRaw = GroupByMode.none.rawValue
        }
        ensureSelectedTypeIsValid()
    }

    private func ensureSelectedTypeIsValid() {
        if !typeTabs.contains(selectedType) {
            selectedType = "all"
        }
    }
}

private enum AllocationSortKey: String, CaseIterable {
    case value
    case asset
    case amount
    case price
    case percentage

    var title: String {
        switch self {
        case .value:
            return "Value"
        case .asset:
            return "Asset"
        case .amount:
            return "Amount"
        case .price:
            return "Price"
        case .percentage:
            return "% Of Net Value"
        }
    }
}

private enum AllocationColumn: String, CaseIterable {
    case source
    case amount
    case price
    case value
    case percentage
    case type

    static let defaultStorage = allCases.map(\.rawValue).joined(separator: ",")

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .amount:
            return "Amount"
        case .price:
            return "Price"
        case .value:
            return "Value"
        case .percentage:
            return "% Of Net Value"
        case .type:
            return "Type"
        }
    }
}

private struct SourceIconItem: Identifiable {
    let id = UUID()
    let iconName: String
    let tooltip: String
}

private struct SourceAllocation: Identifiable {
    var id: String { sourceName ?? source }
    let source: String
    let sourceName: String?
    let amount: String?
    let usdValue: String?
}

private struct AllocationGroupRow: Identifiable {
    var id: String { "\(asset)-\(assetType ?? "")" }
    let asset: String
    let assetType: String?
    let sources: [SourceAllocation]
    let amount: String?
    let usdValue: String?
    let price: String?
    let percentage: String?
}

private struct AllocationSection: Identifiable {
    let id: String
    let title: String
    let iconName: String?
    let iconIsSystemSymbol: Bool
    let totalUsdValue: Decimal
    let percentage: Decimal?
    let rows: [AllocationGroupRow]
}

private struct AllocationGroupAccumulator {
    let asset: String
    let assetType: String?
    private(set) var sources: [SourceAllocation] = []
    private var amountSum: Decimal?
    private var usdSum: Decimal?
    private var priceValue: String?

    init(asset: String, assetType: String?) {
        self.asset = asset
        self.assetType = assetType
    }

    mutating func append(_ holding: AllocationRow) {
        if let amount = holding.amount, let decimal = Decimal(string: amount) {
            amountSum = (amountSum ?? 0) + decimal
        }
        if let usdValue = holding.usdValue, let decimal = Decimal(string: usdValue) {
            usdSum = (usdSum ?? 0) + decimal
        }
        if priceValue == nil, let price = holding.price, !price.isEmpty {
            priceValue = price
        }

        let sourceType = holding.sources.first ?? ""
        sources.append(SourceAllocation(source: sourceType, sourceName: holding.sourceName, amount: holding.amount, usdValue: holding.usdValue))
    }

    func build(netWorth: Decimal?) -> AllocationGroupRow {
        let amount = amountSum.map { NSDecimalNumber(decimal: $0).stringValue }
        let usdValue = usdSum.map { NSDecimalNumber(decimal: $0).stringValue }
        let percentage: String?
        if let netWorth, netWorth > 0, let usdSum {
            let percent = (usdSum / netWorth) * 100
            percentage = NSDecimalNumber(decimal: percent).stringValue
        } else {
            percentage = nil
        }
        return AllocationGroupRow(
            asset: asset,
            assetType: assetType,
            sources: sources,
            amount: amount,
            usdValue: usdValue,
            price: priceValue,
            percentage: percentage
        )
    }
}

private struct SourceIconsPopover: View {
    let items: [SourceIconItem]
    @State private var presentedIndex: Int? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    if presentedIndex == index {
                        presentedIndex = nil
                    } else {
                        presentedIndex = nil
                        DispatchQueue.main.async {
                            presentedIndex = index
                        }
                    }
                } label: {
                    Image(item.iconName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                        .allocationGlassBackground(in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(index) * 18)
                .popover(isPresented: Binding(
                    get: { presentedIndex == index },
                    set: { isPresented in
                        presentedIndex = isPresented ? index : nil
                    }
                )) {
                    TooltipCard(text: item.tooltip)
                        .presentationBackground(.clear)
                }
            }
        }
        .frame(width: totalWidth, height: 24, alignment: .leading)
    }

    private var totalWidth: CGFloat {
        let count = max(items.count, 1)
        return 24 + CGFloat(count - 1) * 18
    }
}

private struct TooltipCard: View {
    let text: String

    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .font(.footnote)
            .foregroundStyle(.primary)
            .frame(maxWidth: 240, alignment: .leading)
            .padding(6)
            .allocationGlassBackground(in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension View {
    @ViewBuilder
    func allocationSurfaceBackground<S: Shape>(in shape: S) -> some View {
        self
            .glassEffect(.regular, in: shape)
    }

    @ViewBuilder
    func allocationGlassBackground<S: Shape>(in shape: S) -> some View {
        self
            .glassEffect(.regular, in: shape)
    }

    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    AllocationView()
        .environmentObject(AppState())
}
