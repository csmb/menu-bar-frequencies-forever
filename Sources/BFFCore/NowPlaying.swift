import Foundation

/// One record from https://data.bff.fm/api/data/onair/now.json.
/// The API returns track + show data when a track is logged, or show-only
/// data otherwise — every field is optional.
struct NowPlaying: Decodable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var label: String?
    var url: String?
    var image: String?
    var program: String?
    var presenter: String?
    var programImage: String?

    enum CodingKeys: String, CodingKey {
        case title, artist, album, label, url, image, program, presenter
        case programImage = "program_image"
    }

    var songLine: String? {
        switch (title, artist) {
        case let (t?, a?): return "\(t) — \(a)"
        case let (t?, nil): return t
        case let (nil, a?): return a
        default: return nil
        }
    }

    var artworkURL: URL? {
        if let image, let parsed = URL(string: image) { return parsed }
        if let programImage, let parsed = URL(string: programImage) { return parsed }
        return nil
    }
}
