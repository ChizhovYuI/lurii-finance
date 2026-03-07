import Foundation

enum AppRelauncher {
    private static let preferredInstalledPath = "/Applications/Lurii Finance.app"

    static func scheduleRelaunch() {
        guard let executableURL = executableURL() else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 2; open -n \(shellQuote(executableURL.path))",
        ]

        do {
            try process.run()
        } catch {
            // Ignore relaunch failures; the app is about to terminate anyway.
        }
    }

    private static func executableURL() -> URL? {
        let installedURL = URL(fileURLWithPath: preferredInstalledPath)
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return installedURL
        }
        return Bundle.main.bundleURL
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
