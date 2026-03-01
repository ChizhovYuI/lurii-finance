import Foundation

// MARK: - Health

struct HealthResponse: Codable {
    let status: String
    let version: String
    let collecting: Bool
}

// MARK: - Source Types

struct SourceTypeField: Codable, Identifiable {
    var id: String { name }
    let name: String
    let prompt: String
    let required: Bool
    let secret: Bool
    let tip: String?
}

// MARK: - Sources

struct SourceDTO: Codable, Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let credentials: [String: String]
    let enabled: Bool
}

struct SourceCreateRequest: Codable {
    let name: String
    let type: String
    let credentials: [String: String]
}

struct SourcePatchRequest: Codable {
    var credentials: [String: String]?
    var enabled: Bool?
}

// MARK: - Portfolio

struct PortfolioSummary: Codable {
    let date: String
    let netWorth: [String: String]?
    let holdings: [AllocationRow]
    let warnings: [String]?
}

struct AllocationRow: Codable, Identifiable {
    var id: String { "\(asset)-\(sources.joined(separator: ","))" }
    let asset: String
    let sources: [String]
    let amount: String?
    let usdValue: String?
    let price: String?
    let percentage: String?
    let assetType: String?

    init(asset: String, sources: [String], amount: String?, usdValue: String?, price: String?, percentage: String?, assetType: String?) {
        self.asset = asset
        self.sources = sources
        self.amount = amount
        self.usdValue = usdValue
        self.price = price
        self.percentage = percentage
        self.assetType = assetType
    }

    enum CodingKeys: String, CodingKey {
        case asset
        case source
        case sources
        case amount
        case usdValue
        case price
        case percentage
        case assetType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asset = try container.decode(String.self, forKey: .asset)
        amount = try container.decodeIfPresent(String.self, forKey: .amount)
        usdValue = try container.decodeIfPresent(String.self, forKey: .usdValue)
        price = try container.decodeIfPresent(String.self, forKey: .price)
        percentage = try container.decodeIfPresent(String.self, forKey: .percentage)
        assetType = try container.decodeIfPresent(String.self, forKey: .assetType)

        if let sources = try container.decodeIfPresent([String].self, forKey: .sources) {
            self.sources = sources
        } else if let source = try container.decodeIfPresent(String.self, forKey: .source) {
            self.sources = [source]
        } else {
            self.sources = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(asset, forKey: .asset)
        try container.encodeIfPresent(amount, forKey: .amount)
        try container.encodeIfPresent(usdValue, forKey: .usdValue)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(percentage, forKey: .percentage)
        try container.encodeIfPresent(assetType, forKey: .assetType)
        if sources.count == 1 {
            try container.encode(sources[0], forKey: .source)
        } else {
            try container.encode(sources, forKey: .sources)
        }
    }
}

struct HoldingsResponse: Codable {
    let date: String
    let holdings: [SnapshotDTO]
}

struct SnapshotDTO: Codable, Identifiable {
    var id: String { "\(date)-\(source)-\(asset)" }
    let date: String
    let source: String
    let asset: String
    let amount: String
    let usdValue: String
}

// MARK: - Analytics

struct PnlResponse: Codable {
    let date: String
    let period: String
    let pnl: PnlResult
}

struct PnlResult: Codable {
    let startDate: String?
    let endDate: String?
    let startValue: String
    let endValue: String
    let absoluteChange: String
    let percentageChange: String
    let byAsset: [PnlAssetRow]
    let topGainers: [PnlAssetRow]
    let topLosers: [PnlAssetRow]
    let notes: [String]
}

struct PnlAssetRow: Codable, Identifiable {
    var id: String { asset }
    let asset: String
    let startValue: String
    let endValue: String
    let absoluteChange: String
    let percentageChange: String
    let costBasisValue: String?
}

struct AllocationResponse: Codable {
    let date: String
    let byAsset: [AllocationRow]
    let bySource: [[String: String]]
    let byCategory: [[String: String]]
    let riskMetrics: RiskMetrics?
}

struct RiskMetrics: Codable {
    let concentrationPercentage: String?
    let hhiIndex: String?
    let top5Assets: [TopAssetRow]?
}

struct TopAssetRow: Codable, Identifiable {
    var id: String { "\(asset)-\(source ?? "")" }
    let asset: String
    let source: String?
    let usdValue: String?
    let price: String?
    let percentage: String?
}

struct ExposureResponse: Codable {
    let date: String
    let exposure: [[String: String]]
}

struct EarnSummaryResponse: Codable {
    let date: String
    let totalUsdValue: String?
    let weightedAvgApy: String?
    let positions: [EarnPosition]
}

struct EarnPosition: Codable, Identifiable {
    var id: String { "\(source)-\(asset)" }
    let source: String
    let asset: String
    let assetType: String?
    let amount: String?
    let usdValue: String?
    let price: String?
    let apy: String?
}

// MARK: - AI

struct AICommentary: Codable {
    let date: String
    let text: String
    let model: String?
    let error: String?
}

struct ErrorMessageResponse: Codable {
    let error: String
}

struct AIConfig: Codable, Equatable {
    let configured: Bool
    let provider: String?
    let model: String?
    let baseUrl: String?
    let hasApiKey: Bool?
}

struct AIConfigUpdateRequest: Codable {
    let provider: String
    var apiKey: String?
    var model: String?
    var baseUrl: String?
}

struct AIProviderField: Codable, Identifiable {
    var id: String { name }
    let name: String
    let required: Bool
    let secret: Bool?
    let defaultValue: String?
    let options: [AIFieldOption]?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case name
        case required
        case secret
        case defaultValue = "default"
        case options
        case hint
    }
}

struct AIFieldOption: Codable, Identifiable {
    var id: String { value }
    let value: String
    let description: String?
}

struct AIProviderConfig: Codable, Identifiable {
    var id: String { type }
    let type: String
    let apiKey: String?
    let apiKeyMasked: Bool?
    let model: String?
    let baseUrl: String?
    let active: Bool?
    let fields: [AIProviderField]?
}

struct AIProviderAvailable: Codable, Identifiable {
    var id: String { type }
    let type: String
    let fields: [AIProviderField]
    let description: String?
}

struct SettingsResponse: Codable {
    let aiProviders: [AIProviderConfig]
    let aiProvidersAvailable: [AIProviderAvailable]
}


// MARK: - Collection

struct CollectStartRequest: Codable {
    var source: String?
}

struct CollectStatus: Codable {
    let collecting: Bool
}

struct CollectStartResponse: Codable {
    let status: String
}

struct CollectionProgressEvent: Codable {
    let type: String
    let source: String?
    let current: Int?
    let total: Int?
    let error: String?
}

// MARK: - Report

struct NotifyResponse: Codable {
    let sent: Bool
}
