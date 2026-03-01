import SwiftUI

struct WeeklyReportView: View {
    @StateObject private var viewModel = ReportsViewModel()

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Weekly AI Report")
                    .font(.title2)

                Spacer()

                Button("Generate") {
                    viewModel.generate()
                }
                .buttonStyle(.bordered)

                Button("Send") {
                    viewModel.notify()
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.isLoading {
                ProgressView("Loading report...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Report unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else if let commentary = viewModel.commentary,
                      !(commentary.text.isEmpty && (commentary.error ?? "").lowercased().contains("no ai commentary cached")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Date: \(commentary.date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let model = commentary.model {
                        Text("Model: \(model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = commentary.error, !error.isEmpty {
                        Text("AI Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(commentary.text)
                        .font(DesignTokens.bodyFont)
                }
                .padding(16)
                .background(DesignTokens.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                EmptyStateView(title: "No report yet", message: "Generate a weekly commentary.")
            }

            if let status = viewModel.sendStatus {
                Text("Send status: \(status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
    }
}

#Preview {
    WeeklyReportView()
}
