//
//  ToolCycleFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/08/2026.
//

import Foundation

nonisolated enum ToolCycleFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Tools.playCycleSound"

    static func playComplete(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        play(.toolCycleComplete, defaults: defaults, bundle: bundle)
    }

    static func playHalt(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        play(.toolCycleHalt, defaults: defaults, bundle: bundle)
    }

    private static func play(
        _ sound: AppFeedback.Sound,
        defaults: UserDefaults,
        bundle: Bundle
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }
        AppFeedback.play(sound, bundle: bundle)
    }
}
