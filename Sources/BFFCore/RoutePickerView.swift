import AVKit
import SwiftUI

/// The system AirPlay picker, sitting at the end of the volume row. The view
/// draws its own button and runs its own menu; its `player` is deliberately
/// never set.
///
/// Attaching our AVPlayer is the obvious wiring and it is broken on macOS:
/// with `player` set, the picker's checkboxes toggle and the audio stays on
/// the Mac (Apple Developer Forums threads 708248 and 744128 — the exact
/// symptom this app shipped with once). Left nil, the picker routes the
/// app's CoreMedia audio as a whole, which is our single AVPlayer — the same
/// shape Radiola ships. App-scoped routing also means there is nothing to
/// re-apply when play() or a reconnect rebuilds the player.
struct RoutePickerView: NSViewRepresentable {
    static func makePicker() -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        return picker
    }

    func makeNSView(context: Context) -> AVRoutePickerView {
        Self.makePicker()
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
