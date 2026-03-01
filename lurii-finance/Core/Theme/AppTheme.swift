import SwiftUI

enum AppTheme {
    static func statusColor(isConnected: Bool) -> Color {
        isConnected ? DesignTokens.success : DesignTokens.error
    }
}
