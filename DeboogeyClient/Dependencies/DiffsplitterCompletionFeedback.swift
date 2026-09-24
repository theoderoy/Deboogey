//
//  DiffsplitterCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DiffsplitterCompletionFeedback {
    static let soundPreferenceKey = "theoderoy.Deboogey.Diffsplitter.playCompletionSound"
    static let notifyWhenBackgroundedKey = "theoderoy.Deboogey.Diffsplitter.notifyWhenBackgrounded"
    static let minimumSecondsKey = "theoderoy.Deboogey.Diffsplitter.completionMinimumSeconds"
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
        if !shouldBypassMinimumDuration(defaults: defaults) {
            guard elapsed >= preferredMinimumSeconds(defaults: defaults) else { return }
        }
        _ = BundleAIFSound.play(named: "ProcessDone", bundle: bundle, volume: completionSoundVolume)
        BannerNotificationCenter.shared.notify(
            title: L10n.t("Diffsplitter Finished"),
            body: L10n.f("%@ finished comparing", label),
            identifierPrefix: "diffsplitter-complete"
        )
    }

    private static func shouldBypassMinimumDuration(defaults: UserDefaults) -> Bool {
#if os(iOS)
        guard defaults.bool(forKey: notifyWhenBackgroundedKey) else { return false }
        return UIApplication.shared.applicationState != .active
#else
        return false
#endif
    }
}
