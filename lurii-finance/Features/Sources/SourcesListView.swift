import SwiftUI

struct SourcesListView: View {
    @StateObject private var viewModel = SourcesViewModel()
    @State private var showAddSheet = false
    @State private var selectedSource: SourceDTO?
    @State private var pendingDeletionSource: SourceDTO?
    @State private var isDeletingSource = false
    @State private var deleteErrorMessage: String?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
            } else if viewModel.sources.isEmpty {
                EmptyStateView(title: "No sources configured", message: "Add an exchange or wallet to start.")
            } else {
                List {
                    ForEach(viewModel.sources) { source in
                        HStack {
                            if let iconName = source.type.sourceIconName() {
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
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                            }
                            Spacer()
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
                }
                .frame(minHeight: 300)
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
}

#Preview {
    SourcesListView()
}
