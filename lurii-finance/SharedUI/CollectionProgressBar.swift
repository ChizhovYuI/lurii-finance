import SwiftUI

struct CollectionProgressBar: View {
    let isCollecting: Bool
    let progress: Double
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if isCollecting {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isCollecting {
                ProgressView(value: progress)
            }
        }
        .padding(DesignTokens.blockPadding)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.blockCornerRadius))
    }

    private var statusText: String {
        if !message.isEmpty {
            return message
        }
        return isCollecting ? "Collecting..." : ""
    }
}

#Preview {
    VStack(spacing: 16) {
        CollectionProgressBar(isCollecting: true, progress: 0.42, message: "Fetched 5/12")
        CollectionProgressBar(isCollecting: false, progress: 1, message: "Done. 10 ok. 2 errors")
    }
    .padding()
}
