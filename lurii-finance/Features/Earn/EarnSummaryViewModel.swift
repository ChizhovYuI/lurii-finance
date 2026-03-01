import SwiftUI
import Combine

@MainActor
final class EarnSummaryViewModel: ObservableObject {
    @Published var summary: EarnSummaryResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                summary = try await APIClient.shared.getEarnSummary()
            } catch {
                errorMessage = "Unable to load earn summary."
            }
            isLoading = false
        }
    }
}
