import SwiftUI

struct AddSourceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedType: String = ""
    @State private var credentials: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @ObservedObject var viewModel: SourcesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Source")
                .font(.title2)

            TextField("Name", text: $name)

            Picker("Type", selection: $selectedType) {
                ForEach(viewModel.sourceTypes.keys.sorted(), id: \.self) { key in
                    Text(key).tag(key)
                }
            }
            .onChange(of: selectedType) { _, _ in
                credentials = [:]
            }

            fieldsView

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isSubmitting ? "Adding..." : "Add") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || name.isEmpty || selectedType.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            if selectedType.isEmpty {
                selectedType = viewModel.sourceTypes.keys.sorted().first ?? ""
            }
        }
    }

    private var fieldsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.sourceTypes[selectedType] ?? []) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.prompt)
                        .font(.caption)
                    if field.secret {
                        SecureField(field.name, text: Binding(
                            get: { credentials[field.name, default: ""] },
                            set: { credentials[field.name] = $0 }
                        ))
                    } else {
                        TextField(field.name, text: Binding(
                            get: { credentials[field.name, default: ""] },
                            set: { credentials[field.name] = $0 }
                        ))
                    }
                }
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            let success = await viewModel.addSource(name: name, type: selectedType, credentials: credentials)
            if success {
                dismiss()
            } else {
                errorMessage = "Unable to add source."
            }
            isSubmitting = false
        }
    }
}

#Preview {
    AddSourceSheet(viewModel: SourcesViewModel())
}
