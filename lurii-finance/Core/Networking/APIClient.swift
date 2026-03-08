import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case let .httpStatus(code):
            return "Request failed with status \(code)."
        case let .message(message):
            return message
        }
    }
}

enum ValidationRequestError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case let .httpStatus(code):
            return "Request failed with status \(code)."
        case let .message(message):
            return message
        }
    }
}

struct APIClient {
    static let shared = APIClient()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func getHealth() async throws -> HealthResponse {
        try await request(path: APIEndpoints.health, method: "GET")
    }

    func getSourceTypes() async throws -> [String: SourceTypeInfo] {
        try await request(path: APIEndpoints.sourceTypes, method: "GET")
    }

    func getSources() async throws -> [SourceDTO] {
        try await request(path: APIEndpoints.sources, method: "GET")
    }

    func createSource(_ requestBody: SourceCreateRequest) async throws {
        _ = try await requestVoid(path: APIEndpoints.sources, method: "POST", body: requestBody)
    }

    func validateSourceConnection(_ requestBody: SourceValidationRequest) async throws -> ConnectionValidationResponse {
        try await requestValidation(path: APIEndpoints.sourceValidate, method: "POST", body: requestBody)
    }

    func deleteSource(name: String) async throws -> DeleteSourceResponse {
        try await request(path: APIEndpoints.sourceDetail(name), method: "DELETE")
    }

    func patchSource(name: String, body: SourcePatchRequest) async throws {
        _ = try await requestVoid(path: APIEndpoints.sourceDetail(name), method: "PATCH", body: body)
    }

    // MARK: - APY Rules

    func getApyRules(sourceName: String) async throws -> [ApyRuleDTO] {
        try await request(path: APIEndpoints.sourceApyRules(sourceName), method: "GET")
    }

    func createApyRule(sourceName: String, body: ApyRuleCreateRequest) async throws -> [ApyRuleDTO] {
        try await request(path: APIEndpoints.sourceApyRules(sourceName), method: "POST", body: body)
    }

    func updateApyRule(sourceName: String, ruleId: String, body: ApyRuleCreateRequest) async throws -> [ApyRuleDTO] {
        try await request(path: APIEndpoints.sourceApyRule(sourceName, ruleId: ruleId), method: "PUT", body: body)
    }

    func deleteApyRule(sourceName: String, ruleId: String) async throws {
        _ = try await requestVoid(path: APIEndpoints.sourceApyRule(sourceName, ruleId: ruleId), method: "DELETE")
    }

    func getPortfolioSummary() async throws -> PortfolioSummary {
        try await request(path: APIEndpoints.portfolioSummary, method: "GET")
    }

    func getHoldings() async throws -> HoldingsResponse {
        try await request(path: APIEndpoints.portfolioHoldings, method: "GET")
    }

    func getPnl(period: String) async throws -> PnlResponse {
        let url = APIEndpoints.url(path: APIEndpoints.pnl, queryItems: [URLQueryItem(name: "period", value: period)])
        return try await request(url: url, method: "GET")
    }

    func getAllocation() async throws -> AllocationResponse {
        try await request(path: APIEndpoints.allocation, method: "GET")
    }

    func getExposure() async throws -> ExposureResponse {
        try await request(path: APIEndpoints.exposure, method: "GET")
    }

    func getEarnSummary() async throws -> EarnSummaryResponse {
        try await request(path: APIEndpoints.earnSummary, method: "GET")
    }

