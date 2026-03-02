import SwiftUI
import Combine

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var commentary: AICommentary?
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?
    @Published var sendStatus: String?

    weak var appState: AppState?
    private var cancellable: AnyCancellable?

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: .commentaryCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let result = notification.object as? AICommentary {
                    self?.commentary = result
                } else {
                    self?.silentRefresh()
                }
            }
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                commentary = try await APIClient.shared.getAICommentary()
            } catch {
                errorMessage = "Unable to fetch weekly report."
            }
            isLoading = false
            hasLoaded = true
        }
    }

    func generate() {
        guard appState?.generatingCommentary != true else { return }
        appState?.generatingCommentary = true
        errorMessage = nil

        Task {
            do {
                try await APIClient.shared.generateAICommentary()
                // 202 accepted — WS events handle the rest
            } catch APIError.httpStatus(409) {
                // Already generating — WS event will clear it
            } catch {
                errorMessage = "Failed to start report generation."
                appState?.generatingCommentary = false
            }
        }
    }

    func silentRefresh() {
        Task {
            if let result = try? await APIClient.shared.getAICommentary() {
                commentary = result
            }
            hasLoaded = true
        }
    }

    func checkGeneratingStatus() {
        Task {
            if let status = try? await APIClient.shared.getCommentaryStatus() {
                appState?.generatingCommentary = status.generating
            }
        }
    }

    func notify() {
        Task {
            do {
                let response = try await APIClient.shared.notifyReport()
                sendStatus = response.sent ? "Sent" : "Failed"
            } catch {
                sendStatus = "Failed"
            }
        }
    }
}
