import SwiftUI
import AppKit

struct IconOnlyDropdown<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let iconProvider: (Item) -> String
    let tooltipProvider: (Item) -> String
    
    @State private var isHovered = false
    
    var body: some View {
        IconOnlyDropdownRepresentable(
            items: items,
            selection: $selection,
            iconProvider: iconProvider,
            tooltipProvider: tooltipProvider
        )
        .frame(width: 44, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(NSColor.controlColor) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isHovered ? Color.primary.opacity(0.2) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltipProvider(selection))
    }
}

struct IconOnlyDropdownRepresentable<Item: Hashable>: NSViewRepresentable {
    let items: [Item]
    @Binding var selection: Item
    let iconProvider: (Item) -> String
    let tooltipProvider: (Item) -> String
    
    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        
        popUp.bezelStyle = .smallSquare
        popUp.controlSize = .regular
        popUp.imagePosition = .imageOnly
        popUp.isBordered = false
        
        updateMenu(popUp)
        
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.selectionChanged(_:))
        
        return popUp
    }
    
    func updateNSView(_ popUp: NSPopUpButton, context: Context) {
        if popUp.numberOfItems != items.count {
            updateMenu(popUp)
        }
        
        if let index = items.firstIndex(of: selection), popUp.indexOfSelectedItem != index {
            popUp.selectItem(at: index)
            updateIcon(popUp, for: selection)
        }
    }
    
    private func updateMenu(_ popUp: NSPopUpButton) {
        popUp.removeAllItems()
        
        for item in items {
            let menuItem = NSMenuItem(title: tooltipProvider(item), action: nil, keyEquivalent: "")
            
            if let image = NSImage(systemSymbolName: iconProvider(item), accessibilityDescription: tooltipProvider(item)) {
                menuItem.image = image.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            }
            
            popUp.menu?.addItem(menuItem)
        }
        
        if let index = items.firstIndex(of: selection) {
            popUp.selectItem(at: index)
            updateIcon(popUp, for: selection)
        }
    }
    
    private func updateIcon(_ popUp: NSPopUpButton, for item: Item) {
        if let image = NSImage(systemSymbolName: iconProvider(item), accessibilityDescription: tooltipProvider(item)) {
            popUp.image = image.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, items: items)
    }
    
    class Coordinator: NSObject {
        let selection: Binding<Item>
        let items: [Item]
        
        init(selection: Binding<Item>, items: [Item]) {
            self.selection = selection
            self.items = items
        }
        
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            if index >= 0 && index < items.count {
                selection.wrappedValue = items[index]
            }
        }
    }
}
