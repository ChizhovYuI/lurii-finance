import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DesignTokens.captionFont)
                .foregroundStyle(.secondary)

            Text(value)
                .font(DesignTokens.titleFont)

            if let subtitle {
                Text(subtitle)
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.border)
        )
    }
}

#Preview {
    StatCard(title: "Net Worth", value: "$124,500", subtitle: "Updated today")
        .padding()
}
