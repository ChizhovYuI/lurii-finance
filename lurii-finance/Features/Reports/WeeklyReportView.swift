import SwiftUI
import Foundation

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

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(MarkdownNormalizer.normalize(text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph(let content):
                    InlineMarkdownText(text: content)
                case .unorderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(DesignTokens.bodyFont)
                                InlineMarkdownText(text: item)
                            }
                        }
                    }
                case .orderedList(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(DesignTokens.bodyFont)
                                InlineMarkdownText(text: item)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum MarkdownNormalizer {
    static func normalize(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }

        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        let listPatterns = [
            #"[ \t]+(-\s+\*\*[^:\n]+:)"#,
            #"[ \t]+(-\s+[^-\n][^\n]*)"#,
        ]

        for pattern in listPatterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: "\n\n$1",
                options: .regularExpression
            )
        }

        text = text.replacingOccurrences(
            of: #"([.!?:;])[ \t]+(\d+\.\s)"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )

        text = text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct InlineMarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
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

private struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: MarkdownBlockKind
}

private enum MarkdownBlockKind {
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
}

private enum MarkdownBlockParser {
    nonisolated static func parse(_ text: String) -> [MarkdownBlock] {
        guard !text.isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        var currentLines: [String] = []
        var nextID = 0

        func flushCurrentParagraph() {
            let content = currentLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            blocks.append(MarkdownBlock(id: nextID, kind: .paragraph(content)))
            nextID += 1
            currentLines.removeAll(keepingCapacity: true)
        }

        let lines = text.components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushCurrentParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("- ") {
                flushCurrentParagraph()
                var items: [String] = []
                while index < lines.count {
                    let listLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard listLine.hasPrefix("- ") else { break }
                    items.append(String(listLine.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID, kind: .unorderedList(items)))
                nextID += 1
                continue
            }

            if isOrderedListItem(trimmed) {
                flushCurrentParagraph()
                var items: [String] = []
                while index < lines.count {
                    let listLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isOrderedListItem(listLine) else { break }
                    items.append(stripOrderedListPrefix(listLine))
                    index += 1
                }
                blocks.append(MarkdownBlock(id: nextID, kind: .orderedList(items)))
                nextID += 1
                continue
            }

            currentLines.append(trimmed)
            index += 1
        }

        flushCurrentParagraph()
        return blocks
    }

    private nonisolated static func isOrderedListItem(_ line: String) -> Bool {
        line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private nonisolated static func stripOrderedListPrefix(_ line: String) -> String {
        line.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
    }
}

#Preview {
    WeeklyReportView()
        .environmentObject(AppState())
}
