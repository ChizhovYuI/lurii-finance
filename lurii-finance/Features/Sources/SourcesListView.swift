import SwiftUI

struct SourcesListView: View {
    @StateObject private var viewModel = SourcesViewModel()
    @State private var showAddSheet = false
    @State private var selectedSource: SourceDTO?

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
                            if let iconName = sourceIconName(for: source.type) {
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
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSource = source
                        }
                    }
                    .onDelete(perform: viewModel.deleteSources)
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
            SourceDetailSheet(source: source)
        }
    }

    private func sourceIconName(for sourceType: String) -> String? {
        switch sourceType.lowercased() {
        case "okx":
            return "okx"
        case "binance":
            return "binance"
        case "binance_th":
            return "binance_th"
        case "bybit":
            return "bybit"
        case "lobstr":
            return "lobstr"
        case "wise":
            return "wise"
        case "kbank":
            return "kbank"
        case "ibkr":
            return "ibkr"
        case "blend":
            return "blend"
        default:
            return nil
        }
    }
}

#Preview {
    SourcesListView()
}
