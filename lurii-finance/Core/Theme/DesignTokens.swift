import SwiftUI

enum DesignTokens {
    static let accent = Color("AccentColor")
    static let cardBackground = Color.gray.opacity(0.12)
    static let border = Color.gray.opacity(0.2)
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    static let titleFont = Font.system(size: 22, weight: .semibold)
    static let bodyFont = Font.system(size: 14)
    static let captionFont = Font.system(size: 12, weight: .medium)
}
