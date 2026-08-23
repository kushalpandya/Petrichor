import AVKit
import SwiftUI

struct AirPlayRoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let routePicker = AVRoutePickerView()
        routePicker.isRoutePickerButtonBordered = false
        return routePicker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
