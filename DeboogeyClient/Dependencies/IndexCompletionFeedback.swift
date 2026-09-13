//
//  IndexCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import Foundation

enum IndexCompletionFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Indexing.playCompletionSound"
    private static let completionSoundVolume: Float = 0.3

    static func playSoundIfEnabled(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }
#if canImport(AppKit)
        _ = BundleAIFSound.play(named: "ProcessDone", bundle: bundle, volume: completionSoundVolume)
#endif
    }

    static func notifyIndexingFinished(for applicationName: String) {
        BannerNotificationCenter.shared.notify(
            title: L10n.t("Indexing Finished"),
            body: L10n.f("%@ was completely indexed", applicationName),
            identifierPrefix: "indexing-complete"
        )
    }
}
