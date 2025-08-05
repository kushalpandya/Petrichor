import SwiftUI

struct PlaylistSortDropdown: View {
    let playlistID: UUID
    let viewType: LibraryViewType
    @ObservedObject var sortManager = PlaylistSortManager.shared
    
    private var currentCriteria: PlaylistSortManager.SortCriteria {
        sortManager.getSortCriteria(for: playlistID)
    }
    
    private var isAscending: Bool {
        sortManager.getSortAscending(for: playlistID)
    }
    
    var body: some View {
        Menu {
            // Sort criteria section
            Section {
                ForEach(PlaylistSortManager.SortCriteria.allCases, id: \.self) { criteria in
                    // Don't show "Custom" as a selectable option
                    if criteria != .custom {
                        Toggle(criteria.displayName, isOn: Binding(
                            get: { currentCriteria == criteria },
                            set: { _ in sortManager.setSortCriteria(criteria, for: playlistID) }
                        ))
                    }
                }
                
                // Show custom as disabled if it's current
                if currentCriteria == .custom {
                    Toggle("Custom", isOn: .constant(true))
                        .disabled(true)
                }
            }
            
            Divider()
            
            // Sort order section
            Section {
                Toggle("Ascending", isOn: Binding(
                    get: { isAscending },
                    set: { _ in sortManager.setSortAscending(true, for: playlistID) }
                ))
                
                Toggle("Descending", isOn: Binding(
                    get: { !isAscending },
                    set: { _ in sortManager.setSortAscending(false, for: playlistID) }
                ))
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
        .help("Sort playlist tracks by \(getCurrentSortLabel())")
    }
    
    private func getCurrentSortLabel() -> String {
        let orderText = isAscending ? "↑" : "↓"
        
        switch currentCriteria {
        case .dateAdded:
            return "Date added \(orderText)"
        case .title:
            return "Title \(orderText)"
        case .custom:
            if let column = sortManager.getCustomSortColumn(for: playlistID) {
                // Capitalize first letter of column name
                let displayName = column.prefix(1).uppercased() + column.dropFirst()
                return "\(displayName) \(orderText)"
            }
            return "Custom \(orderText)"
        }
    }
}
