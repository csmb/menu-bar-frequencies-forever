import AppKit
import SwiftUI

/// Cover art, fetched like everything else the app asks BFF.fm for: through
/// the live provider, so with our User-Agent, and with our app_id. SwiftUI's
/// `AsyncImage` fetches through the shared session with neither, which left
/// the request the app makes most often the one BFF.fm could not attribute.
enum Artwork {
    @MainActor
    static func image(at url: URL) async -> NSImage? {
        do {
            let (data, response) = try await NowPlayingService.liveProvider(BFFAPI.identified(url))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            return NSImage(data: data)
        } catch {
            return nil // the placeholder stays; artwork is decoration
        }
    }
}

/// The artwork square: the placeholder until the image arrives, and for good
/// if it never does — what `AsyncImage` showed in both cases. The task hangs
/// off the stack rather than either branch, so swapping placeholder for image
/// cannot restart it.
struct ArtworkView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }
        }
        .task(id: url) {
            image = nil
            image = await Artwork.image(at: url)
        }
    }
}
