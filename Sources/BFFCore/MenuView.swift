import ServiceManagement
import SwiftUI

struct MenuView: View {
    /// Opens in the browser, so no `app_id` — that rule covers the app's own
    /// requests to BFF.fm services, not a page the user visits themselves.
    static let donateURL = URL(string: "https://bff.fm/donate")!

    @ObservedObject var player: PlayerController
    @ObservedObject var service: NowPlayingService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            showHeader
            artwork
            playButton
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
            Divider()
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            donateCTA
        }
        .padding(12)
        .frame(width: 280)
        .background(PanelCentering())
        .onAppear { service.setMenuOpen(true) }
        .onDisappear { service.setMenuOpen(false) }
    }

    @ViewBuilder
    private var showHeader: some View {
        MarqueeText(programLine)
        if let song = service.nowPlaying?.songLine {
            MarqueeText(song)
            if let album = service.nowPlaying?.album {
                MarqueeText(album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            switch player.state {
            case .stopped, .failed:
                Label("Play", systemImage: "play.fill")
            case .loading:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting…")
                }
            case .playing:
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// BFF.fm is listener-funded, so the dropdown carries a standing ask —
    /// one line of why, then the action, sharing a row with Quit.
    private var donateCTA: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Become a Bestie, and your tax-deductible monthly or quarterly sustaining donation will support BFF.fm all year long!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Link(destination: Self.donateURL) {
                    Label("Donate", systemImage: "heart.fill")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
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
