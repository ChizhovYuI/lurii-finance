import AppKit
import CryptoKit
import Foundation
import WebKit

enum WebSyncTrigger {
    case manual
    case automatic
}

enum WebSyncCoordinatorError: LocalizedError {
    case missingSession(String)
    case invalidResponse(String)
    case unsupportedConfiguration(String)
    case networkFailure(String)
    case reconnectRequired(String)

    var errorDescription: String? {
        switch self {
        case let .missingSession(message),
             let .invalidResponse(message),
             let .unsupportedConfiguration(message),
             let .networkFailure(message),
             let .reconnectRequired(message):
            return message
        }
    }
}

private struct WebSyncCapture {
    let uid: String
    let capturedAt: String
    let kind: String
    let endpoint: String
    let pageURL: String
    let account: [String: Any]
    let summary: [String: Any]
    let assets: [[String: Any]]
    let rawPayload: [String: Any]
    let userInfoRaw: [String: Any]?
}

private final class ConnectSession {
    let id = UUID()
    let host: WebSyncWebViewHost
    let authTask: Task<[HTTPCookie], Error>

    init(host: WebSyncWebViewHost, authTask: Task<[HTTPCookie], Error>) {
        self.host = host
        self.authTask = authTask
    }
}

@MainActor
final class WebSyncCoordinator {
    var onStatusChange: ((WebSyncProvider, WebSyncStatus) -> Void)?

    private let sessionStore = WebSyncCookieSessionStore()
    private let defaults: UserDefaults
    private var statuses: [WebSyncProvider: WebSyncStatus] = [:]
    private var inFlightProviders: Set<WebSyncProvider> = []
    private var connectSessions: [WebSyncProvider: ConnectSession] = [:]
    private let localeDateFormatter: DateFormatter
    private static let dailySyncDefaultsPrefix = "websync.last_success_utc_day."
    private static let automaticInteractiveAuthPromptDefaultsPrefix = "websync.last_auto_auth_prompt_local_day."
    private static let baseMexcHeaders: [String: String] = [
        "Accept": "*/*",
        "Language": Locale.preferredLanguages.first ?? "en-US",
        "Origin": "https://www.mexc.com",
        "Referer": "https://www.mexc.com/earn"
    ]
    private static let mexcEarnEndpoint = "https://www.mexc.com/api/financialactivity/financial/member/positions_by_product"
    private static let mexcUserInfoEndpoint = "https://www.mexc.com/ucenter/api/user_info"
    private static let emcdDepositsEndpoint = "https://endpoint.emcd.io/deposit-staking/deposit/active"
    private static let emcdRatesEndpoint = "https://rate.emcd.io/statsv2?emcd=1"
    private static let emcdTokenRefreshTimeoutSeconds: TimeInterval = 90
    private static let emcdTokenRefreshPollMilliseconds: UInt64 = 500
    private static let emcdMinimumTokenLifetimeSeconds: TimeInterval = 120
    private static let mexcSessionValidationIntervalSeconds: TimeInterval = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for provider in WebSyncProvider.allCases {
            statuses[provider] = .idle
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        localeDateFormatter = formatter
    }

    func status(for provider: WebSyncProvider) -> WebSyncStatus {
        statuses[provider] ?? .idle
    }

    func connect(provider: WebSyncProvider) async {
        if let existing = connectSessions[provider] {
            existing.host.window.makeKeyAndOrderFront(nil)
            updateStatus(provider) { status in
                status.errorMessage = nil
                status.message = "Complete login in browser window."
            }
            return
        }

        let host = WebSyncWebViewHost(title: "Connect \(provider.displayName)", mode: .visible)
        await sessionStore.restoreCookies(into: host.cookieStore, provider: provider)
        host.loadForDisplay(url: provider.loginURL)
        updateStatus(provider) { status in
            status.errorMessage = nil
            status.message = "Complete login in browser window."
        }

        let authTask = Task<[HTTPCookie], Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.waitForAuthorizedCookies(
                provider: provider,
                host: host,
                timeout: nil,
                closeMessage: "\(provider.displayName) connect window was closed before login completed.",
                timeoutMessage: "\(provider.displayName) login did not complete."
            )
        }
        let session = ConnectSession(host: host, authTask: authTask)
        connectSessions[provider] = session

