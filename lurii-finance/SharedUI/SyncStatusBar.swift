import SwiftUI

struct SyncStatusBar: View {
    let isConnected: Bool
    let version: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(AppTheme.statusColor(isConnected: isConnected))
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Disconnected")
                .font(.caption)

            if let version, isConnected {
                Text("v\(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignTokens.cardBackground)
        .clipShape(Capsule())
    }
}

#Preview {
    SyncStatusBar(isConnected: true, version: "1.0.0")
}
