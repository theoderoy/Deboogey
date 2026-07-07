//
//  EducationPlayerView.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 19/10/2025.
//

import SwiftUI
import AVKit

struct EducationPlayerView: NSViewRepresentable {
    let assetName: String
    let fileExtension: String
    
    init(assetName: String, fileExtension: String = "mov") {
        self.assetName = assetName
        self.fileExtension = fileExtension
    }
    
    static func hasAsset(named assetName: String) -> Bool {
        NSDataAsset(name: assetName) != nil
    }

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

        if let url = Self.cachedVideoURL(forAssetNamed: assetName, fileExtension: fileExtension) {
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
    
    private static func cachedVideoURL(forAssetNamed assetName: String, fileExtension: String) -> URL? {
        guard let asset = NSDataAsset(name: assetName) else { return nil }
        
        do {
            let cacheDirectory = try educationVideoCacheDirectory()
            let fileURL = cacheDirectory
                .appendingPathComponent(assetName)
                .appendingPathExtension(fileExtension)
            
            if cachedFileSize(at: fileURL) != asset.data.count {
                try asset.data.write(to: fileURL, options: .atomic)
            }
            
            return fileURL
        } catch {
            return nil
        }
    }
    
    private static func cachedFileSize(at url: URL) -> Int? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSize = attributes[.size] as? NSNumber
        else { return nil }
        
        return fileSize.intValue
    }
    
    private static func educationVideoCacheDirectory() throws -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = cachesDirectory.appendingPathComponent("EducationVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
