import Combine
import SwiftUI

@MainActor
final class TransactionsViewModel: ObservableObject {
    @Published var transactions: [TransactionDTO] = []
    @Published var categories: [TransactionCategoryDTO] = []
    @Published var total: Int = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var isCategorizing = false
    @Published var categorizationMessage: String?

    /// Whether older pages are available.
    var hasMore: Bool { nextEndDate != nil }

    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var loadSequence = 0
    /// Cursor for the next page (end date of the next 7-day window).
    private var nextEndDate: String?

    /// Tracks current filter params so `loadMore` can reuse them.
    private var currentSourceName: String?
    private var currentTxType: String?
    private var currentCategory: String?
    private var currentSearch: String?

    nonisolated init() {}

    /// Loads the first page (replaces existing data).
    func load(
        sourceName: String? = nil,
        txType: String? = nil,
        category: String? = nil,
        search: String? = nil
    ) {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        loadSequence += 1
        let sequence = loadSequence
        nextEndDate = nil

        currentSourceName = sourceName
        currentTxType = txType
        currentCategory = category
        currentSearch = search

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
                    sourceName: sourceName,
                    txType: txType,
                    category: category,
                    search: search
                )
                async let catTask = APIClient.shared.getTransactionCategories()

                let response = try await txTask
                let cats = try? await catTask

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                self.transactions = response.items
                self.total = response.total
                self.nextEndDate = response.nextEndDate
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

    /// Loads the next 7-day window and appends to existing data.
    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true
        let sequence = loadSequence
        let cursor = nextEndDate

        loadMoreTask = Task {
            defer { self.isLoadingMore = false }

            do {
                let response = try await APIClient.shared.getTransactions(
                    sourceName: currentSourceName,
                    txType: currentTxType,
                    category: currentCategory,
                    search: currentSearch,
                    end: cursor
                )

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                let existingIDs = Set(self.transactions.map(\.id))
                let newItems = response.items.filter { !existingIDs.contains($0.id) }
                self.transactions.append(contentsOf: newItems)
                self.total += response.total
                self.nextEndDate = response.nextEndDate
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
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
        // Optimistic UI update.
        if let idx = transactions.firstIndex(where: { $0.id == txId }) {
            let old = transactions[idx]
            let updatedMeta = TransactionMetadataDTO(
                category: old.metadata?.category,
                categorySource: old.metadata?.categorySource,
                categoryConfidence: old.metadata?.categoryConfidence,
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
