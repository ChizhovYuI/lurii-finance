import Foundation

enum APIEndpoints {
    static let baseURL = URL(string: "http://127.0.0.1:19274")!

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
    static let sourceValidate = "/api/v1/source-connections/validate"
    static func sourceDetail(_ name: String) -> String { "/api/v1/sources/\(name)" }
    static func sourceApyRules(_ name: String) -> String { "/api/v1/sources/\(name)/apy-rules" }
    static func sourceApyRule(_ name: String, ruleId: String) -> String { "/api/v1/sources/\(name)/apy-rules/\(ruleId)" }
    static func sourceEarnOverrides(_ name: String) -> String { "/api/v1/sources/\(name)/earn-overrides" }
    static let extSnapshot = "/api/v1/ext/snapshot"
    static let cashManual = "/api/v1/cash/manual"

    static let portfolioSummary = "/api/v1/portfolio/summary"
    static let portfolioNetWorthHistory = "/api/v1/portfolio/net-worth-history"
    static let portfolioHoldings = "/api/v1/portfolio/holdings"
    static let pnl = "/api/v1/analytics/pnl"
    static let allocation = "/api/v1/analytics/allocation"
    static let sourceMovers = "/api/v1/analytics/source-movers"
    static let exposure = "/api/v1/analytics/exposure"
    static let earnSummary = "/api/v1/earn/summary"
    static let earnHistory = "/api/v1/earn/history"

    static let collect = "/api/v1/collect"
    static let collectStatus = "/api/v1/collect/status"
    static let backfillStatus = "/api/v1/backfill/status"

    static let updates = "/api/v1/updates"
    static let updatesInstall = "/api/v1/updates/install"
    static let updatesCheck = "/api/v1/updates/check"
    static let updatesStatus = "/api/v1/updates/status"
    static let updatesRestart = "/api/v1/updates/restart"

    static let ws = "/api/v1/ws"

    static let statementUpload = "/api/v1/statement/upload"
    static let transactions = "/api/v1/transactions"
    static func transactionDetail(_ id: Int) -> String { "/api/v1/transactions/\(id)" }
    static func transactionMetadata(_ id: Int) -> String { "/api/v1/transactions/\(id)/metadata" }
    static func transactionTransferCandidates(_ id: Int) -> String { "/api/v1/transactions/\(id)/transfer-candidates" }
    static func transactionUnlink(_ id: Int) -> String { "/api/v1/transactions/\(id)/link-transfer" }
    static let transactionLinkTransfer = "/api/v1/transactions/link-transfer"
    static let transactionReviewQueue = "/api/v1/transactions/review-queue"
    static let transactionCategories = "/api/v1/transactions/categories"
    static func transactionCategory(_ id: Int) -> String { "/api/v1/transactions/\(id)/category" }
    static func transactionType(_ id: Int) -> String { "/api/v1/transactions/\(id)/type" }
    static let transactionAnalyticsSummary = "/api/v1/transactions/analytics/summary"
    static let transactionAnalyticsTrends = "/api/v1/transactions/analytics/trends"
}
