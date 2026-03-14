import ServiceManagement
import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = AboutViewModel()
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var summaryCardColumnHeight: CGFloat = 0

    private var updates: UpdatesResponse? { appState.updates }

    private var appVersion: String? {
        appState.runningAppVersion
    }

    private var appBuild: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
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

    private var shouldShowInstalledStatusInRestartRow: Bool {
        restartPending && appState.updateStatus == "installed" && !appState.updateMessage.isEmpty
    }

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("About")
                    .font(.title)
                    .foregroundStyle(.primary)

                heroCard
                summaryCardsRow
            }
            .padding(.leading, DesignTokens.pageContentPadding)
            .padding(.trailing, DesignTokens.pageContentTrailingPadding)
            .padding(.top, DesignTokens.pageContentPadding)
            .padding(.bottom, DesignTokens.pageContentPadding)
        }
        .navigationTitle("About")
        .task {
            guard !isPreview else { return }
            await viewModel.syncUpdateStatus(using: appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateCompleted)) { _ in
            Task {
                await viewModel.syncUpdateStatus(using: appState)
            }
        }
    }

    private var summaryCardsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Updates")
                updatesCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: summaryCardColumnHeight == 0 ? nil : summaryCardColumnHeight, alignment: .topLeading)
            .background(summaryHeightReader)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Preferences")
                preferencesCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: summaryCardColumnHeight == 0 ? nil : summaryCardColumnHeight, alignment: .topLeading)
            .background(summaryHeightReader)
        }
        .onPreferenceChange(AboutSummaryColumnHeightPreferenceKey.self) { height in
            if height > 0, abs(height - summaryCardColumnHeight) > 0.5 {
                summaryCardColumnHeight = height
            }
        }
    }

    private var summaryHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: AboutSummaryColumnHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var heroCard: some View {
        AboutSurfaceCard {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lurii Finance")
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(.primary)

                    if let version = appVersion {
                        let buildSuffix = appBuild.map { " (\($0))" } ?? ""
                        Text("Version \(version)\(buildSuffix)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text("Portfolio management and tracking across the app and backend stack.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var updatesCard: some View {
        AboutSurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                if let updates {
                    versionRow(title: "Backend", currentVersion: updates.pfm.current, targetVersion: backendDisplayVersion)

                    if updates.app.latest != nil || updates.app.installed != nil {
                        versionRow(title: "App", currentVersion: appVersion ?? "?", targetVersion: appDisplayVersion)
                    }

                    if appState.updateInstalling {
                        ProgressView(value: appState.updateProgress)
                            .frame(maxWidth: 280)
                    }

                    actionButton

                    if !anyUpdateAvailable, !restartPending, !appState.updateInstalling {
                        AboutInlineNotice(
                            title: "Everything is up to date.",
                            systemImage: "checkmark.circle.fill",
                            tint: DesignTokens.success
                        )
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading update status…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if shouldShowUpdateMessage && !shouldShowInstalledStatusInRestartRow {
                    AboutInlineNotice(
                        title: appState.updateMessage,
                        systemImage: appState.updateStatus == "error" ? "xmark.circle.fill" : "info.circle",
                        tint: appState.updateStatus == "error" ? DesignTokens.error : .secondary
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if restartPending {
            HStack(spacing: 10) {
                Button {
                    appState.restartAfterUpdate()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)

                if shouldShowInstalledStatusInRestartRow {
                    AboutStatusBadge(
                        title: appState.updateMessage,
                        systemImage: "checkmark.circle.fill",
                        tint: DesignTokens.success
                    )
                }
            }
        } else if anyUpdateAvailable {
            Button {
                Task {
                    await appState.installUpdatesManually()
                }
            } label: {
                Label("Install Updates", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
        } else {
            Button {
                Task {
                    await viewModel.forceCheckUpdates(using: appState)
                }
            } label: {
                if viewModel.isCheckingUpdates {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(viewModel.isCheckingUpdates)
        }
    }

    private var preferencesCard: some View {
        AboutSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open at Login")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Launch the app automatically when you sign in to your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 16)

                    Toggle("Open at Login", isOn: $openAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func versionRow(title: String, currentVersion: String, targetVersion: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(currentVersion)
                .foregroundStyle(.primary)

            if let targetVersion {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(targetVersion)
                    .foregroundStyle(DesignTokens.success)
            }
        }
        .font(.callout.monospacedDigit())
    }
}

private struct AboutSummaryColumnHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AboutSurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DesignTokens.blockPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .glassEffect(in: .rect(cornerRadius: DesignTokens.blockCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                    .stroke(DesignTokens.border)
            )
    }
}

private struct AboutInlineNotice: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AboutStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

#Preview {
    AboutSettingsView()
        .environmentObject(AppState())
}
