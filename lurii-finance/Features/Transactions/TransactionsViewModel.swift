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

    /// Current page (0-indexed). Each page is a 7-day window.
    @Published var currentPage = 0
    /// Window label for the current page (e.g. "Jun 10 – Jun 17").
    @Published var windowLabel: String?
    /// Whether a next (older) page exists.
    @Published var hasNextPage = false

    var hasPreviousPage: Bool { currentPage > 0 }

    private var loadTask: Task<Void, Never>?
    private var loadSequence = 0
    /// Stack of `end` cursors: index N holds the cursor for page N.
    /// Page 0 has no cursor (nil).
    private var pageCursors: [String?] = [nil]

    /// Tracks current filter params so page navigation can reuse them.
    private var currentSourceName: String?
    private var currentTxType: String?
    private var currentCategory: String?
    private var currentSearch: String?

    nonisolated init() {}

    /// Loads the first page (replaces existing data, resets pagination).
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
        currentPage = 0
        pageCursors = [nil]

        loadPage(0)
    }

    /// Navigate to the next (older) page.
    func goNextPage() {
        guard hasNextPage else { return }
        loadPage(currentPage + 1)
    }

    /// Navigate to the previous (newer) page.
    func goPreviousPage() {
        guard hasPreviousPage else { return }
        loadPage(currentPage - 1)
    }

    private func loadPage(_ page: Int) {
        loadTask?.cancel()
        loadSequence += 1
        let sequence = loadSequence

        currentPage = page
        isLoading = true
        errorMessage = nil

        let cursor = page < pageCursors.count ? pageCursors[page] : nil

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
                    end: cursor
                )
                async let catTask = APIClient.shared.getTransactionCategories()

                let response = try await txTask
                let cats = try? await catTask

                guard !Task.isCancelled, sequence == self.loadSequence else { return }

                self.transactions = response.items
                self.total = response.total
                self.hasNextPage = response.nextEndDate != nil
                self.windowLabel = Self.formatWindowLabel(start: response.windowStart, end: response.windowEnd)

                // Store cursor for the next page.
                if let next = response.nextEndDate {
                    let nextPage = page + 1
                    if nextPage < self.pageCursors.count {
                        self.pageCursors[nextPage] = next
                    } else {
                        self.pageCursors.append(next)
                    }
                }

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

    private static func formatWindowLabel(start: String?, end: String?) -> String? {
        guard let start, let end else { return nil }
        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        guard let startDate = isoFmt.date(from: String(start.prefix(10))),
              let endDate = isoFmt.date(from: String(end.prefix(10))) else { return nil }
        let displayFmt = DateFormatter()
        displayFmt.dateFormat = "MMM d"
        return "\(displayFmt.string(from: startDate)) – \(displayFmt.string(from: endDate))"
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
