import Foundation

/// Maps a show's on-air name to its page on bff.fm.
///
/// Show slugs can't be derived the way music slugs can — the schedule feed
/// pairs "Weird Al Jazeera" with `/shows/a-hairy-home-companion`, and
/// "Bitch Talk Podcast" with `/shows/bitch-talk`. So the mapping is read from
/// the station's own calendar rather than guessed.
///
/// The feed is ~64KB and the schedule changes weekly, so it's fetched once per
/// launch, lazily, and kept for the session. A failure just means no show link.
@MainActor
final class ShowDirectory: ObservableObject {
    @Published private(set) var urlsByShow: [String: URL] = [:]

    private let provider: DataProvider
    private var loadStarted = false

    init(provider: @escaping DataProvider = NowPlayingService.liveProvider) {
        self.provider = provider
    }

    func url(forShow name: String) -> URL? {
        urlsByShow[Self.key(name)]
    }

    func loadIfNeeded() {
        guard !loadStarted else { return }
        loadStarted = true
        Task { await load() }
    }

    func load() async {
        do {
            let (data, response) = try await provider(BFFAPI.schedule)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            urlsByShow = Self.parse(text)
        } catch {
            // No show links this session; everything else still works.
            loadStarted = false
        }
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Pulls SUMMARY/URL pairs out of the iCalendar feed.
    static func parse(_ ics: String) -> [String: URL] {
        var found: [String: URL] = [:]
        var summary: String?

        for line in unfolded(ics) {
            if line.hasPrefix("BEGIN:VEVENT") {
                summary = nil
            } else if let value = value(of: "SUMMARY", in: line) {
                // Every entry is titled "<Show> on BFF.FM".
                summary = value.replacingOccurrences(
                    of: #"\s+on\s+BFF\.FM$"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            } else if let value = value(of: "URL", in: line) {
                if let name = summary, let url = URL(string: value), !name.isEmpty {
                    found[key(name)] = url
                }
            }
        }
        return found
    }

    /// iCalendar wraps long lines and marks the continuation with a leading
    /// space, so a SUMMARY can arrive split across several lines.
    private static func unfolded(_ ics: String) -> [String] {
        var lines: [String] = []
        for raw in ics.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if raw.hasPrefix(" ") || raw.hasPrefix("\t") {
                lines[lines.isEmpty ? lines.startIndex : lines.index(before: lines.endIndex)]
                    += raw.dropFirst()
            } else {
                lines.append(raw)
            }
        }
        return lines
    }

    /// Property lines look like `SUMMARY;CHARSET=utf-8:Bitch Talk Podcast…`.
    private static func value(of property: String, in line: String) -> String? {
        guard line.uppercased().hasPrefix(property) else { return nil }
        let afterName = line.dropFirst(property.count)
        guard let separator = afterName.firstIndex(of: ":") else { return nil }
        // Anything between the name and the colon must be parameters, not text.
        guard !afterName[afterName.startIndex..<separator].contains(" ") else { return nil }
        return String(afterName[afterName.index(after: separator)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
