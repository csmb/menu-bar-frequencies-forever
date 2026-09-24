import Foundation

/// How this app identifies itself to BFF.fm, and where it talks to them.
///
/// BFF.fm's developer rules ask that every request carry an `app_id`
/// "with a reverse URI form (e.g. com.example.bff.app) so that we may
/// understand who is making use of our endpoints" — hence the bundle
/// identifier rather than a bare slug. Both URLs are built here so a change
/// to how we identify ourselves can't reach one endpoint and miss the other.
///
/// https://developer.bff.fm/about/developer-rules
enum BFFAPI {
    /// Reverse URI form, matching the app's bundle identifier.
    static let appID = "com.bunting.menu-bar-frequencies-forever"
    static let userAgent = "menu-bar-frequencies-forever/1.0"

    /// Show and track metadata for whatever is on air right now.
    static let nowPlaying = identified("https://data.bff.fm/api/data/onair/now.json")

    /// The 128 kbps MP3 live stream.
    static let stream = identified("https://stream.bff.fm/1/mp3.mp3")

    /// The weekly schedule, as iCalendar. The only place show names are paired
    /// with their page URLs.
    static let schedule = identified("https://data.bff.fm/shows/all.ics")

    private static func identified(_ endpoint: String) -> URL {
        URL(string: "\(endpoint)?app_id=\(appID)")!
    }

    /// Passes a URL through only if it points at BFF.fm over TLS.
    ///
    /// Several URLs in this app are not written here — they arrive in the
    /// schedule feed, in now-playing JSON, or in the markup of a show page —
    /// and each is either fetched or handed to the user's browser. Left
    /// unchecked, anything that could alter one of those responses could make
    /// every copy of this app fetch a URL of its choosing, or open one on
    /// click. That is a bigger favour than the station ever asked for, and the
    /// check costs nothing.
    ///
    /// Scheme is pinned to https because a URL is also a way to reach things
    /// that are not the web: `file:` reads the user's disk, and a custom scheme
    /// can launch another application.
    static func trusted(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              // Credentials have no place in a link to bff.fm, and they are
              // the classic way to make a URL read as one host and go to
              // another.
              url.user(percentEncoded: true) == nil,
              url.password(percentEncoded: true) == nil,
              let host = url.host(percentEncoded: true)?.lowercased(),
              // A plain DNS name first, because the suffix test is only as good
              // as the string it runs on: `[::ffff:203.0.113.7%25x.bff.fm]` is
              // an IPv6 address whose zone ID ends in ".bff.fm", and the
              // network stack ignores the zone and connects to the address.
              host.allSatisfy(hostCharacters.contains),
              // Suffix alone would accept "notbff.fm"; the dot makes it a
              // subdomain check rather than a string match.
              host == "bff.fm" || host.hasSuffix(".bff.fm")
        else { return nil }
        return url
    }

    private static let hostCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
}
