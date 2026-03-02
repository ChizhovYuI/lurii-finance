import Foundation

enum DaemonLauncher {
    enum LaunchError: LocalizedError {
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                "pfm not found at /opt/homebrew/bin/pfm or /usr/local/bin/pfm"
            case .failed(let output):
                "pfm daemon start failed: \(output)"
            }
        }
    }

    private static let searchPaths = [
        "/opt/homebrew/bin/pfm",  // Apple Silicon
        "/usr/local/bin/pfm",    // Intel
    ]

    private static func findPfm() -> String? {
        // Check well-known Homebrew paths first
        if let known = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return known
        }
        // Fallback: resolve via shell (covers custom Homebrew prefixes)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "which pfm"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }

    static func ensureRunning() async throws {
        guard let pfmPath = findPfm() else {
            throw LaunchError.notFound
        }

        let result = try await run(pfmPath, arguments: ["daemon", "start"])
        // Exit code 0 = started or already running
        if result.exitCode != 0 {
            throw LaunchError.failed(result.output)
        }
    }

    private struct RunResult {
        let exitCode: Int32
        let output: String
    }

    private static func run(_ path: String, arguments: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: RunResult(exitCode: process.terminationStatus, output: output))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
