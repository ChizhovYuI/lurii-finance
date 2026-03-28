import Foundation

enum GroupByMode: String, CaseIterable, Identifiable {
    case none
    case source
    case type

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .source: "Source"
        case .type: "Type"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "list.bullet"
        case .source: "tray.full"
        case .type: "tag"
        }
    }
}
