import AppKit
import AVFoundation
import XCTest
@testable import BFFCore

/// Auto-reconnect after a drop. Like PlayerControllerTests, these drive the
/// `transition(to:)` funnel with a fake player factory, so a "drop" is a stall
/// (`.playing` → `.loading`) that the watchdog times out — the same path a
/// dead Wi-Fi link takes — and no stream or network is involved.
@MainActor
final class ReconnectTests: XCTestCase {
    private let stallTimeout = Duration.milliseconds(50)
    private let timedOut = PlayerController.State.failed("Couldn’t reach the BFF.fm stream")

    /// Long enough for the watchdog, a short reconnect gap, and the retry's
    /// own watchdog to all have fired.
    private func waitPastTimeout() async {
        try? await Task.sleep(for: .milliseconds(750))
    }

    /// Polls instead of sleeping a fixed time, for a step that has to land
    /// inside a watchdog window. Answers whether the condition came true.
    private func waitUntil(within limit: Duration = .seconds(2),
                           _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// A controller whose `play()` builds a counted, itemless AVPlayer — the
    /// count is how these tests see reconnect attempts happen. `steadyAfter`
    /// defaults to a minute, which no test here lives long enough to reach.
    private func makeController(reconnectDelays: [Duration],
                                builds: Builds,
                                workspaceNotifications: NotificationCenter = .init(),
                                loadingTimeout: Duration? = nil,
                                steadyAfter: Duration = .seconds(60)) -> PlayerController {
        PlayerController(loadingTimeout: loadingTimeout ?? stallTimeout,
                         reconnectDelays: reconnectDelays,
                         steadyAfter: steadyAfter,
                         defaults: UserDefaults(suiteName: "reconnect-tests")!,
                         workspaceNotifications: workspaceNotifications,
                         makePlayer: { item in
                             builds.count += 1
                             builds.lastItem = item
                             return InertPlayer()
                         })
    }

    /// A bare `AVPlayer()` told to play reports `.waitingToPlayAtSpecifiedRate`
    /// — it has no item — and the controller reads that as a stall, so every
    /// test would get a drop it never staged, and a test could pass on the
    /// watchdog alone. This one never starts, leaving the state to the test.
    private final class InertPlayer: AVPlayer {
        override func play() {}
    }

    /// `lastItem` is the stream item the controller built and is watching —
    /// the object its AVPlayerItem notifications are filtered on.
    final class Builds {
        var count = 0
        var lastItem: AVPlayerItem?
    }

    /// Playback reached `.playing`, then dropped: instead of the terminal
    /// `.failed` the app used to show, the controller waits out a backoff gap.
    func testDropWhilePlayingEntersReconnecting() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.seconds(10)], builds: builds)
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)   // the stall notification's move
        await waitPastTimeout()           // watchdog fires → the old dead end
        XCTAssertEqual(player.state, .reconnecting)
        player.stop()
    }

    /// A live stream has no end, so reaching one means the server closed the
    /// connection cleanly — a source restart, a relay recycling listeners.
    /// AVPlayer reports that as the item finishing and quietly pauses: no
    /// error, no stall, nothing for the watchdog. It has to count as a drop,
    /// or the app sits in `.playing` over silence for good.
    func testStreamEndingWhilePlayingReconnects() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.seconds(10)], builds: builds)
        player.play()
        player.transition(to: .playing)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification,
                                        object: builds.lastItem)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .reconnecting)
        player.stop()
    }

    func testReconnectAttemptRebuildsThePlayer() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.milliseconds(10)], builds: builds)
        player.play()
        XCTAssertEqual(builds.count, 1)
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(builds.count, 2)
        player.stop()
    }

    /// The budget is the good-guest bound: when every gap has been used, the
    /// controller settles into the same `.failed` it always showed, rather
    /// than hammering the stream forever.
    func testGivesUpIntoFailedWhenBudgetExhausted() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.milliseconds(10)], builds: builds)
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, timedOut)
        XCTAssertEqual(builds.count, 2)   // exactly one retry for one gap
    }

    /// Stop means stop: a press during the gap must not leave a timer behind
    /// that restarts the stream after the user walked away.
    func testStopDuringReconnectCancelsIt() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.seconds(10)], builds: builds)
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .reconnecting)
        player.stop()
        await waitPastTimeout()
        XCTAssertEqual(player.state, .stopped)
        XCTAssertEqual(builds.count, 1)
    }

    /// Reconnect recovers drops, not failed first connects: Play against a
    /// down stream should still fail honestly within one watchdog, not spin
    /// through the whole backoff schedule first.
    func testFailedFirstConnectDoesNotReconnect() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.milliseconds(10)], builds: builds)
        player.play()
        await waitPastTimeout()
        XCTAssertEqual(player.state, timedOut)
        XCTAssertEqual(builds.count, 1)
    }

    /// Each press of Play is a fresh incident with a fresh budget — a drop an
    /// hour ago must not eat this hour's retries.
    func testPlayGetsAFreshBudgetAfterAnEarlierDrop() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.seconds(10)], builds: builds)
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .reconnecting)   // budget's one gap in use
        player.stop()

        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .reconnecting)
        player.stop()
    }

    /// The budget bounds one incident, not a whole listening session. Once a
    /// reconnect has held steady, the next drop is a new incident with its own
    /// retries — otherwise a radio left on all day stops for good at its sixth
    /// drop, however cleanly it recovered from the first five.
    func testDropAfterSteadyPlaybackGetsItsOwnRetries() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.milliseconds(10)], builds: builds,
                                    loadingTimeout: .milliseconds(300),
                                    steadyAfter: .milliseconds(100))
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)                 // drop 1 spends the only retry
        let firstRetry = await waitUntil { builds.count == 2 }
        XCTAssertTrue(firstRetry)
        player.transition(to: .playing)                 // which works
        try? await Task.sleep(for: .milliseconds(250))  // and holds past steadyAfter
        player.transition(to: .loading)                 // drop 2, a new incident
        let secondRetry = await waitUntil { builds.count == 3 }
        XCTAssertTrue(secondRetry, "the second drop got no retry; builds: \(builds.count)")
        player.stop()
    }

    /// But only steady playback earns that. A stream that connects and drops
    /// again straight away is still one incident, and has to run out of
    /// retries rather than cycle forever — the good-guest bound.
    func testQuickDropsStillExhaustTheBudget() async {
        let builds = Builds()
        let player = makeController(reconnectDelays: [.milliseconds(10)], builds: builds,
                                    loadingTimeout: .milliseconds(300),
                                    steadyAfter: .milliseconds(100))
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)                 // drop 1 spends the only retry
        let firstRetry = await waitUntil { builds.count == 2 }
        XCTAssertTrue(firstRetry)
        player.transition(to: .playing)                 // connects...
        player.transition(to: .loading)                 // ...and drops at once
        try? await Task.sleep(for: .milliseconds(600))  // its watchdog, and then some
        XCTAssertEqual(builds.count, 2)
        XCTAssertEqual(player.state, timedOut)
    }

    /// `toggle()` reads `isActive`; while reconnecting the button must act as
    /// Stop, not Play.
    func testReconnectingIsActive() {
        XCTAssertTrue(PlayerController.State.reconnecting.isActive)
    }

    // MARK: - Wake from sleep

    /// Waking never delivers a notification instantly — give the main-queue
    /// hop time to happen, without waiting out a whole watchdog.
    private func waitForNotificationDelivery() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    /// The pre-sleep connection is dead even when AVPlayer has not noticed
    /// yet, so a wake during playback rebuilds at the live edge instead of
    /// waiting for the stall to surface.
    func testWakeWhilePlayingRebuildsThePlayer() async {
        let builds = Builds()
        let wake = NotificationCenter()
        let player = makeController(reconnectDelays: [.seconds(10)],
                                    builds: builds, workspaceNotifications: wake)
        player.play()
        player.transition(to: .playing)
        wake.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForNotificationDelivery()
        XCTAssertEqual(builds.count, 2)
        player.stop()
    }

    func testWakeWhileStoppedDoesNothing() async {
        let builds = Builds()
        let wake = NotificationCenter()
        let player = makeController(reconnectDelays: [.seconds(10)],
                                    builds: builds, workspaceNotifications: wake)
        wake.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForNotificationDelivery()
        XCTAssertEqual(builds.count, 0)
        XCTAssertEqual(player.state, .stopped)
    }

    /// A wake mid-gap means the network story just changed; try now with a
    /// fresh budget rather than sitting out the rest of the backoff.
    func testWakeDuringReconnectRetriesAtOnce() async {
        let builds = Builds()
        let wake = NotificationCenter()
        let player = makeController(reconnectDelays: [.seconds(10)],
                                    builds: builds, workspaceNotifications: wake)
        player.play()
        player.transition(to: .playing)
        player.transition(to: .loading)
        await waitPastTimeout()
        XCTAssertEqual(player.state, .reconnecting)
        wake.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitForNotificationDelivery()
        XCTAssertEqual(builds.count, 2)
        player.stop()
    }

    /// Waking is not a new press of Play. Wi-Fi is often still rejoining when
    /// the notification lands, so the rebuild it triggers is the connection
    /// most likely to fail — the case the backoff exists for, not a dead end.
    func testFailedConnectAfterWakeStillReconnects() async {
        let builds = Builds()
        let wake = NotificationCenter()
        let player = makeController(reconnectDelays: [.seconds(10)],
                                    builds: builds, workspaceNotifications: wake)
        player.play()
        player.transition(to: .playing)
        wake.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitPastTimeout()           // the post-wake connect times out
        XCTAssertEqual(builds.count, 2)
        XCTAssertEqual(player.state, .reconnecting)
        player.stop()
    }

    /// But a wake does not invent a drop: if the stream never started before
    /// the sleep, the rebuild is still a first connect, and a first connect
    /// that fails says so rather than working through the backoff.
    func testWakeDuringFirstConnectStillFailsHonestly() async {
        let builds = Builds()
        let wake = NotificationCenter()
        let player = makeController(reconnectDelays: [.milliseconds(10)],
                                    builds: builds, workspaceNotifications: wake)
        player.play()                     // still connecting when the lid closes
        wake.post(name: NSWorkspace.didWakeNotification, object: nil)
        await waitPastTimeout()
        XCTAssertEqual(builds.count, 2)
        XCTAssertEqual(player.state, timedOut)
    }
}
