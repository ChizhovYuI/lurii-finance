import SwiftUI

struct AIProviderSettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var fieldValues: [String: String] = [:]
    @State private var providerStatusMessage: String?
    @State private var validationMessage: String?
    @State private var validationSucceeded: Bool?
    @State private var isCheckingConnection = false
    @FocusState private var focusedField: String?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Provider")
                    .font(.title)
                    .foregroundStyle(.primary)

                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else if let errorMessage = viewModel.errorMessage {
                    EmptyStateView(title: "Settings unavailable", message: errorMessage, actionTitle: "Retry") {
                        viewModel.load()
                    }
                } else {
                    providerSettingsSection
                }
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("AI Provider")
        .onAppear {
            guard !isPreview else { return }
            viewModel.load()
        }
        .onChange(of: viewModel.selectedProviderType) { _, newValue in
            applyProviderSelection(type: newValue)
            clearValidationState()
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if !isLoading {
                applyProviderSelection(type: viewModel.selectedProviderType)
            }
        }
    }

    private var providerSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerPicker

            if let meta = viewModel.providerMeta(for: viewModel.selectedProviderType) {
                ForEach(meta.fields) { field in
                    fieldView(field)
                }
            }

            HStack(spacing: 12) {
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || isCheckingConnection)

                Button(isCheckingConnection ? "Checking..." : "Check Connection") {
                    validateConnection()
                }
                .buttonStyle(.bordered)
                .disabled(!isFormValid || isCheckingConnection)

                Button("Activate") {
                    activate()
                }
                .buttonStyle(.bordered)
                .disabled(isActiveProvider || isCheckingConnection)

                Button("Deactivate") {
                    deactivate()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.activeProvider == nil || isCheckingConnection)
            }

            if let providerStatusMessage {
                Text(providerStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(validationSucceeded == true ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.blockPadding)
        .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }

    private func save() {
        providerStatusMessage = nil
        guard isFormValid else {
            providerStatusMessage = "Fill required fields"
            return
        }
        Task {
            let config = viewModel.configuredProvider(for: viewModel.selectedProviderType)
            var fieldsToSend: [String: String] = [:]
            if let meta = viewModel.providerMeta(for: viewModel.selectedProviderType) {
                for field in meta.fields {
                    if let value = valueToSend(field: field, config: config) {
                        fieldsToSend[field.name] = value
                    }
                }
            }
            
            guard !fieldsToSend.isEmpty else {
                providerStatusMessage = "No changes"
                return
            }
            let success = await viewModel.upsertProvider(
                type: viewModel.selectedProviderType,
                fields: fieldsToSend
            )
            providerStatusMessage = success ? "Saved" : "Save failed"
            if success {
                // Clear secret fields from fieldValues after successful save
                if let meta = viewModel.providerMeta(for: viewModel.selectedProviderType) {
                    for field in meta.fields where field.secret == true {
                        fieldValues[field.name] = ""
                    }
                }
                // Reload the settings to get the updated config from the server
                viewModel.load()
            }
        }
    }

    private func activate() {
        providerStatusMessage = nil
        Task {
            let success = await viewModel.activateProvider(type: viewModel.selectedProviderType)
            providerStatusMessage = success ? "Activated" : "Activate failed"
            if success {
                applyProviderSelection(type: viewModel.selectedProviderType)
            }
        }
    }

    private func deactivate() {
        providerStatusMessage = nil
        Task {
            let success = await viewModel.deactivateProvider()
            providerStatusMessage = success ? "Deactivated" : "Deactivate failed"
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Provider")
                    .font(.headline)
            }
            Picker("", selection: $viewModel.selectedProviderType) {
                ForEach(viewModel.aiProvidersAvailable) { provider in
                    let isActive = provider.type == viewModel.activeProvider?.type
                    let label = isActive ? "\(provider.type.uppercased()) ✓" : provider.type.uppercased()
                    Text(label)
                        .tag(provider.type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.leading, -12)

            if let description = viewModel.providerMeta(for: viewModel.selectedProviderType)?.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
    }

    private func fieldView(_ field: AIProviderField) -> some View {
        let placeholder = placeholderText(for: field)
        let binding = Binding<String>(
            get: { fieldValues[field.name, default: ""] },
            set: {
                fieldValues[field.name] = $0
                clearValidationState()
            }
        )
        let label = fieldLabel(for: field.name)
        switch field.name {
        default:
            if field.secret == true {
                return AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabelView(label: label, hint: field.hint)
                        SecureField(label, text: binding, prompt: Text(placeholder))
                    }
                )
            }
            if let options = field.options, !options.isEmpty {
                return AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabelView(label: label, hint: field.hint)
                        TextField(label, text: binding, prompt: Text(placeholder))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: field.name)
                        if focusedField == field.name {
                            autocompleteList(options: options, currentValue: binding.wrappedValue) { option in
                                fieldValues[field.name] = option
                            }
                        }
                    }
                )
            }
            return AnyView(
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabelView(label: label, hint: field.hint)
                    TextField(label, text: binding, prompt: Text(placeholder))
                        .focused($focusedField, equals: field.name)
                }
            )
        }
    }

    private func applyProviderSelection(type: String) {
        guard !type.isEmpty else { return }
        fieldValues.removeAll()
        let config = viewModel.configuredProvider(for: type)
        let meta = viewModel.providerMeta(for: type)
        meta?.fields.forEach { field in
            if field.secret == true {
                fieldValues[field.name] = ""
            } else {
                fieldValues[field.name] = configuredValue(for: field.name, config: config) ?? ""
            }
        }
    }

    private func validateConnection() {
        providerStatusMessage = nil
        guard !isCheckingConnection, isFormValid else {
            return
        }
        isCheckingConnection = true
        clearValidationState()

        Task {
            let config = viewModel.configuredProvider(for: viewModel.selectedProviderType)
            var fieldsToSend: [String: String] = [:]
            if let meta = viewModel.providerMeta(for: viewModel.selectedProviderType) {
                for field in meta.fields {
                    if let value = valueToSend(field: field, config: config) {
                        fieldsToSend[field.name] = value
                    }
                }
            }

            let result = await viewModel.validateProvider(type: viewModel.selectedProviderType, fields: fieldsToSend)
            switch result {
            case let .success(message):
                validationSucceeded = true
                validationMessage = message
            case let .failure(error):
                validationSucceeded = false
                validationMessage = error.errorDescription ?? "Connection check failed."
            }
            isCheckingConnection = false
        }
    }

    private var isActiveProvider: Bool {
        viewModel.activeProvider?.type == viewModel.selectedProviderType
    }

    private var isFormValid: Bool {
        guard !viewModel.selectedProviderType.isEmpty else {
            return false
        }
        guard let meta = viewModel.providerMeta(for: viewModel.selectedProviderType) else {
            return true
        }

        for field in meta.fields where field.required {
            let trimmedValue = fieldValues[field.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            switch field.name {
            default:
                if field.secret == true {
                    if trimmedValue.isEmpty && !hasSecretConfigured(fieldName: field.name) {
                        return false
                    }
                } else if trimmedValue.isEmpty && (configuredValue(for: field.name, config: viewModel.configuredProvider(for: viewModel.selectedProviderType))?.isEmpty != false) {
                    return false
                }
            }
        }
        return true
    }

    private func placeholderText(for field: AIProviderField) -> String {
        let config = viewModel.configuredProvider(for: viewModel.selectedProviderType)
        let defaultValue = field.defaultValue ?? ""
        if field.secret == true {
            if secretMasked(for: field.name, config: config) {
                return maskedValue(for: field.name, config: config) ?? "••••••••"
            }
            if let value = configuredValue(for: field.name, config: config), !value.isEmpty {
                return value
            }
            return fieldLabel(for: field.name)
        }

        if let value = configuredValue(for: field.name, config: config), !value.isEmpty {
            return "Current: \(value)"
        }
        return defaultValue.isEmpty ? fieldLabel(for: field.name) : "Default: \(defaultValue)"
    }

    private func hasSecretConfigured(fieldName: String) -> Bool {
        guard let config = viewModel.configuredProvider(for: viewModel.selectedProviderType) else {
            return false
        }
        if secretMasked(for: fieldName, config: config) {
            return true
        }
        let value = configuredValue(for: fieldName, config: config)
        return value?.isEmpty == false
    }

    private func secretMasked(for fieldName: String, config: AIProviderConfig?) -> Bool {
        switch fieldName {
        case "api_key":
            return config?.apiKeyMasked == true
        default:
            return false
        }
    }

    private func maskedValue(for fieldName: String, config: AIProviderConfig?) -> String? {
        switch fieldName {
        case "api_key":
            return config?.apiKey
        default:
            return nil
        }
    }

    private func configuredValue(for fieldName: String, config: AIProviderConfig?) -> String? {
        switch fieldName {
        case "api_key":
            return config?.apiKey
        case "model":
            return config?.model
        case "base_url":
            return config?.baseUrl
        default:
            return nil
        }
    }

    private func valueToSend(field: AIProviderField, config: AIProviderConfig?) -> String? {
        let value = fieldValues[field.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)

        // For secret fields that are empty, don't send them at all (let backend preserve)
        if value.isEmpty && field.secret == true {
            return nil
        }

        // For non-secret fields or filled secret fields, check if changed
        if value.isEmpty {
            return nil
        }
        if let currentValue = configuredValue(for: field.name, config: config),
           currentValue == value {
            return nil
        }

        return value
    }

    private func clearValidationState() {
        validationMessage = nil
        validationSucceeded = nil
    }

    private func fieldLabel(for fieldName: String) -> String {
        fieldName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func autocompleteList(options: [AIFieldOption], currentValue: String, onSelect: @escaping (String) -> Void) -> some View {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = options.filter { option in
            trimmed.isEmpty || option.value.localizedCaseInsensitiveContains(trimmed)
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(filtered.prefix(6), id: \.value) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    HStack(spacing: 8) {
                        Text(option.value)
                        if let description = option.description, !description.isEmpty {
                            Text("— \(description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(.white.opacity(0.5), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignTokens.border)
        )
    }

    private func fieldLabelView(label: String, hint: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.headline)
            if let hint, !hint.isEmpty {
                HelpButton(text: hint)
            }
        }
    }
}

private struct HelpButton: View {
    let text: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            tooltipContent
                .padding(10)
                .frame(maxWidth: 260, alignment: .leading)
                .padding(6)
                .presentationBackground(.clear)
        }
    }

    private var tooltipContent: some View {
        let parts = linkParts(from: text)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                switch part {
                case .text(let value):
                    Text(value)
                        .textSelection(.enabled)
                case .link(let url, let label):
                    Link(label, destination: url)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.primary)
    }

    private enum TooltipPart {
        case text(String)
        case link(URL, String)
    }

    private func linkParts(from text: String) -> [TooltipPart] {
        let nsText = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) ?? []
        guard !matches.isEmpty else {
            return [.text(text)]
        }

        var parts: [TooltipPart] = []
        var currentIndex = 0
        for match in matches {
            let range = match.range
            if range.location > currentIndex {
                let substring = nsText.substring(with: NSRange(location: currentIndex, length: range.location - currentIndex))
                parts.append(.text(substring))
            }
            if let url = match.url {
                let label = nsText.substring(with: range)
                parts.append(.link(url, label))
            }
            currentIndex = range.location + range.length
        }
        if currentIndex < nsText.length {
            let substring = nsText.substring(from: currentIndex)
            parts.append(.text(substring))
        }
        return parts
    }
}

#Preview {
    AIProviderSettingsView()
}
