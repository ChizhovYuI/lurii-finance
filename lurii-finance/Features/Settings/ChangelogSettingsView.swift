import SwiftUI

struct ChangelogSettingsView: View {
    @StateObject private var viewModel = AboutViewModel()

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Changelog")
                    .font(.title)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Release Timeline")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Full release history from GitHub for both the app and backend, merged by publish date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                changelogContent
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("Changelog")
        .task {
            guard !isPreview else { return }
            await viewModel.loadChangelogIfNeeded()
        }
    }

    @ViewBuilder
    private var changelogContent: some View {
        if viewModel.isLoadingChangelog && viewModel.changelogEntries.isEmpty {
            ChangelogSurfaceCard {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading changelog from GitHub…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let errorMessage = viewModel.changelogErrorMessage, viewModel.changelogEntries.isEmpty {
            ChangelogSurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    ChangelogInlineNotice(
                        title: errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: DesignTokens.warning
                    )

                    Button("Retry") {
                        Task {
                            await viewModel.reloadChangelog()
                        }
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }
            }
        } else if viewModel.changelogEntries.isEmpty {
            ChangelogSurfaceCard {
                Text("No changelog entries available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.changelogEntries) { entry in
                    ChangelogEntryCard(entry: entry)
                }
            }
        }
    }
}

private struct ChangelogSurfaceCard<Content: View>: View {
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

private struct ChangelogInlineNotice: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChangelogEntryCard: View {
    let entry: AboutChangelogEntry

    var body: some View {
        ChangelogSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ChangelogSourceBadge(source: entry.source)
                            Text(entry.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }

                        HStack(spacing: 8) {
                            Text(entry.tagName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(entry.publishedLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    Link(destination: entry.htmlURL) {
                        Label("Open on GitHub", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }

                MarkdownBodyText(text: entry.bodyText)
            }
        }
    }
}

private struct ChangelogSourceBadge: View {
    let source: AboutChangelogSource

    private var tint: Color {
        switch source {
        case .app:
            return .blue
        case .backend:
            return .green
        }
    }

    var body: some View {
        Text(source.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    ChangelogSettingsView()
}
