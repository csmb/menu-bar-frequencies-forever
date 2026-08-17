import AppKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var service: NowPlayingService
    @ObservedObject var shows: ShowDirectory

    @State private var page: Page = .nowPlaying
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// The dropdown is two screens: the music, and everything else.
    private enum Page {
        case nowPlaying, more
    }

    /// #efefef in light, #252525bf in dark — the dark one is translucent, so
    /// the panel keeps a little of the vibrancy behind it.
    static let backgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x25 / 255, green: 0x25 / 255, blue: 0x25 / 255, alpha: 0xbf / 255)
            : NSColor(srgbRed: 0xef / 255, green: 0xef / 255, blue: 0xef / 255, alpha: 1)
    }

    private static let background = Color(nsColor: backgroundColor)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch page {
            case .nowPlaying: nowPlayingPage
            case .more: morePage
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Self.background)
        .onAppear {
            shows.loadIfNeeded()
            resolvePresenter()
            // Always open on the music, never on wherever we were left.
            page = .nowPlaying
        }
        .onChange(of: service.nowPlaying?.program) { _, _ in resolvePresenter() }
        .onChange(of: shows.urlsByShow.count) { _, _ in resolvePresenter() }
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlayingPage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(programLine)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                page = .more
            } label: {
                // The glyph alone is only a couple of points tall, which is
                // far too small to hit — the frame is the real target.
                Image(systemName: "ellipsis")
                    .imageScale(.large)
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Station links and settings")
        }

        if let track = trackLine {
            Text(track)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }

        artwork

        HStack(spacing: 8) {
            playButton
            donateButton
        }

        if case .failed(let message) = player.state {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if service.fetchFailed {
            Text("Can’t reach BFF.fm — info may be stale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Show and DJ share the top line, the show name carrying the larger of
    /// the two sizes so it still reads as the heading. The show name links to
    /// its page when the schedule feed has told us where that is.
    private var programLine: AttributedString {
        let program = service.nowPlaying?.program
        var line = AttributedString(program ?? "Live on BFF.fm")
        line.font = .headline
        if let program, let url = shows.url(forShow: program) {
            line.link = url
        }
        guard let presenter = service.nowPlaying?.presenter else { return line }
        var with = AttributedString(" with ")
        with.font = .subheadline
        with.foregroundColor = .secondary
        line.append(with)

        var credit = AttributedString(presenter)
        credit.font = .subheadline
        if let url = shows.url(forPresenter: presenter) {
            credit.link = url
        } else {
            credit.foregroundColor = .secondary
        }
        line.append(credit)
        return line
    }

    /// The DJ's page lives on the show's page, so this can only run once the
    /// schedule has told us where the show is.
    private func resolvePresenter() {
        guard let now = service.nowPlaying,
              let presenter = now.presenter,
              let program = now.program
        else { return }
        shows.loadPresenterIfNeeded(presenter, forShow: program)
    }

    /// "Title by Artist on Album (Label)", each part linked to its own page on
    /// bff.fm. Anything the API didn't send is simply left out of the sentence.
    private var trackLine: AttributedString? {
        guard let now = service.nowPlaying else { return nil }
        return Self.trackLine(title: now.title, artist: now.artist,
                              album: now.album, label: now.label)
    }

    static func trackLine(title: String?, artist: String?,
                          album: String?, label: String?) -> AttributedString? {
        guard let title else { return nil }

        var line = linked(title, to: artist.flatMap { MusicLinks.track(title, by: $0) })
        line.font = .subheadline.weight(.medium)

        if let artist {
            line += plain(" by ")
            line += linked(artist, to: MusicLinks.artist(artist))
        }
        if let album {
            line += plain(" on ")
            line += linked(album, to: artist.flatMap { MusicLinks.release(album, by: $0) })
        }
        if let label {
            line += plain(" (")
            line += linked(label, to: MusicLinks.label(label))
            line += plain(")")
        }
        return line
    }

    private static func linked(_ text: String, to url: URL?) -> AttributedString {
        var part = AttributedString(text)
        if let url { part.link = url }
        return part
    }

    private static func plain(_ text: String) -> AttributedString {
        var part = AttributedString(text)
        part.foregroundColor = .secondary
        return part
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = service.nowPlaying?.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }
            .frame(width: 256, height: 256)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Play and Donate split the artwork's width exactly: two equal halves of
    /// the 256pt content column with one 8pt gap between them. The stretch has
    /// to be applied to the label — on the `Button` it widens the frame but
    /// leaves the control itself intrinsically sized and centred inside it.
    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            playLabel.modifier(PanelButtonLabel())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 5))
    }

    @ViewBuilder
    private var playLabel: some View {
        switch player.state {
        case .stopped, .failed:
            Label("Play", systemImage: "play.fill")
        case .loading:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }
        case .playing:
            Label("Stop", systemImage: "stop.fill")
        }
    }

    private var donateButton: some View {
        Link(destination: StationLinks.donate) {
            Label("Donate", systemImage: "heart.fill")
                .modifier(PanelButtonLabel())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 5))
    }

    // MARK: - More

    @ViewBuilder
    private var morePage: some View {
        Button {
            page = .nowPlaying
        } label: {
            Label("Now Playing", systemImage: "chevron.left")
                .font(.subheadline)
        }
        .buttonStyle(.borderless)

        Divider()

        sectionLabel("Station")
        linkGrid(StationLinks.station)

        sectionLabel("Follow")
        linkGrid(StationLinks.social)

        Divider()

        Text("Become a Bestie, and your tax-deductible monthly or quarterly sustaining donation will support BFF.fm all year long!")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 8) {
            launchAtLoginButton
            quitButton
        }
    }

    /// Still a real toggle — `.button` style just gives it the same footprint
    /// as Quit, and highlights itself while it's on.
    private var launchAtLoginButton: some View {
        Toggle(isOn: $launchAtLogin) {
            Text("Launch at Login").modifier(PanelButtonLabel())
        }
        .toggleStyle(.button)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 5))
        .onChange(of: launchAtLogin) { _, enabled in
            setLaunchAtLogin(enabled)
        }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text("Quit").modifier(PanelButtonLabel())
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 5))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2)
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }

    /// Two columns keeps six links inside 280pt without truncating any of them.
    private func linkGrid(_ items: [StationLinks.Item]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading),
                      GridItem(.flexible(), alignment: .leading)],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(items) { item in
                Link(item.name, destination: item.url)
                    .font(.subheadline)
            }
        }
    }

    /// Fills the button's half of the row and squares it up, so the pair reads
    /// as two blocks under the artwork rather than two floating pills.
    private struct PanelButtonLabel: ViewModifier {
        func body(content: Content) -> some View {
            content.frame(maxWidth: .infinity, minHeight: 24)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle to what the system actually has.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