    func getAICommentary() async throws -> AICommentary {
        let url = APIEndpoints.url(path: APIEndpoints.aiCommentary)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            if let commentary = try? decoder.decode(AICommentary.self, from: data) {
                return commentary
            }
            if let errorResponse = try? decoder.decode(ErrorMessageResponse.self, from: data) {
                return AICommentary(date: "", text: "", model: nil, error: errorResponse.error, sections: nil)
            }
            throw APIError.invalidResponse
        case 404:
            if let errorResponse = try? decoder.decode(ErrorMessageResponse.self, from: data) {
                return AICommentary(date: "", text: "", model: nil, error: errorResponse.error, sections: nil)
            }
            return AICommentary(date: "", text: "", model: nil, error: "No AI commentary cached", sections: nil)
        default:
            throw APIError.httpStatus(httpResponse.statusCode)
        }
    }

    func generateAICommentary() async throws {
        try await requestVoid(path: APIEndpoints.aiCommentary, method: "POST")
    }

    func getCommentaryStatus() async throws -> CommentaryStatus {
        try await request(path: APIEndpoints.aiCommentaryStatus, method: "GET")
    }

    func getAIConfig() async throws -> AIConfig {
        try await request(path: APIEndpoints.aiConfig, method: "GET")
    }

    func updateAIConfig(_ requestBody: AIConfigUpdateRequest) async throws {
        _ = try await requestVoid(path: APIEndpoints.aiConfig, method: "PUT", body: requestBody)
    }

    func startCollect(source: String?) async throws -> CollectStartResponse {
        let body = CollectStartRequest(source: source)
        return try await request(path: APIEndpoints.collect, method: "POST", body: body)
    }

    func getCollectStatus() async throws -> CollectStatus {
        try await request(path: APIEndpoints.collectStatus, method: "GET")
    }

    func notifyReport() async throws -> NotifyResponse {
        try await request(path: APIEndpoints.reportNotify, method: "POST")
    }

    // MARK: - Updates

    func getUpdates() async throws -> UpdatesResponse {
        try await request(path: APIEndpoints.updates, method: "GET")
    }

    func installUpdate(target: String) async throws {
        let body = InstallUpdateRequest(target: target)
        _ = try await requestVoid(path: APIEndpoints.updatesInstall, method: "POST", body: body)
    }

    func forceCheckUpdates() async throws -> UpdatesResponse {
        try await request(path: APIEndpoints.updatesCheck, method: "POST")
    }

    func getUpdateStatus() async throws -> UpdateStatusResponse {
        try await request(path: APIEndpoints.updatesStatus, method: "GET")
    }

    func restartServices() async throws {
        _ = try await requestVoid(path: APIEndpoints.updatesRestart, method: "POST")
    }

    func getSettings() async throws -> SettingsResponse {
        try await request(path: APIEndpoints.settings, method: "GET")
    }

    func updateSettings(_ settings: [String: String]) async throws {
        _ = try await requestVoid(path: APIEndpoints.settings, method: "PUT", body: settings)
    }

    func upsertAIProviderFields(type: String, fields: [String: String]) async throws {
        _ = try await requestVoid(path: APIEndpoints.aiProvider(type), method: "PUT", body: fields)
    }

    func validateAIProviderConnection(type: String, fields: [String: String]) async throws -> ConnectionValidationResponse {
        try await requestValidation(path: APIEndpoints.aiProviderValidate(type), method: "POST", body: fields)
    }

    func activateAIProvider(type: String) async throws {
        _ = try await requestVoid(path: APIEndpoints.aiProviderActivate(type), method: "POST")
    }

    func deactivateAIProvider() async throws {
        _ = try await requestVoid(path: APIEndpoints.aiProvidersDeactivate, method: "POST")
    }

    func deleteAIProvider(type: String) async throws {
        _ = try await requestVoid(path: APIEndpoints.aiProvider(type), method: "DELETE")
    }

    private func request<T: Decodable>(path: String, method: String, body: Encodable? = nil, timeout: TimeInterval? = nil) async throws -> T {
        let url = APIEndpoints.url(path: path)
        return try await request(url: url, method: method, body: body, timeout: timeout)
    }

    private func request<T: Decodable>(url: URL, method: String, body: Encodable? = nil, timeout: TimeInterval? = nil) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpStatus(httpResponse.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func requestVoid(path: String, method: String, body: Encodable? = nil) async throws {
        let url = APIEndpoints.url(path: path)
        _ = try await requestVoid(url: url, method: method, body: body)
    }

    private func requestVoid(url: URL, method: String, body: Encodable? = nil) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(ErrorMessageResponse.self, from: data) {
                throw APIError.message(error.error)
            }
            throw APIError.httpStatus(httpResponse.statusCode)
        }
    }

    private func requestValidation<T: Decodable>(path: String, method: String, body: Encodable? = nil) async throws -> T {
        let url = APIEndpoints.url(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ValidationRequestError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 || httpResponse.statusCode == 405 {
                throw ValidationRequestError.message(
                    "Connection checks require a newer lurii-pfm backend. Update the local service and retry."
                )
            }
            if let error = try? decoder.decode(ErrorMessageResponse.self, from: data) {
                throw ValidationRequestError.message(error.error)
            }
            throw ValidationRequestError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ValidationRequestError.invalidResponse
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        encodeFunc = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
