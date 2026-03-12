import SwiftUI

struct SourcesListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SourcesViewModel()
    @State private var showAddSheet = false
    @State private var selectedSource: SourceDTO?
    @State private var pendingDeletionSource: SourceDTO?
    @State private var isDeletingSource = false
    @State private var deleteErrorMessage: String?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var missingWebSyncProviders: [WebSyncProvider] {
        WebSyncProvider.allCases.filter { provider in
            !viewModel.sources.contains(where: { $0.type.lowercased() == provider.sourceType })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Sources")
                    .font(.title2)

                Spacer()

                Button("Add Source") {
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeletingSource)
            }

            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading {
                ProgressView("Loading sources...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Sources unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else {
                sourcesList
            }
        }
        .padding(24)
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
        .sheet(isPresented: $showAddSheet) {
            AddSourceSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedSource) { source in
            SourceDetailSheet(
                source: source,
                fields: viewModel.sourceTypes[source.type]?.fields ?? [],
                supportedApyRules: viewModel.sourceTypes[source.type]?.supportedApyRules ?? [],
                onSaved: { Task { await viewModel.reload() } },
                viewModel: viewModel
            )
        }
        .alert(
            "Delete Source?",
            isPresented: Binding(
                get: { pendingDeletionSource != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletionSource = nil
                    }
                }
            ),
            presenting: pendingDeletionSource
        ) { source in
            Button("Cancel", role: .cancel) {
                pendingDeletionSource = nil
            }
            Button("Delete", role: .destructive) {
                confirmDelete(source)
            }
            .disabled(isDeletingSource)
        } message: { source in
            Text(
                """
                Delete '\(source.name)' permanently?

                Historical snapshots and transactions for this source will be removed. APY rules for this source will be removed. Cached report and commentary data for affected dates will be cleared. Portfolio and Earn summaries will update after deletion.
                """
            )
        }
    }

    private var sourcesList: some View {
        List {
            configuredSourcesSection
            if !missingWebSyncProviders.isEmpty {
                Section("Web Sync Quick Connect") {
                    ForEach(missingWebSyncProviders) { provider in
                        quickConnectProviderRow(provider)
                    }
                }
            }
        }
        .frame(minHeight: 300)
    }

    private var configuredSourcesSection: some View {
        Section("Configured Sources") {
            if viewModel.sources.isEmpty {
                Text("No sources configured")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.sources) { source in
                configuredSourceRow(source)
            }
        }
    }

    private func configuredSourceRow(_ source: SourceDTO) -> some View {
        HStack {
            sourceIcon(source.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.name)
                if let provider = WebSyncProvider(sourceType: source.type),
                   let statusText = providerStatusLine(appState.webSyncStatus(for: provider)) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(appState.webSyncStatus(for: provider).errorMessage == nil ? Color.secondary : Color.red)
                }
            }
            Spacer()
            if let provider = WebSyncProvider(sourceType: source.type) {
                sourceWebSyncActions(provider: provider)
            }
            Toggle("Enabled", isOn: Binding(
                get: { source.enabled },
                set: { newValue in
                    viewModel.toggleSource(source, enabled: newValue)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(isDeletingSource)
            Button(role: .destructive) {
                deleteErrorMessage = nil
                pendingDeletionSource = source
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isDeletingSource)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSource = source
        }
    }

    private func quickConnectProviderRow(_ provider: WebSyncProvider) -> some View {
        let status = appState.webSyncStatus(for: provider)
        return HStack {
            sourceIcon(provider.sourceType)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.displayName)
                Text("Source will be auto-created after successful sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let statusText = providerStatusLine(status) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(status.errorMessage == nil ? Color.secondary : Color.red)
                }
            }
            Spacer()
            Button("Connect") {
                appState.connectWebSource(provider)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(status.isSyncing ? "Syncing..." : "Sync now") {
                Task {
                    _ = await appState.syncWebSourceNow(provider)
                    await viewModel.reload()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(status.isSyncing)
        }
    }

    private func sourceWebSyncActions(provider: WebSyncProvider) -> some View {
        let status = appState.webSyncStatus(for: provider)
        return HStack(spacing: 8) {
            Button("Connect") {
                appState.connectWebSource(provider)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDeletingSource)

            Button(status.isSyncing ? "Syncing..." : "Sync now") {
                Task {
                    _ = await appState.syncWebSourceNow(provider)
                    await viewModel.reload()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDeletingSource || status.isSyncing)
        }
    }

    @ViewBuilder
    private func sourceIcon(_ sourceType: String) -> some View {
        if let iconName = sourceType.sourceIconName() {
            Image(iconName)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .background(Circle().fill(Color.white))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
        } else {
            EmptyView()
        }
    }

    private func confirmDelete(_ source: SourceDTO) {
        guard !isDeletingSource else { return }
        isDeletingSource = true

        Task {
            let result = await viewModel.deleteSource(source)
            switch result {
            case .success:
                pendingDeletionSource = nil
            case let .failure(error):
                deleteErrorMessage = error.errorDescription ?? "Unable to delete source."
            }
            isDeletingSource = false
        }
    }

    private func providerStatusLine(_ status: WebSyncStatus) -> String? {
        if status.isSyncing {
            return status.message ?? "Syncing..."
        }
        if let error = status.errorMessage, !error.isEmpty {
            return error
        }
        if let message = status.message, !message.isEmpty {
            return message
        }
        return nil
    }
}

#Preview {
    SourcesListView()
        .environmentObject(AppState())
}
