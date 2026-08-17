import AppKit
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var service: NowPlayingService

    @State private var page: Page = .nowPlaying
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// The dropdown is two screens: the music, and everything else.
    private enum Page {
        case nowPlaying, more
    }

    private static let background = Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255)

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
        .background(PanelCentering())
        .onAppear {
            service.setMenuOpen(true)
            // Always open on the music, never on wherever we were left.
            page = .nowPlaying
        }
        .onDisappear { service.setMenuOpen(false) }
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlayingPage: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            MarqueeText(programLine)
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

        if let song = service.nowPlaying?.songLine {
            MarqueeText(song)
            if let album = service.nowPlaying?.album {
                MarqueeText(album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    /// the two sizes so it still reads as the heading.
    private var programLine: AttributedString {
        var line = AttributedString(service.nowPlaying?.program ?? "Live on BFF.fm")
        line.font = .headline
        guard let presenter = service.nowPlaying?.presenter else { return line }
        var credit = AttributedString(" with \(presenter)")
        credit.font = .subheadline
        credit.foregroundColor = .secondary
        line.append(credit)
        return line
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

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { _, enabled in
                setLaunchAtLogin(enabled)
            }

        HStack {
            Link(destination: StationLinks.donate) {
                Label("Donate", systemImage: "heart.fill")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
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
