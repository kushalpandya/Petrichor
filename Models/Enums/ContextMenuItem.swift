import SwiftUI

enum ContextMenuItem {
    case button(title: String, icon: String? = nil, role: ButtonRole? = nil, action: () -> Void)
    case menu(title: String, icon: String? = nil, items: [ContextMenuItem])
    case divider

    var id: String {
        switch self {
        case .button(let title, _, _, _):
            return "button_\(title)"
        case .menu(let title, _, _):
            return "menu_\(title)"
        case .divider:
            return "divider_\(UUID().uuidString)"
        }
    }
    
    var icon: String? {
        if #available(macOS 26.0, *) {
            switch self {
            case .button(_, let icon, _, _), .menu(_, let icon, _):
                return icon
            case .divider:
                return nil
            }
        } else {
            return nil
        }
    }
    
    var title: String {
        switch self {
        case .button(let title, _, _, _), .menu(let title, _, _):
            return title
        case .divider:
            return ""
        }
    }
}
