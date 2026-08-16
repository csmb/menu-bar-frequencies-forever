import XCTest
@testable import BFFCore

final class NowPlayingTests: XCTestCase {
    private let fullPayload = Data("""
    {"title":"Take Five","artist":"The Dave Brubeck Quartet","album":"Time Out",\
    "label":"Columbia","url":"https:\\/\\/bff.fm\\/now\\/20260816122123",\
    "image":"https:\\/\\/a.bff.fm\\/image\\/original\\/cover-art.jpg",\
    "program":"Luddite Radio","presenter":"the GeeZ'R",\
    "program_image":"https:\\/\\/a.bff.fm\\/image\\/original\\/luddide-high.jpg"}
    """.utf8)

    private let showOnlyPayload = Data("""
    {"program":"Luddite Radio","presenter":"the GeeZ'R",\
    "program_image":"https:\\/\\/a.bff.fm\\/image\\/original\\/luddide-high.jpg"}
    """.utf8)

    func testDecodesFullPayload() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.title, "Take Five")
        XCTAssertEqual(np.artist, "The Dave Brubeck Quartet")
        XCTAssertEqual(np.album, "Time Out")
        XCTAssertEqual(np.label, "Columbia")
        XCTAssertEqual(np.program, "Luddite Radio")
        XCTAssertEqual(np.presenter, "the GeeZ'R")
        XCTAssertEqual(np.programImage, "https://a.bff.fm/image/original/luddide-high.jpg")
    }

    func testDecodesShowOnlyPayload() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertNil(np.title)
        XCTAssertNil(np.artist)
        XCTAssertEqual(np.program, "Luddite Radio")
    }

    func testDecodesEmptyObject() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data("{}".utf8))
        XCTAssertNil(np.title)
        XCTAssertNil(np.program)
    }

    func testGarbageFailsToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(NowPlaying.self, from: Data("<html>".utf8)))
    }

    func testSongLineJoinsTitleAndArtist() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.songLine, "Take Five — The Dave Brubeck Quartet")
    }

    func testSongLineWithTitleOnly() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data(#"{"title":"Take Five"}"#.utf8))
        XCTAssertEqual(np.songLine, "Take Five")
    }

    func testSongLineNilWhenNoTrack() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertNil(np.songLine)
    }

    func testArtworkPrefersTrackImage() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.artworkURL, URL(string: "https://a.bff.fm/image/original/cover-art.jpg"))
    }

    func testArtworkFallsBackToProgramImage() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertEqual(np.artworkURL, URL(string: "https://a.bff.fm/image/original/luddide-high.jpg"))
    }

    func testArtworkNilWhenNoImages() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data("{}".utf8))
        XCTAssertNil(np.artworkURL)
    }
}
