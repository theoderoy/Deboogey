//
//  DiffsplitterCompletionFeedback.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 13/09/2026.
//

import Foundation

enum DiffsplitterCompletionFeedback {
    static let soundPreferenceKey = "theoderoy.Deboogey.Diffsplitter.playCompletionSound"
    static let minimumSecondsKey = "theoderoy.Deboogey.Diffsplitter.completionMinimumSeconds"
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

    static var usesLiveActivityUX: Bool {
#if os(iOS)
        !ProcessInfo.processInfo.isiOSAppOnVision
#elseif DEBOOGEY_MAC_LIVE_ACTIVITIES
        if #available(macOS 27.3, *) { return true }
        return false
#else
        false
#endif
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: soundPreferenceKey)
    }

    static var suppressesBatchExportSaveSound: Bool {
        usesLiveActivityUX && isEnabled
    }

    static var completionNotifySectionHeader: String {
        usesLiveActivityUX ? "Live Activity" : "In-App Tones"
    }

    static var completionNotifySymbolName: String {
        usesLiveActivityUX ? "platter.filled.top.and.arrow.up.iphone" : "speaker.wave.2"
    }

    static var completionNotifyTitle: String {
        usesLiveActivityUX
            ? L10n.t("Show a Live Activity while Diffsplitter compares")
            : L10n.t("Play a sound when Diffsplitter finishes a comparison")
    }

    static var completionNotifyCaption: String {
        usesLiveActivityUX
            ? L10n.t("Keeps comparison progress visible in the background. Manage Live Activities and sounds in Settings.")
            : L10n.t("Notify with a sound and banner when a Diffsplitter comparison takes at least the selected duration.")
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
        includeBanner: Bool = true,
        defaults: UserDefaults = .standard
    ) async {
        let enabled = defaults.bool(forKey: soundPreferenceKey)
        if usesLiveActivityUX {
            guard enabled else {
                await AppFeedback.playIfActive(.processDone)
                return
            }
        } else {
            guard enabled else { return }
            guard elapsed >= preferredMinimumSeconds(defaults: defaults) else { return }
        }
        await AppFeedback.deliverCompletion(
            title: L10n.t("Diffsplitter Finished"),
            body: L10n.f("%@ finished comparing", label),
            sound: .processDone,
            identifierPrefix: "diffsplitter-complete",
            wantsBanner: includeBanner
        )
    }
}
