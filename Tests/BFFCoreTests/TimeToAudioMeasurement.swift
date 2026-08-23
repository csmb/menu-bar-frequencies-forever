import XCTest
@testable import BFFCore

/// Not a test — a measurement, and the only thing here that opens the real
/// stream. It is skipped unless `MEASURE_TIME_TO_AUDIO=1`, so `make test`
/// stays offline, silent, and fast.
///
///     MEASURE_TIME_TO_AUDIO=1 swift test --filter TimeToAudioMeasurement
///
/// Reports the interval from `play()` to `.playing` — the wait between
/// pressing the button and hearing the station. Each run holds the connection
/// only until playback starts, then drops it.
@MainActor
final class TimeToAudioMeasurement: XCTestCase {
    private let runs = 4
    private let giveUpAfter = 15.0

    /// What the first press of Play pays to rasterise the animation, on top
    /// of the network wait. `playingFrames` is a lazy static, so this is the
    /// real first-access cost in a fresh process.
    func testIconFrameRenderCost() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MEASURE_TIME_TO_AUDIO"] == "1",
            "measurement only")

        let started = Date()
        let frames = StatusIcon.playingFrames
        let elapsed = Date().timeIntervalSince(started)
        print(String(format: "  playingFrames: %d frames, first access %.1fms",
                     frames.count, elapsed * 1000))

        let again = Date()
        _ = StatusIcon.playingFrames
        print(String(format: "  playingFrames: cached access %.3fms",
                     Date().timeIntervalSince(again) * 1000))
    }

    func testTimeToAudio() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MEASURE_TIME_TO_AUDIO"] == "1",
            "measurement only — set MEASURE_TIME_TO_AUDIO=1 to run it")

        var samples: [Double] = []

        for run in 1...runs {
            let player = PlayerController()
            let started = Date()
            player.play()

            var reached: Double?
            var claimed: Double?
            while Date().timeIntervalSince(started) < giveUpAfter {
                if claimed == nil, player.state == .playing {
                    claimed = Date().timeIntervalSince(started)
                }
                // Buffer, not status. `.playing` fires the moment AVPlayer
                // stops waiting, which with stall-minimising off is well
                // before there is anything to hear.
                if player.isReadyForSmoothPlayback {
                    reached = Date().timeIntervalSince(started)
                    break
                }
                if case .failed(let message) = player.state {
                    print(String(format: "  run %d: failed — %@", run, message))
                    break
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            player.stop()

            if let reached {
                samples.append(reached)
                print(String(format: "  run %d: ready %.3fs   (state said .playing at %.3fs)",
                             run, reached, claimed ?? -1))
            } else {
                print("  run \(run): never became ready")
            }

            // Don't hammer the CDN with back-to-back reconnects.
            try? await Task.sleep(for: .seconds(3))
        }

        guard !samples.isEmpty else {
            XCTFail("no runs became ready")
            return
        }

        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let mean = samples.reduce(0, +) / Double(samples.count)
        print(String(format: "  --- n=%d  min %.3fs  median %.3fs  mean %.3fs  max %.3fs",
                     samples.count, sorted.first!, median, mean, sorted.last!))
    }
}
