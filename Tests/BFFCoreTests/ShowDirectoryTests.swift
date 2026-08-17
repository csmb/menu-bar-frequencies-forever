import XCTest
@testable import BFFCore

@MainActor
final class ShowDirectoryTests: XCTestCase {
    /// Shaped exactly like data.bff.fm/shows/all.ics, including the pairs that
    /// prove show slugs can't be derived from the show's name.
    private let feed = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:show-372@bff.fm
    SUMMARY;CHARSET=utf-8:Bitch Talk Podcast on BFF.FM
    URL:https://bff.fm/shows/bitch-talk
    END:VEVENT
    BEGIN:VEVENT
    UID:show-19@bff.fm
    SUMMARY;CHARSET=utf-8:Weird Al Jazeera on BFF.FM
    URL:https://bff.fm/shows/a-hairy-home-companion
    END:VEVENT
    BEGIN:VEVENT
    UID:show-88@bff.fm
    SUMMARY;CHARSET=utf-8:HELLA DIMENSIONAL on BFF.FM
    URL:https://bff.fm/shows/hella-dimensional
    END:VEVENT
    BEGIN:VEVENT
    UID:show-91@bff.fm
    SUMMARY;CHARSET=utf-8:A Very Long Show Name That The Feed
      Wrapped Across Lines on BFF.FM
    URL:https://bff.fm/shows/wrapped-name
    END:VEVENT
    END:VCALENDAR
    """

    private func directory(returning body: String) -> ShowDirectory {
        ShowDirectory { url in
            (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200,
                                              httpVersion: nil, headerFields: nil)!)
        }
    }

    func testResolvesNamesThatCouldNotBeGuessed() async {
        let directory = directory(returning: feed)
        await directory.load()
        XCTAssertEqual(directory.url(forShow: "Weird Al Jazeera")?.absoluteString,
                       "https://bff.fm/shows/a-hairy-home-companion")
        XCTAssertEqual(directory.url(forShow: "Bitch Talk Podcast")?.absoluteString,
                       "https://bff.fm/shows/bitch-talk")
    }

    func testLookupIgnoresCaseAndSurroundingSpace() async {
        let directory = directory(returning: feed)
        await directory.load()
        XCTAssertEqual(directory.url(forShow: "  hella dimensional ")?.absoluteString,
                       "https://bff.fm/shows/hella-dimensional")
    }

    func testUnfoldsWrappedSummaryLines() async {
        let directory = directory(returning: feed)
        await directory.load()
        XCTAssertEqual(
            directory.url(forShow: "A Very Long Show Name That The Feed Wrapped Across Lines")?.absoluteString,
            "https://bff.fm/shows/wrapped-name"
        )
    }

    func testUnknownShowHasNoURL() async {
        let directory = directory(returning: feed)
        await directory.load()
        XCTAssertNil(directory.url(forShow: "Not A Real Show"))
    }

    func testFetchFailureLeavesTheDirectoryEmpty() async {
        let directory = ShowDirectory { _ in throw URLError(.notConnectedToInternet) }
        await directory.load()
        XCTAssertTrue(directory.urlsByShow.isEmpty)
    }
}
