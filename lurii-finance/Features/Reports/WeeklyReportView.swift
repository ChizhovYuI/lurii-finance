import SwiftUI

struct WeeklyReportView: View {
    @EnvironmentObject private var appState: AppState
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

                Button {
                    viewModel.silentRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button("Generate") {
                    viewModel.generate()
                }
                .buttonStyle(.bordered)
                .disabled(appState.generatingCommentary)
            }

            if appState.generatingCommentary {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(commentaryProgressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.hasLoaded {
                Spacer()
            } else if viewModel.isLoading {
                ProgressView("Loading report...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Report unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else if let commentary = viewModel.commentary,
                      !(commentary.text.isEmpty && (commentary.error ?? "").lowercased().contains("no ai commentary cached")) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Date: \(commentary.date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let model = commentary.model {
                                Text("Model: \(model)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let error = commentary.error, !error.isEmpty {
                            Text("AI Error: \(error)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if commentary.stale == true {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(commentary.staleReason ?? "This report was generated before your report context changed. Generate again to refresh.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignTokens.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        if let sections = commentary.sections, !sections.isEmpty {
                            ForEach(sections) { section in
                                SectionCard(section: section)
                            }
                        } else {
                            MarkdownBodyText(text: commentary.text)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DesignTokens.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .blur(radius: appState.hideBalance ? 8 : 0)
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
            viewModel.appState = appState
            guard !isPreview else { return }
            viewModel.silentRefresh()
            viewModel.checkGeneratingStatus()
        }
        .onChange(of: appState.selectedSection) { _, newSection in
            if newSection == .reports {
                viewModel.silentRefresh()
                viewModel.checkGeneratingStatus()
            }
        }
    }

    private var commentaryProgressText: String {
        let total = appState.commentaryTotalSections
        if total > 0, let current = appState.commentaryCurrentSection, !current.isEmpty {
            let currentIndex = min(appState.commentaryCompletedSections + 1, total)
            return "Generating section \(currentIndex)/\(total): \(current)…"
        }
        return "Generating report…"
    }
}

private struct SectionCard: View {
    let section: CommentarySection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)

            MarkdownBodyText(text: section.description)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MarkdownBodyText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)
        ) {
            Text(attributed)
                .font(DesignTokens.bodyFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(DesignTokens.bodyFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WeeklyReportView()
        .environmentObject(AppState())
}
