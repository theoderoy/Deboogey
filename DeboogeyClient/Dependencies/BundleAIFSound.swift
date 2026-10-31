//
//  BundleAIFSound.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import AudioToolbox
import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(AVFoundation)
import AVFoundation
#endif

enum BundleAIFSound {
    static let processDoneName = "ProcessDone"
    static let processDoneVolume: Float = 0.3
    static let processDoneNotificationFileName = "ProcessDone.caf"
    static let documentSaveSuccessName = "FufillDeploymentTask"
    static let documentSaveSuccessVolume: Float = processDoneVolume

    static func url(named name: String, bundle: Bundle = .main) -> URL? {
        resourceURL(named: name, ext: "aif", bundle: bundle)
    }

    static func notificationSoundURL(bundle: Bundle = .main) -> URL? {
        resourceURL(named: processDoneName, ext: "caf", bundle: bundle)
            ?? url(named: processDoneName, bundle: bundle)
    }

    @discardableResult
    static func playProcessDone(bundle: Bundle = .main) -> Bool {
#if canImport(AppKit)
        if play(named: processDoneName, bundle: bundle, volume: processDoneVolume) != nil {
            return true
        }
#elseif canImport(AVFoundation)
        if playAlert(named: processDoneName, bundle: bundle, volume: processDoneVolume) != nil {
            return true
        }
#endif
        return playProcessDoneAlert(bundle: bundle)
    }

    @discardableResult
    static func playProcessDoneAlert(bundle: Bundle = .main) -> Bool {
        guard let soundURL = notificationSoundURL(bundle: bundle) else { return false }
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID) == noErr else {
            return false
        }
        AudioServicesPlayAlertSoundWithCompletion(soundID) {
            AudioServicesDisposeSystemSoundID(soundID)
        }
        return true
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
        playAlert(named: name, bundle: bundle, volume: volume, category: .ambient)
    }

    @discardableResult
    static func playAlert(
        named name: String,
        bundle: Bundle = .main,
        volume: Float,
        category: AVAudioSession.Category = .playback
    ) -> AVAudioPlayer? {
        guard let soundURL = url(named: name, bundle: bundle),
              let player = try? AVAudioPlayer(contentsOf: soundURL) else {
            return nil
        }
        player.volume = volume
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            category,
            options: category == .playback ? [.duckOthers] : [.mixWithOthers]
        )
        try? session.setActive(true)
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

    private static func resourceURL(named name: String, ext: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }
}
