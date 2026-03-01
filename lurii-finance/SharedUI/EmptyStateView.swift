import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(DesignTokens.bodyFont)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}

#Preview {
    EmptyStateView(title: "No data yet", message: "Connect a source to start collecting.")
}
