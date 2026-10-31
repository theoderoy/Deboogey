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

    func notify(
        title: String,
        body: String,
        identifierPrefix: String,
        playsSound: Bool = true
    ) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let deliver = {
                self.deliver(
                    title: title,
                    body: body,
                    identifierPrefix: identifierPrefix,
                    playsSound: playsSound
                )
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                deliver()
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    deliver()
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func deliver(
        title: String,
        body: String,
        identifierPrefix: String,
        playsSound: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playsSound {
            Self.installProcessDoneNotificationSoundIfNeeded()
            content.sound = Self.processDoneSound
        }
        center.add(
            UNNotificationRequest(
                identifier: "\(identifierPrefix)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    private static let processDoneSound = UNNotificationSound(
        named: UNNotificationSoundName(BundleAIFSound.processDoneNotificationFileName)
    )

    private static func installProcessDoneNotificationSoundIfNeeded() {
        guard let source = BundleAIFSound.notificationSoundURL() else { return }
        let fileManager = FileManager.default
        guard let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        let destination = library
            .appendingPathComponent("Sounds", isDirectory: true)
            .appendingPathComponent(BundleAIFSound.processDoneNotificationFileName)
        let sizeAt: (URL) -> Int? = {
            (try? fileManager.attributesOfItem(atPath: $0.path)[.size] as? NSNumber)?.intValue
        }
        if let sourceSize = sizeAt(source), sourceSize == sizeAt(destination) { return }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {}
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        completionHandler(options)
    }
}
