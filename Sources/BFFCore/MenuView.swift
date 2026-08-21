import AppKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var service: NowPlayingService
    @ObservedObject var shows: ShowDirectory
    @ObservedObject var navigation: MenuNavigation

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
            switch navigation.page {
            case .nowPlaying: nowPlayingPage
            case .more: morePage
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Self.background)
        .onChange(of: service.nowPlaying?.program) { _, _ in onMetadataChanged() }
        .onChange(of: shows.urlsByShow.count) { _, _ in onMetadataChanged() }
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlayingPage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(programLine)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                navigation.page = .more
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

        volumeRow

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

    /// The show can change while the dropdown is open, and the schedule may
    /// land after it opened — either means a new DJ page to look up.
    private func onMetadataChanged() {
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

    /// The stream's own level, under the artwork and above the transport.
    ///
    /// The glyph tracks the level rather than decorating the row — an app left
    /// at 10% and forgotten otherwise reads as broken rather than quiet. Its
    /// frame is fixed because the symbols are not the same width, and a slider
    /// that shifted sideways as you dragged would be its own small bug.
    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: volumeSymbol)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: $player.volume, in: 0...1)
                .controlSize(.small)
                .accessibilityLabel("Stream volume")
        }
    }

    private var volumeSymbol: String {
        switch player.volume {
        case ..<0.001: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
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
        // No heart: the glyph plus this label needs 141pt against the 124pt
        // each button gets, and the words already say what the heart did.
        Link(destination: StationLinks.donate) {
            Text("Donate to BFF.fm")
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
            navigation.page = .nowPlaying
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
