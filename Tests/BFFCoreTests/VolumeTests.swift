import AVFoundation
import XCTest
@testable import BFFCore

/// The stream's own volume, which multiplies against the system's.
///
/// No network here either: `play()` is given a player factory that hands back
/// an itemless `AVPlayer`, so the call exercises the real code path without
/// opening the stream or making a sound.
@MainActor
final class VolumeTests: XCTestCase {
    private var suiteName = ""

    /// A private defaults domain per test, so these never read or write the
    /// volume the app is actually using on this machine.
    private func freshDefaults(function: String = #function) -> UserDefaults {
        suiteName = "volume-tests.\(function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        if !suiteName.isEmpty {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    /// The one that would otherwise ship silence to every new install:
    /// `UserDefaults.double(forKey:)` answers 0 for a key that was never set.
    func testFreshInstallStartsAtFullVolume() {
        let player = PlayerController(defaults: freshDefaults())
        XCTAssertEqual(player.volume, 1.0, accuracy: 0.0001)
    }

    func testStoredVolumeIsRestored() {
        let defaults = freshDefaults()
        defaults.set(0.4, forKey: PlayerController.volumeKey)

        let player = PlayerController(defaults: defaults)
        XCTAssertEqual(player.volume, 0.4, accuracy: 0.0001)
    }

    func testVolumeSurvivesRelaunch() {
        let defaults = freshDefaults()
        PlayerController(defaults: defaults).volume = 0.25

        let relaunched = PlayerController(defaults: defaults)
        XCTAssertEqual(relaunched.volume, 0.25, accuracy: 0.0001)
    }

    func testStoredVolumeAboveRangeIsClamped() {
        let defaults = freshDefaults()
        defaults.set(4.2, forKey: PlayerController.volumeKey)

        XCTAssertEqual(PlayerController(defaults: defaults).volume, 1.0, accuracy: 0.0001)
    }

    func testStoredVolumeBelowRangeIsClamped() {
        let defaults = freshDefaults()
        defaults.set(-3.0, forKey: PlayerController.volumeKey)

        XCTAssertEqual(PlayerController(defaults: defaults).volume, 0.0, accuracy: 0.0001)
    }

    /// `play()` builds a brand new AVPlayer every time so it rejoins the live
    /// edge. A player born at full volume ignores the setting, so the stream
    /// would come back loud the first time you pressed Stop and Play again.
    func testPlayAppliesTheVolumeToTheNewPlayer() {
        let player = PlayerController(defaults: freshDefaults(),
                                      makePlayer: { _ in AVPlayer() })
        player.volume = 0.3
        player.play()

        XCTAssertEqual(player.playerVolume ?? -1, 0.3, accuracy: 0.0001)
        player.stop()
    }

    /// Dragging the slider mid-song has to be audible immediately, not on the
    /// next play.
    func testChangingVolumeWhilePlayingAppliesAtOnce() {
        let player = PlayerController(defaults: freshDefaults(),
                                      makePlayer: { _ in AVPlayer() })
        player.play()
        player.volume = 0.6

        XCTAssertEqual(player.playerVolume ?? -1, 0.6, accuracy: 0.0001)
        player.stop()
    }
}
