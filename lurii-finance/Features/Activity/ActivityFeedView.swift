import SwiftUI

struct ActivityFeedView: View {
    var body: some View {
        VStack {
            EmptyStateView(title: "Activity feed", message: "Coming soon in Phase 3b.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#Preview {
    ActivityFeedView()
}
