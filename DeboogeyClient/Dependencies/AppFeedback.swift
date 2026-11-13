//
//  AppFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 05/11/2026.
//

import AVFoundation
import Foundation
import UserNotifications
#if os(iOS)
import CryptoKit
#endif
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
        case batchCommence = "BatchCommence"
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

    private static let soundResourceName = "ProcessDone"
    private static let soundExtension = "caf"
    private static let ownershipKey = "theoderoy.Deboogey.noticeSound"

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var didInstall = false
    private var didAskAuthorization = false
    private var installedSoundFileName: String?

    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !didInstall else { return }
        didInstall = true
        center.delegate = self
#if os(macOS)
        removeStaleUserProcessDoneSoundsUnlocked()
#endif
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
            AppFeedback.play(.processDone)
            removeStaleUserProcessDoneSounds()
#else
            if let soundFileName = installSoundIfNeeded() {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFileName))
                content.userInfo = [Self.ownershipKey: soundFileName]
            } else {
                content.sound = .default
            }
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
#endif
        completionHandler(options)
    }

#if os(iOS)
    private func installSoundIfNeeded() -> String? {
        lock.lock()
        if let installedSoundFileName {
            lock.unlock()
            return installedSoundFileName
        }
        lock.unlock()
        guard let source = AppFeedback.resourceURL(
            named: Self.soundResourceName,
            ext: Self.soundExtension,
            bundle: .main
        ),
              let digest = fileDigest(at: source),
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return nil }
        let fileName = "\(Self.soundResourceName)-\(digest).\(Self.soundExtension)"
        let folder = library.appendingPathComponent("Sounds", isDirectory: true)
        let destination = folder.appendingPathComponent(fileName)
        let files = FileManager.default
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            if !files.fileExists(atPath: destination.path) {
                try files.copyItem(at: source, to: destination)
            }
            removeStaleProcessDoneSounds(in: folder, keeping: fileName)
            lock.lock()
            installedSoundFileName = fileName
            lock.unlock()
            return fileName
        } catch {
            return nil
        }
    }

    private func fileDigest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
#endif

#if os(macOS)
    private func removeStaleUserProcessDoneSounds() {
        lock.lock()
        defer { lock.unlock() }
        removeStaleUserProcessDoneSoundsUnlocked()
    }

    private func removeStaleUserProcessDoneSoundsUnlocked() {
        if installedSoundFileName != nil { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds", isDirectory: true)
        removeStaleProcessDoneSounds(in: folder, keeping: nil)
        installedSoundFileName = "cleared"
    }
#endif

    private func removeStaleProcessDoneSounds(in folder: URL, keeping currentFileName: String?) {
        let files = FileManager.default
        guard let contents = try? files.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
#if os(iOS)
        let allowedExtensions: Set<String> = [Self.soundExtension]
#else
        let allowedExtensions: Set<String> = ["caf", "aif", "aiff", "wav"]
#endif
        let prefix = "\(Self.soundResourceName)-"
        for url in contents {
            let name = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            let stem = String(name.dropLast(ext.count + 1))
            guard stem == Self.soundResourceName || stem.hasPrefix(prefix) else { continue }
            if let currentFileName, name == currentFileName { continue }
            try? files.removeItem(at: url)
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }
}
