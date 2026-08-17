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

@MainActor
final class PresenterLookupTests: XCTestCase {
    /// Shaped like a real show page: the DJ's own link plus sidebar links to
    /// other shows' DJs, which must not be mistaken for this show's.
    private let showPage = """
    <html><body>
      <div class="ShowHeader">
        <h1>Weird Al Jazeera</h1>
        <a href="/people/donna" class="Byline"><span>Donna Arkee</span></a>
      </div>
      <aside>
        <a href="/people/browse/radio">DJs</a>
        <a href="/people/erikadelgato">Space&nbsp;Abuela</a>
        <a href="/people/theocmd">@indierockgirl</a>
      </aside>
    </body></html>
    """

    func testFindsEveryPersonLinkByTheNameItIsShownUnder() {
        let links = ShowDirectory.peopleLinks(in: showPage)
        XCTAssertEqual(links["donna arkee"]?.absoluteString, "https://bff.fm/people/donna")
        XCTAssertEqual(links["@indierockgirl"]?.absoluteString, "https://bff.fm/people/theocmd")
    }

    func testBrowseAndFollowAreNotPeople() {
        XCTAssertNil(ShowDirectory.peopleLinks(in: showPage)["djs"])
    }

    func testResolvesThePresenterOfTheShowOnAir() async {
        let schedule = """
        BEGIN:VEVENT
        SUMMARY:Weird Al Jazeera on BFF.FM
        URL:https://bff.fm/shows/a-hairy-home-companion
        END:VEVENT
        """
        let page = showPage
        let directory = ShowDirectory { url in
            let body = url.absoluteString.contains(".ics") ? schedule : page
            return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200,
                                                     httpVersion: nil, headerFields: nil)!)
        }
        await directory.load()
        let showURL = try! XCTUnwrap(directory.url(forShow: "Weird Al Jazeera"))
        await directory.loadPresenter("Donna Arkee", from: showURL)
        XCTAssertEqual(directory.url(forPresenter: "Donna Arkee")?.absoluteString,
                       "https://bff.fm/people/donna")
    }

    /// bff.fm answers an unknown /people/ slug with 200 and its generic page,
    /// so a derived link would look fine and go somewhere wrong. Nothing here
    /// may invent a URL: a name absent from the page yields no link at all.
    func testPresenterMissingFromThePageGetsNoGuessedLink() async {
        let page = showPage
        let directory = ShowDirectory { url in
            (Data(page.utf8), HTTPURLResponse(url: url, statusCode: 200,
                                              httpVersion: nil, headerFields: nil)!)
        }
        await directory.loadPresenter("Someone Else",
                                      from: URL(string: "https://bff.fm/shows/x")!)
        XCTAssertNil(directory.url(forPresenter: "Someone Else"))
    }
}
