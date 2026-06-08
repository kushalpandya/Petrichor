import Foundation

enum TableRowSize: String, CaseIterable, Codable {
    case expanded
    case compact
    
    var displayName: String {
        switch self {
        case .expanded: return String(localized: "Expanded")
        case .compact: return String(localized: "Compact")
        }
    }
    
    var rowHeight: CGFloat {
        switch self {
        case .expanded: return ViewDefaults.listArtworkSize + 16
        case .compact: return 28
        }
    }
}
