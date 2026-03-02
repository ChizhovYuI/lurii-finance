import ServiceManagement
import SwiftUI

struct SettingsRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case about
        case ai

        var id: String { rawValue }

        var title: String {
            switch self {
            case .about:
                return "About"
            case .ai:
                return "AI"
            }
        }
    }

    @State private var selectedSection: Section = .about

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
                case .about:
                    AboutView()
                case .ai:
                    AISettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
    }
}

private struct AboutView: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 20) {
            // Note: Add an image set named "app-logo" to Assets.xcassets
            Image("app-logo")
                .resizable()
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Text("Lurii Finance")
                .font(.title)
                .fontWeight(.semibold)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Portfolio management and tracking")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle("Open at Login", isOn: $openAtLogin)
                .toggleStyle(.switch)
                .frame(maxWidth: 200)
                .onChange(of: openAtLogin) { _, newValue in
                    let service = SMAppService.mainApp
                    do {
                        if newValue {
                            try service.register()
                        } else {
                            try service.unregister()
                        }
                    } catch {
                        openAtLogin = service.status == .enabled
                    }
                }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
}

#Preview {
    SettingsRootView()
}
