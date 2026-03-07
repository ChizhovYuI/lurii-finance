import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    enum DaemonStatus: Equatable {
        case unknown
        case connected(version: String)
        case disconnected
    }

    enum AppSection: String, CaseIterable, Identifiable {
        case dashboard
        case earn
        case sources
        case reports
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard:
                return "Dashboard"
            case .earn:
                return "Earn"
            case .sources:
                return "Sources"
            case .reports:
                return "Reports"
            case .settings:
                return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard:
                return "chart.bar.xaxis"
            case .earn:
                return "percent"
            case .sources:
                return "tray.full"
            case .reports:
                return "doc.text"
            case .settings:
                return "gearshape"
            }
        }
    }

    @Published var daemonStatus: DaemonStatus = .unknown
    @Published var selectedSection: AppSection = .dashboard
    @Published var collecting: Bool = false
    @Published var collectionProgress: Double = 0
    @Published var collectionMessage: String = ""
    @Published var generatingCommentary: Bool = false

    private let eventStreamClient = EventStreamClient()
    private var eventStreamConfigured = false

    var isConnected: Bool {
        if case .connected = daemonStatus {
            return true
        }
        return false
    }

    func updateFromHealth(_ health: HealthResponse) {
        daemonStatus = .connected(version: health.version)
        collecting = health.collecting
    }

    func updateCollectStatus(_ status: CollectStatus) {
        collecting = status.collecting
    }

    func startEventStream() {
        guard !eventStreamConfigured else { return }
        eventStreamConfigured = true
        eventStreamClient.onMessage = { [weak self] message in
            self?.handleEventMessage(message)
        }
        eventStreamClient.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.collecting = false
            }
        }
        eventStreamClient.onReconnect = { [weak self] in
            Task { @MainActor in
                self?.syncCollectStatus()
            }
        }
        eventStreamClient.connect()
    }

    func stopEventStream() {
        eventStreamClient.disconnect()
        eventStreamConfigured = false
    }

    private func syncCollectStatus() {
        Task {
            let url = APIEndpoints.url(path: APIEndpoints.collectStatus)
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let status = try? JSONDecoder().decode(CollectStatus.self, from: data) else { return }
            collecting = status.collecting
        }
    }

    func markDisconnected() {
        daemonStatus = .disconnected
        collecting = false
        collectionProgress = 0
        collectionMessage = ""
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
            Task { @MainActor in
                collecting = false
                collectionProgress = 1
                if let message {
                    collectionMessage = message
                }
            }
            NotificationCenter.default.post(name: .collectionCompleted, object: nil)
        case "collection_failed":
            let error = payload["error"] as? String
            Task { @MainActor in
                collecting = false
                collectionProgress = 0
                collectionMessage = error ?? "Collection failed"
            }
        case "snapshot_updated":
            NotificationCenter.default.post(name: .snapshotUpdated, object: nil)
        case "commentary_started":
            Task { @MainActor in
                generatingCommentary = true
            }
        case "commentary_completed":
            Task { @MainActor in
                generatingCommentary = false
            }
            // Parse the commentary from the event payload if available
            var commentary: AICommentary?
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload) {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                commentary = try? decoder.decode(AICommentary.self, from: jsonData)
            }
            NotificationCenter.default.post(name: .commentaryCompleted, object: commentary)
        case "commentary_failed":
            Task { @MainActor in
                generatingCommentary = false
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
}
