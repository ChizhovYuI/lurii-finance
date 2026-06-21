import AppKit
import SwiftUI
import Combine
import OSLog

@MainActor
final class AppState: ObservableObject {
    private static let logger = Logger(subsystem: "money.lurii.finance", category: "AppState")

    private enum UpdateRefreshMode {
        case regular
        case forced
    }

    private enum UpdateInstallStartResult {
        case started
        case alreadyInProgress
        case failed(String)
    }

    enum DaemonStatus: Equatable {
        case unknown
        case connected(version: String)
        case disconnected
    }

    enum AppSection: String, CaseIterable, Identifiable {
        case dashboard
        case allocation
        case earn
        case transactions
        case sources
        case about
        case changelog

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard:
                return "Dashboard"
            case .allocation:
                return "Allocation"
            case .earn:
                return "Earn"
            case .transactions:
                return "Transactions"
            case .sources:
                return "Sources"
            case .about:
                return "About"
            case .changelog:
                return "Changelog"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard:
                return "chart.bar.xaxis"
            case .allocation:
                return "chart.pie"
            case .earn:
                return "percent"
            case .transactions:
                return "list.bullet.rectangle"
            case .sources:
                return "tray.full"
            case .about:
                return "info.circle"
            case .changelog:
                return "clock.arrow.trianglehead.counterclockwise.rotate.90"
            }
        }
    }

    @Published var daemonStatus: DaemonStatus = .unknown
    @Published var selectedSection: AppSection = .dashboard
    @Published var collecting: Bool = false
    @Published var collectionProgress: Double = 0
    @Published var collectionMessage: String = ""
    @Published var valuing: Bool = false
    @Published var valuationProgress: Double = 0
    @Published var valuationMessage: String = ""
    @Published var updateStatus: String = "idle"
    @Published var updateInstalling: Bool = false
    @Published var updateProgress: Double = 0
    @Published var updateMessage: String = ""
    @Published var updateAvailable: Bool = false
    @Published var hideBalance: Bool = false
    @Published var globalSearchQuery: String = ""
    @Published var updates: UpdatesResponse?
    @Published var webSyncStatuses: [String: WebSyncStatus] = [:]

    private let eventStreamClient = EventStreamClient()
    private let webSyncCoordinator = WebSyncCoordinator()
    private var eventStreamConfigured = false
    private var updateCheckTask: Task<Void, Never>?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var autoInstallAttemptsByFingerprint: [String: Int] = [:]
    private var autoInstallInFlightFingerprint: String?
    private static let updateCheckInterval: TimeInterval = 3600
    private static let autoInstallRetryDelay: Duration = .seconds(4)
    private static let maxAutoInstallAttemptsPerFingerprint = 2

    init() {
        for provider in WebSyncProvider.allCases {
            webSyncStatuses[provider.rawValue] = webSyncCoordinator.status(for: provider)
        }
        webSyncCoordinator.onStatusChange = { [weak self] provider, status in
            guard let self else { return }
            var nextStatuses = self.webSyncStatuses
            nextStatuses[provider.rawValue] = status
            self.webSyncStatuses = nextStatuses
        }
    }

    var isConnected: Bool {
        if case .connected = daemonStatus {
            return true
        }
        return false
    }

    var runningAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var restartNeeded: Bool {
        restartNeeded(for: updates) || updateStatus == "installed"
    }

    var hasInstallableUpdate: Bool {
        guard let updates else { return false }
        return hasAnyInstallableUpdate(updates)
    }

    func updateFromHealth(_ health: HealthResponse) {
        daemonStatus = .connected(version: health.version)
        collecting = health.collecting
        startUpdateCheckLoop()
        Task { await runWebSyncDailyIfNeeded() }
    }

    func updateCollectStatus(_ status: CollectStatus) {
        collecting = status.collecting
    }

    func startEventStream() {
        guard !eventStreamConfigured else { return }
        eventStreamConfigured = true
        if appDidBecomeActiveObserver == nil {
            appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.runWebSyncDailyIfNeeded()
                }
            }
        }
        eventStreamClient.onMessage = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.handleEventMessage(message)
            }
        }
        eventStreamClient.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.collecting = false
                // A dropped socket loses the backfill_completed/failed event, so
                // clear the indicator; onReconnect re-syncs the true state.
                self?.valuing = false
                self?.valuationProgress = 0
                self?.valuationMessage = ""
                if self?.updateInstalling == true {
                    self?.updateMessage = "Reconnecting to update service..."
                }
            }
        }
        eventStreamClient.onReconnect = { [weak self] in
            Task { @MainActor in
                await self?.syncCollectStatus()
                await self?.syncValuationStatus()
                await self?.syncUpdateStatus()
                await self?.runWebSyncDailyIfNeeded()
            }
        }
        eventStreamClient.connect()
        // Recover an in-flight valuation started while the app was closed — the
        // WS only replays live events, and onReconnect fires on reconnects, not
        // this first connect.
        Task { @MainActor [weak self] in
            await self?.syncValuationStatus()
        }
    }

    func stopEventStream() {
        eventStreamClient.disconnect()
        eventStreamConfigured = false
        updateCheckTask?.cancel()
        updateCheckTask = nil
        if let appDidBecomeActiveObserver {
            NotificationCenter.default.removeObserver(appDidBecomeActiveObserver)
            self.appDidBecomeActiveObserver = nil
        }
    }

    private func syncCollectStatus() async {
        let url = APIEndpoints.url(path: APIEndpoints.collectStatus)
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let status = try? JSONDecoder().decode(CollectStatus.self, from: data) else { return }
        collecting = status.collecting
    }

    private func syncValuationStatus() async {
        let url = APIEndpoints.url(path: APIEndpoints.backfillStatus)
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let status = try? JSONDecoder().decode(BackfillStatus.self, from: data) else { return }
        valuing = status.valuing
        if !status.valuing {
            valuationProgress = 0
            valuationMessage = ""
        }
    }

    func checkForUpdates() async {
        await refreshUpdates(mode: .regular)
    }

    func forceCheckUpdates() async {
        await refreshUpdates(mode: .forced)
    }

    func installUpdatesManually() async {
        beginLocalInstallState(message: "Starting update...")
        let result = await startInstallRequest()
        switch result {
        case .started, .alreadyInProgress:
            return
        case let .failed(message):
            applyInstallFailure(message: message)
        }
    }

    func restartAfterUpdate() {
        Task { @MainActor in
            do {
                try await APIClient.shared.restartServices()
                AppRelauncher.scheduleRelaunch()
                NSApp.terminate(nil)
            } catch {
                updateStatus = "error"
                updateInstalling = false
                updateMessage = error.localizedDescription
            }
        }
    }

    func syncUpdateStatus() async {
        await refreshUpdates(mode: .regular)
    }

    private func refreshUpdates(mode: UpdateRefreshMode) async {
        do {
            let status = try await APIClient.shared.getUpdateStatus()
            applyUpdateStatus(status)
        } catch {
            if updateInstalling {
                updateMessage = "Reconnecting to update service..."
            }
            return
        }

        let response: UpdatesResponse?
        do {
            switch mode {
            case .regular:
                response = try await APIClient.shared.getUpdates()
            case .forced:
                response = try await APIClient.shared.forceCheckUpdates()
            }
        } catch {
            // Fall back to regular check if forced refresh fails.
            if mode == .forced {
                response = try? await APIClient.shared.getUpdates()
            } else {
                response = nil
            }
        }

        guard let response else { return }
        applyUpdatesResponse(response)
        await autoInstallIfNeeded(for: response)
    }

    private func startUpdateCheckLoop() {
        guard updateCheckTask == nil else { return }
        updateCheckTask = Task {
            await syncUpdateStatus()
            await runWebSyncDailyIfNeeded()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.updateCheckInterval))
                guard !Task.isCancelled else { break }
                await syncUpdateStatus()
                await runWebSyncDailyIfNeeded()
            }
        }
    }

    func webSyncStatus(for provider: WebSyncProvider) -> WebSyncStatus {
        webSyncStatuses[provider.rawValue] ?? .idle
    }

    func connectWebSource(_ provider: WebSyncProvider) {
        Task { @MainActor in
            await Task.yield()
            await webSyncCoordinator.connect(provider: provider)
        }
    }

    @discardableResult
    func syncWebSourceNow(_ provider: WebSyncProvider) async -> Bool {
        await Task.yield()
        return await webSyncCoordinator.syncNow(provider: provider)
    }

    private func runWebSyncDailyIfNeeded() async {
        guard isConnected else { return }
        guard let sources = try? await APIClient.shared.getSources() else { return }
        await webSyncCoordinator.runDailySyncIfNeeded(sources: sources)
    }

    private func syncEnabledWebSourcesAfterCollect() async {
        guard isConnected else { return }
        guard let sources = try? await APIClient.shared.getSources() else { return }

        let enabledProviders = Set(
            sources
                .filter(\.enabled)
                .compactMap { WebSyncProvider(sourceType: $0.type) }
        )
        guard !enabledProviders.isEmpty else { return }

        for provider in enabledProviders {
            _ = await webSyncCoordinator.syncNow(provider: provider, trigger: .automatic)
        }
    }

    func markDisconnected() {
        daemonStatus = .disconnected
        collecting = false
        collectionProgress = 0
        collectionMessage = ""
        valuing = false
        valuationProgress = 0
        valuationMessage = ""
        if updateInstalling {
            updateMessage = "Reconnecting to update service..."
        }
    }

    private func handleEventMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let payload = object as? [String: Any] {
            handleEventPayload(payload)
        } else if let number = Double(message.trimmingCharacters(in: .whitespacesAndNewlines)) {
            Task { @MainActor in
                collectionProgress = clampProgress(number)
            }
        }
    }

    private func handleEventPayload(_ payload: [String: Any]) {
        let type = payload["type"] as? String

        switch type {
        case "collection_started":
            Task { @MainActor in
                collecting = true
                collectionProgress = 0
                collectionMessage = "Starting..."
            }
        case "collection_progress":
            let current = (payload["current"] as? Double) ?? Double(payload["current"] as? Int ?? 0)
            let total = (payload["total"] as? Double) ?? Double(payload["total"] as? Int ?? 1)
            let message = payload["message"] as? String
            Task { @MainActor in
                collecting = true
                if total > 0 {
                    collectionProgress = clampProgress(current / total)
                }
                if let message {
                    collectionMessage = message
                }
            }
        case "collection_completed":
            let message = payload["message"] as? String
            let singleSource = payload["source"] as? String
            Task { @MainActor in
                collecting = false
                collectionProgress = 1
                if let message {
                    collectionMessage = message
                }
            }
            NotificationCenter.default.post(name: .collectionCompleted, object: nil)
            if singleSource == nil {
                Task { @MainActor [weak self] in
                    await self?.syncEnabledWebSourcesAfterCollect()
                }
            }
        case "collection_failed":
            let error = payload["error"] as? String
            Task { @MainActor in
                collecting = false
                collectionProgress = 0
                collectionMessage = error ?? "Collection failed"
            }
        case "snapshot_updated":
            NotificationCenter.default.post(name: .snapshotUpdated, object: nil)
        case "backfill_started":
            Task { @MainActor in
                valuing = true
                valuationProgress = 0
                valuationMessage = "Valuing transactions…"
            }
        case "backfill_progress":
            let current = (payload["current"] as? Double) ?? Double(payload["current"] as? Int ?? 0)
            let total = (payload["total"] as? Double) ?? Double(payload["total"] as? Int ?? 0)
            Task { @MainActor in
                valuing = true
                if total > 0 {
                    valuationProgress = clampProgress(current / total)
                    // Only show counts for a real backlog; a 0/0 no-op keeps the plain label.
                    valuationMessage = "Valuing transactions… \(Int(current))/\(Int(total))"
                }
            }
        case "backfill_completed":
            Task { @MainActor in
                valuing = false
                valuationProgress = 1
                valuationMessage = ""
                // Post after the state reset so observers see valuing == false.
                // usd_value of transactions changed — refresh PnL/analytics views.
                NotificationCenter.default.post(name: .valuationCompleted, object: nil)
            }
        case "backfill_failed":
            let error = payload["error"] as? String ?? "unknown error"
            Self.logger.error("Background valuation failed: \(error, privacy: .public)")
            Task { @MainActor in
                valuing = false
                valuationProgress = 0
                valuationMessage = ""
            }
        case "update_started":
            Task { @MainActor in
                updateStatus = "installing"
                updateInstalling = true
                updateProgress = 0
                updateMessage = "Starting update..."
            }
        case "update_progress":
            let progress = payload["progress"] as? Double ?? 0
            let message = payload["message"] as? String ?? ""
            Task { @MainActor in
                updateStatus = "installing"
                updateInstalling = true
                updateProgress = progress
                updateMessage = message
            }
        case "update_completed":
            Task { @MainActor in
                updateStatus = "installed"
                updateInstalling = false
                updateProgress = 1
                updateMessage = "Updates installed"
            }
            NotificationCenter.default.post(name: .updateCompleted, object: nil)
        case "update_failed":
            let error = payload["error"] as? String ?? "Update failed"
            Task { @MainActor in
                updateStatus = "error"
                updateInstalling = false
                updateProgress = 0
                updateMessage = error
            }
        default:
            if let collectingValue = payload["collecting"] as? Bool {
                Task { @MainActor in
                    collecting = collectingValue
                }
            }
            if let progressValue = payload["progress"] ?? payload["collection_progress"] ?? payload["percentage"] ?? payload["pct"] {
                Task { @MainActor in
                    collectionProgress = normalizeProgress(progressValue)
                }
            }
        }
    }

    private func normalizeProgress(_ value: Any) -> Double {
        if let doubleValue = value as? Double {
            return clampProgress(doubleValue)
        }
        if let intValue = value as? Int {
            return clampProgress(Double(intValue))
        }
        if let stringValue = value as? String, let doubleValue = Double(stringValue) {
            return clampProgress(doubleValue)
        }
        return collectionProgress
    }

    private func clampProgress(_ rawValue: Double) -> Double {
        let normalized = rawValue > 1 ? rawValue / 100.0 : rawValue
        return min(max(normalized, 0), 1)
    }

    func applyUpdatesResponse(_ response: UpdatesResponse) {
        updates = response
        let appNeedsUpdate = appNeedsUpdate(for: response)
        if updateStatus == "error", !updateInstalling, !restartNeeded(for: response) {
            updateStatus = "idle"
            updateProgress = 0
            updateMessage = ""
        }
        updateAvailable = response.pfm.updateAvailable || appNeedsUpdate || restartNeeded(for: response)
    }

    private func applyUpdateStatus(_ status: UpdateStatusResponse) {
        updateStatus = status.status
        updateProgress = clampProgress(status.progress)

        switch status.status {
        case "installing":
            updateInstalling = true
            updateMessage = status.message.isEmpty ? "Installing updates..." : status.message
        case "installed":
            updateInstalling = false
            updateProgress = 1
            updateMessage = status.message.isEmpty ? "Updates installed" : status.message
            updateAvailable = true
            if let currentUpdates = updates {
                updates = UpdatesResponse(pfm: currentUpdates.pfm, app: currentUpdates.app, restartPending: true)
            }
        case "error":
            updateInstalling = false
            updateProgress = 0
            updateMessage = status.message.isEmpty ? "Update failed" : status.message
        default:
            updateInstalling = false
            updateMessage = status.message
        }
    }

    private func restartNeeded(for response: UpdatesResponse?) -> Bool {
        guard let response else { return false }
        return response.restartPending == true || hasPfmInstalledMismatch(response) || hasAppInstalledMismatch(response)
    }

    private func hasPfmInstalledMismatch(_ response: UpdatesResponse) -> Bool {
        guard let installed = response.pfm.installed, !installed.isEmpty else { return false }
        return installed != response.pfm.current
    }

    private func hasAppInstalledMismatch(_ response: UpdatesResponse) -> Bool {
        guard let installed = response.app.installed, !installed.isEmpty, let current = runningAppVersion else {
            return false
        }
        return installed != current
    }

    private func appNeedsUpdate(for response: UpdatesResponse) -> Bool {
        guard let appVersion = runningAppVersion, let latest = response.app.latest else { return false }
        return latest != appVersion
    }

    private func hasAnyInstallableUpdate(_ response: UpdatesResponse) -> Bool {
        response.pfm.updateAvailable || appNeedsUpdate(for: response)
    }

    private func updateFingerprint(for response: UpdatesResponse) -> String? {
        let pfmPart = if response.pfm.updateAvailable {
            response.pfm.latest ?? "unknown"
        } else {
            "-"
        }
        let appPart = if appNeedsUpdate(for: response) {
            response.app.latest ?? "unknown"
        } else {
            "-"
        }
        if pfmPart == "-", appPart == "-" {
            return nil
        }
        return "pfm:\(pfmPart)|app:\(appPart)"
    }

    private func shouldAutoInstall(for response: UpdatesResponse) -> Bool {
        hasAnyInstallableUpdate(response) &&
            !updateInstalling &&
            updateStatus != "installed" &&
            !restartNeeded(for: response)
    }

    private func autoInstallIfNeeded(for response: UpdatesResponse) async {
        guard shouldAutoInstall(for: response) else { return }
        guard let fingerprint = updateFingerprint(for: response) else { return }
        guard autoInstallInFlightFingerprint != fingerprint else { return }

        let attemptsSoFar = autoInstallAttemptsByFingerprint[fingerprint, default: 0]
        guard attemptsSoFar < Self.maxAutoInstallAttemptsPerFingerprint else { return }

        beginLocalInstallState(message: "Installing updates...")
        autoInstallInFlightFingerprint = fingerprint
        defer {
            if autoInstallInFlightFingerprint == fingerprint {
                autoInstallInFlightFingerprint = nil
            }
        }

        var nextAttempt = attemptsSoFar + 1
        while nextAttempt <= Self.maxAutoInstallAttemptsPerFingerprint {
            autoInstallAttemptsByFingerprint[fingerprint] = nextAttempt
            let result = await startInstallRequest()
            switch result {
            case .started, .alreadyInProgress:
                return
            case let .failed(message):
                if nextAttempt < Self.maxAutoInstallAttemptsPerFingerprint {
                    try? await Task.sleep(for: Self.autoInstallRetryDelay)
                    guard !Task.isCancelled else { return }
                    nextAttempt += 1
                    continue
                }
                applyInstallFailure(message: message)
                return
            }
        }
    }

    private func beginLocalInstallState(message: String) {
        updateStatus = "installing"
        updateInstalling = true
        updateProgress = 0
        updateMessage = message
    }

    private func startInstallRequest() async -> UpdateInstallStartResult {
        do {
            try await APIClient.shared.installUpdate(target: "all")
            return .started
        } catch {
            if isInstallAlreadyInProgressError(error) {
                updateStatus = "installing"
                updateInstalling = true
                updateMessage = "Installing updates..."
                return .alreadyInProgress
            }
            return .failed(userMessage(forInstallError: error))
        }
    }

    private func isInstallAlreadyInProgressError(_ error: Error) -> Bool {
        if case APIError.httpStatus(409) = error {
            return true
        }
        if case let APIError.message(message) = error {
            return message.localizedCaseInsensitiveContains("already in progress")
        }
        return false
    }

    private func userMessage(forInstallError error: Error) -> String {
        switch error {
        case let APIError.message(message):
            return message
        case let APIError.httpStatus(code):
            return "Update failed with status \(code)."
        default:
            return error.localizedDescription
        }
    }

    private func applyInstallFailure(message: String) {
        updateStatus = "error"
        updateInstalling = false
        updateProgress = 0
        updateMessage = message
    }

}
