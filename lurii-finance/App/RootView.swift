import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        Group {
            if appState.isConnected {
                MainShellView()
            } else {
                LoginView()
            }
        }
        .frame(minWidth: 1024, minHeight: 700)
        .onAppear {
            guard !isPreview else { return }
            appState.startEventStream()
        }
        .onDisappear {
            guard !isPreview else { return }
            appState.stopEventStream()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
