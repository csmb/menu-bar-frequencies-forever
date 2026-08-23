import AVKit
import SwiftUI

/// The system AirPlay picker, sitting at the end of the volume row. The view
/// draws its own button and runs its own menu; our only job is pointing its
/// `player` at the stream, and that is `PlayerController`'s job rather than
/// this view's — every play() and every reconnect builds a new AVPlayer, and
/// the controller is the one that knows when.
struct RoutePickerView: NSViewRepresentable {
    let player: PlayerController

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        player.attachRoutePicker(picker)
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
