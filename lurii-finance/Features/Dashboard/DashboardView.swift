import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    @AppStorage("dashboard.selectedDateRange") private var selectedDateRangeRaw = DashboardDateRange.oneMonth.rawValue

    @MainActor init(viewModel: DashboardViewModel = DashboardViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var selectedDateRange: DashboardDateRange {
        get { DashboardDateRange(rawValue: selectedDateRangeRaw) ?? .oneMonth }
        set { selectedDateRangeRaw = newValue.rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dashboard")
                    .font(.title)
                    .foregroundStyle(.primary)

                if appState.collecting {
                    CollectionProgressBar(isCollecting: true, progress: appState.collectionProgress, message: appState.collectionMessage)
                        .frame(maxWidth: .infinity)
                }

                if appState.valuing && !appState.collecting {
                    ValuationIndicator(progress: appState.valuationProgress, message: appState.valuationMessage)
                        .frame(maxWidth: .infinity)
                }

                if viewModel.isLoading {
                    ProgressView("Loading portfolio...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Dashboard unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load(range: selectedDateRange)
                    }
                } else {
                    dashboardCards
                }
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                dateRangePicker
            }
        }
        .onAppear {
            guard !isPreview else { return }
            viewModel.load(range: selectedDateRange)
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionCompleted)) { _ in
            viewModel.load(range: selectedDateRange)
        }
        .onReceive(NotificationCenter.default.publisher(for: .valuationCompleted)) { _ in
            viewModel.load(range: selectedDateRange)
        }
        .onReceive(NotificationCenter.default.publisher(for: .snapshotUpdated)) { _ in
            viewModel.load(range: selectedDateRange)
        }
        .onChange(of: selectedDateRangeRaw) { _, _ in
            guard !isPreview else { return }
            viewModel.load(range: selectedDateRange)
        }
        .onChange(of: appState.selectedSection) { _, newValue in
            guard !isPreview, newValue == .dashboard else { return }
            viewModel.load(range: selectedDateRange)
        }
    }

    private var dashboardCards: some View {
        let netWorthCode = viewModel.summary?.netWorth?.keys.sorted().first ?? "usd"
        let netWorthValue = viewModel.summary?.netWorth?[netWorthCode]
        let netWorthText = ValueFormatters.currency(from: netWorthValue, code: netWorthCode) ?? "—"

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], spacing: 12) {
            DashboardNetWorthCard(value: netWorthText, history: viewModel.netWorthHistory, range: selectedDateRange)
                .frame(minHeight: 174)
            DashboardPnlCard(pnl: viewModel.pnl, range: selectedDateRange)
                .frame(minHeight: 174)
            DashboardAllocationSnapshotCard(allocation: viewModel.allocation)
                .frame(minHeight: 174)
            DashboardSourceMoversCard(sourceMovers: viewModel.sourceMovers)
                .frame(minHeight: 174)
            DashboardYieldSnapshotCard(summary: viewModel.earnSummary)
                .frame(minHeight: 174)
            DashboardIdleAssetsCard(summary: viewModel.earnSummary)
                .frame(minHeight: 174)
            DashboardRiskHealthCard(
                allocation: viewModel.allocation,
                warnings: dashboardWarnings
            )
            .frame(minHeight: 174)
            DashboardTransactionCard(analytics: viewModel.txAnalytics)
                .frame(minHeight: 174)
            DashboardTrendsCard(trends: viewModel.trendPoints, granularity: "month")
                .frame(minHeight: 220)
            DashboardSpendByCategoryCard(analytics: viewModel.txAnalytics)
                .frame(minHeight: 220)
            DashboardStatementDropCard()
                .frame(minHeight: 174)
        }
    }

    private var dashboardWarnings: [String] {
        let combined = (viewModel.summary?.warnings ?? []) + (viewModel.allocation?.warnings ?? [])
        var seen = Set<String>()
        return combined.filter { warning in
            seen.insert(warning).inserted
        }
    }

    private var dateRangePicker: some View {
        Picker("", selection: $selectedDateRangeRaw) {
            ForEach(DashboardDateRange.allCases) { range in
                Text(range.rawValue)
                    .tag(range.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Dashboard date range")
    }
}

@MainActor
private struct DashboardPreviewHost: View {
    private var previewHistory: [NetWorthHistoryPoint] {
        let values: [String] = [
            "68200", "68450", "68120", "68900", "69150", "69500", "69840", "70120", "69980", "70310",
            "70650", "70820", "71140", "70990", "71330", "71520", "71780", "71910", "72150", "72340",
            "72480", "72610", "72890", "73120", "73380", "73640", "73920", "74260", "71500", "71850"
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
            return NetWorthHistoryPoint(
                date: formatter.string(from: pointDate),
                usdValue: value
            )
        }
    }

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
                "Source not synced today: ibkr (latest 2026-02-28)",
                "Source not synced today: blend usd (latest 2026-02-27)",
                "Source not synced today: cash (latest 2026-02-26)",
                "KBank statement is outdated: kbank (2026-02-01, 29 days old)"
            ]
        )
        let viewModel = DashboardViewModel()
        viewModel.summary = summary
        viewModel.netWorthHistory = previewHistory
        viewModel.pnl = PnlResponse(
            date: "2026-03-01",
            period: "1m",
            pnl: PnlResult(
                startDate: "2026-01-31",
                endDate: "2026-03-01",
                startValue: "68200.00",
                endValue: "71850.00",
                absoluteChange: "3650.00",
                percentageChange: "5.35",
                byAsset: [],
                topGainers: [
                    PnlAssetRow(
                        asset: "BTC",
                        startValue: "29500.00",
                        endValue: "32500.00",
                        absoluteChange: "3000.00",
                        percentageChange: "10.17",
                        costBasisValue: nil
                    )
                ],
                topLosers: [],
                notes: []
            )
        )
        viewModel.allocation = AllocationResponse(
            date: "2026-03-01",
            byAsset: [
                AllocationRow(
                    asset: "BTC",
                    sources: ["okx"],
                    amount: "0.5",
                    usdValue: "32500.00",
                    price: "65000.00",
                    percentage: "45.24",
                    assetType: "crypto"
                ),
                AllocationRow(
                    asset: "ETH",
                    sources: ["bybit"],
                    amount: "4.2",
                    usdValue: "11800.00",
                    price: "2809.52",
                    percentage: "16.42",
                    assetType: "crypto"
                )
            ],
            bySource: [],
            byCategory: [
                ["category": "crypto", "usd_value": "47200.00", "percentage": "65.69"],
                ["category": "fiat", "usd_value": "16350.00", "percentage": "22.76"],
                ["category": "stocks", "usd_value": "8300.00", "percentage": "11.55"]
            ],
            riskMetrics: RiskMetrics(
                concentrationPercentage: "45.24",
                hhiIndex: "2486.20",
                top5Assets: [
                    TopAssetRow(
                        asset: "BTC",
                        source: nil,
                        usdValue: "32500.00",
                        price: "65000.00",
                        percentage: "45.24"
                    )
                ]
            ),
            warnings: [
                "Source not synced today: ibkr (latest 2026-02-28)",
                "Source not synced today: blend usd (latest 2026-02-27)",
                "Source not synced today: cash (latest 2026-02-26)",
                "KBank statement is outdated: kbank (2026-02-01, 29 days old)"
            ]
        )
        viewModel.sourceMovers = SourceMoversResponse(
            date: "2026-03-01",
            previousDate: "2026-02-28",
            gainers: [
                SourceMoverRow(
                    source: "okx",
                    absoluteChange: "2400.00",
                    currentUsdValue: "32500.00",
                    previousUsdValue: "30100.00"
                ),
                SourceMoverRow(
                    source: "trading212",
                    absoluteChange: "780.00",
                    currentUsdValue: "8300.00",
                    previousUsdValue: "7520.00"
                )
            ],
            reducers: [
                SourceMoverRow(
                    source: "wise",
                    absoluteChange: "-920.00",
                    currentUsdValue: "7800.00",
                    previousUsdValue: "8720.00"
                ),
                SourceMoverRow(
                    source: "bybit",
                    absoluteChange: "-540.00",
                    currentUsdValue: "11800.00",
                    previousUsdValue: "12340.00"
                )
            ]
        )
        viewModel.earnSummary = EarnSummaryResponse(
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
                    source: "Binance",
                    asset: "ETH",
                    assetType: "crypto",
                    amount: "2.2",
                    usdValue: "6420.00",
                    price: "2918.18",
                    apy: "0.058"
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
                    asset: "USDT",
                    assetType: "crypto",
                    amount: "5200.00",
                    usdValue: "5200.00",
                    price: "1.00",
                    apy: "0"
                )
            ],
            idleTotalUsdValue: "37700.00"
        )
        return DashboardView(viewModel: viewModel)
            .environmentObject(appState)
    }
}

