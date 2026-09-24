import XCTest
@testable import BFFCore

/// Exercises the `.loading` watchdog through `transition(to:)` — the same
/// funnel `play()`, `stop()` and the AVPlayer sinks use — so no stream, and no
/// network, is involved.
@MainActor
final class PlayerControllerTests: XCTestCase {
    private let stallTimeout = Duration.milliseconds(50)
    private let timedOut = PlayerController.State.failed("Couldn’t reach the BFF.fm stream")

    private func waitPastTimeout() async {
        try? await Task.sleep(for: .milliseconds(750))
    }

    func testStallThatNeverRecoversFails() async {
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        XCTAssertEqual(player.state, .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, timedOut)
    }

    /// The watchdog bounds connecting, not playback: reaching `.playing` before
    /// it fires means it never fails the stream. These tests are named for the
    /// outcome because the outcome is all they can see — the watchdog checks
    /// the state before acting, so each passes with or without the cancel.
    /// What cancelling on `.playing` buys is a fresh watchdog for the next
    /// stall, and `testStallAfterPlayingIsStillBounded` fails without it.
    func testAPlayingStreamIsNotFailedByTheWatchdog() async {
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.transition(to: .playing)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .playing)
    }

    /// A Stop pressed while connecting stays a Stop: the watchdog's deadline
    /// passing afterwards must not turn it into `.failed`.
    func testTheWatchdogNeverOverridesAStop() async {
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.stop()
        await waitPastTimeout()
        XCTAssertEqual(player.state, .stopped)
    }

    /// The reported defect: a stall partway through playback used to park the
    /// UI in `.loading` forever, with the icon still claiming it was playing.
    func testStallAfterPlayingIsStillBounded() async {
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.transition(to: .playing)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, timedOut)
    }

    func testARecoveredStallIsNotFailedLater() async {
        // playing → stall → playing: once the stall recovers, the watchdog it
        // armed must not fail the stream when its deadline comes.
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.transition(to: .playing)
        player.transition(to: .loading)
        player.transition(to: .playing)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .playing)
    }

    func testLoadingAgainAfterTeardownRearmsWatchdog() async {
        // stop() tears down and clears the watchdog; the next .loading — what
        // play() does after its own teardown() — must arm a fresh one.
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.stop()
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, timedOut)
    }
}
