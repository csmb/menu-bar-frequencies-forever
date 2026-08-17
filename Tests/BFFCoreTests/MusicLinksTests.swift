import XCTest
@testable import BFFCore

final class MusicLinksTests: XCTestCase {
    /// Real name/slug pairs read off bff.fm's own markup. These pin the rule:
    /// fold accents, lowercase, drop "the"/"a"/"and", run the words together.
    private let knownSlugs: [(String, String)] = [
        ("The Goods", "goods"),
        ("Feeble Little Horse", "feeblelittlehorse"),
        ("Charli XCX", "charlixcx"),
        ("Yea-Ming and the Rumours", "yeamingrumours"),
        ("Mexican Institute of Sound and Meridian Brothers", "mexicaninstituteofsoundmeridianbrothers"),
        ("Summer's Almost Gone", "summersalmostgone"),
        ("Past the Veil", "pastveil"),
        ("Music, Fashion, Film", "musicfashionfilm"),
        ("The Color of Rain", "colorofrain"),
        ("Enjoy The Clouds", "enjoyclouds"),
        ("So Help Me God", "sohelpmegod"),
        ("You're Gonna Need A Little Music", "youregonnaneedlittlemusic"),
        ("Looking For People To Unfollow", "lookingforpeopletounfollow"),
        ("Bring on the Psychics", "bringonpsychics"),
        ("Baby I'll Change", "babyillchange"),
    ]

    func testSlugMatchesTheStationsOwnURLs() {
        for (name, expected) in knownSlugs {
            XCTAssertEqual(MusicLinks.slug(name), expected, "slug for \(name)")
        }
    }

    func testStopWordOnlyNameKeepsItsWords() {
        XCTAssertEqual(MusicLinks.slug("The The"), "thethe")
    }

    func testNameWithNoUsableCharactersHasNoSlug() {
        XCTAssertNil(MusicLinks.slug("!!!???"))
        XCTAssertNil(MusicLinks.slug(""))
    }

    /// The worked example the station's own pages demonstrate.
    func testSylvesterExample() {
        XCTAssertEqual(MusicLinks.track("Stars", by: "Sylvester")?.absoluteString,
                       "https://bff.fm/music/artists/sylvester/tracks/stars")
        XCTAssertEqual(MusicLinks.artist("Sylvester")?.absoluteString,
                       "https://bff.fm/music/artists/sylvester")
        XCTAssertEqual(MusicLinks.release("Stars", by: "Sylvester")?.absoluteString,
                       "https://bff.fm/music/artists/sylvester/releases/stars")
        XCTAssertEqual(MusicLinks.label("Fantasy")?.absoluteString,
                       "https://bff.fm/music/labels/fantasy")
    }

    func testAccentsAreFoldedNotDropped() {
        XCTAssertEqual(MusicLinks.slug("Björk"), "bjork")
    }
}
