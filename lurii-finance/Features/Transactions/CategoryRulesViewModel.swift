import Combine
import SwiftUI

@MainActor
final class CategoryRulesViewModel: ObservableObject {
    @Published var rules: [CategoryRuleDTO] = []
    @Published var categories: [TransactionCategoryDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    nonisolated init() {}

    var builtinRules: [CategoryRuleDTO] {
        rules.filter { $0.builtin == true }
    }

    var customRules: [CategoryRuleDTO] {
        rules.filter { $0.builtin != true }
    }

    func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                async let rulesTask = APIClient.shared.getCategoryRules()
                async let catsTask = APIClient.shared.getTransactionCategories()
                rules = try await rulesTask
                categories = (try? await catsTask) ?? []
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func deleteRule(_ rule: CategoryRuleDTO) {
        guard let id = rule.id else { return }
        Task {
            do {
                try await APIClient.shared.deleteCategoryRule(id: id)
                load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func resetRules(source: String?) {
        Task {
            do {
                try await APIClient.shared.resetCategoryRules(source: source)
                load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func categoryDisplayName(for slug: String?) -> String {
        guard let slug else { return "—" }
        return categories.first(where: { $0.category == slug })?.displayName ?? slug
    }
}
