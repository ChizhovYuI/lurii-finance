import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case message(String)
    /// `409 Conflict` — the resource already exists (e.g. duplicate category).
    case conflict(String)
    /// `423 Locked` — the local database is locked (SQLCipher). Routes to the unlock flow.
    case locked

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case let .httpStatus(code):
            return "Request failed with status \(code)."
        case let .message(message):
            return message
        case let .conflict(message):
            return message
        case .locked:
            return "The local database is locked. Unlock it to continue."
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

    func getCashManual() async throws -> CashManualState {
        try await request(path: APIEndpoints.cashManual, method: "GET")
    }

    func upsertCashManual(_ requestBody: CashManualUpsertRequest) async throws -> CashManualState {
        try await request(path: APIEndpoints.cashManual, method: "PUT", body: requestBody)
    }

    func postExtSnapshot(sourceType: String, uid: String, payloadData: Data) async throws {
        let url = APIEndpoints.url(
            path: APIEndpoints.extSnapshot,
            queryItems: [
                URLQueryItem(name: "source_type", value: sourceType),
                URLQueryItem(name: "uid", value: uid)
            ]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payloadData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
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

    // MARK: - Earn Overrides

    func getEarnOverrides(sourceName: String) async throws -> EarnOverridesResponse {
        try await request(path: APIEndpoints.sourceEarnOverrides(sourceName), method: "GET")
    }

    func setEarnOverrides(sourceName: String, body: EarnOverridesSaveRequest) async throws -> EarnOverridesResponse {
        try await request(path: APIEndpoints.sourceEarnOverrides(sourceName), method: "PUT", body: body)
    }

    func deleteEarnOverrides(sourceName: String) async throws {
        _ = try await requestVoid(path: APIEndpoints.sourceEarnOverrides(sourceName), method: "DELETE")
    }

    func getPortfolioSummary() async throws -> PortfolioSummary {
        try await request(path: APIEndpoints.portfolioSummary, method: "GET")
    }

    func getPortfolioNetWorthHistory(days: Int) async throws -> NetWorthHistoryResponse {
        let url = APIEndpoints.url(
            path: APIEndpoints.portfolioNetWorthHistory,
            queryItems: [URLQueryItem(name: "days", value: String(days))]
        )
        return try await request(url: url, method: "GET")
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

    func getSourceMovers() async throws -> SourceMoversResponse {
        try await request(path: APIEndpoints.sourceMovers, method: "GET")
    }

    func getExposure() async throws -> ExposureResponse {
        try await request(path: APIEndpoints.exposure, method: "GET")
    }

    func getEarnSummary() async throws -> EarnSummaryResponse {
        try await request(path: APIEndpoints.earnSummary, method: "GET")
    }

    func getEarnHistory(days: Int) async throws -> EarnHistoryResponse {
        let url = APIEndpoints.url(
            path: APIEndpoints.earnHistory,
            queryItems: [URLQueryItem(name: "days", value: String(days))]
        )
        return try await request(url: url, method: "GET")
    }

    func startCollect(source: String?) async throws -> CollectStartResponse {
        let body = CollectStartRequest(source: source)
        return try await request(path: APIEndpoints.collect, method: "POST", body: body)
    }

    func getCollectStatus() async throws -> CollectStatus {
        try await request(path: APIEndpoints.collectStatus, method: "GET")
    }

    // MARK: - Transactions

    func getTransactions(sourceName: String? = nil, txType: String? = nil, category: String? = nil, search: String? = nil, month: String? = nil) async throws -> TransactionsListResponse {
        var queryItems: [URLQueryItem] = []
        if let month { queryItems.append(URLQueryItem(name: "month", value: month)) }
        if let sourceName { queryItems.append(URLQueryItem(name: "source_name", value: sourceName)) }
        if let txType { queryItems.append(URLQueryItem(name: "tx_type", value: txType)) }
        if let category { queryItems.append(URLQueryItem(name: "category", value: category)) }
        if let search { queryItems.append(URLQueryItem(name: "search", value: search)) }
        let url = APIEndpoints.url(path: APIEndpoints.transactions, queryItems: queryItems)
        return try await request(url: url, method: "GET")
    }

    func getTransaction(id: Int) async throws -> TransactionDTO {
        try await request(path: APIEndpoints.transactionDetail(id), method: "GET")
    }

    func updateTransactionMetadata(id: Int, body: TransactionMetadataUpdateRequest) async throws {
        _ = try await requestVoid(path: APIEndpoints.transactionMetadata(id), method: "PUT", body: body)
    }

    func getTransactionCategories() async throws -> [TransactionCategoryDTO] {
        try await request(path: APIEndpoints.transactionCategories, method: "GET")
    }

    func createCategory(txType: String, category: String, displayName: String) async throws -> TransactionCategoryDTO {
        let body: [String: String] = ["tx_type": txType, "category": category, "display_name": displayName]
        return try await request(path: APIEndpoints.transactionCategories, method: "POST", body: body)
    }

    func getTrends(start: String? = nil, end: String? = nil, granularity: String = "month") async throws -> TrendsResponse {
        var queryItems = [URLQueryItem(name: "granularity", value: granularity)]
        if let start { queryItems.append(URLQueryItem(name: "start", value: start)) }
        if let end { queryItems.append(URLQueryItem(name: "end", value: end)) }
        let url = APIEndpoints.url(path: APIEndpoints.transactionAnalyticsTrends, queryItems: queryItems)
        return try await request(url: url, method: "GET")
    }

    func getTransactionReviewQueue(limit: Int = 50) async throws -> TransactionsListResponse {
        let url = APIEndpoints.url(path: APIEndpoints.transactionReviewQueue, queryItems: [
            URLQueryItem(name: "limit", value: String(limit))
        ])
        return try await request(url: url, method: "GET")
    }

    func setTransactionCategory(id: Int, category: String) async throws -> SetCategoryResponse {
        try await request(path: APIEndpoints.transactionCategory(id), method: "PUT", body: SetCategoryRequest(category: category))
    }

    func setTransactionType(id: Int, type: String) async throws {
        _ = try await requestVoid(path: APIEndpoints.transactionType(id), method: "PUT", body: SetTypeRequest(type: type))
    }

    func uploadStatement(fileData: Data, filename: String = "statement.csv") async throws -> StatementUploadResponse {
        let url = APIEndpoints.url(path: APIEndpoints.statementUpload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
        return try JSONDecoder().decode(StatementUploadResponse.self, from: data)
    }

    func getTransferCandidates(id: Int, source: String? = nil) async throws -> TransferCandidatesResponse {
        var queryItems: [URLQueryItem] = []
        if let source { queryItems.append(URLQueryItem(name: "source", value: source)) }
        let url = APIEndpoints.url(path: APIEndpoints.transactionTransferCandidates(id), queryItems: queryItems)
        return try await request(url: url, method: "GET")
    }

    func linkTransfer(txIdA: Int, txIdB: Int) async throws {
        let body = TransactionLinkRequest(txIdA: txIdA, txIdB: txIdB)
        _ = try await requestVoid(path: APIEndpoints.transactionLinkTransfer, method: "POST", body: body)
    }

    func unlinkTransfer(id: Int) async throws {
        _ = try await requestVoid(path: APIEndpoints.transactionUnlink(id), method: "DELETE")
    }

    func getTransactionAnalyticsSummary(start: String? = nil, end: String? = nil) async throws -> TransactionAnalyticsSummary {
        var queryItems: [URLQueryItem] = []
        if let start { queryItems.append(URLQueryItem(name: "start", value: start)) }
        if let end { queryItems.append(URLQueryItem(name: "end", value: end)) }
        let url = APIEndpoints.url(path: APIEndpoints.transactionAnalyticsSummary, queryItems: queryItems)
        return try await request(url: url, method: "GET")
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
            throw apiError(statusCode: httpResponse.statusCode, data: data)
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
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Maps a non-2xx response to a typed `APIError`, decoding the backend's
    /// `{"error": "..."}` body when present. `423` also notifies the app so it can
    /// route to the unlock flow.
    private func apiError(statusCode: Int, data: Data) -> APIError {
        let message = (try? decoder.decode(ErrorMessageResponse.self, from: data))?.error
        switch statusCode {
        case 423:
            NotificationCenter.default.post(name: .databaseLocked, object: nil)
            return .locked
        case 409:
            return .conflict(message ?? "This item already exists.")
        default:
            if let message { return .message(message) }
            return .httpStatus(statusCode)
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
