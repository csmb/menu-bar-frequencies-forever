import XCTest
@testable import BFFCore

/// The note under the controls when now.json can't be fetched. These pin which
/// note shows, not its wording, so the copy can change without them.
@MainActor
final class InfoNoteTests: XCTestCase {
    /// Wi-Fi off: the fetch fails as offline, and the note says so — not
    /// "playback is fine" beside a stream that is failing too, putting it
    /// down to BFF.fm.
    func testOfflineSaysOffline() {
        for player: PlayerController.State in [.stopped, .loading, .reconnecting, .failed("gone")] {
            XCTAssertEqual(MenuView.infoNote(for: .offline, player: player), .offline, "\(player)")
        }
    }

    /// Only a stream that is actually playing is called fine — and a playing
    /// stream is proof of a connection, so it outranks "offline".
    func testOnlyAPlayingStreamIsCalledFine() {
        XCTAssertEqual(MenuView.infoNote(for: .unavailable, player: .playing), .infoDownStreamPlaying)
        XCTAssertEqual(MenuView.infoNote(for: .offline, player: .playing), .infoDownStreamPlaying)
    }

    /// Their info service failing while the stream is down too is said as
    /// both; while the stream is stopped or still connecting, it goes
    /// unmentioned.
    func testAStreamThatIsNotPlayingIsNotCalledFine() {
        XCTAssertEqual(MenuView.infoNote(for: .unavailable, player: .reconnecting), .infoAndStreamDown)
        XCTAssertEqual(MenuView.infoNote(for: .unavailable, player: .failed("gone")), .infoAndStreamDown)
        XCTAssertEqual(MenuView.infoNote(for: .unavailable, player: .stopped), .infoDown)
        XCTAssertEqual(MenuView.infoNote(for: .unavailable, player: .loading), .infoDown)
    }

    func testNoFailureNoNote() {
        XCTAssertNil(MenuView.infoNote(for: nil, player: .failed("gone")))
    }
}
