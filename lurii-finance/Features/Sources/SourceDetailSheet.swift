import SwiftUI

struct SourceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: SourceDTO

    @State private var enabled: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(source: SourceDTO) {
        self.source = source
        _enabled = State(initialValue: source.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(source.name)
                .font(.title2)

            Text("Type: \(source.type)")
                .foregroundStyle(.secondary)

            Toggle("Enabled", isOn: $enabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("Credentials")
                    .font(.headline)
                ForEach(source.credentials.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text(source.credentials[key] ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                Button(isSaving ? "Saving..." : "Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await APIClient.shared.patchSource(name: source.name, body: SourcePatchRequest(credentials: nil, enabled: enabled))
                dismiss()
            } catch {
                errorMessage = "Unable to update source."
            }
            isSaving = false
        }
    }
}

#Preview {
    SourceDetailSheet(source: SourceDTO(name: "Coinbase", type: "exchange", credentials: ["apiKey": "••••"], enabled: true))
}
