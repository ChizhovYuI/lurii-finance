import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var aiProviders: [AIProviderConfig] = []
    @Published var aiProvidersAvailable: [AIProviderAvailable] = []
    @Published var selectedProviderType: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let settings = try await APIClient.shared.getSettings()
                aiProviders = settings.aiProviders
                aiProvidersAvailable = settings.aiProvidersAvailable
                if selectedProviderType.isEmpty {
                    selectedProviderType = activeProvider?.type ?? settings.aiProvidersAvailable.first?.type ?? ""
                }
            } catch {
                errorMessage = "Unable to load settings."
            }
            isLoading = false
        }
    }

    var activeProvider: AIProviderConfig? {
        aiProviders.first { $0.active == true }
    }

    func providerMeta(for type: String) -> AIProviderAvailable? {
        aiProvidersAvailable.first { $0.type == type }
    }

    func configuredProvider(for type: String) -> AIProviderConfig? {
        aiProviders.first { $0.type == type }
    }

    func upsertProvider(type: String, fields: [String: String]) async -> Bool {
        do {
            try await APIClient.shared.upsertAIProviderFields(type: type, fields: fields)
            let settings = try await APIClient.shared.getSettings()
            aiProviders = settings.aiProviders
            aiProvidersAvailable = settings.aiProvidersAvailable
            return true
        } catch {
            return false
        }
    }

    func validateProvider(type: String, fields: [String: String]) async -> Result<String, ValidationRequestError> {
        do {
            let response = try await APIClient.shared.validateAIProviderConnection(type: type, fields: fields)
            return .success(response.message)
        } catch let error as ValidationRequestError {
            return .failure(error)
        } catch {
            return .failure(.message("Connection check failed."))
        }
    }

    func activateProvider(type: String) async -> Bool {
        do {
            try await APIClient.shared.activateAIProvider(type: type)
            let settings = try await APIClient.shared.getSettings()
            aiProviders = settings.aiProviders
            aiProvidersAvailable = settings.aiProvidersAvailable
            return true
        } catch {
            return false
        }
    }

    func deactivateProvider() async -> Bool {
        do {
            try await APIClient.shared.deactivateAIProvider()
            let settings = try await APIClient.shared.getSettings()
            aiProviders = settings.aiProviders
            aiProvidersAvailable = settings.aiProvidersAvailable
            return true
        } catch {
            return false
        }
    }
}
