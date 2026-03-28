import SwiftUI

struct EarnSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: EarnSummaryViewModel
    @State private var filter = ""
    @State private var overrideTarget: EarnPosition?
    @State private var expandedSections: Set<String> = []
    @Namespace private var earnNamespace

    @AppStorage("earn.groupBy") private var groupByRaw = GroupByMode.none.rawValue

    private var groupBy: GroupByMode {
        get { GroupByMode(rawValue: groupByRaw) ?? .none }
        set { groupByRaw = newValue.rawValue }
    }

    private let controlSize: CGFloat = 24

    @MainActor init(viewModel: EarnSummaryViewModel = EarnSummaryViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Earn")
                    .font(.title)
                    .foregroundStyle(.primary)

                content
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Earn")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                groupByPicker
            }
            if groupBy != .none {
                ToolbarItem(placement: .automatic) {
                    expandAllToggle
                }
            }
            ToolbarItem(placement: .automatic) {
                searchField
                    .frame(width: 200)
            }
        }
        .sheet(item: $overrideTarget) { position in
            EarnOverrideSheet(
                sourceName: position.sourceName ?? position.source,
                existingOverride: EarnOverrideDTO(
                    category: position.earnCategory ?? "",
                    coin: position.asset,
                    apr: position.apy.flatMap { apy in
                        guard let d = Decimal(string: apy), d > 0 else { return nil }
                        return "\(d * 100)"
                    },
                    settlementAt: position.settlementAt
                ),
                onSaved: { viewModel.load() }
            )
        }
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated)) { _ in
            viewModel.load()
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            if newValue == .earn {
                viewModel.load()
            }
        }
        .onChange(of: groupByRaw) { _, _ in
            expandedSections = []
        }
    }

    private var content: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading earn summary...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Earn unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else if let summary = viewModel.summary {
                VStack(alignment: .leading, spacing: 16) {
                    totals(summary)

                    if groupBy == .none {
                        positionsTable(summary)
                        idleAssetsTable(summary)
                    } else {
                        let sections = earnSections(summary)
                        if sections.isEmpty {
                            Text("No earn data")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sections) { section in
                                earnSectionBlock(section)
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(title: "No earn data", message: "Yield-bearing positions will appear here once available.")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $filter)
                .textFieldStyle(.plain)
                .font(.subheadline)

            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: controlSize)
        .glassEffect(.regular, in: Capsule())
        .glassEffectID("earn-search", in: earnNamespace)
    }

    private func totals(_ summary: EarnSummaryResponse) -> some View {
        let totalValue = appState.hideBalance
            ? "••••"
            : (ValueFormatters.currency(from: summary.totalUsdValue, code: "usd") ?? "—")
        let avgApy = appState.hideBalance
            ? "••••"
            : (ValueFormatters.percent(from: summary.weightedAvgApy) ?? summary.weightedAvgApy ?? "—")
        let dates = viewModel.history.map(\.date)
        let totalValueHistory = viewModel.history.compactMap { Double($0.totalUsdValue) }
        let weightedAvgApyHistory = viewModel.history.compactMap { Double($0.weightedAvgApy) }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            EarnSummaryMetricCard(
                title: "Total Value",
                value: totalValue,
                systemImage: "dollarsign.circle",
                graphValues: totalValueHistory,
                dates: dates
            )
            .frame(minHeight: 120)

            EarnSummaryMetricCard(
                title: "APY",
                value: avgApy,
                systemImage: "percent",
                graphValues: weightedAvgApyHistory,
                dates: dates,
                formatValue: { String(format: "%.2f%%", $0 * 100) }
            )
            .frame(minHeight: 120)
        }
    }

    private func positionsTable(_ summary: EarnSummaryResponse) -> some View {
        let sorted = summary.positions.sorted { lhs, rhs in
            let l = Decimal(string: lhs.apy ?? "0") ?? 0
            let r = Decimal(string: rhs.apy ?? "0") ?? 0
            return l > r
        }
        let localTokens = filter.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let globalTokens = appState.globalSearchQuery.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let filtered: [EarnPosition] = if localTokens.isEmpty && globalTokens.isEmpty {
            sorted
        } else {
            sorted.filter { position in
                let haystack = [position.asset.lowercased(), position.source.lowercased()]
                let localMatches = localTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
                let globalMatches = globalTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
                return localMatches && globalMatches
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Positions")
                .font(.headline)

            headerRow

            if filtered.isEmpty {
                Text("No yield-bearing positions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { position in
                    positionRow(position)
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

    @ViewBuilder
    private func idleAssetsTable(_ summary: EarnSummaryResponse) -> some View {
        let idle = summary.idleAssets ?? []
        if !idle.isEmpty {
            let localTokens = filter.lowercased()
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let globalTokens = appState.globalSearchQuery.lowercased()
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let filtered: [EarnPosition] = if localTokens.isEmpty && globalTokens.isEmpty {
                idle
            } else {
                idle.filter { position in
                    let haystack = [position.asset.lowercased(), position.source.lowercased()]
                    let localMatches = localTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
                    let globalMatches = globalTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
                    return localMatches && globalMatches
                }
            }
            let idleTotalText = appState.hideBalance
                ? "••••"
                : (ValueFormatters.currency(from: summary.idleTotalUsdValue, code: "usd") ?? "—")

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.warning)
                    Text("Idle Assets")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(idleTotalText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("Crypto and stablecoins not earning yield")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                idleHeaderRow

                if filtered.isEmpty {
                    Text("No matching idle assets")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { position in
                        idleRow(position)
                    }
                }
            }
            .padding(DesignTokens.blockPadding)
            .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .stroke(DesignTokens.warning.opacity(0.4))
            )
        }
    }

    private var idleHeaderRow: some View {
        HStack(spacing: 12) {
            headerCell("Asset")
            headerCell("Source")
            headerCell("Amount", alignment: .trailing)
            headerCell("Price", alignment: .trailing)
            headerCell("Value", alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func idleRow(_ position: EarnPosition) -> some View {
        let hidden = appState.hideBalance
        return HStack(spacing: 12) {
            rowCell(position.asset)
            sourceCell(position.source)
            let amountText = hidden ? "••••" : (ValueFormatters.number(from: position.amount) ?? position.amount ?? "—")
            rowCell(amountText, alignment: .trailing)
            let priceText = ValueFormatters.currency(from: position.price, code: "usd") ?? position.price ?? "—"
            rowCell(priceText, alignment: .trailing)
            let valueText = hidden ? "••••" : (ValueFormatters.currency(from: position.usdValue, code: "usd") ?? position.usdValue ?? "—")
            rowCell(valueText, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .font(.subheadline)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            headerCell("Asset")
            headerCell("Source")
            headerCell("Amount", alignment: .trailing)
            headerCell("Price", alignment: .trailing)
            headerCell("Value", alignment: .trailing)
            headerCell("APY", alignment: .trailing)
            headerCell("Settlement", alignment: .trailing)
            // Spacer for edit button column
            Text("").frame(width: 24)
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func positionRow(_ position: EarnPosition) -> some View {
        let hidden = appState.hideBalance
        return HStack(spacing: 12) {
            rowCell(position.asset)
            sourceCell(position.source)
            let amountText = hidden ? "••••" : (ValueFormatters.number(from: position.amount) ?? position.amount ?? "—")
            rowCell(amountText, alignment: .trailing)
            let priceText = ValueFormatters.currency(from: position.price, code: "usd") ?? position.price ?? "—"
            rowCell(priceText, alignment: .trailing)
            let valueText = hidden ? "••••" : (ValueFormatters.currency(from: position.usdValue, code: "usd") ?? position.usdValue ?? "—")
            rowCell(valueText, alignment: .trailing)
            let apyText = ValueFormatters.percent(from: position.apy) ?? position.apy ?? "—"
            rowCell(apyText, alignment: .trailing)
            rowCell(formatSettlement(position.settlementAt), alignment: .trailing)

            if position.earnCategory != nil {
                Button {
                    overrideTarget = position
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)
            } else {
                Text("").frame(width: 24)
            }
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .font(.subheadline)
    }

    private func formatSettlement(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    private func headerCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func rowCell(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private func sourceCell(_ source: String) -> some View {
        if let iconName = source.sourceIconName() {
            Image(iconName)
                .resizable()
                .scaledToFill()
                .frame(width: 24, height: 24)
                .clipShape(Circle())
                .glassEffect(.regular, in: Circle())
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            rowCell(source)
        }
    }

    // MARK: - Group By

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
        .glassEffect(.regular, in: Capsule())
        .glassEffectID("earn-group-by", in: earnNamespace)
    }

    private var expandAllToggle: some View {
        Toggle(
            isOn: Binding(
                get: { !expandedSections.isEmpty },
                set: { expand in
                    if expand {
                        if let summary = viewModel.summary {
                            expandedSections = Set(earnSections(summary).map(\.id))
                        }
                    } else {
                        expandedSections = []
                    }
                }
            )
        ) {
            Label("Expand all", systemImage: "rectangle.expand.vertical")
        }
    }

    private func filterPositions(_ positions: [EarnPosition]) -> [EarnPosition] {
        let localTokens = filter.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let globalTokens = appState.globalSearchQuery.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard !localTokens.isEmpty || !globalTokens.isEmpty else { return positions }

        return positions.filter { position in
            let haystack = [position.asset.lowercased(), position.source.lowercased()]
            let localMatches = localTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
            let globalMatches = globalTokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
            return localMatches && globalMatches
        }
    }

    private func earnSections(_ summary: EarnSummaryResponse) -> [EarnSection] {
        let allPositions = filterPositions(
            summary.positions.sorted { lhs, rhs in
                let l = Decimal(string: lhs.apy ?? "0") ?? 0
                let r = Decimal(string: rhs.apy ?? "0") ?? 0
                return l > r
            }
        )
        let allIdle = filterPositions(summary.idleAssets ?? [])

        let totalPortfolioValue: Decimal = {
            let posValue = allPositions.reduce(Decimal.zero) { $0 + (Decimal(string: $1.usdValue ?? "") ?? 0) }
            let idleValue = allIdle.reduce(Decimal.zero) { $0 + (Decimal(string: $1.usdValue ?? "") ?? 0) }
            return posValue + idleValue
        }()

        switch groupBy {
        case .none:
            return []

        case .source:
            var groups: [String: (positions: [EarnPosition], idle: [EarnPosition])] = [:]
            for p in allPositions {
                let key = p.sourceName ?? p.source
                groups[key, default: ([], [])].positions.append(p)
            }
            for p in allIdle {
                let key = p.sourceName ?? p.source
                groups[key, default: ([], [])].idle.append(p)
            }

            return groups.compactMap { key, items in
                guard !items.positions.isEmpty || !items.idle.isEmpty else { return nil }
                let total = (items.positions + items.idle).reduce(Decimal.zero) {
                    $0 + (Decimal(string: $1.usdValue ?? "") ?? 0)
                }
                let pct = totalPortfolioValue > 0 ? (total / totalPortfolioValue) * 100 : nil
                let sourceKey = items.positions.first?.source ?? items.idle.first?.source ?? key
                return EarnSection(
                    id: key,
                    title: key,
                    iconName: sourceKey.sourceIconName(),
                    iconIsSystemSymbol: false,
                    totalUsdValue: total,
                    percentage: pct,
                    positions: items.positions,
                    idleAssets: items.idle
                )
            }
            .sorted { $0.totalUsdValue > $1.totalUsdValue }

        case .type:
            var groups: [String: (positions: [EarnPosition], idle: [EarnPosition])] = [:]
            for p in allPositions {
                let key = normalizeType(p.assetType) ?? "other"
                groups[key, default: ([], [])].positions.append(p)
            }
            for p in allIdle {
                let key = normalizeType(p.assetType) ?? "other"
                groups[key, default: ([], [])].idle.append(p)
            }

            return groups.compactMap { key, items in
                guard !items.positions.isEmpty || !items.idle.isEmpty else { return nil }
                let total = (items.positions + items.idle).reduce(Decimal.zero) {
                    $0 + (Decimal(string: $1.usdValue ?? "") ?? 0)
                }
                let pct = totalPortfolioValue > 0 ? (total / totalPortfolioValue) * 100 : nil
                return EarnSection(
                    id: key,
                    title: typeTitle(for: key),
                    iconName: typeSymbol(for: key),
                    iconIsSystemSymbol: true,
                    totalUsdValue: total,
                    percentage: pct,
                    positions: items.positions,
                    idleAssets: items.idle
                )
            }
            .sorted { $0.totalUsdValue > $1.totalUsdValue }
        }
    }

    private func earnSectionBlock(_ section: EarnSection) -> some View {
        let expanded = expandedSections.contains(section.id)
        return VStack(alignment: .leading, spacing: 12) {
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

                if !section.positions.isEmpty {
                    headerRow

                    ForEach(section.positions) { position in
                        positionRow(position)
                    }
                }

                if !section.idleAssets.isEmpty {
                    if !section.positions.isEmpty {
                        Divider()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.warning)
                        Text("Idle")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)

                    idleHeaderRow

                    ForEach(section.idleAssets) { position in
                        idleRow(position)
                    }
                }

                if section.positions.isEmpty && section.idleAssets.isEmpty {
                    Text("No positions")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
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

    // MARK: - Type Helpers

    private func normalizeType(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func typeSymbol(for rawType: String?) -> String {
        switch normalizeType(rawType) {
        case "crypto": "bitcoinsign.circle"
        case "defi": "link.circle"
        case "fiat": "banknote"
        case "stocks": "chart.line.uptrend.xyaxis"
        case "deposit": "building.columns.circle"
        default: "questionmark.circle"
        }
    }

    private func typeTitle(for rawType: String?) -> String {
        switch normalizeType(rawType) {
        case "crypto": "Crypto"
        case "defi": "DeFi"
        case "fiat": "Fiat"
        case "stocks": "Stocks"
        case "deposit": "Deposit"
        default: "Other"
        }
    }
}

private struct EarnSection: Identifiable {
    let id: String
    let title: String
    let iconName: String?
    let iconIsSystemSymbol: Bool
    let totalUsdValue: Decimal
    let percentage: Decimal?
    let positions: [EarnPosition]
    let idleAssets: [EarnPosition]
}

private struct EarnSummaryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let graphValues: [Double]
    var dates: [String] = []
    var formatValue: ((Double) -> String)?

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(title)
                        .font(DesignTokens.captionFont)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(value)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 118, alignment: .leading)

            if graphValues.count > 1 {
                EarnSummarySparkline(values: graphValues, dates: dates, formatValue: formatValue)
                    .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(DesignTokens.blockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }
}

private struct EarnSummarySparkline: View {
    let values: [Double]
    var dates: [String] = []
    var formatValue: ((Double) -> String)?

    @State private var hoverIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let sparkline = EarnSparklineMetrics(values: values, size: geometry.size)
            let pts = sparkline.points

            ZStack(alignment: .topLeading) {
                sparkline.areaPath
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.18),
                                Color.accentColor.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                sparkline.linePath
                    .stroke(
                        Color.accentColor.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                if let idx = hoverIndex, idx < pts.count, idx < values.count {
                    let pt = pts[idx]

                    Path { path in
                        path.move(to: CGPoint(x: pt.x, y: 0))
                        path.addLine(to: CGPoint(x: pt.x, y: geometry.size.height))
                    }
                    .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .position(pt)

                    let valStr = formatValue?(values[idx]) ?? String(format: "%.2f", values[idx])
                    let dateStr: String? = idx < dates.count ? dates[idx] : nil
                    let isRightHalf = pt.x > geometry.size.width / 2

                    VStack(alignment: isRightHalf ? .trailing : .leading, spacing: 1) {
                        if let dateStr {
                            Text(dateStr)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Text(valStr)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(
                        x: isRightHalf ? pt.x - 44 : pt.x + 44,
                        y: max(16, min(pt.y, geometry.size.height - 16))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverIndex = sparkline.nearestIndex(for: location.x)
                case .ended:
                    hoverIndex = nil
                @unknown default:
                    hoverIndex = nil
                }
            }
        }
    }
}

private struct EarnSparklineMetrics {
    let values: [Double]
    let size: CGSize

    private let horizontalInset: CGFloat = 2
    private let verticalInset: CGFloat = 4

    private var chartMinValue: Double {
        min(values.min() ?? 0, 0)
    }

    private var chartMaxValue: Double {
        max(values.max() ?? 0, 0)
    }

    private var baselineY: CGFloat {
        yPosition(for: 0)
    }

    private func yPosition(for value: Double) -> CGFloat {
        let range = chartMaxValue - chartMinValue
        let usableHeight = max(size.height - (verticalInset * 2), 1)
        let baseline = size.height - verticalInset

        let normalizedY: CGFloat
        if range <= 0 {
            normalizedY = verticalInset + (usableHeight * 0.5)
        } else {
            normalizedY = verticalInset + (usableHeight * CGFloat((chartMaxValue - value) / range))
        }

        return min(max(normalizedY, verticalInset), baseline)
    }

    var points: [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }

        let usableWidth = max(size.width - (horizontalInset * 2), 1)

        return values.enumerated().map { index, value in
            let progress = values.count == 1 ? 0 : CGFloat(index) / CGFloat(values.count - 1)
            let x = horizontalInset + (usableWidth * progress)
            return CGPoint(x: x, y: yPosition(for: value))
        }
    }

    func nearestIndex(for x: CGFloat) -> Int? {
        let pts = points
        guard !pts.isEmpty else { return nil }
        var bestIndex = 0
        var bestDist = abs(pts[0].x - x)
        for i in 1..<pts.count {
            let dist = abs(pts[i].x - x)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }
        return bestIndex
    }

    var linePath: Path {
        Path { path in
            guard let firstPoint = points.first else { return }
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    var areaPath: Path {
        Path { path in
            guard let firstPoint = points.first, let lastPoint = points.last else { return }

            path.move(to: CGPoint(x: firstPoint.x, y: baselineY))
            path.addLine(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: lastPoint.x, y: baselineY))
            path.closeSubpath()
        }
    }
}

@MainActor
private struct EarnPreviewHost: View {
    private var previewHistory: [EarnHistoryPoint] {
        let values: [(String, String)] = [
            ("15200", "0.061"), ("15480", "0.062"), ("15360", "0.0615"), ("15620", "0.063"), ("15850", "0.064"),
            ("16010", "0.0645"), ("16180", "0.065"), ("16320", "0.0655"), ("16240", "0.065"), ("16410", "0.066"),
            ("16560", "0.0665"), ("16680", "0.067"), ("16820", "0.0675"), ("16910", "0.068"), ("17020", "0.0685"),
            ("17140", "0.069"), ("17210", "0.0695"), ("17300", "0.07"), ("17420", "0.0705"), ("17510", "0.071"),
            ("17680", "0.0715"), ("17720", "0.071"), ("17810", "0.0718"), ("17960", "0.072"), ("18040", "0.0722"),
            ("18120", "0.0725"), ("18210", "0.0728"), ("18360", "0.073"), ("18410", "0.0727"), ("18420", "0.0725")
        ]
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))

        return values.enumerated().compactMap { index, value in
            guard let startDate, let pointDate = calendar.date(byAdding: .day, value: index, to: startDate) else {
                return nil
            }
            return EarnHistoryPoint(
                date: formatter.string(from: pointDate),
                totalUsdValue: value.0,
                weightedAvgApy: value.1
            )
        }
    }

    var body: some View {
        let appState = AppState()
        let viewModel = EarnSummaryViewModel()
        viewModel.summary = EarnSummaryResponse(
            date: "2026-03-01",
            totalUsdValue: "18420.00",
            weightedAvgApy: "0.0725",
            positions: [
                EarnPosition(
                    id: 1,
                    source: "Aave",
                    asset: "USDC",
                    assetType: "defi",
                    amount: "12000.00",
                    usdValue: "12000.00",
                    price: "1.00",
                    apy: "0.081"
                ),
                EarnPosition(
                    id: 2,
                    source: "bybit",
                    sourceName: "bybit-main",
                    asset: "USDT",
                    assetType: "crypto",
                    amount: "1053.63",
                    usdValue: "1053.63",
                    price: "1.00",
                    apy: "1.7936",
                    settlementAt: "2026-03-28T07:59:00Z",
                    earnCategory: "Dual Asset"
                )
            ],
            idleAssets: [
                EarnPosition(
                    id: 3,
                    source: "okx",
                    asset: "BTC",
                    assetType: "crypto",
                    amount: "0.5",
                    usdValue: "32500.00",
                    price: "65000.00",
                    apy: "0"
                ),
                EarnPosition(
                    id: 4,
                    source: "bybit",
                    asset: "ETH",
                    assetType: "crypto",
                    amount: "2.2",
                    usdValue: "6420.00",
                    price: "2918.18",
                    apy: "0"
                )
            ],
            idleTotalUsdValue: "37700.00"
        )
        viewModel.history = previewHistory

        return EarnSummaryView(viewModel: viewModel)
            .environmentObject(appState)
    }
}

#Preview {
    EarnPreviewHost()
}
