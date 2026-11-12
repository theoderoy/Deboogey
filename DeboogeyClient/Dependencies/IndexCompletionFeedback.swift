//
//  IndexCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import Foundation

enum IndexCompletionFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Indexing.playCompletionSound"

    static var usesLiveActivityUX: Bool {
#if os(macOS)
        DiffsplitterCompletionFeedback.usesLiveActivityUX
#else
        false
#endif
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    static var completionNotifyTitle: String {
        usesLiveActivityUX
            ? L10n.t("Show a Live Activity while Loupe Machine indexes")
            : L10n.t("Play a sound when Loupe Machine finishes an index cycle")
    }

    static var completionNotifyCaption: String {
        usesLiveActivityUX
            ? L10n.t("Keeps indexing progress visible in the background. Manage Live Activities and sounds in Settings.")
            : L10n.t("Notify with a sound and banner when Loupe Machine finishes an index cycle.")
    }

    static var completionNotifySymbolName: String {
        usesLiveActivityUX ? DiffsplitterCompletionFeedback.completionNotifySymbolName : "loupe"
    }

    static func notifyIndexingFinished(
        for applicationName: String,
        includeBanner: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        let enabled = defaults.bool(forKey: preferenceKey)
        if usesLiveActivityUX {
            guard enabled else {
                Task { await AppFeedback.playIfActive(.processDone) }
                return
            }
        } else {
            guard enabled else { return }
        }
        Task {
            await AppFeedback.deliverCompletion(
                title: L10n.t("Indexing Finished"),
                body: L10n.f("%@ was completely indexed", applicationName),
                sound: .processDone,
                identifierPrefix: "indexing-complete",
                wantsBanner: includeBanner
            )
        }
    }
}
