import Foundation

final class EventStreamClient: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var isConnected = false

    var onMessage: ((String) -> Void)?
    var onDisconnect: (() -> Void)?

    func connect() {
        guard !isConnected else { return }
        let url = APIEndpoints.wsURL(path: APIEndpoints.ws)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        isConnected = true
        receiveLoop()
    }

    func disconnect() {
        isConnected = false
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onMessage?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.onMessage?(text)
                    }
                @unknown default:
                    break
                }
                if self.isConnected {
                    self.receiveLoop()
                }
            case .failure:
                self.isConnected = false
                self.onDisconnect?()
            }
        }
    }
}
