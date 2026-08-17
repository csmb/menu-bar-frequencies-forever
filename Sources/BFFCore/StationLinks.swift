import Foundation

/// The corners of bff.fm the dropdown links out to, taken from the site's own
/// footer and social row.
enum StationLinks {
    struct Item: Identifiable {
        let name: String
        let url: URL
        var id: String { name }
    }

    static let station: [Item] = [
        item("Schedule", "https://bff.fm/shows/schedule"),
        item("Shows", "https://bff.fm/shows"),
        item("Events", "https://bff.fm/pages/events"),
        item("Merch", "https://bff.fm/merch"),
        item("Blog", "https://bff.fm/news"),
        item("Listen", "https://bff.fm/listen"),
    ]

    static let social: [Item] = [
        item("Instagram", "https://instagram.com/bffdotfm"),
        item("Bluesky", "https://bsky.app/profile/bff.fm"),
        item("TikTok", "https://www.tiktok.com/@bffdotfm"),
        item("YouTube", "https://youtube.com/bffdotfm"),
    ]

    static let donate = URL(string: "https://bff.fm/donate")!

    private static func item(_ name: String, _ url: String) -> Item {
        Item(name: name, url: URL(string: url)!)
    }
}
