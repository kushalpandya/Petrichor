import SwiftUI

struct LibraryTypeSidebarView: View {
    @EnvironmentObject var libraryManager: LibraryManager

    @Binding var selectedFilterType: LibraryFilterType

    @State private var selectedItem: LibraryTypeSidebarItem?

    private let items = LibraryFilterType.allCases.map(LibraryTypeSidebarItem.init)

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(opaque: true) {
                Text("")
                    .headerTitleStyle()
                Spacer()
            }

            Divider()

            SidebarView(
                items: items,
                selectedItem: $selectedItem,
                onItemTap: { item in
                    selectedFilterType = item.filterType
                },
                contextMenuItems: { item in
                    [libraryManager.createCategoryPinContextMenuItem(for: item.filterType)]
                }
            )
        }
        .onAppear {
            syncSelection()
        }
        .onChange(of: selectedFilterType) {
            syncSelection()
        }
    }

    private func syncSelection() {
        let matching = items.first { $0.filterType == selectedFilterType }
        if selectedItem != matching {
            selectedItem = matching
        }
    }
}

#Preview {
    @Previewable @State var selectedFilterType: LibraryFilterType = .artists

    LibraryTypeSidebarView(selectedFilterType: $selectedFilterType)
        .environmentObject(LibraryManager())
        .frame(width: 250, height: 500)
}
