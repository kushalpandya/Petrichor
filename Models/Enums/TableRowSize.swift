import Foundation

enum TableRowSize: String, CaseIterable, Codable {
    case cozy
    case compact
    
    var displayName: String {
        switch self {
        case .cozy: return "Cozy"
        case .compact: return "Compact"
        }
    }
    
    var rowHeight: CGFloat {
        switch self {
        case .cozy: return ViewDefaults.listArtworkSize + 16
        case .compact: return 28
        }
    }
}
