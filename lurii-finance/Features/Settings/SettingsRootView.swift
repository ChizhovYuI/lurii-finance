import SwiftUI

struct SettingsRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general
        case ai
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .ai:
                return "AI"
            case .advanced:
                return "Advanced"
            }
        }
    }

    @State private var selectedSection: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $selectedSection) { section in
                Text(section.title)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

            Divider()

            Group {
                switch selectedSection {
                case .general:
                    SettingsPlaceholderView(title: "General Settings")
                case .ai:
                    AISettingsView()
                case .advanced:
                    SettingsPlaceholderView(title: "Advanced Settings")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
    }
}

private struct SettingsPlaceholderView: View {
    let title: String

    var body: some View {
        VStack {
            EmptyStateView(title: title, message: "Configuration options will appear here.")
        }
        .padding(24)
    }
}

#Preview {
    SettingsRootView()
}
