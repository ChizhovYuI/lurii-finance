import Combine
import SwiftUI

@MainActor
final class EarnSummaryViewModel: ObservableObject {
    @Published var summary: EarnSummaryResponse?
    @Published var history: [EarnHistoryPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0

    nonisolated init() {}

    func load() {
        loadTask?.cancel()
        loadSequence += 1
        let sequence = loadSequence

        isLoading = true
        errorMessage = nil

        loadTask = Task {
            defer {
                if sequence == self.loadSequence {
                    self.isLoading = false
                }
            }

            do {
                async let summaryTask = APIClient.shared.getEarnSummary()
                async let historyTask = APIClient.shared.getEarnHistory(days: 30)

                let summary = try await summaryTask
                let history = try? await historyTask

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                self.summary = summary
                self.history = history?.points ?? []
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, sequence == self.loadSequence else { return }
                self.summary = nil
                self.history = []
                self.errorMessage = "Unable to load earn summary."
            }
        }
    }
}
