//
//  DocumentSaveFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 31/10/2026.
//

import Foundation

enum DocumentSaveFeedback {
    static let preferenceKey = "theoderoy.Deboogey.Documents.playSaveSound"
    static let legacyPreferenceKey = "theoderoy.Deboogey.LoupeMachine.playSaveSound"

    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: preferenceKey) == nil,
              defaults.object(forKey: legacyPreferenceKey) != nil else { return }
        defaults.set(defaults.bool(forKey: legacyPreferenceKey), forKey: preferenceKey)
        defaults.removeObject(forKey: legacyPreferenceKey)
    }

    static func playSoundIfEnabled(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        migrateIfNeeded(defaults: defaults)
        guard defaults.bool(forKey: preferenceKey) else { return }
        _ = BundleAIFSound.play(
            named: BundleAIFSound.documentSaveSuccessName,
            bundle: bundle,
            volume: BundleAIFSound.documentSaveSuccessVolume
        )
    }
}
