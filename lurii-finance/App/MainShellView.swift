import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
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
            .background(Color.white)
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
                Button {
                    appState.hideBalance.toggle()
                } label: {
                    Image(systemName: appState.hideBalance ? "eye.slash" : "eye")
                }
                .help("Toggle hidden balances")
            }
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
}

#Preview {
    MainShellView()
        .environmentObject(AppState())
}
