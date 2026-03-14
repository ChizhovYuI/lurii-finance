import SwiftUI

struct SourcesListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SourcesViewModel()
    @State private var showAddSheet = false
    @State private var selectedSource: SourceDTO?
    @State private var pendingDeletionSource: SourceDTO?
    @State private var isDeletingSource = false
    @State private var deleteErrorMessage: String?
    @State private var filter = ""
    @Namespace private var sourcesNamespace

    private let controlSize: CGFloat = 24

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var missingWebSyncProviders: [WebSyncProvider] {
        WebSyncProvider.allCases.filter { provider in
            !viewModel.sources.contains(where: { $0.type.lowercased() == provider.sourceType }) && providerMatches(provider)
        }
    }

    private var filteredSources: [SourceDTO] {
        viewModel.sources.filter(sourceMatches)
    }

    private var localTokens: [String] {
        filter.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var globalTokens: [String] {
        appState.globalSearchQuery.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sources")
                    .font(.title)
                    .foregroundStyle(.primary)

                if let deleteErrorMessage {
                    Label(deleteErrorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                content
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Sources")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                searchField
                    .frame(width: 200)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .automatic) {
                Button("Add Source") {
                    showAddSheet = true
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(isDeletingSource)
            }
        }
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

    private var content: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading sources...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Sources unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else {
                sourcesContent
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
        .glassEffectID("sources-search", in: sourcesNamespace)
    }

    private var sourcesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourcesSection(title: "Configured Sources") {
                if viewModel.sources.isEmpty {
                    sectionEmptyState("No sources configured")
                } else if filteredSources.isEmpty {
                    sectionEmptyState("No sources match current search")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSources.enumerated()), id: \.element.id) { index, source in
                            configuredSourceRow(source)
                            if index < filteredSources.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            if !missingWebSyncProviders.isEmpty {
                sourcesSection(title: "Web Sync Quick Connect") {
                    VStack(spacing: 0) {
                        ForEach(Array(missingWebSyncProviders.enumerated()), id: \.element.id) { index, provider in
                            quickConnectProviderRow(provider)
                            if index < missingWebSyncProviders.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
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
        .padding(.horizontal, DesignTokens.blockPadding)
        .padding(.vertical, 12)
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
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            Button(status.isSyncing ? "Syncing..." : "Sync now") {
                Task {
                    _ = await appState.syncWebSourceNow(provider)
                    await viewModel.reload()
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(status.isSyncing)
        }
        .padding(.horizontal, DesignTokens.blockPadding)
        .padding(.vertical, 12)
    }

    private func sourceWebSyncActions(provider: WebSyncProvider) -> some View {
        let status = appState.webSyncStatus(for: provider)
        return HStack(spacing: 8) {
            Button("Connect") {
                appState.connectWebSource(provider)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .disabled(isDeletingSource)

            Button(status.isSyncing ? "Syncing..." : "Sync now") {
                Task {
                    _ = await appState.syncWebSourceNow(provider)
                    await viewModel.reload()
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
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
                .glassEffect(.regular, in: Circle())
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

    private func sourceMatches(_ source: SourceDTO) -> Bool {
        let haystack = [
            source.name.lowercased(),
            source.type.lowercased(),
            source.id.lowercased()
        ]
        let localMatches = localTokens.allSatisfy { token in
            haystack.contains { $0.contains(token) }
        }
        let globalMatches = globalTokens.allSatisfy { token in
            haystack.contains { $0.contains(token) }
        }
        return localMatches && globalMatches
    }

    private func providerMatches(_ provider: WebSyncProvider) -> Bool {
        let haystack = [provider.displayName.lowercased(), provider.sourceType.lowercased()]
        let localMatches = localTokens.allSatisfy { token in
            haystack.contains { $0.contains(token) }
        }
        let globalMatches = globalTokens.allSatisfy { token in
            haystack.contains { $0.contains(token) }
        }
        return localMatches && globalMatches
    }

    private func sourcesSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            SourcesSurfaceCard {
                content()
            }
        }
    }

    private func sectionEmptyState(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.blockPadding)
            .padding(.vertical, 14)
    }
}

private struct SourcesSurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .stroke(DesignTokens.border)
            )
    }
}

#Preview {
    SourcesListView()
        .environmentObject(AppState())
}
