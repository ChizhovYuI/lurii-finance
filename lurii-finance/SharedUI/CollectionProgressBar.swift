import SwiftUI

struct CollectionProgressBar: View {
    let isCollecting: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isCollecting ? "Collecting data" : "Collection idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: isCollecting ? progress : 0)
        }
        .padding(12)
        .background(DesignTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    CollectionProgressBar(isCollecting: true, progress: 0.42)
        .padding()
}
