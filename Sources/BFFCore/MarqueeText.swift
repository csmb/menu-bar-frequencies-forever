import SwiftUI

/// One line of text that scrolls itself when it is too wide to fit.
///
/// Text that already fits renders as a plain `Text` with no animation at all —
/// the scroll exists only for the long show names and song titles that would
/// otherwise be cut off. Each pass holds still at both ends so the start and
/// the end of the line are each readable, then jumps back and repeats.
///
/// Font and color come from the environment, so callers style this the same
/// way they would style a `Text`.
struct MarqueeText: View {
    let text: String

    /// Points per second the text travels while it is moving.
    private let speed: CGFloat = 30
    /// Seconds held still at the start and at the end of each pass.
    private let pause: TimeInterval = 2

    @State private var textWidth: CGFloat = 0

    var body: some View {
        // A normally-laid-out copy establishes this row's height and its
        // available width, but never draws. Everything visible lives in the
        // overlay — an overlay can't stretch its parent, which is what keeps
        // the full-width `line` below from widening the whole dropdown.
        Text(text)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    marquee(containerWidth: proxy.size.width)
                }
            }
            .clipped()
    }

    @ViewBuilder
    private func marquee(containerWidth: CGFloat) -> some View {
        let overflow = max(0, textWidth - containerWidth)
        if overflow > 0 {
            KeyframeAnimator(initialValue: CGFloat.zero, repeating: true) { offset in
                line.offset(x: offset)
            } keyframes: { _ in
                LinearKeyframe(CGFloat.zero, duration: pause)
                LinearKeyframe(-overflow, duration: TimeInterval(overflow / speed))
                LinearKeyframe(-overflow, duration: pause)
            }
            // Start a fresh cycle when the track changes, so a new song
            // doesn't inherit the previous line's scroll position.
            .id(text)
        } else {
            line
        }
    }

    /// The text at its full intrinsic width — wider than the container when it
    /// overflows, which is exactly what makes the offset animation visible.
    private var line: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .measuringWidth(into: $textWidth)
    }
}

private extension View {
    /// Reports this view's rendered width into `width`, keeping it current as
    /// the layout changes.
    func measuringWidth(into width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width.wrappedValue = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, new in
                        width.wrappedValue = new
                    }
            }
        }
    }
}
