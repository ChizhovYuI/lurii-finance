import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel
    @State private var allocationFilter = ""

    @MainActor init(viewModel: DashboardViewModel = DashboardViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CollectionProgressBar(isCollecting: appState.collecting, progress: appState.collectionProgress)
                    .frame(maxWidth: .infinity)

                if viewModel.isLoading {
                    ProgressView("Loading portfolio...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Dashboard unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load()
                    }
                } else {
                    warningsSection
                    statCards
                    allocationSection
                }
            }
            .padding(24)
        }
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionCompleted)) { _ in
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated)) { _ in
            viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Portfolio Overview")
                    .font(.title2)
                if let date = viewModel.summary?.date {
                    Text("As of \(date)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Spacer()

            Button("Collect") {
                Task {
                    _ = try? await APIClient.shared.startCollect(source: nil)
                    if let status = try? await APIClient.shared.getCollectStatus() {
                        appState.updateCollectStatus(status)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            switch appState.daemonStatus {
            case .connected(let version):
                SyncStatusBar(isConnected: true, version: version)
            case .disconnected:
                SyncStatusBar(isConnected: false, version: nil)
            case .unknown:
                SyncStatusBar(isConnected: false, version: nil)
            }
        }
    }

    private var statCards: some View {
        let netWorthCode = viewModel.summary?.netWorth?.keys.sorted().first ?? "usd"
        let netWorthValue = viewModel.summary?.netWorth?[netWorthCode]
        let netWorthText = ValueFormatters.currency(from: netWorthValue, code: netWorthCode) ?? "—"

        return LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Net Worth", value: netWorthText, subtitle: "Total")
                .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if let warnings = viewModel.summary?.warnings, !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Data Warnings")
                    .font(.headline)
                ForEach(warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(12)
            .background(DesignTokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var allocationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Allocation")
                    .font(.headline)
                Spacer()
                TextField("Filter by asset, source, type", text: $allocationFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }

            allocationHeader

            let filteredRows = filteredAllocationRows()
            if !filteredRows.isEmpty {
                ForEach(filteredRows) { row in
                    allocationRow(row)
                }
            } else {
                Text("No allocation data yet")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var allocationHeader: some View {
        HStack(spacing: 12) {
            headerCell("Asset")
            headerCell("Source")
            headerCell("Amount", alignment: .trailing)
            headerCell("Price", alignment: .trailing)
            headerCell("Value", alignment: .trailing)
            headerCell("% Of Net Value", alignment: .trailing)
            headerCell("Type", alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func allocationRow(_ row: AllocationGroupRow) -> some View {
        HStack(spacing: 12) {
            rowCell(row.asset)
            sourceCell(sources: row.sources, asset: row.asset)
            let amountText = ValueFormatters.number(from: row.amount) ?? row.amount ?? "—"
            rowCell(amountText, alignment: .trailing)
            let priceText = ValueFormatters.currency(from: row.price, code: "usd") ?? row.price ?? "—"
            rowCell(priceText, alignment: .trailing)
            let valueText = ValueFormatters.currency(from: row.usdValue, code: "usd") ?? row.usdValue ?? "—"
            rowCell(valueText, alignment: .trailing)
            let percentText = ValueFormatters.percentFromPercentValue(row.percentage) ?? row.percentage ?? "—"
            rowCell(percentText, alignment: .trailing)
            if let type = row.assetType {
                rowCell(type.uppercased(), alignment: .trailing)
            } else {
                rowCell("—", alignment: .trailing)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func sourceCell(sources: [SourceAllocation], asset: String) -> some View {
        let items: [SourceIconItem] = sources.compactMap { source in
            guard let iconName = sourceIconName(for: source.source) else { return nil }
            let valueText = ValueFormatters.currency(from: source.usdValue, code: "usd") ?? source.usdValue ?? "—"
            let amountText = source.amount ?? "—"
            let tooltip = "\(asset)\n\(amountText)\n\(valueText)"
            return SourceIconItem(iconName: iconName, tooltip: tooltip)
        }
        if items.isEmpty {
            rowCell(sourcesText(sources))
        } else {
            SourceIconsPopover(items: items)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourceIconName(for source: String) -> String? {
        switch source.lowercased() {
        case "okx":
            return "okx"
        case "binance":
            return "binance"
        case "binance_th":
            return "binance_th"
        case "bybit":
            return "bybit"
        case "lobstr":
            return "lobstr"
        case "wise":
            return "wise"
        case "kbank":
            return "kbank"
        case "ibkr":
            return "ibkr"
        case "blend":
            return "blend"
        default:
            return nil
        }
    }

    private func sourcesText(_ sources: [SourceAllocation]) -> String {
        let joined = sources.map { $0.source }.joined(separator: ", ")
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

    private func filteredAllocationRows() -> [AllocationGroupRow] {
        let rows = groupedAllocationRows()
        let tokens = allocationFilter
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else {
            return rows
        }

        return rows
            .map { row -> (AllocationGroupRow, Int) in
                let haystack = allocationHaystack(for: row)
                let score = tokens.reduce(0) { partial, token in
                    partial + tokenScore(token: token, haystack: haystack)
                }
                return (row, score)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.asset < rhs.0.asset
            }
            .map { $0.0 }
    }

    private func allocationHaystack(for row: AllocationGroupRow) -> [String] {
        var values: [String] = [row.asset.lowercased()]
        if !row.sources.isEmpty {
            values.append(contentsOf: row.sources.map { $0.source.lowercased() })
        }
        if let type = row.assetType?.lowercased(), !type.isEmpty {
            values.append(type)
        }
        return values
    }

    private func tokenScore(token: String, haystack: [String]) -> Int {
        var best = 0
        for value in haystack {
            if value.hasPrefix(token) {
                best = max(best, 3)
            } else if value.contains(token) {
                if value.hasSuffix(token) {
                    best = max(best, 1)
                } else {
                    best = max(best, 2)
                }
            }
        }
        return best
    }
    private func groupedAllocationRows() -> [AllocationGroupRow] {
        let holdings = viewModel.summary?.holdings ?? []
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
            .sorted { lhs, rhs in
                let left = Decimal(string: lhs.usdValue ?? "0") ?? 0
                let right = Decimal(string: rhs.usdValue ?? "0") ?? 0
                if left != right {
                    return left > right
                }
                return lhs.asset < rhs.asset
            }
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
}

@MainActor
private struct DashboardPreviewHost: View {
    var body: some View {
        let appState = AppState()
        let summary = PortfolioSummary(
            date: "2026-03-01",
            netWorth: ["usd": "71850.00"],
            holdings: [
                AllocationRow(
                    asset: "BTC",
                    sources: ["okx"],
                    amount: "0.5",
                    usdValue: "32500.00",
                    price: "65000.00",
                    percentage: nil,
                    assetType: "crypto"
                )
            ],
            warnings: [
                "No snapshot data for source: wise",
                "KBank statement is outdated (2026-02-01, 29 days old)"
            ]
        )
        let viewModel = DashboardViewModel()
        viewModel.summary = summary
        return DashboardView(viewModel: viewModel)
            .environmentObject(appState)
    }
}

#Preview {
    DashboardPreviewHost()
}

private struct SourceIconItem: Identifiable {
    let id = UUID()
    let iconName: String
    let tooltip: String
}

private struct SourceAllocation: Identifiable {
    var id: String { source }
    let source: String
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

        let sourceName = holding.sources.first ?? ""
        sources.append(SourceAllocation(source: sourceName, amount: holding.amount, usdValue: holding.usdValue))
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
                        .background(Circle().fill(Color.white))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

