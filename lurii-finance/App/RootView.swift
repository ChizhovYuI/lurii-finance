import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        ZStack {
            WindowGlassBackground()
                .ignoresSafeArea()

            Group {
                if appState.isConnected {
                    MainShellView()
                } else {
                    LoginView()
                }
            }
        }
        .background(WindowChromeConfigurator())
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

private struct WindowGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.blendingMode = .withinWindow
        view.material = .underWindowBackground
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.blendingMode = .withinWindow
        nsView.material = .underWindowBackground
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowChromeHostView {
        WindowChromeHostView(frame: .zero)
    }

    func updateNSView(_ nsView: WindowChromeHostView, context: Context) {
        nsView.applyWindowStyleIfPossible()
    }
}

private final class WindowChromeHostView: NSView {
    private var observerTokens: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resetObservers()
        applyWindowStyleIfPossible()
        registerObservers()

        // AppKit may restore separator during/after layout transitions.
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowStyleIfPossible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.applyWindowStyleIfPossible()
        }
    }

    deinit {
        resetObservers()
    }

    func applyWindowStyleIfPossible() {
        guard let window else { return }
        window.titlebarSeparatorStyle = .none
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
    }

    private func registerObservers() {
        guard let window else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification
        ]
        for name in names {
            let token = center.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.applyWindowStyleIfPossible()
            }
            observerTokens.append(token)
        }
    }

    private func resetObservers() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
