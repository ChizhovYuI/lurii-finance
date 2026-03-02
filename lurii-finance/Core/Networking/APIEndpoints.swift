import Foundation

enum APIEndpoints {
    static let baseURL = URL(string: "http://localhost:19274")!

    static func url(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url ?? baseURL
    }

    static func wsURL(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "ws"
        components?.path = path
        return components?.url ?? baseURL
    }

    static let health = "/api/v1/health"
    static let sourceTypes = "/api/v1/source-types"
    static let sources = "/api/v1/sources"
    static func sourceDetail(_ name: String) -> String { "/api/v1/sources/\(name)" }

    static let portfolioSummary = "/api/v1/portfolio/summary"
    static let portfolioHoldings = "/api/v1/portfolio/holdings"
    static let pnl = "/api/v1/analytics/pnl"
    static let allocation = "/api/v1/analytics/allocation"
    static let exposure = "/api/v1/analytics/exposure"
    static let earnSummary = "/api/v1/earn/summary"

    static let aiCommentary = "/api/v1/ai/commentary"
    static let aiCommentaryStatus = "/api/v1/ai/commentary/status"
    static let aiConfig = "/api/v1/ai/config"
    static let aiProviders = "/api/v1/ai/providers"
    static func aiProvider(_ type: String) -> String { "/api/v1/ai/providers/\(type)" }
    static func aiProviderActivate(_ type: String) -> String { "/api/v1/ai/providers/\(type)/activate" }
    static let aiProvidersDeactivate = "/api/v1/ai/providers/deactivate"

    static let collect = "/api/v1/collect"
    static let collectStatus = "/api/v1/collect/status"

    static let reportNotify = "/api/v1/report/notify"
    static let settings = "/api/v1/settings"

    static let ws = "/api/v1/ws"
}
