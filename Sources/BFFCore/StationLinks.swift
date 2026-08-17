import Foundation

/// The corners of bff.fm the dropdown links out to, taken from the site's own
/// footer and social row.
enum StationLinks {
    struct Item: Identifiable {
        let name: String
        let url: URL
        var id: String { name }
    }

    /// bff.fm's own footer, in its own order. DJ Sign In is deliberately left
    /// out — it's a staff door, not something a listener needs in a menu bar.
    static let station: [Item] = [
        item("About BFF.fm", "https://bff.fm/about"),
        item("Join Us", "https://bff.fm/join"),
        item("Blog", "https://bff.fm/news"),
        item("Press", "https://bff.fm/posts/categories/press"),
        item("FCC Applications", "https://bff.fm/lpfm"),
        item("Radio Shows", "https://bff.fm/shows"),
        item("Schedule", "https://bff.fm/shows/schedule"),
        item("Events", "https://bff.fm/pages/events"),
        item("Giveaways", "https://bff.fm/posts/categories/giveaways"),
        item("Donate", "https://bff.fm/donate"),
        item("Merch", "https://bff.fm/merch"),
        item("Underwriters", "https://bff.fm/underwriters"),
        item("Supporters", "https://bff.fm/supporters"),
        item("Listening Options", "https://bff.fm/listen"),
        item("Developers & APIs", "https://developer.bff.fm"),
        item("Contact", "https://bff.fm/contact"),
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
