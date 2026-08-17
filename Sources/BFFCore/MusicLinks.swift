import Foundation

/// Builds bff.fm music URLs for the track that's playing.
///
/// The station has no API for these, so the slug is derived: fold accents,
/// lowercase, drop "the"/"a"/"and", then run the remaining words together —
/// `The Color of Rain` becomes `colorofrain`. That rule was checked against 61
/// name/slug pairs taken from bff.fm's own markup and matched all of them.
///
/// Derived means fallible: a title the station slugged by hand will 404. These
/// are read-only links out to a website, so the cost of a miss is a wrong page,
/// never wrong data in the app.
enum MusicLinks {
    private static let stopWords: Set<String> = ["the", "a", "and"]

    static func slug(_ name: String) -> String? {
        let folded = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        let words = folded.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }

        // Every word being a stop word is better served by keeping them than
        // by producing an empty slug.
        let kept = words.filter { !stopWords.contains($0) }
        return (kept.isEmpty ? words : kept).joined()
    }

    static func artist(_ artist: String) -> URL? {
        slug(artist).flatMap { URL(string: "https://bff.fm/music/artists/\($0)") }
    }

    static func track(_ title: String, by artist: String) -> URL? {
        guard let artist = slug(artist), let title = slug(title) else { return nil }
        return URL(string: "https://bff.fm/music/artists/\(artist)/tracks/\(title)")
    }

    static func release(_ album: String, by artist: String) -> URL? {
        guard let artist = slug(artist), let album = slug(album) else { return nil }
        return URL(string: "https://bff.fm/music/artists/\(artist)/releases/\(album)")
    }

    static func label(_ label: String) -> URL? {
        slug(label).flatMap { URL(string: "https://bff.fm/music/labels/\($0)") }
    }
}
