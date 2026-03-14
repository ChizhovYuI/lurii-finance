import Foundation

enum GitHubReleasesError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .httpStatus(statusCode, message):
            return message ?? "GitHub request failed with status \(statusCode)."
        case .decodingFailed:
            return "Unable to read GitHub release data."
        }
    }
}

actor GitHubReleasesClient {
    static let shared = GitHubReleasesClient()

    private let decoder: JSONDecoder
    private var cachedEntries: [AboutChangelogEntry]?

    init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchMergedChangelog(forceRefresh: Bool = false) async throws -> [AboutChangelogEntry] {
        if !forceRefresh, let cachedEntries {
            return cachedEntries
        }

        async let appEntries = fetchAllReleases(for: .app)
        async let backendEntries = fetchAllReleases(for: .backend)

        let merged = try await (appEntries + backendEntries)
            .sorted {
                if $0.publishedAt == $1.publishedAt {
                    return $0.source.sortOrder < $1.source.sortOrder
                }
                return $0.publishedAt > $1.publishedAt
            }

        cachedEntries = merged
        return merged
    }

    private func fetchAllReleases(for source: AboutChangelogSource) async throws -> [AboutChangelogEntry] {
        var entries: [AboutChangelogEntry] = []
        var page = 1
        let perPage = 100

        while true {
            let items = try await fetchReleasePage(for: source, page: page, perPage: perPage)
            if items.isEmpty {
                break
            }

            entries.append(contentsOf: items.compactMap { item in
                guard !item.draft, !item.prerelease else { return nil }
                return AboutChangelogEntry(
                    source: source,
                    tagName: item.tagName,
                    name: item.name,
                    body: item.body ?? "",
                    publishedAt: item.publishedAt,
                    htmlURL: item.htmlURL
                )
            })

            if items.count < perPage {
                break
            }
            page += 1
        }

        return entries
    }

    private func fetchReleasePage(for source: AboutChangelogSource, page: Int, perPage: Int) async throws -> [GitHubReleasePageItem] {
        let url = URL(string: "https://api.github.com/repos/\(source.repository)/releases?per_page=\(perPage)&page=\(page)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LuriiFinance", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleasesError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GitHubReleasesError.httpStatus(httpResponse.statusCode, errorMessage)
        }

        do {
            return try decoder.decode([GitHubReleasePageItem].self, from: data)
        } catch {
            throw GitHubReleasesError.decodingFailed
        }
    }
}
