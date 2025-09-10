import Foundation

enum TableRowSize: String, CaseIterable, Codable {
    case expanded
    case compact
    
    var displayName: String {
        switch self {
        case .expanded: return "Expanded"
        case .compact: return "Compact"
        }
    }
    
    var rowHeight: CGFloat {
        switch self {
        case .expanded: return ViewDefaults.listArtworkSize + 16
        case .compact: return 28
        }
    }
}
