//
//  AppFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 05/11/2026.
//

import AVFoundation
import Foundation
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum AppFeedback {
    enum Sound: String {
        case processDone = "ProcessDone"
        case documentSaved = "FufillDeploymentTask"
        case batchComposerStart = "BatchComposerStart"
        case toolCycleComplete = "ToolCycleComplete"
        case toolCycleHalt = "ToolCycleHalt"
    }

    static func install() {
        NoticeCenter.shared.install()
    }

    static func requestNoticePermissionIfNeeded() {
        NoticeCenter.shared.requestAuthorizationIfNeeded()
    }

    static func play(_ sound: Sound, bundle: Bundle = .main) {
        guard let url = resourceURL(named: sound.rawValue, ext: "aif", bundle: bundle) else { return }
        Playback.shared.play(url: url)
    }

    static func playIfActive(_ sound: Sound, bundle: Bundle = .main) async {
        await MainActor.run {
            guard isApplicationActive else { return }
            play(sound, bundle: bundle)
        }
    }

    static func deliverCompletion(
        title: String,
        body: String,
        sound: Sound,
        identifierPrefix: String,
        wantsBanner: Bool,
        bundle: Bundle = .main
    ) async {
        let active = await MainActor.run { isApplicationActive }
#if os(iOS)
        guard wantsBanner else { return }
#endif
        if active {
            play(sound, bundle: bundle)
        }
#if !os(iOS)
        guard !active || wantsBanner else { return }
#endif
        await NoticeCenter.shared.post(
            title: title,
            body: body,
            identifierPrefix: identifierPrefix,
            includeSound: !active
        )
    }

    fileprivate static func resourceURL(named name: String, ext: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    private static var isApplicationActive: Bool {
#if os(iOS) || os(visionOS)
        UIApplication.shared.applicationState == .active
#elseif os(macOS)
        NSApplication.shared.isActive
#else
        true
#endif
    }
}

private final class Playback: NSObject, AVAudioPlayerDelegate {
    static let shared = Playback()

    private static let volume: Float = 0.3

    private let lock = NSLock()
    private var players: [AVAudioPlayer] = []
#if os(iOS) || os(visionOS)
    private var playbackInBackground: Bool?
#endif

    func play(url: URL) {
        if Thread.isMainThread {
            start(url: url)
        } else {
            DispatchQueue.main.async { self.start(url: url) }
        }
    }

    private func start(url: URL) {
#if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        let inBackground = UIApplication.shared.applicationState != .active
        if playbackInBackground != inBackground {
            let category: AVAudioSession.Category = inBackground ? .playback : .ambient
            if (try? session.setCategory(category, options: [.mixWithOthers])) != nil {
                playbackInBackground = inBackground
            }
        }
        try? session.setActive(true)
#endif
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.volume = Self.volume
        player.prepareToPlay()
        lock.lock()
        players.append(player)
        lock.unlock()
        guard player.play() else {
            discard(player)
            return
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        discard(player)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        discard(player)
    }

    private func discard(_ player: AVAudioPlayer) {
        lock.lock()
        players.removeAll { $0 === player }
        lock.unlock()
    }
}

private final class NoticeCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NoticeCenter()

    private static let soundFileName = "ProcessDone.caf"
    private static let ownershipKey = "theoderoy.Deboogey.noticeSound"

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var didInstall = false
    private var didAskAuthorization = false
    private var didInstallSound = false

    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !didInstall else { return }
        didInstall = true
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        lock.lock()
        guard !didAskAuthorization else {
            lock.unlock()
            return
        }
        didAskAuthorization = true
        lock.unlock()
        center.getNotificationSettings { settings in
            let missingSound = settings.soundSetting == .notSupported
            let undecided = settings.authorizationStatus == .notDetermined
                || settings.authorizationStatus == .provisional
            guard missingSound || undecided else { return }
            self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    @discardableResult
    func post(
        title: String,
        body: String,
        identifierPrefix: String,
        includeSound: Bool
    ) async -> Bool {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let playSound = includeSound && settings.soundSetting != .disabled
        if playSound {
#if os(macOS)
            if settings.soundSetting == .notSupported {
                AppFeedback.play(.processDone)
            } else {
                content.sound = processDoneSound
            }
#else
            content.sound = processDoneSound
            content.userInfo = [Self.ownershipKey: Self.soundFileName]
#endif
        }
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            return false
        }
        return content.sound != nil
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
#if os(iOS)
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.userInfo[Self.ownershipKey] != nil {
            options.insert(.sound)
        }
#else
        let options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil {
            AppFeedback.play(.processDone)
        }
#endif
        completionHandler(options)
    }

    private var processDoneSound: UNNotificationSound {
        installSoundIfNeeded()
        return UNNotificationSound(named: UNNotificationSoundName(Self.soundFileName))
    }

    private func installSoundIfNeeded() {
#if os(iOS)
        lock.lock()
        if didInstallSound {
            lock.unlock()
            return
        }
        lock.unlock()
        guard let source = AppFeedback.resourceURL(named: "ProcessDone", ext: "caf", bundle: .main),
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let folder = library.appendingPathComponent("Sounds", isDirectory: true)
        let destination = folder.appendingPathComponent(Self.soundFileName)
        let files = FileManager.default
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if files.fileExists(atPath: destination.path) {
                let sourceSize = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let destinationSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if sourceSize == destinationSize {
                    markSoundInstalled()
                    return
                }
                try files.removeItem(at: destination)
            }
            try files.copyItem(at: source, to: destination)
            markSoundInstalled()
        } catch {
            return
        }
#endif
    }

    private func markSoundInstalled() {
        lock.lock()
        didInstallSound = true
        lock.unlock()
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }
}
