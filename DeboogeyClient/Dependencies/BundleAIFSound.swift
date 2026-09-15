//
//  BundleAIFSound.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(AVFoundation)
import AVFoundation
#endif

enum BundleAIFSound {
    static func url(named name: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "aif")
            ?? bundle.url(
                forResource: name,
                withExtension: "aif",
                subdirectory: "Resources"
            )
    }

#if canImport(AppKit)
    static func load(
        named name: String,
        bundle: Bundle = .main,
        volume: Float
    ) -> NSSound? {
        guard let soundURL = url(named: name, bundle: bundle),
              let sound = NSSound(contentsOf: soundURL, byReference: true) else {
            return nil
        }
        sound.volume = volume
        return sound
    }

    @discardableResult
    static func play(
        named name: String,
        bundle: Bundle = .main,
        volume: Float
    ) -> NSSound? {
        guard let sound = load(named: name, bundle: bundle, volume: volume) else {
            return nil
        }
        sound.play()
        return sound
    }
#elseif canImport(AVFoundation)
    @discardableResult
    static func play(
        named name: String,
        bundle: Bundle = .main,
        volume: Float
    ) -> AVAudioPlayer? {
        guard let soundURL = url(named: name, bundle: bundle),
              let player = try? AVAudioPlayer(contentsOf: soundURL) else {
            return nil
        }
        player.volume = volume
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioPlayerRetention.shared.play(player)
        return player
    }

    private final class AudioPlayerRetention: NSObject, AVAudioPlayerDelegate {
        static let shared = AudioPlayerRetention()
        private var players: [AVAudioPlayer] = []

        func play(_ player: AVAudioPlayer) {
            player.delegate = self
            players.append(player)
            player.play()
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            players.removeAll { $0 === player }
        }
    }
#endif
}
