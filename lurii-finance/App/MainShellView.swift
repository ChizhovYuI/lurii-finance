import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isPreparingCashEntry = false
    @State private var cashEntryErrorMessage: String?
    @State private var cashManualState: CashManualState?
    @State private var showCashSheet = false
    @Namespace private var sidebarFooterNamespace
    private let primarySections: [AppState.AppSection] = [.dashboard, .allocation, .earn, .reports]
    private let settingsSections: [AppState.AppSection] = [.sources, .ai, .about]

    private var shouldShowSidebarFooter: Bool {
        appState.updateInstalling ||
        appState.restartNeeded ||
        appState.hasInstallableUpdate ||
        (appState.updateStatus == "error" && !appState.updateMessage.isEmpty)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $appState.selectedSection) {
                    Section {
                        ForEach(primarySections, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }

                    Section("Settings") {
                        ForEach(settingsSections, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
                .listStyle(.sidebar)
 
                if shouldShowSidebarFooter {
                    Divider()
                    sidebarFooter
                }
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius, style: .continuous))
        } detail: {
            Group {
                switch appState.selectedSection {
                case .dashboard:
                    DashboardView()
                case .allocation:
                    AllocationView()
                case .earn:
                    EarnSummaryView()
                case .reports:
                    WeeklyReportView()
                case .sources:
                    SourcesListView()
                case .ai:
                    AISettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.clear)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                quickActionsToolbar
            }
        }
        .sheet(isPresented: $showCashSheet, onDismiss: { cashManualState = nil }) {
            if let cashManualState {
                CashManualSheet(state: cashManualState) {
                    NotificationCenter.default.post(name: .snapshotUpdated, object: nil)
                }
            } else {
                ProgressView("Loading cash editor...")
                    .padding(24)
            }
        }
        .alert("Unable to open Cash editor", isPresented: cashEntryAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cashEntryErrorMessage ?? "Unknown error")
        }
    }

    private var sidebarFooter: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if appState.updateInstalling {
                    Text("Installing updates...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: appState.updateProgress)
                        .controlSize(.small)
                    if !appState.updateMessage.isEmpty {
                        Text(appState.updateMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if appState.restartNeeded {
                    Button {
                        appState.restartAfterUpdate()
                    } label: {
                        Label("Restart Lurii Finance", systemImage: "arrow.clockwise.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .glassEffectID("sidebar-restart", in: sidebarFooterNamespace)
                } else if appState.hasInstallableUpdate {
                    Button {
                        Task { await appState.installUpdatesManually() }
                    } label: {
                        Label("Update Lurii Finance", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .glassEffectID("sidebar-update", in: sidebarFooterNamespace)
                }

                if appState.updateStatus == "error", !appState.updateMessage.isEmpty {
                    Text(appState.updateMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickActionsToolbar: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                quickActionButton(
                    systemImage: appState.hideBalance ? "eye.slash" : "eye",
                    help: appState.hideBalance ? "Show balances" : "Hide balances"
                ) {
                    appState.hideBalance.toggle()
                }

                quickActionButton(
                    systemImage: "plus",
                    help: isPreparingCashEntry ? "Opening cash editor..." : "Add cash",
                    isDisabled: isPreparingCashEntry
                ) {
                    prepareCashEntry()
                }

                quickActionButton(
                    systemImage: "arrow.clockwise",
                    help: appState.collecting ? "Collecting..." : "Collect latest data",
                    isDisabled: appState.collecting
                ) {
                    startCollect()
                }
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            .background(.clear)
            .tint(Color.clear)
            .clipShape(Capsule())
            .glassEffect(.regular, in: Capsule())
        }
    }

    private var cashEntryAlertIsPresented: Binding<Bool> {
        Binding(
            get: { cashEntryErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    cashEntryErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func quickActionButton(
        systemImage: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if systemImage == "plus" && isPreparingCashEntry {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else if systemImage == "arrow.clockwise" && appState.collecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 0)
            .contentShape(Circle())
        }
        .tint(.clear)
        .background(.white)
        .clipShape(Capsule())
        .glassEffect(.regular, in: Capsule())
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private func startCollect() {
        Task {
            _ = try? await APIClient.shared.startCollect(source: nil)
            if let status = try? await APIClient.shared.getCollectStatus() {
                await MainActor.run {
                    appState.updateCollectStatus(status)
                }
            }
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
                cashEntryErrorMessage = error.localizedDescription
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

#Preview {
    MainShellView()
        .environmentObject(AppState())
}
