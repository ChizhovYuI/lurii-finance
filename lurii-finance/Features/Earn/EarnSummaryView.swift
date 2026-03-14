import SwiftUI

struct EarnSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: EarnSummaryViewModel
    @State private var filter = ""
    @Namespace private var earnNamespace

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
                searchField
                    .frame(width: 200)
            }
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
                    positionsTable(summary)
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
        let totalValueHistory = viewModel.history.compactMap { Double($0.totalUsdValue) }
        let weightedAvgApyHistory = viewModel.history.compactMap { Double($0.weightedAvgApy) }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            EarnSummaryMetricCard(
                title: "Total Value",
                value: totalValue,
                systemImage: "dollarsign.circle",
                graphValues: totalValueHistory
            )
            .frame(minHeight: 120)

            EarnSummaryMetricCard(
                title: "APY",
                value: avgApy,
                systemImage: "percent",
                graphValues: weightedAvgApyHistory
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

    private var headerRow: some View {
        HStack(spacing: 12) {
            headerCell("Asset")
            headerCell("Source")
            headerCell("Amount", alignment: .trailing)
            headerCell("Price", alignment: .trailing)
            headerCell("Value", alignment: .trailing)
            headerCell("APY", alignment: .trailing)
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
        }
        .padding(.horizontal, DesignTokens.blockRowHorizontalPadding)
        .font(.subheadline)
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
}

private struct EarnSummaryMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let graphValues: [Double]

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
                EarnSummarySparkline(values: graphValues)
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

    var body: some View {
        GeometryReader { geometry in
            let sparkline = EarnSparklineMetrics(values: values, size: geometry.size)

            ZStack {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var points: [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }

        let usableWidth = max(size.width - (horizontalInset * 2), 1)

        return values.enumerated().map { index, value in
            let progress = values.count == 1 ? 0 : CGFloat(index) / CGFloat(values.count - 1)
            let x = horizontalInset + (usableWidth * progress)
            return CGPoint(x: x, y: yPosition(for: value))
        }
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
                    source: "Binance",
                    asset: "ETH",
                    assetType: "crypto",
                    amount: "2.2",
                    usdValue: "6420.00",
                    price: "2918.18",
                    apy: "0.058"
                )
            ]
        )
        viewModel.history = previewHistory

        return EarnSummaryView(viewModel: viewModel)
            .environmentObject(appState)
    }
}

#Preview {
    EarnPreviewHost()
}
