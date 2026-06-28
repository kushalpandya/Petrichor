import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var selectedTab: SettingsTab = .general
    
    @Environment(\.dismiss)
    var dismiss

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case library = "Library"
        case integrations = "Integrations"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return Icons.settings
            case .appearance: return Icons.paintpalette
            case .library: return Icons.customMusicNoteRectangleStack
            case .integrations: return Icons.globe
            case .about: return Icons.infoCircle
            }
        }

        var selectedIcon: String {
            switch self {
            case .general: return Icons.settings
            case .appearance: return Icons.paintpalette
            case .library: return Icons.customMusicNoteRectangleStack
            case .integrations: return Icons.globe
            case .about: return Icons.infoCircleFill
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: { dismiss() }, label: {
                        Image(systemName: Icons.xmarkCircleFill)
                            .font(.title2)
                            .foregroundColor(.secondary)
                    })
                    .help("Dismiss")
                    .buttonStyle(.plain)
                    .focusable(false)
                    
                    Spacer()
                }
                
                TabbedButtons(
                    items: SettingsTab.allCases,
                    selection: $selectedTab,
                    style: tabbedButtonStyle,
                    animation: .transform
                )
                .focusable(false)
            }
            .padding(10)

            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralTabView()
                case .appearance:
                    AppearanceTabView()
                case .library:
                    LibraryTabView()
                case .integrations:
                    IntegrationsTabView()
                case .about:
                    AboutTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 650, height: 670)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SettingsSelectTab"))) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
    }
    
    private var tabbedButtonStyle: TabbedButtonStyle {
        if #available(macOS 26.0, *) {
            return .moderncompact
        } else {
            return .compact
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject({
            let manager = LibraryManager()
            return manager
        }())
}
