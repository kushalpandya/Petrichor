import AppKit

enum ImageResizer {
    /// Resize an image from Data to specified size and return as JPEG Data
    /// - Parameters:
    ///   - imageData: Original image data
    ///   - size: Target size (will be used for both width and height)
    ///   - compressionFactor: JPEG compression quality (0.0 to 1.0)
    /// - Returns: Resized JPEG data, or nil if resizing fails
    static func resizeImage(from imageData: Data, to size: NSSize, compressionFactor: Float = 0.8) -> Data? {
        guard let image = NSImage(data: imageData) else { return nil }
        
        guard let resized = image.resized(to: size),
              let tiffData = resized.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor])
    }
    
    /// Common sizes used in the app
    enum Size {
        static let small = NSSize(width: 60, height: 60)    // Table view
        static let medium = NSSize(width: 80, height: 80)    // List view
        static let large = NSSize(width: 320, height: 320)   // Grid view
    }
}
