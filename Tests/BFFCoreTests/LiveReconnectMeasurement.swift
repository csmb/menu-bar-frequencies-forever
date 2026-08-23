import AVFoundation
import XCTest
@testable import BFFCore

/// End-to-end proof against the real stream that a dropped connection comes
/// back on its own. Gated like TimeToAudioMeasurement, because it opens the
/// live stream twice:
///
///     LIVE_RECONNECT=1 swift test --filter LiveReconnectMeasurement
///
/// The "drop" is the same move the stall notification makes — park in
/// `.loading` — after which the shortened watchdog fails the player for real:
/// teardown, backoff gap, a genuinely new connection to the stream.
@MainActor
final class LiveReconnectMeasurement: XCTestCase {
    func testDropRecoversAgainstLiveStream() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIVE_RECONNECT"] == "1",
                          "Set LIVE_RECONNECT=1 to run against the real stream")
        let player = PlayerController(loadingTimeout: .seconds(3),
                                      reconnectDelays: [.milliseconds(200)],
                                      defaults: UserDefaults(suiteName: "live-reconnect-tests")!,
                                      workspaceNotifications: NotificationCenter())
        player.play()
        try await waitFor(player, toReach: .playing, within: .seconds(15))

        player.transition(to: .loading)   // the stall notification's move
        try await waitFor(player, toReach: .reconnecting, within: .seconds(5))
        try await waitFor(player, toReach: .playing, within: .seconds(15))
        player.stop()
    }

    private func waitFor(_ player: PlayerController,
                         toReach target: PlayerController.State,
                         within limit: Duration) async throws {
        let deadline = ContinuousClock.now + limit
        while player.state != target {
            if ContinuousClock.now > deadline {
                XCTFail("timed out waiting for \(target); still \(player.state)")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
