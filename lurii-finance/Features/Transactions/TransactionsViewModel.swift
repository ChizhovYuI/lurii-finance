import Combine
import SwiftUI

@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [TransactionDTO] = []
    @Published var categories: [TransactionCategoryDTO] = []
    @Published var total: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isCategorizing = false
    @Published var categorizationMessage: String?

    /// Current month being displayed (e.g. "2026-03").
    @Published var currentMonth: String?
    /// Display label for the current month (e.g. "Mar 2026").
    @Published var windowLabel: String?
    /// Whether an older month exists.
    @Published var hasNextPage = false
    /// Whether a newer month exists (not the current month).
    @Published var hasPreviousPage = false

    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0
    /// History of visited months for back navigation.
    private var monthHistory: [String] = []

    /// Tracks current filter params so page navigation can reuse them.
    private var currentSourceName: String?
    private var currentTxType: String?
    private var currentCategory: String?
    private var currentSearch: String?

    nonisolated init() {}

    /// Loads the current month (replaces existing data, resets navigation).
    func load(
        sourceName: String? = nil,
        txType: String? = nil,
        category: String? = nil,
        search: String? = nil
    ) {
        currentSourceName = sourceName
        currentTxType = txType
        currentCategory = category
        currentSearch = search
        monthHistory = []

        loadMonth(nil)
    }

    /// Navigate to the next (older) month.
    func goNextPage() {
        guard hasNextPage else { return }
        if let current = currentMonth {
            monthHistory.append(current)
        }
        loadMonth(nextMonthCursor)
    }

    /// Navigate to the previous (newer) month.
    func goPreviousPage() {
        guard hasPreviousPage, let prev = monthHistory.popLast() else { return }
        loadMonth(prev)
    }

    private var nextMonthCursor: String?

    private func loadMonth(_ month: String?) {
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
                async let txTask = APIClient.shared.getTransactions(
                    sourceName: currentSourceName,
                    txType: currentTxType,
                    category: currentCategory,
                    search: currentSearch,
                    month: month
                )
                async let catTask = APIClient.shared.getTransactionCategories()

                let response = try await txTask
                let cats = try? await catTask

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                self.transactions = response.items
                self.total = response.total
                self.currentMonth = response.month
                self.hasNextPage = response.nextMonth != nil
                self.hasPreviousPage = !self.monthHistory.isEmpty
                self.nextMonthCursor = response.nextMonth
                self.windowLabel = Self.formatMonthLabel(response.month)

                if let cats {
                    self.categories = cats
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, sequence == self.loadSequence else { return }
                self.errorMessage = "Unable to load transactions: \(error.localizedDescription)"
            }
        }
    }

    private static func formatMonthLabel(_ month: String?) -> String? {
        guard let month else { return nil }
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM"
        isoFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = isoFmt.date(from: month) else { return nil }
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMMM yyyy"
        return displayFmt.string(from: date)
    }

    func runCategorization() {
        isCategorizing = true
        categorizationMessage = nil

        Task {
            do {
                let result = try await APIClient.shared.runCategorization()
                self.categorizationMessage = "Categorized \(result.categorized) transactions, detected \(result.transfers) transfers"
            } catch {
                self.categorizationMessage = "Categorization failed: \(error.localizedDescription)"
            }
            self.isCategorizing = false
        }
    }

    func updateMetadata(id: Int, category: String?, reviewed: Bool?, notes: String?) {
        Task {
            do {
                try await APIClient.shared.updateTransactionMetadata(
                    id: id,
                    body: TransactionMetadataUpdateRequest(
                        category: category,
                        categorySource: category != nil ? "manual" : nil,
                        reviewed: reviewed,
                        notes: notes
                    )
                )
            } catch {
                // Silently fail for now.
            }
        }
    }

    func setCategory(txId: Int, category: String) {
        // Optimistic UI update.
        if let idx = transactions.firstIndex(where: { $0.id == txId }) {
            let old = transactions[idx]
            let updatedMeta = TransactionMetadataDTO(
                category: category,
                categorySource: "manual",
                categoryConfidence: 1.0,
                typeOverride: old.metadata?.typeOverride,
                isInternalTransfer: old.metadata?.isInternalTransfer,
                transferPairId: old.metadata?.transferPairId,
                transferDetectedBy: old.metadata?.transferDetectedBy,
                reviewed: old.metadata?.reviewed,
                notes: old.metadata?.notes
            )
            transactions[idx] = TransactionDTO(
                id: old.id, date: old.date, time: old.time, source: old.source,
                sourceName: old.sourceName, txType: old.txType, effectiveType: old.effectiveType,
                asset: old.asset, amount: old.amount, usdValue: old.usdValue,
                counterpartyAsset: old.counterpartyAsset, counterpartyAmount: old.counterpartyAmount,
                txId: old.txId, tradeSide: old.tradeSide, description: old.description,
                metadata: updatedMeta, group: old.group,
                rawFields: old.rawFields, matchedRule: old.matchedRule,
                availableCategories: old.availableCategories, availableTypes: old.availableTypes
            )
        }

        Task {
            do {
                _ = try await APIClient.shared.setTransactionCategory(id: txId, category: category)
            } catch {
                // Revert on failure — reload.
                self.load()
            }
        }
    }

    func setType(txId: Int, type: String) {
        // Optimistic UI update — clear category since it's type-specific.
        if let idx = transactions.firstIndex(where: { $0.id == txId }) {
            let old = transactions[idx]
            let updatedMeta = TransactionMetadataDTO(
                category: nil,
                categorySource: nil,
                categoryConfidence: nil,
                typeOverride: type,
                isInternalTransfer: old.metadata?.isInternalTransfer,
                transferPairId: old.metadata?.transferPairId,
                transferDetectedBy: old.metadata?.transferDetectedBy,
                reviewed: old.metadata?.reviewed,
                notes: old.metadata?.notes
            )
            transactions[idx] = TransactionDTO(
                id: old.id, date: old.date, time: old.time, source: old.source,
                sourceName: old.sourceName, txType: old.txType, effectiveType: type,
                asset: old.asset, amount: old.amount, usdValue: old.usdValue,
                counterpartyAsset: old.counterpartyAsset, counterpartyAmount: old.counterpartyAmount,
                txId: old.txId, tradeSide: old.tradeSide, description: old.description,
                metadata: updatedMeta, group: old.group,
                rawFields: old.rawFields, matchedRule: old.matchedRule,
                availableCategories: old.availableCategories, availableTypes: old.availableTypes
            )
        }

        Task {
            do {
                try await APIClient.shared.setTransactionType(id: txId, type: type)
            } catch {
                self.load()
            }
        }
    }

    func categoriesForType(_ txType: String) -> [TransactionCategoryDTO] {
        categories.filter { $0.txType == txType }
    }

    func categoryDisplayName(for category: String?) -> String {
        guard let category else { return "Uncategorized" }
        return categories.first(where: { $0.category == category })?.displayName ?? category
    }
}
