import SwiftUI
import Combine

@MainActor
final class SourcesViewModel: ObservableObject {
    @Published var sources: [SourceDTO] = []
    @Published var sourceTypes: [String: SourceTypeInfo] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                async let sources = APIClient.shared.getSources()
                async let types = APIClient.shared.getSourceTypes()

                self.sources = try await sources
                self.sourceTypes = try await types
            } catch {
                errorMessage = "Unable to load sources."
            }
            isLoading = false
        }
    }

    func deleteSources(at offsets: IndexSet) {
        let targets = offsets.map { sources[$0] }
        sources.remove(atOffsets: offsets)

        Task {
            for source in targets {
                try? await APIClient.shared.deleteSource(name: source.name)
            }
            await reload()
        }
    }

    func toggleSource(_ source: SourceDTO, enabled: Bool) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index] = SourceDTO(name: source.name, type: source.type, credentials: source.credentials, enabled: enabled)
        }

        Task {
            do {
                try await APIClient.shared.patchSource(name: source.name, body: SourcePatchRequest(credentials: nil, enabled: enabled))
            } catch {
                await reload()
            }
        }
    }

    func addSource(name: String, type: String, credentials: [String: String]) async -> Bool {
        do {
            try await APIClient.shared.createSource(SourceCreateRequest(name: name, type: type, credentials: credentials))
            await reload()
            return true
        } catch {
            return false
        }
    }

    func reload() async {
        do {
            sources = try await APIClient.shared.getSources()
        } catch {
            errorMessage = "Unable to refresh sources."
        }
    }
}
