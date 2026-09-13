//
//  DiffsplitterCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

enum DiffsplitterCompletionFeedback {
    private static let soundPreferenceKey = "theoderoy.Deboogey.Diffsplitter.playCompletionSound"
    private static let minimumSecondsKey = "theoderoy.Deboogey.Diffsplitter.completionMinimumSeconds"
    private static let completionSoundVolume: Float = 0.3
    static let selectableMinimumSeconds: [Double] = [0] + (5...30).map(Double.init)
    static let minimumSecondsRange: ClosedRange<Double> = 0...30
    static let sliderIndexRange: ClosedRange<Double> = 0...Double(selectableMinimumSeconds.count - 1)
    static let defaultMinimumSeconds: Double = 10

    static func clampedMinimumSeconds(_ value: Double) -> Double {
        let rounded = value.rounded()
        if rounded <= 0 { return 0 }
        return min(max(rounded, 5), minimumSecondsRange.upperBound)
    }

    static func sliderIndex(forSeconds seconds: Double) -> Double {
        let clamped = clampedMinimumSeconds(seconds)
        if let index = selectableMinimumSeconds.firstIndex(of: clamped) {
            return Double(index)
        }
        return 0
    }

    static func seconds(forSliderIndex index: Double) -> Double {
        let clampedIndex = Int(min(max(index.rounded(), sliderIndexRange.lowerBound), sliderIndexRange.upperBound))
        return selectableMinimumSeconds[clampedIndex]
    }

    static func preferredMinimumSeconds(defaults: UserDefaults = .standard) -> Double {
        clampedMinimumSeconds(defaults.double(forKey: minimumSecondsKey))
    }

    static func durationLabel(for seconds: Double) -> String {
        let value = Int(clampedMinimumSeconds(seconds).rounded())
        if value <= 0 {
            return L10n.t("Immediately")
        }
        return L10n.f("%d seconds", value)
    }

    static func notifyIfNeeded(
        elapsed: TimeInterval,
        label: String,
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        guard defaults.bool(forKey: soundPreferenceKey) else { return }
        let minimumSeconds = preferredMinimumSeconds(defaults: defaults)
        guard elapsed >= minimumSeconds else { return }
        playSound(bundle: bundle)
        DiffsplitterCompletionNotificationCenter.shared.notify(label: label)
    }

    private static func playSound(bundle: Bundle) {
#if canImport(AppKit)
        let soundURL = bundle.url(forResource: "ProcessDone", withExtension: "aif")
            ?? bundle.url(
                forResource: "ProcessDone",
                withExtension: "aif",
                subdirectory: "Resources"
            )
        guard let soundURL, let sound = NSSound(contentsOf: soundURL, byReference: true) else {
            return
        }
        sound.volume = completionSoundVolume
        sound.play()
#endif
    }
}

private final class DiffsplitterCompletionNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DiffsplitterCompletionNotificationCenter()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func notify(label: String) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                self.deliver(label: label)
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { return }
                    self.deliver(label: label)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func deliver(label: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Diffsplitter Finished")
        content.body = L10n.f("%@ finished comparing", label)
        let request = UNNotificationRequest(
            identifier: "diffsplitter-complete-\(UUID().uuidString)",
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
