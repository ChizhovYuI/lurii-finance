import SwiftUI
import Combine

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var commentary: AICommentary?
    @Published var isLoading = false
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
