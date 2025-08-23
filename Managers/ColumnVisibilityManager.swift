//
// ColumnVisibilityManager class
//
// This class handles the column visibility for TrackTableView.
//

import Foundation
import Combine

class ColumnVisibilityManager: ObservableObject {
    static let shared = ColumnVisibilityManager()

    @Published var columnVisibility: TrackTableColumnVisibility {
        didSet {
            saveColumnVisibility()
        }
    }
    
    @Published var columnOrder: [String]? {
        didSet {
            saveColumnOrder()
        }
    }
    
    @Published var columnWidths: [String: CGFloat] = [:] {
        didSet {
            saveColumnWidths()
        }
    }

    private let columnVisibilityKey = "trackTableColumnVisibility"
    private let columnOrderKey = "trackTableColumnOrder"
    private let columnWidthsKey = "trackTableColumnWidths"

    private init() {
        // Load from UserDefaults on init
        if let data = UserDefaults.standard.data(forKey: columnVisibilityKey),
           let decoded = try? JSONDecoder().decode(TrackTableColumnVisibility.self, from: data) {
            self.columnVisibility = decoded
        } else {
            self.columnVisibility = TrackTableColumnVisibility()
        }
        self.columnOrder = UserDefaults.standard.array(forKey: columnOrderKey) as? [String]

        if let widths = UserDefaults.standard.dictionary(forKey: columnWidthsKey) as? [String: CGFloat] {
            self.columnWidths = widths
        }
    }

    private func saveColumnVisibility() {
        if let encoded = try? JSONEncoder().encode(columnVisibility) {
            UserDefaults.standard.set(encoded, forKey: columnVisibilityKey)
        }
    }
    
    private func saveColumnOrder() {
        if let order = columnOrder {
            UserDefaults.standard.set(order, forKey: columnOrderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: columnOrderKey)
        }
    }
    
    private func saveColumnWidths() {
        UserDefaults.standard.set(columnWidths, forKey: columnWidthsKey)
    }
    
    func toggleVisibility(_ column: TrackTableColumn) {
        columnVisibility.toggleVisibility(column)
    }

    func isVisible(_ column: TrackTableColumn) -> Bool {
        columnVisibility.isVisible(column)
    }

    func setVisibility(_ column: TrackTableColumn, isVisible: Bool) {
        columnVisibility.setVisibility(column, isVisible: isVisible)
    }
    
    func updateColumnOrder(_ order: [String]) {
        columnOrder = order
    }
    
    func setColumnWidth(_ columnId: String, width: CGFloat) {
        columnWidths[columnId] = width
    }
    
    func getColumnWidth(_ columnId: String) -> CGFloat? {
        columnWidths[columnId]
    }
}
