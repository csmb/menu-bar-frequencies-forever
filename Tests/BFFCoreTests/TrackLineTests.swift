import SwiftUI
import XCTest
@testable import BFFCore

@MainActor
final class TrackLineTests: XCTestCase {
    private func line(_ title: String?, _ artist: String?,
                      _ album: String?, _ label: String?) -> AttributedString? {
        MenuView.trackLine(title: title, artist: artist, album: album, label: label)
    }

    private func text(_ s: AttributedString?) -> String {
        s.map { String($0.characters) } ?? ""
    }

    /// Every link in the line, in the order they appear.
    private func links(_ s: AttributedString?) -> [String] {
        guard let s else { return [] }
        return s.runs.compactMap { $0.link?.absoluteString }
    }

    /// The example from the station's own pages, end to end.
    func testSylvesterLineReadsAndLinksCorrectly() {
        let line = self.line("Stars", "Sylvester", "Stars", "Fantasy")
        XCTAssertEqual(text(line), "Stars by Sylvester on Stars (Fantasy)")
        XCTAssertEqual(links(line), [
            "https://bff.fm/music/artists/sylvester/tracks/stars",
            "https://bff.fm/music/artists/sylvester",
            "https://bff.fm/music/artists/sylvester/releases/stars",
            "https://bff.fm/music/labels/fantasy",
        ])
    }

    func testNoTrackMeansNoLine() {
        XCTAssertNil(line(nil, "Sylvester", "Stars", "Fantasy"))
    }

    func testMissingPartsAreLeftOutOfTheSentence() {
        XCTAssertEqual(text(line("Stars", "Sylvester", nil, nil)), "Stars by Sylvester")
        XCTAssertEqual(text(line("Stars", nil, nil, nil)), "Stars")
        XCTAssertEqual(text(line("Stars", "Sylvester", nil, "Fantasy")),
                       "Stars by Sylvester (Fantasy)")
    }

    /// Track and release URLs are both namespaced under the artist, so with no
    /// artist there is nowhere to point them.
    func testTrackAndAlbumAreUnlinkedWithoutAnArtist() {
        let line = self.line("Stars", nil, "Stars", "Fantasy")
        XCTAssertEqual(text(line), "Stars on Stars (Fantasy)")
        XCTAssertEqual(links(line), ["https://bff.fm/music/labels/fantasy"])
    }

    func testUnsluggableNameSimplyGoesUnlinked() {
        let line = self.line("???", "!!!", nil, nil)
        XCTAssertEqual(text(line), "??? by !!!")
        XCTAssertTrue(links(line).isEmpty)
    }
}