#Preview {
    DashboardPreviewHost()
}

private struct DashboardNetWorthCard: View {
    @EnvironmentObject private var appState: AppState

    let value: String
    let history: [NetWorthHistoryPoint]
    let range: DashboardDateRange

    var body: some View {
        DashboardCardShell {
            DashboardCardHeader(title: "Net Worth", systemImage: "wallet.bifold")

            Text(appState.hideBalance ? "••••" : value)
                .font(DesignTokens.titleFont)
                .foregroundStyle(.primary)

            if history.count > 1 {
                DashboardNetWorthSparkline(history: history)
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
                    .accessibilityHidden(true)
            } else {
                DashboardUnavailableMessage("Trend is not available for the \(range.rawValue) range yet.")
            }
        }
    }
}

private struct DashboardPnlCard: View {
    @EnvironmentObject private var appState: AppState

    let pnl: PnlResponse?
    let range: DashboardDateRange

    private var absoluteChange: Decimal? {
        guard let pnl else { return nil }
        return Decimal(string: pnl.pnl.absoluteChange)
    }

    private var tone: DashboardMetricTone {
        guard let absoluteChange else { return .unavailable }
        if absoluteChange > 0 { return .positive }
        if absoluteChange < 0 { return .negative }
        return .neutral
    }

    private var absoluteText: String {
        ValueFormatters.currency(from: pnl?.pnl.absoluteChange, code: "usd") ?? "—"
    }