        host.onWindowWillClose = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.connectSessions[provider]?.id == session.id else { return }
                self.connectSessions[provider] = nil
                await self.sessionStore.saveCookies(from: host.cookieStore, provider: provider)
                if !self.status(for: provider).isSyncing {
                    self.updateStatus(provider) { status in
                        guard status.errorMessage == nil else { return }
                        if status.message == "Complete login in browser window." {
                            status.message = "Connect canceled. Use Connect or Sync now."
                        }
                    }
                }
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let cookies = try await authTask.value
                guard self.connectSessions[provider]?.id == session.id else { return }
                self.sessionStore.persistCookies(cookies, provider: provider)
                if !self.status(for: provider).isSyncing {
                    self.updateStatus(provider) { status in
                        status.errorMessage = nil
                        status.message = "Connected. Run Sync now."
                    }
                }
                host.close()
            } catch is CancellationError {
                return
            } catch {
                guard self.connectSessions[provider]?.id == session.id else { return }
                guard !host.isClosed else { return }
                self.updateStatus(provider) { status in
                    status.errorMessage = error.localizedDescription
                    status.message = nil
                }
                host.close()
            }
        }
    }

    @discardableResult
    func syncNow(provider: WebSyncProvider, trigger: WebSyncTrigger = .manual) async -> Bool {
        guard !inFlightProviders.contains(provider) else {
            updateStatus(provider) { status in
                status.message = "Sync already in progress."
            }
            return false
        }

        inFlightProviders.insert(provider)
        updateStatus(provider) { status in
            status.isSyncing = true
            status.errorMessage = nil
            status.message = "Syncing \(provider.displayName)..."
        }

        defer {
            inFlightProviders.remove(provider)
            updateStatus(provider) { status in
                status.isSyncing = false
            }
        }

        do {
            let capture = try await collectCapture(provider: provider, trigger: trigger)
            let sources = try await APIClient.shared.getSources()
            try await ensureSource(provider: provider, identity: capture.uid, existingSources: sources)
            let payload = try buildExtensionPayload(provider: provider, capture: capture)
            try await APIClient.shared.postExtSnapshot(
                sourceType: provider.sourceType,
                uid: capture.uid,
                payloadData: payload
            )

            let now = Date()
            markSuccessfulDailySync(provider: provider, at: now)
            updateStatus(provider) { status in
                status.lastSyncedAt = now
                status.errorMessage = nil
                status.message = "Synced at \(localeDateFormatter.string(from: now))."
            }
            return true
        } catch let error as WebSyncCoordinatorError {
            switch error {
            case let .reconnectRequired(message):
                updateStatus(provider) { status in
                    status.errorMessage = nil
                    status.message = message
                }
            default:
                updateStatus(provider) { status in
                    status.errorMessage = error.localizedDescription
                    status.message = nil
                }
            }
            return false
        } catch {
            let message = error.localizedDescription
            updateStatus(provider) { status in
                status.errorMessage = message
                status.message = nil
            }
            return false
        }
    }

    func runDailySyncIfNeeded(sources: [SourceDTO]) async {
        let now = Date()
        for provider in WebSyncProvider.allCases {
            let enabledProviderSources = sources.filter { source in
                source.enabled && source.type.lowercased() == provider.sourceType
            }
            guard !enabledProviderSources.isEmpty else { continue }
            guard shouldRunDailySync(provider: provider, now: now) else { continue }
            _ = await syncNow(provider: provider, trigger: .automatic)
        }
    }

    private func updateStatus(_ provider: WebSyncProvider, mutate: (inout WebSyncStatus) -> Void) {
        var next = statuses[provider] ?? .idle
        mutate(&next)
        statuses[provider] = next
        onStatusChange?(provider, next)
    }

    private func collectCapture(provider: WebSyncProvider, trigger: WebSyncTrigger) async throws -> WebSyncCapture {
        switch provider {
        case .mexc:
            let cookies = try await authorizedCookiesForSync(provider: .mexc, trigger: trigger)
            guard let headers = mexcHeaders(from: cookies) else {
                throw WebSyncCoordinatorError.missingSession("MEXC session is unavailable. Use Connect or Sync now.")
            }
            return try await collectMexcCapture(headers: headers)
        case .emcd:
            let cookies = try await authorizedCookiesForSync(provider: .emcd, trigger: trigger)
            guard let token = emcdAccessToken(from: cookies),
                  tokenHasSufficientRemainingLifetime(
                      token,
                      minimumSeconds: Self.emcdMinimumTokenLifetimeSeconds
                  ) else {
                throw WebSyncCoordinatorError.missingSession("EMCD session is unavailable. Use Connect or Sync now.")
            }
            return try await collectEmcdCapture(token: token)
        }
    }

    private func collectMexcCapture(headers: [String: String]) async throws -> WebSyncCapture {
        let earnAny = try await performJSONRequest(
            url: URL(string: Self.mexcEarnEndpoint)!,
            method: "GET",
            headers: headers
        )
        guard let earnPayload = earnAny as? [String: Any] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected MEXC earn response payload.")
        }
        let code = intValue(earnPayload["code"])
        guard code == 0 else {
            let msg = stringValue(earnPayload["msg"]) ?? "unknown"
            throw WebSyncCoordinatorError.networkFailure("MEXC earn request failed: code \(code), \(msg)")
        }
        guard let rows = earnPayload["data"] as? [[String: Any]] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected MEXC earn data format.")
        }

        let userInfoAny = try await performJSONRequest(
            url: URL(string: Self.mexcUserInfoEndpoint)!,
            method: "POST",
            headers: headers
        )
        guard let userInfoPayload = userInfoAny as? [String: Any] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected MEXC user info response payload.")
        }
        let userInfoCode = intValue(userInfoPayload["code"])
        guard userInfoCode == 0 else {
            let msg = stringValue(userInfoPayload["msg"]) ?? "unknown"
            throw WebSyncCoordinatorError.networkFailure("MEXC user info failed: code \(userInfoCode), \(msg)")
        }
        guard let userInfoData = userInfoPayload["data"] as? [String: Any] else {
            throw WebSyncCoordinatorError.invalidResponse("MEXC user info does not include data object.")
        }
        let digitalId = stringValue(userInfoData["digitalId"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !digitalId.isEmpty else {
            throw WebSyncCoordinatorError.invalidResponse("MEXC user info does not include digitalId.")
        }

        let assets = rows.compactMap { row -> [String: Any]? in
            let assetRaw = stringValue(row["pledgeCurrency"]) ?? stringValue(row["profitCurrency"]) ?? ""
            let asset = assetRaw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !asset.isEmpty else { return nil }
            let quantity = doubleValue(row["positionQuantity"])
            let usdValue = doubleValue(row["positionUsdtQuantity"])
            let quotedApr = doubleValue(row["showApr"])
            let yesterdayProfit = doubleValue(row["yesterdayProfitQuantity"])
            return [
                "symbol": asset,
                "amount": quantity,
                "usdValue": usdValue,
                "quotedAprPercent": quotedApr,
                "yesterdayProfitAmount": yesterdayProfit
            ]
        }

        let summary = summarizeAssets(assets)
        let account: [String: Any] = [
            "digitalId": digitalId,
            "memberId": stringValue(userInfoData["memberId"]) ?? "",
            "nickname": stringValue(userInfoData["nickname"]) ?? ""
        ]

        return WebSyncCapture(
            uid: digitalId,
            capturedAt: isoTimestamp(),
            kind: "earn_positions",
            endpoint: Self.mexcEarnEndpoint,
            pageURL: WebSyncProvider.mexc.loginURL.absoluteString,
            account: account,
            summary: summary,
            assets: assets,
            rawPayload: earnPayload,
            userInfoRaw: userInfoPayload
        )
    }

    private func collectEmcdCapture(token: String) async throws -> WebSyncCapture {
        let jwtPayload = decodeJWTPayload(token: token)
        let email = normalizeIdentity(provider: .emcd, stringValue(jwtPayload["email"]) ?? "")
        guard !email.isEmpty else {
            throw WebSyncCoordinatorError.invalidResponse("Cannot extract email from EMCD session token.")
        }
        let username = stringValue(jwtPayload["username"]) ?? ""

        let emcdHeaders = [
            "Accept": "application/json, text/plain, */*",
            "x-access-token": token
        ]
        let depositsAny = try await performJSONRequest(
            url: URL(string: Self.emcdDepositsEndpoint)!,
            method: "GET",
            headers: emcdHeaders
        )
        guard let depositsPayload = depositsAny as? [String: Any] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected EMCD deposits payload.")
        }
        guard let deposits = depositsPayload["deposits"] as? [[String: Any]] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected EMCD deposits format.")
        }

        let ratesAny = try await performJSONRequest(
            url: URL(string: Self.emcdRatesEndpoint)!,
            method: "GET",
            headers: ["Accept": "application/json, text/plain, */*"]
        )
        guard let ratesPayload = ratesAny as? [String: Any] else {
            throw WebSyncCoordinatorError.invalidResponse("Unexpected EMCD rates payload.")
        }
        var rates: [String: Double] = [
            "usdt": 1,
            "usdc": 1
        ]
        if let ratesData = ratesPayload["data"] as? [String: Any] {
            for (coin, value) in ratesData {
                guard let info = value as? [String: Any] else { continue }
                guard let usdRate = doubleOptionalValue(info["usd_rate"]) else { continue }
                rates[coin.lowercased()] = usdRate
            }
        }

        let assets = deposits.compactMap { deposit -> [String: Any]? in
            guard stringValue(deposit["status"]) == "open" else { return nil }
            let balance = doubleValue(deposit["balance"])
            guard balance > 0 else { return nil }
            guard let setting = deposit["setting"] as? [String: Any] else { return nil }
            let coin = (stringValue(setting["coin"]) ?? "").uppercased()
            guard !coin.isEmpty else { return nil }
            let quotedApr = doubleValue(setting["percent"])
            let usdRate = rates[coin.lowercased()] ?? 0
            return [
                "symbol": coin,
                "amount": balance,
                "usdValue": balance * usdRate,
                "quotedAprPercent": quotedApr,
                "yesterdayProfitAmount": 0
            ]
        }

        let summary = summarizeAssets(assets)
        let account: [String: Any] = [
            "digitalId": email,
            "username": username,
            "email": email
        ]
        return WebSyncCapture(
            uid: email,
            capturedAt: isoTimestamp(),
            kind: "coinhold_deposits",
            endpoint: Self.emcdDepositsEndpoint,
            pageURL: WebSyncProvider.emcd.loginURL.absoluteString,
            account: account,
            summary: summary,
            assets: assets,
            rawPayload: depositsPayload,
            userInfoRaw: nil
        )
    }

    private func mexcHeaders(from cookies: [HTTPCookie]) -> [String: String]? {
        let cookieHeader = cookiesHeader(cookies: cookies, domainSuffix: WebSyncProvider.mexc.cookieDomainSuffix)
        guard !cookieHeader.isEmpty else { return nil }
        var headers = Self.baseMexcHeaders
        headers["Cookie"] = cookieHeader
        return headers
    }

    private func authorizedCookiesForSync(
        provider: WebSyncProvider,
        trigger: WebSyncTrigger
    ) async throws -> [HTTPCookie] {
        if let cookies = await authorizedCookiesIfAvailable(provider: provider) {
            return cookies
        }

        if let session = connectSessions[provider] {
            updateStatus(provider) { status in
                status.errorMessage = nil
                status.message = "Finish login in browser window to continue sync."
            }
            let cookies = try await waitForAuthorizedCookies(
                provider: provider,
                host: session.host,
                timeout: Self.emcdTokenRefreshTimeoutSeconds,
                closeMessage: "\(provider.displayName) window was closed before login completed.",
                timeoutMessage: "\(provider.displayName) session was not refreshed. Keep the window open until relogin finishes, then run Sync now again."
            )
            sessionStore.persistCookies(cookies, provider: provider)
            return cookies
        }

        switch trigger {
        case .manual:
            return try await requestInteractiveAuthorization(provider: provider, trigger: trigger)
        case .automatic:
            let now = Date()
            guard shouldAttemptAutomaticInteractiveAuth(provider: provider, now: now) else {
                throw WebSyncCoordinatorError.reconnectRequired(
                    "Reconnect required. Use Connect or Sync now. Auto-open paused until tomorrow."
                )
            }
            markAutomaticInteractiveAuthPrompt(provider: provider, at: now)
            return try await requestInteractiveAuthorization(provider: provider, trigger: trigger)
        }
    }

    private func requestInteractiveAuthorization(
        provider: WebSyncProvider,
        trigger: WebSyncTrigger
    ) async throws -> [HTTPCookie] {
        let host = WebSyncWebViewHost(title: "\(provider.displayName) Sync", mode: .visible)
        defer {
            host.close()
        }

        await sessionStore.restoreCookies(into: host.cookieStore, provider: provider)
        host.loadForDisplay(url: provider.loginURL)
        updateStatus(provider) { status in
            status.errorMessage = nil
            switch trigger {
            case .manual:
                status.message = "Finish login in browser window to continue sync."
            case .automatic:
                status.message = "Finish login in browser window to continue automatic sync."
            }
        }

        let cookies = try await waitForAuthorizedCookies(
            provider: provider,
            host: host,
            timeout: Self.emcdTokenRefreshTimeoutSeconds,
            closeMessage: "\(provider.displayName) window was closed before login completed.",
            timeoutMessage: "\(provider.displayName) session was not refreshed. Keep the window open until relogin finishes, then run Sync now again."
        )
        sessionStore.persistCookies(cookies, provider: provider)
        return cookies
    }

    private func waitForAuthorizedCookies(
        provider: WebSyncProvider,
        host: WebSyncWebViewHost,
        timeout: TimeInterval?,
        closeMessage: String,
        timeoutMessage: String
    ) async throws -> [HTTPCookie] {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var lastMexcValidationAt = Date.distantPast

        while true {
            if Task.isCancelled {
                throw CancellationError()
            }
            if host.isClosed {
                throw WebSyncCoordinatorError.missingSession(closeMessage)
            }

            let cookies = await host.cookieStore.allCookies()
            switch provider {
            case .mexc:
                if let headers = mexcHeaders(from: cookies),
                   Date().timeIntervalSince(lastMexcValidationAt) >= Self.mexcSessionValidationIntervalSeconds {
                    lastMexcValidationAt = Date()
                    if await mexcSessionLooksAuthorized(headers: headers) {
                        return cookies
                    }
                }
            case .emcd:
                if let token = emcdAccessToken(from: cookies),
                   !token.isEmpty,
                   tokenHasSufficientRemainingLifetime(
                       token,
                       minimumSeconds: Self.emcdMinimumTokenLifetimeSeconds
                   ) {
                    return cookies
                }
            }

            if let deadline, Date() >= deadline {
                throw WebSyncCoordinatorError.missingSession(timeoutMessage)
            }

            try? await Task.sleep(nanoseconds: Self.emcdTokenRefreshPollMilliseconds * 1_000_000)
        }
    }

    private func authorizedCookiesIfAvailable(provider: WebSyncProvider) async -> [HTTPCookie]? {
        let cookies = await resolveCookies(provider: provider)
        guard await sessionIsAuthorized(provider: provider, cookies: cookies) else { return nil }
        return cookies
    }

    private func sessionIsAuthorized(provider: WebSyncProvider, cookies: [HTTPCookie]) async -> Bool {
        switch provider {
        case .mexc:
            guard let headers = mexcHeaders(from: cookies) else { return false }
            return await mexcSessionLooksAuthorized(headers: headers)
        case .emcd:
            guard let token = emcdAccessToken(from: cookies), !token.isEmpty else { return false }
            return tokenHasSufficientRemainingLifetime(
                token,
                minimumSeconds: Self.emcdMinimumTokenLifetimeSeconds
            )
        }
    }

    private func mexcSessionLooksAuthorized(headers: [String: String]) async -> Bool {
        guard let payload = try? await performJSONRequest(
            url: URL(string: Self.mexcUserInfoEndpoint)!,
            method: "POST",
            headers: headers
        ) as? [String: Any] else {
            return false
        }
        guard intValue(payload["code"]) == 0 else { return false }
        guard let data = payload["data"] as? [String: Any] else { return false }
        let digitalId = stringValue(data["digitalId"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !digitalId.isEmpty
    }

    private func summarizeAssets(_ assets: [[String: Any]]) -> [String: Any] {
        let totalAmount = assets.reduce(0.0) { partial, asset in
            partial + doubleValue(asset["amount"])
        }
        let totalUsdValue = assets.reduce(0.0) { partial, asset in
            partial + doubleValue(asset["usdValue"])
        }
        let totalYesterdayProfit = assets.reduce(0.0) { partial, asset in
            partial + doubleValue(asset["yesterdayProfitAmount"])
        }
        let weightedAprPercent: Double
        if totalAmount > 0 {
            let weighted = assets.reduce(0.0) { partial, asset in
                partial + doubleValue(asset["quotedAprPercent"]) * doubleValue(asset["amount"])
            }
            weightedAprPercent = weighted / totalAmount
        } else {
            weightedAprPercent = 0
        }

        let realizedDailyRate = totalAmount > 0 ? totalYesterdayProfit / totalAmount : 0
        let realizedApyPercent: Double
        if realizedDailyRate > -1 {
            realizedApyPercent = (pow(1 + realizedDailyRate, 365) - 1) * 100
        } else {
            realizedApyPercent = 0
        }

        return [
            "positionCount": assets.count,
            "totalAmount": totalAmount,
            "totalUsdValue": totalUsdValue,
            "quotedAprPercent": weightedAprPercent,
            "yesterdayProfitAmount": totalYesterdayProfit,
            "realizedApyPercent": realizedApyPercent
        ]
    }

    private func performJSONRequest(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data? = nil
    ) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.httpBody = body
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebSyncCoordinatorError.invalidResponse("Invalid HTTP response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw WebSyncCoordinatorError.networkFailure("HTTP \(httpResponse.statusCode): \(preview)")
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WebSyncCoordinatorError.invalidResponse("Non-JSON response from \(url.host ?? "remote host").")
        }
    }

    private func buildExtensionPayload(provider: WebSyncProvider, capture: WebSyncCapture) throws -> Data {
        let producerVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let payload: [String: Any] = [
            "schemaVersion": "lurii.extension.snapshot.v1",
            "eventType": "snapshot.capture",
            "capturedAt": capture.capturedAt,
            "producer": [
                "app": "lurii-finance-macos-app",
                "version": producerVersion,
                "provider": provider.rawValue
            ],
            "source": [
                "type": provider.sourceType,
                "uid": capture.uid
            ],
            "snapshot": [
                "summary": capture.summary,
                "assets": capture.assets
            ],
            "context": [
                "endpoint": capture.endpoint,
                "pageUrl": capture.pageURL,
                "account": capture.account
            ],
            "providerPayload": [
                "kind": capture.kind,
                "raw": capture.rawPayload,
                "userInfoRaw": capture.userInfoRaw as Any? ?? NSNull()
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func ensureSource(
        provider: WebSyncProvider,
        identity: String,
        existingSources: [SourceDTO]
    ) async throws {
        let normalizedIdentity = normalizeIdentity(provider: provider, identity)
        let providerSources = existingSources.filter { source in
            source.type.lowercased() == provider.sourceType
        }

        if providerSources.count > 1 {
            throw WebSyncCoordinatorError.unsupportedConfiguration(
                "Multiple \(provider.displayName) sources found. Keep one source for app sync."
            )
        }

        let matching = providerSources.filter { source in
            normalizeIdentity(provider: provider, source.credentials[provider.identityCredentialKey] ?? "") == normalizedIdentity
        }

        if matching.count > 1 {
            throw WebSyncCoordinatorError.unsupportedConfiguration(
                "Multiple \(provider.displayName) sources match the same account identity."
            )
        }

        if matching.count == 1 {
            return
        }

        if let existing = providerSources.first {
            let configuredIdentity = existing.credentials[provider.identityCredentialKey] ?? "unknown"
            throw WebSyncCoordinatorError.unsupportedConfiguration(
                "Connected account \(identity) does not match source \(existing.name) (\(configuredIdentity))."
            )
        }

        let sourceName = sourceNameForNewSource(provider: provider, identity: normalizedIdentity)
        let credentials = [provider.identityCredentialKey: normalizedIdentity]

        do {
            try await APIClient.shared.createSource(
                SourceCreateRequest(
                    name: sourceName,
                    type: provider.sourceType,
                    credentials: credentials
                )
            )
        } catch {
            let refreshed = try await APIClient.shared.getSources()
            let refreshedMatches = refreshed.filter { source in
                source.type.lowercased() == provider.sourceType &&
                    normalizeIdentity(provider: provider, source.credentials[provider.identityCredentialKey] ?? "") == normalizedIdentity
            }
            if refreshedMatches.count == 1 {
                return
            }
            throw error
        }
    }

    private func sourceNameForNewSource(provider: WebSyncProvider, identity: String) -> String {
        switch provider {
        case .mexc:
            return "mexc-earn-\(sanitizeSourceNameComponent(identity))"
        case .emcd:
            let sanitized = sanitizeSourceNameComponent(identity)
            if !sanitized.isEmpty {
                return "emcd-\(sanitized)"
            }
            return "emcd-\(shortSHA256(identity))"
        }
    }

    private func sanitizeSourceNameComponent(_ value: String) -> String {
        let lowercased = value.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var sanitized = ""
        var previousWasSeparator = false
        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                sanitized.append("-")
                previousWasSeparator = true
            }
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if sanitized.count > 40 {
            return String(sanitized.prefix(40))
        }
        return sanitized
    }

    private func shortSHA256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(10))
    }

    private func shouldRunDailySync(provider: WebSyncProvider, now: Date) -> Bool {
        let key = Self.dailySyncDefaultsPrefix + provider.rawValue
        let currentDay = utcDayString(for: now)
        return defaults.string(forKey: key) != currentDay
    }

    private func markSuccessfulDailySync(provider: WebSyncProvider, at date: Date) {
        defaults.set(utcDayString(for: date), forKey: Self.dailySyncDefaultsPrefix + provider.rawValue)
    }

    private func shouldAttemptAutomaticInteractiveAuth(provider: WebSyncProvider, now: Date) -> Bool {
        let key = Self.automaticInteractiveAuthPromptDefaultsPrefix + provider.rawValue
        let currentDay = localDayString(for: now)
        return defaults.string(forKey: key) != currentDay
    }

    private func markAutomaticInteractiveAuthPrompt(provider: WebSyncProvider, at date: Date) {
        defaults.set(
            localDayString(for: date),
            forKey: Self.automaticInteractiveAuthPromptDefaultsPrefix + provider.rawValue
        )
    }

    private func utcDayString(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func localDayString(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func cookiesHeader(cookies: [HTTPCookie], domainSuffix: String) -> String {
        cookies
            .filter { cookie in
                cookie.domain.lowercased().contains(domainSuffix)
            }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    private func resolveCookies(provider: WebSyncProvider) async -> [HTTPCookie] {
        if let session = connectSessions[provider] {
            let liveCookies = await session.host.cookieStore.allCookies()
            sessionStore.persistCookies(liveCookies, provider: provider)
            return liveCookies
        }
        return sessionStore.persistedCookies(provider: provider)
    }

    private func emcdAccessToken(from cookies: [HTTPCookie]) -> String? {
        cookies.first(where: { cookie in
            cookie.name == "auth__access_token" &&
                cookie.domain.lowercased().contains(WebSyncProvider.emcd.cookieDomainSuffix)
        })?.value
    }

    private func decodeJWTPayload(token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        let payloadPart = String(parts[1])
        let base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - base64.count % 4) % 4
        let padded = base64 + String(repeating: "=", count: paddingLength)
        guard let data = Data(base64Encoded: padded) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return object as? [String: Any] ?? [:]
    }

    private func tokenHasSufficientRemainingLifetime(
        _ token: String,
        minimumSeconds: TimeInterval
    ) -> Bool {
        let payload = decodeJWTPayload(token: token)
        let exp: TimeInterval?
        if let intExp = payload["exp"] as? Int {
            exp = TimeInterval(intExp)
        } else if let doubleExp = payload["exp"] as? Double {
            exp = doubleExp
        } else if let stringExp = payload["exp"] as? String, let parsed = Double(stringExp) {
            exp = parsed
        } else {
            // If no exp is present, don't block sync on this check.
            return true
        }

        guard let exp else { return true }
        let remaining = Date(timeIntervalSince1970: exp).timeIntervalSinceNow
        return remaining >= minimumSeconds
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func normalizeIdentity(provider: WebSyncProvider, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .mexc:
            return trimmed
        case .emcd:
            return trimmed.lowercased()
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let int = value as? Int {
            return String(int)
        }
        if let double = value as? Double {
            return String(double)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int {
            return int
        }
        if let string = value as? String, let int = Int(string) {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        return -1
    }

    private func doubleOptionalValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double {
        doubleOptionalValue(value) ?? 0
    }
}
