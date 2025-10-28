//
//  EducationPlayerView.swift
//  Deboogey
//
//  Created by Théo De Roy on 19/10/2025.
//

import SwiftUI
import AVKit

struct EducationPlayerView: NSViewRepresentable {
    let name: String
    let fileExtension: String

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.black.cgColor
        playerView.layer?.cornerRadius = 8
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.videoGravity = .resizeAspectFill
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.updatesNowPlayingInfoCenter = false

        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            let playerItem = AVPlayerItem(url: url)
            let player = AVQueuePlayer(items: [playerItem])
            player.allowsExternalPlayback = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.isMuted = true
            let looper = AVPlayerLooper(player: player, templateItem: playerItem)
            context.coordinator.player = player
            context.coordinator.looper = looper
            playerView.player = player
            player.play()
        }

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player?.rate == 0 {
            nsView.player?.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
}
