import Foundation

enum WebSyncProvider: String, CaseIterable, Identifiable {
    case mexc
    case emcd

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mexc:
            return "MEXC Earn"
        case .emcd:
            return "EMCD"
        }
    }

    var sourceType: String {
        switch self {
        case .mexc:
            return "mexc_earn"
        case .emcd:
            return "emcd"
        }
    }

    var identityCredentialKey: String {
        switch self {
        case .mexc:
            return "uid"
        case .emcd:
            return "email"
        }
    }

    var loginURL: URL {
        switch self {
        case .mexc:
            return URL(string: "https://www.mexc.com/earn")!
        case .emcd:
            return URL(string: "https://emcd.io/coinhold")!
        }
    }

    var cookieDomainSuffix: String {
        switch self {
        case .mexc:
            return "mexc.com"
        case .emcd:
            return "emcd.io"
        }
    }

    init?(sourceType: String) {
        switch sourceType.lowercased() {
        case "mexc_earn":
            self = .mexc
        case "emcd":
            self = .emcd
        default:
            return nil
        }
    }
}

struct WebSyncStatus: Equatable {
    var isSyncing: Bool
    var message: String?
    var errorMessage: String?
    var lastSyncedAt: Date?

    static let idle = WebSyncStatus(isSyncing: false, message: nil, errorMessage: nil, lastSyncedAt: nil)
}
