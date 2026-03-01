import SwiftUI
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var summary: PortfolioSummary?
    @Published var isLoading = false
    @Published var errorMessage: String?

    nonisolated init() {}

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                self.summary = try await APIClient.shared.getPortfolioSummary()
            } catch {
                errorMessage = "Unable to load dashboard data: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}
