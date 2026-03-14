import SwiftUI

struct MarkdownBodyText: View {
    let text: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .heading(let content):
                    InlineMarkdownText(text: content)
                        .font(.headline)
                        .foregroundStyle(.primary)
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
                case .blockquote(let content):
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 999)
                            .fill(DesignTokens.border)
                            .frame(width: 3)

                        InlineMarkdownText(text: content)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineMarkdownText: View {
    let text: String
    var font: Font = DesignTokens.bodyFont
    var foregroundStyle: Color = .primary

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarkdownBlock: Identifiable {
    let id: Int
    let kind: MarkdownBlockKind
}

private enum MarkdownBlockKind {
    case heading(String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case blockquote(String)
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

            if trimmed.hasPrefix("## ") {
                flushCurrentParagraph()
                let content = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(MarkdownBlock(id: nextID, kind: .heading(content)))
                    nextID += 1
                }
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

            if trimmed.hasPrefix(">") {
                flushCurrentParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(stripBlockquotePrefix(quoteLine))
                    index += 1
                }
                let content = quoteLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    blocks.append(MarkdownBlock(id: nextID, kind: .blockquote(content)))
                    nextID += 1
                }
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

    private nonisolated static func stripBlockquotePrefix(_ line: String) -> String {
        line.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
    }
}
