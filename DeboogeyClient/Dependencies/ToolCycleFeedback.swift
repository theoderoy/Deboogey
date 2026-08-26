//
//  ToolCycleFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/08/2026.
//

import AppKit

enum ToolCycleFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Tools.playCycleSound"
    private static let soundVolume: Float = 0.3

    static func playComplete(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }
        play(named: "ToolCycleComplete", bundle: bundle, waitUntilFinished: true)
    }

    static func playHalt(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }
        play(named: "ToolCycleHalt", bundle: bundle, waitUntilFinished: false)
    }

    private static func play(named name: String, bundle: Bundle, waitUntilFinished: Bool) {
        let prepareAndStart: () -> (NSSound, TimeInterval)? = {
            let soundURL = bundle.url(forResource: name, withExtension: "aif")
                ?? bundle.url(
                    forResource: name,
                    withExtension: "aif",
                    subdirectory: "Resources"
                )
            guard let soundURL, let sound = NSSound(contentsOf: soundURL, byReference: true) else {
                return nil
            }
            sound.volume = soundVolume
            let duration = sound.duration
            sound.play()
            return (sound, duration)
        }

        if !waitUntilFinished {
            let fireAndForget = {
                _ = prepareAndStart()
            }
            if Thread.isMainThread {
                fireAndForget()
            } else {
                DispatchQueue.main.async(execute: fireAndForget)
            }
            return
        }

        let started: (NSSound, TimeInterval)?
        if Thread.isMainThread {
            started = prepareAndStart()
        } else {
            started = DispatchQueue.main.sync(execute: prepareAndStart)
        }

        guard let (sound, duration) = started else { return }

        if duration > 0, duration.isFinite {
            Thread.sleep(forTimeInterval: duration)
            return
        }

        while sound.isPlaying {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
