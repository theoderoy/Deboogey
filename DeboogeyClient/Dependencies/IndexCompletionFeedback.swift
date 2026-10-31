//
//  IndexCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import Foundation

enum IndexCompletionFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Indexing.playCompletionSound"

    static func notifyIndexingFinished(
        for applicationName: String,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }
        BannerNotificationCenter.shared.notify(
            title: L10n.t("Indexing Finished"),
            body: L10n.f("%@ was completely indexed", applicationName),
            identifierPrefix: "indexing-complete"
        )
    }
}
