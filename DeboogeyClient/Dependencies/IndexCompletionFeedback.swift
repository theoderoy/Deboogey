//
//  IndexCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 30/07/2026.
//

import AppKit
import UserNotifications

enum IndexCompletionFeedback {
    private static let preferenceKey = "theoderoy.Deboogey.Indexing.playCompletionSound"
    private static let completionSoundVolume: Float = 0.3

    static func playSoundIfEnabled(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard defaults.bool(forKey: preferenceKey) else { return }

        let soundURL = bundle.url(forResource: "IndexingDone", withExtension: "aif")
            ?? bundle.url(
                forResource: "IndexingDone",
                withExtension: "aif",
                subdirectory: "Resources"
            )
        guard let soundURL, let sound = NSSound(contentsOf: soundURL, byReference: true) else {
            return
        }
        sound.volume = completionSoundVolume
        sound.play()
    }

    static func notifyIndexingFinished(for applicationName: String) {
        IndexCompletionNotificationCenter.shared.notify(applicationName: applicationName)
    }
}

private final class IndexCompletionNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = IndexCompletionNotificationCenter()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func notify(applicationName: String) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliver(applicationName: applicationName)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { return }
                    self.deliver(applicationName: applicationName)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func deliver(applicationName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Indexing Finished")
        content.body = L10n.f("%@ was completely indexed", applicationName)

        let request = UNNotificationRequest(
            identifier: "indexing-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
