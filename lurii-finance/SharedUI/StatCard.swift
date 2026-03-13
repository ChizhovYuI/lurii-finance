import SwiftUI

struct StatCard: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)

            Text(appState.hideBalance ? "••••" : value)
                .font(DesignTokens.titleFont)

            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(DesignTokens.blockPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }
}

#Preview {
    StatCard(title: "Net Worth", value: "$124,500", subtitle: "Updated today")
        .environmentObject(AppState())
        .padding()
}
