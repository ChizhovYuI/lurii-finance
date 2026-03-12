import Foundation

final class EventStreamClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var isConnected = false
    private var shouldReconnect = false
    private var reconnectDelay: TimeInterval = 1.0
    private static let maxReconnectDelay: TimeInterval = 30.0

    var onMessage: ((String) -> Void)?
    var onDisconnect: (() -> Void)?
    var onReconnect: (() -> Void)?

    func connect() {
        shouldReconnect = true
        openSocket()
    }

    func disconnect() {
        shouldReconnect = false
        isConnected = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func openSocket() {
        guard !isConnected else { return }
        let url = APIEndpoints.wsURL(path: APIEndpoints.ws)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true
        reconnectDelay = 1.0
        receiveLoop()
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.shouldReconnect, !self.isConnected else { return }
            self.onReconnect?()
            self.openSocket()
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async { [weak self] in
                        self?.onMessage?(text)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        DispatchQueue.main.async { [weak self] in
                            self?.onMessage?(text)
                        }
                    }
                @unknown default:
                    break
                }
                if self.isConnected {
                    self.receiveLoop()
                }
            case .failure:
                self.isConnected = false
                self.task = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onDisconnect?()
                }
                self.scheduleReconnect()
            }
        }
    }
}
