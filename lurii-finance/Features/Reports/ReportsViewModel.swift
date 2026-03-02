import SwiftUI
import Combine

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var commentary: AICommentary?
    @Published var isLoading = false
    @Published var hasLoaded = false
    @Published var errorMessage: String?
    @Published var sendStatus: String?

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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                commentary = try await APIClient.shared.generateAICommentary()
            } catch {
                errorMessage = "Failed to generate report."
            }
            isLoading = false
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
