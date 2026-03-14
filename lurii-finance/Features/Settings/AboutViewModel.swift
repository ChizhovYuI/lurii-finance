import Combine
import Foundation

enum AboutChangelogSource: String, Codable {
    case app
    case backend

    var label: String {
        switch self {
        case .app:
            return "App"
        case .backend:
            return "Backend"
        }
    }

    nonisolated var repository: String {
        switch self {
        case .app:
            return "ChizhovYuI/lurii-finance"
        case .backend:
            return "ChizhovYuI/lurii-pfm"
        }
    }

    var tint: String {
        switch self {
        case .app:
            return "blue"
        case .backend:
            return "green"
        }
    }

    nonisolated var sortOrder: Int {
        switch self {
        case .app:
            return 0
        case .backend:
            return 1
        }
    }
}

struct GitHubReleasePageItem: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName
        case name
        case body
        case draft
        case prerelease
        case publishedAt
        case htmlURL = "htmlUrl"
    }
}

struct AboutChangelogEntry: Identifiable, Equatable {
    let source: AboutChangelogSource
    let tagName: String
    let name: String?
    let body: String
    let publishedAt: Date
    let htmlURL: URL

    var id: String { "\(source.rawValue)-\(tagName)" }

    var title: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty || trimmedName == tagName {
            return tagName
        }
        return trimmedName
    }

    var publishedLabel: String {
        Self.dateFormatter.string(from: publishedAt)
    }

    var bodyText: String {
        let cleanedBody = body
            .components(separatedBy: .newlines)
            .filter { !$0.localizedCaseInsensitiveContains("full changelog") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedBody.isEmpty ? "Release published without changelog notes." : cleanedBody
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

@MainActor
final class AboutViewModel: ObservableObject {
    @Published private(set) var changelogEntries: [AboutChangelogEntry] = []
    @Published private(set) var isLoadingChangelog = false
    @Published private(set) var hasLoadedChangelog = false
    @Published var changelogErrorMessage: String?
    @Published var isCheckingUpdates = false

    func syncUpdateStatus(using appState: AppState) async {
        await appState.syncUpdateStatus()
    }

    func forceCheckUpdates(using appState: AppState) async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        await appState.forceCheckUpdates()
    }

    func loadChangelogIfNeeded() async {
        guard !hasLoadedChangelog else { return }
        await loadChangelog(forceRefresh: false)
    }

    func reloadChangelog() async {
        await loadChangelog(forceRefresh: true)
    }

    private func loadChangelog(forceRefresh: Bool) async {
        guard !isLoadingChangelog else { return }

        isLoadingChangelog = true
        changelogErrorMessage = nil
        defer { isLoadingChangelog = false }

        do {
            changelogEntries = try await GitHubReleasesClient.shared.fetchMergedChangelog(forceRefresh: forceRefresh)
            hasLoadedChangelog = true
        } catch {
            changelogErrorMessage = error.localizedDescription
        }
    }
}
