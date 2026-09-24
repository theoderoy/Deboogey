//
//  BannerNotificationCenter.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation
import UserNotifications

final class BannerNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BannerNotificationCenter()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func notify(title: String, body: String, identifierPrefix: String) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliver(title: title, body: body, identifierPrefix: identifierPrefix)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { return }
                    self.deliver(title: title, body: body, identifierPrefix: identifierPrefix)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func deliver(title: String, body: String, identifierPrefix: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(UUID().uuidString)",
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
