import ServiceManagement
import SwiftUI

struct MenuView: View {
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
            Button("Quit BFF.fm") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { service.setMenuOpen(true) }
        .onDisappear { service.setMenuOpen(false) }
    }

    @ViewBuilder
    private var showHeader: some View {
        Text(service.nowPlaying?.program ?? "BFF.fm — Best Frequencies Forever")
            .font(.headline)
        if let presenter = service.nowPlaying?.presenter {
            Text("with \(presenter)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let song = service.nowPlaying?.songLine {
            Text(song)
            if let album = service.nowPlaying?.album {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                Label("Connecting…", systemImage: "hourglass")
            case .playing:
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
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
