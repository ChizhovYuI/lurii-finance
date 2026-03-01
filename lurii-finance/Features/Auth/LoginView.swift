import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isChecking = false
    @State private var errorMessage: String?

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect to Lurii Daemon")
                .font(.title2)

            if isChecking {
                ProgressView("Checking health...")
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

        Task {
            do {
                let health = try await APIClient.shared.getHealth()
                appState.updateFromHealth(health)
                let collectStatus = try await APIClient.shared.getCollectStatus()
                appState.updateCollectStatus(collectStatus)
            } catch {
                appState.markDisconnected()
                let description = (error as NSError).localizedDescription
                errorMessage = "Unable to reach daemon. \(description)"
            }
            isChecking = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
