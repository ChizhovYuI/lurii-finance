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
    @EnvironmentObject private var appState: AppState
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isCheckingUpdates = false

    private var updates: UpdatesResponse? { appState.updates }

    private var appVersion: String? {
        appState.runningAppVersion
    }

    private var appUpdateAvailable: Bool {
        guard let current = appVersion, let latest = updates?.app.latest else { return false }
        return latest != current
    }

    private var anyUpdateAvailable: Bool {
        (updates?.pfm.updateAvailable ?? false) || appUpdateAvailable
    }

    private var restartPending: Bool {
        appState.restartNeeded
    }

    private var backendDisplayVersion: String? {
        guard let updates else { return nil }
        if let installed = updates.pfm.installed, installed != updates.pfm.current {
            return installed
        }
        if updates.pfm.updateAvailable {
            return updates.pfm.latest
        }
        return nil
    }

    private var appDisplayVersion: String? {
        guard let updates else { return nil }
        if let current = appVersion, let installed = updates.app.installed, installed != current {
            return installed
        }
        if let current = appVersion, let latest = updates.app.latest, latest != current {
            return latest
        }
        return nil
    }

    private var shouldShowUpdateMessage: Bool {
        !appState.updateMessage.isEmpty && (appState.updateInstalling || appState.updateStatus == "installed" || appState.updateStatus == "error")
    }

    var body: some View {
        VStack(spacing: 20) {
            Image("app-logo")
                .resizable()
                .frame(width: 128, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Text("Lurii Finance")
                .font(.title)
                .fontWeight(.semibold)

            if let version = appVersion,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Portfolio management and tracking")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Version info & update section
            if let updates {
                VStack(spacing: 8) {
                    HStack {
                        Text("Backend")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(updates.pfm.current)
                        if let displayVersion = backendDisplayVersion {
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(displayVersion)
                                .foregroundStyle(.green)
                        }
                    }

                    if updates.app.latest != nil || updates.app.installed != nil {
                        HStack {
                            Text("App")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(appVersion ?? "?")
                            if let displayVersion = appDisplayVersion {
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(displayVersion)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .font(.callout.monospacedDigit())
                .frame(maxWidth: 260)

                if appState.updateInstalling {
                    VStack(spacing: 6) {
                        ProgressView(value: appState.updateProgress)
                            .frame(maxWidth: 260)
                    }
                } else if restartPending {
                    Button {
                        restartAfterUpdate()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                        Text("Restart")
                    }
                    .buttonStyle(.borderedProminent)
                } else if anyUpdateAvailable {
                    Button {
                        installUpdates()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                        Text("Install Updates")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        forceCheckUpdates()
                    } label: {
                        if isCheckingUpdates {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Checking...")
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text("Check for Updates")
                        }
                    }
                    .disabled(isCheckingUpdates)
                }

                if shouldShowUpdateMessage {
                    Text(appState.updateMessage)
                        .font(.caption)
                        .foregroundStyle(appState.updateStatus == "error" ? .red : .secondary)
                        .frame(maxWidth: 260)
                        .multilineTextAlignment(.center)
                }
            }

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
        .task { await appState.syncUpdateStatus() }
        .onReceive(NotificationCenter.default.publisher(for: .updateCompleted)) { _ in
            Task { await appState.syncUpdateStatus() }
        }
    }

    private func forceCheckUpdates() {
        isCheckingUpdates = true
        Task {
            defer { isCheckingUpdates = false }
            do {
                let response = try await APIClient.shared.forceCheckUpdates()
                appState.applyUpdatesResponse(response)
            } catch {
                // Fall back to regular check
                await appState.checkForUpdates()
            }
        }
    }

    private func installUpdates() {
        Task {
            do {
                try await APIClient.shared.installUpdate(target: "all")
            } catch {
                // Silently ignore — upgrade runs in background on the server
            }
        }
    }

    private func restartAfterUpdate() {
        Task {
            do {
                try await APIClient.shared.restartServices()
                AppRelauncher.scheduleRelaunch()
                NSApp.terminate(nil)
            } catch {
                appState.updateStatus = "error"
                appState.updateInstalling = false
                appState.updateMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    SettingsRootView()
}
