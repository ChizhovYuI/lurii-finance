import SwiftUI

/// Subtle secondary indicator for the background USD-valuation job that runs
/// after a collection completes. Slimmer than `CollectionProgressBar` so it
/// reads as a quiet background task rather than a primary action.
struct ValuationIndicator: View {
    let progress: Double
    let message: String

    var body: some View {
        HStack(spacing: DesignTokens.elementSpacing) {
            ProgressView()
                .controlSize(.small)

            Text(message.isEmpty ? "Valuing transactions…" : message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: DesignTokens.elementSpacing)

            ProgressView(value: progress)
                .frame(width: DesignTokens.inlineProgressWidth)

            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.blockPadding)
        .padding(.vertical, DesignTokens.elementSpacing)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius)
                .stroke(DesignTokens.border)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        ValuationIndicator(progress: 0.35, message: "Valuing transactions… 70/200")
        ValuationIndicator(progress: 0.9, message: "")
    }
    .padding()
}
