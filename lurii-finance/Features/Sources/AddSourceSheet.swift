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
            // Show tip from first field if available
            if let firstField = viewModel.sourceTypes[selectedType]?.fields.first,
               let tip = firstField.tip,
               !tip.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                        .font(.body)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tip.components(separatedBy: "\n"), id: \.self) { line in
                            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                                TipLineView(text: line)
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Credential fields
            ForEach(viewModel.sourceTypes[selectedType]?.fields ?? []) { field in
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

private struct TipLineView: View {
    let text: String
    
    var body: some View {
        let parts = parseParts(from: text)
        
        if parts.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Render parts inline using HStack
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    switch part {
                    case .text(let str):
                        Text(str)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .link(let url, let label):
                        Link(label, destination: url)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private enum Part {
        case text(String)
        case link(URL, String)
    }
    
    private func parseParts(from text: String) -> [Part] {
        let nsText = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        
        guard !matches.isEmpty else {
            return []
        }
        
        var parts: [Part] = []
        var currentIndex = 0
        
        for match in matches {
            let range = match.range
            
            // Add text before the URL
            if range.location > currentIndex {
                let substring = nsText.substring(with: NSRange(location: currentIndex, length: range.location - currentIndex))
                parts.append(.text(substring))
            }
            
            // Add the URL
            if let url = match.url {
                let label = nsText.substring(with: range)
                parts.append(.link(url, label))
            }
            
            currentIndex = range.location + range.length
        }
        
        // Add remaining text after the last URL
        if currentIndex < nsText.length {
            let substring = nsText.substring(from: currentIndex)
            parts.append(.text(substring))
        }
        
        return parts
    }
}

#Preview {
    AddSourceSheet(viewModel: SourcesViewModel())
}
