import SwiftUI

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppState.AppSection.allCases, selection: $appState.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Lurii Finance")
            .toolbarTitleDisplayMode(.inline)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
        } detail: {
            Group {
                switch appState.selectedSection {
                case .dashboard:
                    DashboardView()
                case .earn:
                    EarnSummaryView()
                case .sources:
                    SourcesListView()
                case .activity:
                    ActivityFeedView()
                case .reports:
                    WeeklyReportView()
                case .settings:
                    SettingsRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }
}

#Preview {
    MainShellView()
        .environmentObject(AppState())
}
