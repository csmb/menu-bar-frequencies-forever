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
    @Published private(set) var urlsByPresenter: [String: URL] = [:]

    private let provider: DataProvider
    private var loadStarted = false
    private var presenterLookups: Set<String> = []
    /// A failed load is retried, but not on every click — see `retryFloor`.
    private var lastLoadAttempt: Date?
    /// The same, per DJ: a show page that errors is asked for again only once
    /// `retryFloor` has passed.
    private var lastPresenterAttempt: [String: Date] = [:]
    private let now: () -> Date

    /// How long a failure is allowed to stand before another attempt, for the
    /// schedule and for each DJ's show page. Without it, a station that is down
    /// turns every dropdown open into another request — 64KB for the feed,
    /// 40KB or more for a show page.
    static let retryFloor: TimeInterval = 60

    init(provider: @escaping DataProvider = NowPlayingService.liveProvider,
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    func url(forShow name: String) -> URL? {
        urlsByShow[Self.key(name)]
    }

    func loadIfNeeded() {
        guard !loadStarted else { return }
        if let last = lastLoadAttempt, now().timeIntervalSince(last) < Self.retryFloor {
            return
        }
        loadStarted = true
        lastLoadAttempt = now()
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

    // MARK: - Presenters

    func url(forPresenter presenter: String) -> URL? {
        urlsByPresenter[Self.key(presenter)]
    }

    /// Resolves a DJ's page by reading their show's page and matching the
    /// presenter's name against the `/people/` links on it.
    ///
    /// The slug cannot be derived, and derivation fails *silently*: bff.fm
    /// answers `/people/donnaarkee` with HTTP 200, but it's the station's
    /// generic page, not Donna Arkee's — hers is `/people/donna`. A guessed
    /// link would look like it worked and quietly go somewhere wrong, so the
    /// name is matched against the show page instead.
    func loadPresenterIfNeeded(_ presenter: String, forShow show: String) {
        let key = Self.key(presenter)
        guard urlsByPresenter[key] == nil,
              !presenterLookups.contains(key),
              let showURL = url(forShow: show)
        else { return }
        if let last = lastPresenterAttempt[key], now().timeIntervalSince(last) < Self.retryFloor {
            return
        }

        presenterLookups.insert(key)
        lastPresenterAttempt[key] = now()
        Task { await loadPresenter(presenter, from: showURL) }
    }

    func loadPresenter(_ presenter: String, from showURL: URL) async {
        do {
            let (data, response) = try await provider(showURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let html = String(data: data, encoding: .utf8) else { return }
            if let match = Self.peopleLinks(in: html)[Self.key(presenter)] {
                urlsByPresenter[Self.key(presenter)] = match
            }
        } catch {
            // No DJ link for this show; a later open may try again once
            // `retryFloor` has passed.
            presenterLookups.remove(Self.key(presenter))
        }
    }

    /// Every `/people/…` link on a page, keyed by the name it was shown under.
    static func peopleLinks(in html: String) -> [String: URL] {
        let pattern = ##"<a[^>]+href="(/people/(?!browse|follow)[^"#?]+)"[^>]*>(.*?)</a>"##
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [:] }

        var found: [String: URL] = [:]
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let path = Range(match.range(at: 1), in: html),
                  let label = Range(match.range(at: 2), in: html),
                  let url = BFFAPI.trusted(URL(string: "https://bff.fm\(html[path])"))
            else { continue }

            let name = key(stripTags(String(html[label])))
            guard !name.isEmpty, found[name] == nil else { continue }
            found[name] = url
        }
        return found
    }

    private static func stripTags(_ html: String) -> String {
        decodeEntities(html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Character references, decoded in a single pass. bff.fm writes every
    /// apostrophe as `&#039;`, so numeric references are handled in general
    /// rather than one spelling at a time — decoding `&#39;` alone left every
    /// DJ with an apostrophe in their name unlinked. `&amp;` goes in the same
    /// pass, so an escaped reference is never decoded twice.
    private static func decodeEntities(_ text: String) -> String {
        text.replacing(#/&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]{2,4});/#) { match in
            let reference = match.output.1
            let scalar: Unicode.Scalar?
            if reference.hasPrefix("#x") || reference.hasPrefix("#X") {
                scalar = UInt32(reference.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }
            } else if reference.hasPrefix("#") {
                scalar = UInt32(reference.dropFirst()).flatMap { Unicode.Scalar($0) }
            } else {
                scalar = namedEntities[String(reference)]
            }
            return scalar.map { String(Character($0)) } ?? String(match.output.0)
        }
    }

    /// The named references that turn up in link text. Anything else is left
    /// exactly as written.
    private static let namedEntities: [String: Unicode.Scalar] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    /// Pulls SUMMARY/URL pairs out of the iCalendar feed.
    static func parse(_ ics: String) -> [String: URL] {
        var found: [String: URL] = [:]
        var summary: String?

        for line in unfolded(ics) {
            if line.hasPrefix("BEGIN:VEVENT") {
                summary = nil
            } else if let value = value(of: "SUMMARY", in: line) {
                // Every entry is titled "<Show> on BFF.FM".
                summary = unescaped(value).replacingOccurrences(
                    of: #"\s+on\s+BFF\.FM$"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            } else if let value = value(of: "URL", in: line) {
                // Checked, not trusted: this URL is later fetched by
                // loadPresenter and handed to the user's browser on click.
                if let name = summary, let url = BFFAPI.trusted(URL(string: value)),
                   !name.isEmpty {
                    found[key(name)] = url
                }
            }
        }
        return found
    }

    /// iCalendar wraps long lines and marks the continuation with a leading
    /// space, so a SUMMARY can arrive split across several lines. A
    /// continuation with nothing before it — a body that opens with a space —
    /// is kept as a line of its own; there is nothing to join it to.
    ///
    /// Unfolding comes first, so an escape split across two lines is whole
    /// again before `unescaped(_:)` reads it.
    private static func unfolded(_ ics: String) -> [String] {
        var lines: [String] = []
        for raw in ics.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if raw.hasPrefix(" ") || raw.hasPrefix("\t"), let last = lines.indices.last {
                lines[last] += raw.dropFirst()
            } else {
                lines.append(raw)
            }
        }
        return lines
    }

    /// iCalendar's TEXT escapes (RFC 5545 §3.3.11) — `\,` `\;` `\\` and `\n` —
    /// undone in one pass, left to right, so an escaped backslash is never
    /// taken for the start of another escape. Left in, a show with a comma or
    /// semicolon in its name never matched now.json's plain program name.
    private static func unescaped(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                result.append(character == "n" || character == "N" ? "\n" : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return escaping ? result + "\\" : result
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
