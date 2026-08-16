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

    func testReachingPlayingCancelsWatchdog() async {
        let player = PlayerController(loadingTimeout: stallTimeout)
        player.transition(to: .loading)
        player.transition(to: .playing)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .playing)
    }

    func testStopCancelsWatchdog() async {
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

    func testRecoveredStallDoesNotFireLater() async {
        // playing → stall → playing: the recovery must disarm the watchdog the
        // stall armed, not just the one play() armed.
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
