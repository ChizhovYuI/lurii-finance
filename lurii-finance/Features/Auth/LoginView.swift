import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isChecking = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect to Lurii Daemon")
                .font(.title2)

            if isChecking {
                ProgressView(statusMessage ?? "Checking health...")
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("The daemon must be running locally at 127.0.0.1:19274.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Retry") {
                    checkHealth()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 420)
        .padding(32)
        .onAppear {
            guard !isPreview else { return }
            checkHealth()
        }
    }

    private func checkHealth() {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        statusMessage = "Checking health..."

        Task {
            // First attempt
            if await tryConnect() { return }

            // Health check failed — try starting the daemon
            statusMessage = "Starting daemon..."
            do {
                try await DaemonLauncher.ensureRunning()
            } catch {
                fail("Failed to start daemon. \(error.localizedDescription)")
                return
            }

            // Give daemon time to boot
            try? await Task.sleep(for: .seconds(2))

            // Retry
            statusMessage = "Connecting..."
            if await tryConnect() { return }

            fail("Daemon started but not responding. Check pfm daemon status.")
        }
    }

    /// Attempts health + collect-status. Returns `true` on success.
    private func tryConnect() async -> Bool {
        do {
            let health = try await APIClient.shared.getHealth()
            appState.updateFromHealth(health)
            let collectStatus = try await APIClient.shared.getCollectStatus()
            appState.updateCollectStatus(collectStatus)
            isChecking = false
            return true
        } catch {
            return false
        }
    }

    private func fail(_ message: String) {
        appState.markDisconnected()
        errorMessage = message
        isChecking = false
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
