import SwiftUI

struct EarnSummaryView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = EarnSummaryViewModel()
    @State private var filter = ""

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if viewModel.isLoading {
                    ProgressView("Loading earn summary...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Earn unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load()
                    }
                } else if let summary = viewModel.summary {
                    totals(summary)
                    positionsTable(summary)
                } else {
                    EmptyStateView(title: "No earn data", message: "Yield-bearing positions will appear here once available.")
                }
            }
            .padding(24)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Earn")
                .font(.title2)
            if let date = viewModel.summary?.date, !date.isEmpty {
                Text("As of \(date)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func totals(_ summary: EarnSummaryResponse) -> some View {
        let totalValue = ValueFormatters.currency(from: summary.totalUsdValue, code: "usd") ?? "—"
        let avgApy = ValueFormatters.percent(from: summary.weightedAvgApy) ?? summary.weightedAvgApy ?? "—"

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Total Value", value: totalValue, subtitle: "Yield positions")
                .frame(minHeight: 120)
            StatCard(title: "Weighted Avg APY", value: avgApy, subtitle: "Portfolio")
                .frame(minHeight: 120)
        }
    }

    private func positionsTable(_ summary: EarnSummaryResponse) -> some View {
        let sorted = summary.positions.sorted { lhs, rhs in
            let l = Decimal(string: lhs.apy ?? "0") ?? 0
            let r = Decimal(string: rhs.apy ?? "0") ?? 0
            return l > r
        }
        let tokens = filter.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let filtered: [EarnPosition] = if tokens.isEmpty {
            sorted
        } else {
            sorted.filter { position in
                let haystack = [position.asset.lowercased(), position.source.lowercased()]
                return tokens.allSatisfy { token in haystack.contains { $0.contains(token) } }
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Positions")
                    .font(.headline)
                Spacer()
                TextField("Filter by asset, source", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }

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
        .padding(16)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .background(Circle().fill(Color.white))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            rowCell(source)
        }
    }
}

#Preview {
    EarnSummaryView()
        .environmentObject(AppState())
}
