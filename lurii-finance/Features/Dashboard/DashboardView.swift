import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel
    @State private var isPreparingCashEntry = false
    @State private var cashEntryErrorMessage: String?
    @State private var cashManualState: CashManualState?
    @State private var showCashSheet = false

    @MainActor init(viewModel: DashboardViewModel = DashboardViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CollectionProgressBar(isCollecting: appState.collecting, progress: appState.collectionProgress, message: appState.collectionMessage)
                    .frame(maxWidth: .infinity)
                if let cashEntryErrorMessage {
                    Text(cashEntryErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("Loading portfolio...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Dashboard unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load()
                    }
                } else {
                    warningsSection
                    statCards
                }
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(isPreparingCashEntry ? "Add Cash..." : "Add Cash") {
                    prepareCashEntry()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(isPreparingCashEntry)

                Button("Collect") {
                    Task {
                        _ = try? await APIClient.shared.startCollect(source: nil)
                        if let status = try? await APIClient.shared.getCollectStatus() {
                            appState.updateCollectStatus(status)
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
            }

            ToolbarItem(placement: .status) {
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
        .sheet(isPresented: $showCashSheet, onDismiss: { cashManualState = nil }) {
            if let cashManualState {
                CashManualSheet(state: cashManualState) {
                    viewModel.load()
                }
            } else {
                ProgressView("Loading cash editor...")
                    .padding(24)
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
            .padding(DesignTokens.blockPadding)
            .background(DesignTokens.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius))
        }
    }

    private func prepareCashEntry() {
        guard !isPreparingCashEntry else { return }
        isPreparingCashEntry = true
        cashEntryErrorMessage = nil

        Task { @MainActor in
            do {
                try await ensureCashSourceExists()
                cashManualState = try await APIClient.shared.getCashManual()
                showCashSheet = true
            } catch {
                cashEntryErrorMessage = "Unable to open Cash editor: \(error.localizedDescription)"
            }
            isPreparingCashEntry = false
        }
    }

    private func ensureCashSourceExists() async throws {
        let existingSources = try await APIClient.shared.getSources()
        if existingSources.contains(where: { $0.type.lowercased() == "cash" }) {
            return
        }

        do {
            try await APIClient.shared.createSource(
                SourceCreateRequest(
                    name: "cash",
                    type: "cash",
                    credentials: ["fiat_currencies": "USD"]
                )
            )
        } catch {
            // Another client may have created the source in parallel.
        }
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
