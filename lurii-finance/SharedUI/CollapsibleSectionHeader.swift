import SwiftUI

struct CollapsibleSectionHeader: View {
    let title: String
    let iconName: String?
    let iconIsSystemSymbol: Bool
    let totalUsdValue: String?
    let percentage: String?
    @Binding var isExpanded: Bool
    let hideBalance: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                if let iconName {
                    if iconIsSystemSymbol {
                        Image(systemName: iconName)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    } else {
                        Image(iconName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                    }
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                if let totalUsdValue {
                    Text(hideBalance ? "••••" : totalUsdValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                if let percentage {
                    Text(hideBalance ? "••••" : percentage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