    private var percentageText: String {
        ValueFormatters.percentFromPercentValue(pnl?.pnl.percentageChange) ?? "—"
    }

    var body: some View {
        DashboardCardShell {
            HStack(alignment: .top, spacing: 12) {
                DashboardCardHeader(title: range.pnlTitle, systemImage: "chart.line.uptrend.xyaxis")
                Spacer(minLength: 0)
                DashboardStatusBadge(
                    title: tone.label,
                    systemImage: tone.systemImage,
                    tint: tone.color
                )
            }

            if pnl == nil {
                DashboardUnavailableMessage("Performance data is not available yet.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.hideBalance ? "••••" : absoluteText)
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(tone.color)

                    Text(appState.hideBalance ? "••••" : percentageText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.color.opacity(0.9))

                    Text(range.pnlSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct DashboardAllocationSnapshotCard: View {
    @EnvironmentObject private var appState: AppState

    let allocation: AllocationResponse?

    private var categories: [DashboardCategorySnapshot] {
        (allocation?.byCategory ?? []).prefix(3).compactMap { row in
            guard let name = row["category"], !name.isEmpty else { return nil }
            return DashboardCategorySnapshot(
                name: name.replacingOccurrences(of: "_", with: " ").capitalized,
                percentage: row["percentage"]
            )
        }
    }

    var body: some View {
        Button {
            appState.selectedSection = .allocation
        } label: {
            DashboardCardShell {
                HStack(alignment: .top, spacing: 12) {
                    DashboardCardHeader(title: "Allocation Snapshot", systemImage: "chart.pie")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !categories.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categories) { category in
                            DashboardCategoryBar(
                                title: category.name,
                                percentage: category.percentage,
                                isMasked: appState.hideBalance
                            )
                        }
                    }
                } else {
                    DashboardUnavailableMessage("Allocation data is not available yet.")
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardSourceMoversCard: View {
    @EnvironmentObject private var appState: AppState

    let sourceMovers: SourceMoversResponse?

    var body: some View {
        DashboardCardShell {
            DashboardCardHeader(title: "1D Source Movers", systemImage: "arrow.left.arrow.right.circle")

            if let sourceMovers, sourceMovers.previousDate != nil {
                VStack(alignment: .leading, spacing: 10) {
                    DashboardSourceMoverSection(
                        title: "Growing",
                        rows: sourceMovers.gainers,
                        isMasked: appState.hideBalance,
                        tint: DesignTokens.success
                    )
                    DashboardSourceMoverSection(
                        title: "Reducing",
                        rows: sourceMovers.reducers,
                        isMasked: appState.hideBalance,
                        tint: DesignTokens.error
                    )
                }
            } else {
                DashboardUnavailableMessage("Day-over-day source changes are not available yet.")
            }
        }
    }
}

private struct DashboardYieldSnapshotCard: View {
    @EnvironmentObject private var appState: AppState

    let summary: EarnSummaryResponse?

    private var totalValueText: String {
        ValueFormatters.currency(from: summary?.totalUsdValue, code: "usd") ?? "—"
    }

    private var apyText: String {
        ValueFormatters.percent(from: summary?.weightedAvgApy) ?? "—"
    }

    var body: some View {
        Button {
            appState.selectedSection = .earn
        } label: {
            DashboardCardShell {
                HStack(alignment: .top, spacing: 12) {
                    DashboardCardHeader(title: "Yield Snapshot", systemImage: "percent")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if summary == nil {
                    DashboardUnavailableMessage("Yield data is not available yet.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.hideBalance ? "••••" : totalValueText)
                            .font(DesignTokens.titleFont)
                            .foregroundStyle(.primary)

                        Text(appState.hideBalance ? "••••" : apyText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.success)

                        Text("Weighted average APY across yield positions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardIdleAssetsCard: View {
    @EnvironmentObject private var appState: AppState

    let summary: EarnSummaryResponse?

    private var idleCount: Int {
        summary?.idleAssets?.count ?? 0
    }

    private var idleTotalText: String {
        ValueFormatters.currency(from: summary?.idleTotalUsdValue, code: "usd") ?? "—"
    }

    private var topIdleAssets: [EarnPosition] {
        Array((summary?.idleAssets ?? []).prefix(3))
    }

    var body: some View {
        Button {
            appState.selectedSection = .earn
        } label: {
            DashboardCardShell {
                HStack(alignment: .top, spacing: 12) {
                    DashboardCardHeader(title: "Idle Assets", systemImage: "exclamationmark.triangle")
                    Spacer(minLength: 0)
                    if idleCount > 0 {
                        DashboardStatusBadge(
                            title: "\(idleCount) idle",
                            systemImage: "moon.zzz",
                            tint: DesignTokens.warning
                        )
                    }
                }

                if idleCount == 0 {
                    DashboardUnavailableMessage("All crypto and stablecoins are earning yield.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appState.hideBalance ? "••••" : idleTotalText)
                            .font(DesignTokens.titleFont)
                            .foregroundStyle(.primary)

                        Text("Crypto not earning yield")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(topIdleAssets) { asset in
                                HStack {
                                    Text(asset.asset)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(appState.hideBalance ? "••••" : (ValueFormatters.currency(from: asset.usdValue, code: "usd") ?? asset.usdValue ?? "—"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if idleCount > 3 {
                                Text("and \(idleCount - 3) more...")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardRiskHealthCard: View {
    @EnvironmentObject private var appState: AppState

    let allocation: AllocationResponse?
    let warnings: [String]

    private var concentrationPercentage: String? {
        allocation?.riskMetrics?.concentrationPercentage ?? allocation?.byAsset.first?.percentage
    }

    private var concentrationText: String {
        ValueFormatters.percentFromPercentValue(concentrationPercentage) ?? "—"
    }

    private var topAssetName: String {
        allocation?.riskMetrics?.top5Assets?.first?.asset ?? allocation?.byAsset.first?.asset ?? "—"
    }

    private var hasDataContext: Bool {
        allocation != nil || !warnings.isEmpty
    }

    private var unsyncedSourceNames: [String] {
        var seen = Set<String>()
        return warnings.compactMap(parseUnsyncedSourceName).filter { sourceName in
            seen.insert(sourceName).inserted
        }
    }

    private var kbankWarningText: String? {
        warnings.first(where: { $0.hasPrefix("KBank statement is outdated") })
    }

    private var unsyncedSourcesText: String {
        guard !unsyncedSourceNames.isEmpty else { return "All enabled sources synced today" }
        if unsyncedSourceNames.count == 1 {
            return "Not synced today: \(unsyncedSourceNames[0])"
        }
        if unsyncedSourceNames.count == 2 {
            return "Not synced today: \(unsyncedSourceNames[0]), \(unsyncedSourceNames[1])"
        }
        return "Not synced today: \(unsyncedSourceNames[0]), \(unsyncedSourceNames[1]) and \(unsyncedSourceNames.count - 2) more"
    }

    private var statusTitle: String {
        if !hasDataContext {
            return "Limited"
        }
        return hasHealthIssues ? "Stale" : "Fresh"
    }

    private var statusImage: String {
        if !hasDataContext {
            return "questionmark.circle.fill"
        }
        return hasHealthIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if !hasDataContext {
            return .secondary
        }
        return hasHealthIssues ? DesignTokens.warning : DesignTokens.success
    }

    private var sourceHealthTint: Color {
        if !hasDataContext {
            return .secondary
        }
        return unsyncedSourceNames.isEmpty ? DesignTokens.success : DesignTokens.warning
    }

    private var sourceHealthIcon: String {
        if !hasDataContext {
            return "questionmark.circle"
        }
        return unsyncedSourceNames.isEmpty ? "clock.badge.checkmark" : "clock.arrow.circlepath"
    }

    private var kbankWarningDisplayText: String? {
        guard let kbankWarningText else { return nil }
        if let details = kbankWarningText.split(separator: ":", maxSplits: 1).last {
            return "KBank outdated:\(details)"
        }
        return kbankWarningText
    }

    private var hasHealthIssues: Bool {
        !unsyncedSourceNames.isEmpty || kbankWarningText != nil
    }

    private func parseUnsyncedSourceName(from warning: String) -> String? {
        if warning.hasPrefix("Source not synced today: ") {
            let rawName = String(warning.dropFirst("Source not synced today: ".count))
            return rawName.components(separatedBy: " (latest ").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if warning.hasPrefix("No snapshot data for source: ") {
            return String(warning.dropFirst("No snapshot data for source: ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private var sourceHealthText: String {
        if !hasDataContext {
            return "Risk metrics unavailable"
        }
        return unsyncedSourcesText
    }

    var body: some View {
        DashboardCardShell {
            HStack(alignment: .top, spacing: 12) {
                DashboardCardHeader(title: "Risk & Data Health", systemImage: "shield.lefthalf.filled")
                Spacer(minLength: 0)
                DashboardStatusBadge(
                    title: statusTitle,
                    systemImage: statusImage,
                    tint: statusTint
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(appState.hideBalance ? "••••" : concentrationText)
                    .font(DesignTokens.titleFont)
                    .foregroundStyle(.primary)

                Text("Largest position: \(topAssetName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    if unsyncedSourceNames.isEmpty {
                        DashboardStatusBadge(
                            title: sourceHealthText,
                            systemImage: sourceHealthIcon,
                            tint: sourceHealthTint
                        )
                    } else {
                        DashboardWarningLine(
                            title: sourceHealthText,
                            systemImage: sourceHealthIcon,
                            tint: sourceHealthTint
                        )
                    }

                    if let kbankWarningDisplayText {
                        DashboardWarningLine(
                            title: kbankWarningDisplayText,
                            systemImage: "building.columns.circle",
                            tint: DesignTokens.warning
                        )
                    }
                }
            }
        }
    }
}

private struct DashboardCardShell<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(DesignTokens.blockPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }
}

private struct DashboardCardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DashboardStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct DashboardUnavailableMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardWarningLine: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
    }
}

private struct DashboardCategorySnapshot: Identifiable {
    let name: String
    let percentage: String?

    var id: String { name }

    var percentageText: String {
        ValueFormatters.percentFromPercentValue(percentage) ?? "—"
    }

    var progress: Double {
        guard let percentage, let value = Double(percentage) else { return 0 }
        return min(max(value / 100, 0), 1)
    }
}

private struct DashboardCategoryBar: View {
    let title: String
    let percentage: String?
    let isMasked: Bool

    private var progress: Double {
        guard let percentage, let value = Double(percentage) else { return 0 }
        return min(max(value / 100, 0), 1)
    }

    private var percentageText: String {
        ValueFormatters.percentFromPercentValue(percentage) ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(isMasked ? "••••" : percentageText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                let fullWidth = geometry.size.width
                let fillWidth = max(fullWidth * progress, progress > 0 ? 18 : 0)

                Capsule()
                    .fill(DesignTokens.cardBackground)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.72))
                            .frame(width: min(fillWidth, fullWidth))
                    }
            }
            .frame(height: 7)
        }
    }
}

private struct DashboardSourceMoverSection: View {
    let title: String
    let rows: [SourceMoverRow]
    let isMasked: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    DashboardSourceMoverRowView(row: row, isMasked: isMasked, tint: tint)
                }
            }
        }
    }
}

private struct DashboardSourceMoverRowView: View {
    let row: SourceMoverRow
    let isMasked: Bool
    let tint: Color

    private var amountText: String {
        guard !isMasked else { return "••••" }
        return ValueFormatters.currency(from: row.absoluteChange, code: "usd") ?? "—"
    }

    private var displayName: String {
        row.source
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 10) {
            sourceIcon

            Text(displayName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(amountText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let iconName = row.source.sourceIconName() {
            Image(iconName)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 22)
                .clipShape(Circle())
        } else {
            Image(systemName: "building.columns")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(DesignTokens.cardBackground, in: Circle())
        }
    }
}

private enum DashboardMetricTone {
    case positive
    case negative
    case neutral
    case unavailable

    var color: Color {
        switch self {
        case .positive:
            return DesignTokens.success
        case .negative:
            return DesignTokens.error
        case .neutral, .unavailable:
            return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .positive:
            return "arrow.up.right"
        case .negative:
            return "arrow.down.right"
        case .neutral:
            return "minus"
        case .unavailable:
            return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .positive:
            return "Positive"
        case .negative:
            return "Negative"
        case .neutral:
            return "Flat"
        case .unavailable:
            return "Unavailable"
        }
    }
}

private struct DashboardTransactionCard: View {
    @EnvironmentObject private var appState: AppState

    let analytics: TransactionAnalyticsSummary?

    private var topSpending: [CategoryBreakdownRow] {
        Array((analytics?.spendingByCategory ?? []).prefix(3))
    }

    private var totalSpendingText: String {
        ValueFormatters.currency(from: analytics?.totalSpending, code: "usd") ?? "—"
    }

    private var totalIncomeText: String {
        ValueFormatters.currency(from: analytics?.totalIncome, code: "usd") ?? "—"
    }

    var body: some View {
        Button {
            appState.selectedSection = .transactions
        } label: {
            DashboardCardShell {
                HStack(alignment: .top, spacing: 12) {
                    DashboardCardHeader(title: "Transactions", systemImage: "list.bullet.rectangle")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if analytics == nil {
                    DashboardUnavailableMessage("Transaction analytics are not available yet. Run categorization first.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spending")
                                    .font(DesignTokens.captionFont)
                                    .foregroundStyle(.secondary)
                                Text(appState.hideBalance ? "••••" : totalSpendingText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.error)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Income")
                                    .font(DesignTokens.captionFont)
                                    .foregroundStyle(.secondary)
                                Text(appState.hideBalance ? "••••" : totalIncomeText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.success)
                            }
                        }

                        if !topSpending.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Top expenses")
                                    .font(DesignTokens.captionFont)
                                    .foregroundStyle(.secondary)
                                ForEach(topSpending) { row in
                                    HStack {
                                        Text(row.displayName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        Text(appState.hideBalance ? "••••" : (ValueFormatters.currency(from: row.usdValue, code: "usd") ?? row.usdValue))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private func formatTrendLabel(_ key: String, granularity: String) -> String {
    if granularity == "month" {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        guard let date = fmt.date(from: key) else { return key }
        let display = DateFormatter()
        display.dateFormat = "MMM"
        return display.string(from: date)
    }
    // day or week: "2026-03-14" → "Mar 14"
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let date = fmt.date(from: String(key.prefix(10))) else { return key }
    let display = DateFormatter()
    display.dateFormat = "MMM d"
    return display.string(from: date)
}

private struct DashboardTrendsCard: View {
    @EnvironmentObject private var appState: AppState

    let trends: [TrendPoint]
    let granularity: String

    @State private var hoverIndex: Int?

    private var maxValue: Double {
        let s = trends.compactMap { Double($0.spending) }.max() ?? 0
        let i = trends.compactMap { Double($0.income) }.max() ?? 0
        return max(s, i, 1)
    }

    var body: some View {
        DashboardCardShell {
            DashboardCardHeader(title: "Income & Spending", systemImage: "chart.bar")

            if trends.count < 2 {
                DashboardUnavailableMessage("Not enough data for chart.")
            } else {
                GeometryReader { geometry in
                    let barGroupWidth = geometry.size.width / CGFloat(trends.count)
                    let barWidth = max((barGroupWidth - 8) / 2, 4)
                    let chartHeight = geometry.size.height

                    ZStack(alignment: .bottom) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(Array(trends.enumerated()), id: \.offset) { index, point in
                                let spending = Double(point.spending) ?? 0
                                let income = Double(point.income) ?? 0
                                let isHovered = hoverIndex == index

                                VStack(spacing: 2) {
                                    HStack(alignment: .bottom, spacing: 2) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(DesignTokens.success.opacity(isHovered ? 1 : 0.7))
                                            .frame(width: barWidth, height: max(CGFloat(income / maxValue) * chartHeight, income > 0 ? 2 : 0))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(DesignTokens.error.opacity(isHovered ? 1 : 0.7))
                                            .frame(width: barWidth, height: max(CGFloat(spending / maxValue) * chartHeight, spending > 0 ? 2 : 0))
                                    }
                                }
                                .frame(width: barGroupWidth)
                                .onHover { hoverIndex = $0 ? index : nil }
                            }
                        }

                        if let idx = hoverIndex, idx < trends.count {
                            let point = trends[idx]
                            let spending = Double(point.spending) ?? 0
                            let income = Double(point.income) ?? 0

                            VStack(alignment: .leading, spacing: 2) {
                                Text(formatTrendLabel(point.key, granularity: granularity))
                                    .font(.system(size: 10, weight: .semibold))
                                if !appState.hideBalance {
                                    HStack(spacing: 8) {
                                        Label(String(format: "$%.0f", income), systemImage: "arrow.down")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(DesignTokens.success)
                                        Label(String(format: "$%.0f", spending), systemImage: "arrow.up")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(DesignTokens.error)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .position(x: (CGFloat(idx) + 0.5) * barGroupWidth, y: 16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)

                HStack(spacing: 12) {
                    Label("Income", systemImage: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.success)
                    Label("Spending", systemImage: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.error)
                }
            }
        }
    }
}

private struct DashboardSpendByCategoryCard: View {
    @EnvironmentObject private var appState: AppState

    let analytics: TransactionAnalyticsSummary?

    private var topCategories: [(name: String, value: Double)] {
        Array((analytics?.spendingByCategory ?? []).prefix(5).map {
            (name: $0.displayName, value: Double($0.usdValue) ?? 0)
        })
    }

    var body: some View {
        DashboardCardShell {
            DashboardCardHeader(title: "Spending by Category", systemImage: "chart.pie")

            if topCategories.isEmpty {
                DashboardUnavailableMessage("No spending data available.")
            } else {
                let maxVal = topCategories.first?.value ?? 1

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(topCategories.enumerated()), id: \.offset) { _, cat in
                        HStack(spacing: 8) {
                            Text(cat.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 100, alignment: .leading)

                            GeometryReader { geometry in
                                let fillWidth = max(geometry.size.width * CGFloat(cat.value / maxVal), cat.value > 0 ? 4 : 0)
                                Capsule()
                                    .fill(DesignTokens.cardBackground)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(DesignTokens.error.opacity(0.72))
                                            .frame(width: min(fillWidth, geometry.size.width))
                                    }
                            }
                            .frame(height: 7)

                            Text(appState.hideBalance ? "••••" : String(format: "$%.0f", cat.value))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardStatementDropCard: View {
    @State private var isTargeted = false
    @State private var showingCSVPicker = false
    @State private var uploadMessage: String?

    var body: some View {
        DashboardCardShell {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Import Statement")
                    .font(.headline)

                Text("Drop a CSV statement here or use the button to import transactions.")
                    .font(DesignTokens.captionFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button {
                    showingCSVPicker = true
                } label: {
                    Label("Choose Files", systemImage: "folder")
                        .font(.subheadline)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                if let uploadMessage {
                    Text(uploadMessage)
                        .font(DesignTokens.captionFont)
                        .foregroundStyle(uploadMessage.hasPrefix("Imported") ? DesignTokens.success : DesignTokens.error)
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    .padding(6)
            )
        }
        .fileImporter(
            isPresented: $showingCSVPicker,
            allowedContentTypes: [.commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleCSVImport(result) }
        }
        .onDrop(of: [.commaSeparatedText, .fileURL], isTargeted: $isTargeted) { providers in
            Task {
                for provider in providers {
                    guard let url = await Self.resolveFileURL(from: provider) else { continue }
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let response = try? await APIClient.shared.uploadStatement(fileData: data)
                    if let response {
                        uploadMessage = "Imported \(response.imported) from \(response.source)"
                    }
                }
            }
            return true
        }
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) async {
        guard case let .success(urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let response = try await APIClient.shared.uploadStatement(fileData: data, filename: url.lastPathComponent)
                uploadMessage = "Imported \(response.imported) from \(response.source)"
            } catch {
                uploadMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }
}

extension DashboardStatementDropCard {
    @MainActor
    static func resolveFileURL(from provider: NSItemProvider) async -> URL? {
        let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url")
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
            return URL(string: str)
        }
        return nil
    }
}

private struct DashboardNetWorthSparkline: View {
    let history: [NetWorthHistoryPoint]

    @State private var hoverIndex: Int?

    private var values: [Double] {
        history.compactMap { Double($0.usdValue) }
    }

    var body: some View {
        GeometryReader { geometry in
            let sparkline = DashboardSparklineMetrics(values: values, size: geometry.size)
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

                if let idx = hoverIndex, idx < pts.count, idx < history.count {
                    let pt = pts[idx]

                    // Vertical indicator line.
                    Path { path in
                        path.move(to: CGPoint(x: pt.x, y: 0))
                        path.addLine(to: CGPoint(x: pt.x, y: geometry.size.height))
                    }
                    .stroke(Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // Dot on the line.
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .position(pt)

                    // Value tooltip.
                    let dateStr = history[idx].date
                    let valStr = ValueFormatters.currency(from: history[idx].usdValue, code: "usd") ?? history[idx].usdValue
                    let isRightHalf = pt.x > geometry.size.width / 2

                    VStack(alignment: isRightHalf ? .trailing : .leading, spacing: 1) {
                        Text(dateStr)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
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

private struct DashboardSparklineMetrics {
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
