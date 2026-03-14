import SwiftUI
import Foundation

struct WeeklyReportView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ReportsViewModel()

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reports")
                    .font(.title)
                    .foregroundStyle(.primary)

                if appState.generatingCommentary {
                    commentaryProgressRow
                }

                content

                if let status = viewModel.sendStatus {
                    Text("Send status: \(status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Reports")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Generate") {
                    viewModel.generate()
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(appState.generatingCommentary)
            }
        }
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

    private var content: some View {
        Group {
            if !viewModel.hasLoaded || viewModel.isLoading {
                ProgressView("Loading report...")
            } else if let errorMessage = viewModel.errorMessage {
                EmptyStateView(title: "Report unavailable", message: errorMessage, actionTitle: "Retry") {
                    viewModel.load()
                }
            } else if let commentary = viewModel.commentary,
                      !(commentary.text.isEmpty && (commentary.error ?? "").lowercased().contains("no ai commentary cached")) {
                reportContent(for: commentary)
                    .blur(radius: appState.hideBalance ? 8 : 0)
            } else {
                EmptyStateView(title: "No report yet", message: "Generate a weekly commentary.")
            }
        }
    }

    private var commentaryProgressRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(commentaryProgressText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reportContent(for commentary: AICommentary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            reportMetadataRow(for: commentary)

            if let error = commentary.error, !error.isEmpty {
                Label("AI Error: \(error)", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.warning)
            }

            if commentary.stale == true {
                ReportSurfaceCard {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(DesignTokens.warning)
                        Text(commentary.staleReason ?? "This report was generated before your report context changed. Generate again to refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let sections = commentary.sections, !sections.isEmpty {
                ForEach(sections) { section in
                    ReportArticleBlock(
                        title: section.title,
                        text: section.description
                    )
                }
            } else {
                ReportArticleBlock(
                    title: "Weekly Report",
                    text: commentary.text
                )
            }
        }
    }

    private func reportMetadataRow(for commentary: AICommentary) -> some View {
        HStack(spacing: 12) {
            Text("Date: \(commentary.date)")
            if let model = commentary.model, !model.isEmpty {
                Text("Model: \(model)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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

private struct ReportArticleBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            ReportSurfaceCard {
                MarkdownBodyText(text: text)
            }
        }
    }
}

private struct ReportSurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DesignTokens.blockPadding)
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
    WeeklyReportView()
        .environmentObject(AppState())
}
