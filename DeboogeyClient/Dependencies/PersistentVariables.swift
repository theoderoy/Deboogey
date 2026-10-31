//
//  PersistentVariables.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/10/2025.
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Combine

public final class PersistentVariables: ObservableObject {
    private enum Keys {
        static let pesterMeWithSipping = "pesterMeWithSipping"
        static let showNetworkNotices = "showNetworkNotices"
        static let upgradeChannel = "upgradeChannel"
        static let hideUpgradeAlerts = "hideUpgradeAlerts"
        static let deleteBackupOnStartup = "deleteBackupOnStartup"
        static let lastAcknowledgedWhatsNewIdentity = "lastAcknowledgedWhatsNewIdentity"
        static let legacyHasShownWhatsNew = "hasShownWhatsNew"
        static let entityTrackerAutoDeleteEnabled = "theoderoy.Deboogey.EntityTracker.autoDeleteEnabled"
        static let entityTrackerAutoDeleteScope = "theoderoy.Deboogey.EntityTracker.autoDeleteScope"
        static let entityTrackerAutoDeleteTrigger = "theoderoy.Deboogey.EntityTracker.autoDeleteTrigger"
        static let entityTrackerAutoDeleteLoupeActivities = "theoderoy.Deboogey.EntityTracker.autoDeleteLoupeActivities"
        static let playIndexingDoneSound = "theoderoy.Deboogey.Indexing.playCompletionSound"
        static let playDocumentSaveSound = DocumentSaveFeedback.preferenceKey
        static let playToolCycleSound = "theoderoy.Deboogey.Tools.playCycleSound"
        static let playDiffsplitterDoneSound = DiffsplitterCompletionFeedback.soundPreferenceKey
        static let diffsplitterNotifyWhenBackgrounded = DiffsplitterCompletionFeedback.notifyWhenBackgroundedKey
        static let diffsplitterNotifyMinimumSeconds = DiffsplitterCompletionFeedback.minimumSecondsKey
        static let diffsplitterStatusPriority = "theoderoy.Deboogey.Diffsplitter.statusPriority"
        static let diffsplitterIncludeHiddenFiles = DiffsplitterSettings.Keys.includeHiddenFiles
        static let diffsplitterPreferDiskTempForLargeFiles = DiffsplitterSettings.Keys.preferDiskTempForLargeFiles
        static let diffsplitterHexWindowLines = DiffsplitterSettings.Keys.hexWindowLines
        static let diffsplitterLargeFileHexConversionEnabled = DiffsplitterSettings.Keys.largeFileHexConversionEnabled
        static let diffsplitterMaxTextMegabytes = DiffsplitterSettings.Keys.maxTextMegabytes
        static let diffsplitterMaxNestDepth = DiffsplitterSettings.Keys.maxNestDepth
        static let diffsplitterMaxEntries = DiffsplitterSettings.Keys.maxEntries
        static let showCLTNotices = "showCLTNotices"
        static let showLoupeApplyVerification = "showLoupeApplyVerification"
        static let animateEmptyDocumentBackgrounds = "theoderoy.Deboogey.animateEmptyDocumentBackgrounds"
    }

    public static func settingsDisplayTitle() -> String {
#if os(macOS)
        guard #available(macOS 13.0, *) else { return L10n.t("Preferences") }
#endif
        return L10n.t("Settings")
    }

    public static let defaultDiffsplitterStatusPriority: [String] = [
        "added", "modified", "removed", "binary"
    ]

    static let diffsplitterStatusPriorityDidChange = Notification.Name(
        "theoderoy.Deboogey.Diffsplitter.statusPriorityDidChange"
    )

    public static func normalizedDiffsplitterStatusPriority(_ stored: [String]?) -> [String] {
        let allowed = Set(defaultDiffsplitterStatusPriority)
        var seen = Set<String>()
        var result: [String] = []
        for raw in stored ?? [] {
            guard allowed.contains(raw), !seen.contains(raw) else { continue }
            seen.insert(raw)
            result.append(raw)
        }
        for raw in defaultDiffsplitterStatusPriority where !seen.contains(raw) {
            result.append(raw)
        }
        return result
    }

    public static func loadDiffsplitterStatusPriority(
        from defaults: UserDefaults = .standard
    ) -> [String] {
        let stored = defaults.array(forKey: Keys.diffsplitterStatusPriority) as? [String]
        return normalizedDiffsplitterStatusPriority(stored)
    }

    private let defaults: UserDefaults

    private static let registeredDefaults: [String: Any] = [
        Keys.pesterMeWithSipping: true,
        Keys.showNetworkNotices: true,
        Keys.upgradeChannel: "Release",
        Keys.hideUpgradeAlerts: false,
        Keys.deleteBackupOnStartup: true,
        Keys.lastAcknowledgedWhatsNewIdentity: "",
        Keys.entityTrackerAutoDeleteEnabled: true,
        Keys.entityTrackerAutoDeleteScope: "ephemerals",
        Keys.entityTrackerAutoDeleteTrigger: "login",
        Keys.entityTrackerAutoDeleteLoupeActivities: true,
        Keys.playIndexingDoneSound: true,
        Keys.playDocumentSaveSound: true,
        Keys.playToolCycleSound: true,
        Keys.playDiffsplitterDoneSound: true,
        Keys.diffsplitterNotifyWhenBackgrounded: true,
        Keys.diffsplitterNotifyMinimumSeconds: DiffsplitterCompletionFeedback.defaultMinimumSeconds,
        Keys.diffsplitterStatusPriority: defaultDiffsplitterStatusPriority,
        Keys.diffsplitterIncludeHiddenFiles: DiffsplitterSettings.defaultIncludeHiddenFiles,
        Keys.diffsplitterPreferDiskTempForLargeFiles: DiffsplitterSettings.defaultPreferDiskTempForLargeFiles,
        Keys.diffsplitterHexWindowLines: DiffsplitterSettings.defaultHexWindowLines,
        Keys.diffsplitterLargeFileHexConversionEnabled: DiffsplitterSettings.defaultLargeFileHexConversionEnabled,
        Keys.diffsplitterMaxTextMegabytes: DiffsplitterSettings.defaultMaxTextMegabytes,
        Keys.diffsplitterMaxNestDepth: DiffsplitterSettings.defaultMaxNestDepth,
        Keys.diffsplitterMaxEntries: DiffsplitterSettings.defaultMaxEntries,
        Keys.showCLTNotices: true,
        Keys.showLoupeApplyVerification: true,
        Keys.animateEmptyDocumentBackgrounds: true
    ]

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        DocumentSaveFeedback.migrateIfNeeded(defaults: defaults)
        defaults.register(defaults: registeredDefaults)
    }

    @Published public var pesterMeWithSipping: Bool {
        didSet { defaults.set(pesterMeWithSipping, forKey: Keys.pesterMeWithSipping) }
    }
    
    @Published public var showNetworkNotices: Bool {
        didSet { defaults.set(showNetworkNotices, forKey: Keys.showNetworkNotices) }
    }
    
    @Published public var upgradeChannel: String {
        didSet { defaults.set(upgradeChannel, forKey: Keys.upgradeChannel) }
    }
    
    @Published public var hideUpgradeAlerts: Bool {
        didSet { defaults.set(hideUpgradeAlerts, forKey: Keys.hideUpgradeAlerts) }
    }
    
    @Published public var deleteBackupOnStartup: Bool {
        didSet { defaults.set(deleteBackupOnStartup, forKey: Keys.deleteBackupOnStartup) }
    }
    
    @Published public var lastAcknowledgedWhatsNewIdentity: String {
        didSet { defaults.set(lastAcknowledgedWhatsNewIdentity, forKey: Keys.lastAcknowledgedWhatsNewIdentity) }
    }

    public static func currentWhatsNewIdentity(
        shortVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    ) -> String {
        "\(shortVersion)|\(buildNumber)"
    }

    public var shouldPresentWhatsNew: Bool {
        DebugVariables.alwaysShowWhatsNewView
            || lastAcknowledgedWhatsNewIdentity != Self.currentWhatsNewIdentity()
    }

    public func acknowledgeWhatsNew() {
        lastAcknowledgedWhatsNewIdentity = Self.currentWhatsNewIdentity()
    }

    @Published public var entityTrackerAutoDeleteEnabled: Bool {
        didSet { defaults.set(entityTrackerAutoDeleteEnabled, forKey: Keys.entityTrackerAutoDeleteEnabled) }
    }

    @Published public var entityTrackerAutoDeleteScope: String {
        didSet { defaults.set(entityTrackerAutoDeleteScope, forKey: Keys.entityTrackerAutoDeleteScope) }
    }

    @Published public var entityTrackerAutoDeleteTrigger: String {
        didSet { defaults.set(entityTrackerAutoDeleteTrigger, forKey: Keys.entityTrackerAutoDeleteTrigger) }
    }

    @Published public var entityTrackerAutoDeleteLoupeActivities: Bool {
        didSet { defaults.set(entityTrackerAutoDeleteLoupeActivities, forKey: Keys.entityTrackerAutoDeleteLoupeActivities) }
    }

    @Published public var playIndexingDoneSound: Bool {
        didSet { defaults.set(playIndexingDoneSound, forKey: Keys.playIndexingDoneSound) }
    }

    @Published public var playDocumentSaveSound: Bool {
        didSet { defaults.set(playDocumentSaveSound, forKey: Keys.playDocumentSaveSound) }
    }

    @Published public var playToolCycleSound: Bool {
        didSet { defaults.set(playToolCycleSound, forKey: Keys.playToolCycleSound) }
    }

    @Published public var playDiffsplitterDoneSound: Bool {
        didSet { defaults.set(playDiffsplitterDoneSound, forKey: Keys.playDiffsplitterDoneSound) }
    }

    @Published public var diffsplitterNotifyWhenBackgrounded: Bool {
        didSet { defaults.set(diffsplitterNotifyWhenBackgrounded, forKey: Keys.diffsplitterNotifyWhenBackgrounded) }
    }

    @Published public var diffsplitterNotifyMinimumSeconds: Double {
        didSet {
            let clamped = DiffsplitterCompletionFeedback.clampedMinimumSeconds(
                diffsplitterNotifyMinimumSeconds
            )
            if clamped != diffsplitterNotifyMinimumSeconds {
                diffsplitterNotifyMinimumSeconds = clamped
                return
            }
            defaults.set(diffsplitterNotifyMinimumSeconds, forKey: Keys.diffsplitterNotifyMinimumSeconds)
        }
    }

    @Published public var diffsplitterStatusPriority: [String] {
        didSet {
            let normalized = Self.normalizedDiffsplitterStatusPriority(diffsplitterStatusPriority)
            if normalized != diffsplitterStatusPriority {
                diffsplitterStatusPriority = normalized
                return
            }
            defaults.set(diffsplitterStatusPriority, forKey: Keys.diffsplitterStatusPriority)
            NotificationCenter.default.post(name: Self.diffsplitterStatusPriorityDidChange, object: nil)
        }
    }

    @Published public var diffsplitterIncludeHiddenFiles: Bool {
        didSet { defaults.set(diffsplitterIncludeHiddenFiles, forKey: Keys.diffsplitterIncludeHiddenFiles) }
    }

    @Published public var diffsplitterPreferDiskTempForLargeFiles: Bool {
        didSet {
            defaults.set(
                diffsplitterPreferDiskTempForLargeFiles,
                forKey: Keys.diffsplitterPreferDiskTempForLargeFiles
            )
        }
    }

    @Published public var diffsplitterHexWindowLines: Double {
        didSet {
            let clamped = Self.clampedContinuous(
                diffsplitterHexWindowLines,
                range: DiffsplitterSettings.hexWindowLinesRange
            )
            if clamped != diffsplitterHexWindowLines {
                diffsplitterHexWindowLines = clamped
                return
            }
            defaults.set(Int(clamped.rounded()), forKey: Keys.diffsplitterHexWindowLines)
        }
    }

    @Published public var diffsplitterLargeFileHexConversionEnabled: Bool {
        didSet {
            defaults.set(
                diffsplitterLargeFileHexConversionEnabled,
                forKey: Keys.diffsplitterLargeFileHexConversionEnabled
            )
        }
    }

    @Published public var diffsplitterMaxTextMegabytes: Double {
        didSet {
            let clamped = Self.clampedContinuous(
                diffsplitterMaxTextMegabytes,
                range: DiffsplitterSettings.maxTextMegabytesRange
            )
            if clamped != diffsplitterMaxTextMegabytes {
                diffsplitterMaxTextMegabytes = clamped
                return
            }
            defaults.set(Int(clamped.rounded()), forKey: Keys.diffsplitterMaxTextMegabytes)
        }
    }

    @Published public var diffsplitterMaxNestDepth: Double {
        didSet {
            let clamped = Self.clamped(
                diffsplitterMaxNestDepth,
                range: DiffsplitterSettings.maxNestDepthRange
            )
            if clamped != diffsplitterMaxNestDepth {
                diffsplitterMaxNestDepth = clamped
                return
            }
            defaults.set(Int(clamped), forKey: Keys.diffsplitterMaxNestDepth)
        }
    }

    @Published public var diffsplitterMaxEntries: Double {
        didSet {
            let stop = DiffsplitterSettings.nearestMaxEntriesStop(Int(diffsplitterMaxEntries.rounded()))
            let snapped = Double(stop)
            if snapped != diffsplitterMaxEntries {
                diffsplitterMaxEntries = snapped
                return
            }
            defaults.set(stop, forKey: Keys.diffsplitterMaxEntries)
        }
    }

    @Published public var showCLTNotices: Bool {
        didSet { defaults.set(showCLTNotices, forKey: Keys.showCLTNotices) }
    }

    @Published public var showLoupeApplyVerification: Bool {
        didSet { defaults.set(showLoupeApplyVerification, forKey: Keys.showLoupeApplyVerification) }
    }

    @Published public var animateEmptyDocumentBackgrounds: Bool {
        didSet { defaults.set(animateEmptyDocumentBackgrounds, forKey: Keys.animateEmptyDocumentBackgrounds) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.registerDefaults(in: self.defaults)
        self.pesterMeWithSipping = false
        self.showNetworkNotices = false
        self.upgradeChannel = "Release"
        self.hideUpgradeAlerts = false
        self.deleteBackupOnStartup = false
        self.lastAcknowledgedWhatsNewIdentity = ""
        self.entityTrackerAutoDeleteEnabled = false
        self.entityTrackerAutoDeleteScope = "ephemerals"
        self.entityTrackerAutoDeleteTrigger = "login"
        self.entityTrackerAutoDeleteLoupeActivities = false
        self.playIndexingDoneSound = false
        self.playDocumentSaveSound = false
        self.playToolCycleSound = false
        self.playDiffsplitterDoneSound = false
        self.diffsplitterNotifyWhenBackgrounded = false
        self.diffsplitterNotifyMinimumSeconds = 0
        self.diffsplitterStatusPriority = []
        self.diffsplitterIncludeHiddenFiles = false
        self.diffsplitterPreferDiskTempForLargeFiles = false
        self.diffsplitterHexWindowLines = 0
        self.diffsplitterLargeFileHexConversionEnabled = false
        self.diffsplitterMaxTextMegabytes = 0
        self.diffsplitterMaxNestDepth = 0
        self.diffsplitterMaxEntries = 0
        self.showCLTNotices = false
        self.showLoupeApplyVerification = false
        self.animateEmptyDocumentBackgrounds = false
        applyFromDefaults()
    }

    public func resetDiffsplitterStatusPriority() {
        diffsplitterStatusPriority = Self.defaultDiffsplitterStatusPriority
    }

    public func resetPreferenceValues() {
        for key in Self.registeredDefaults.keys where key != Keys.lastAcknowledgedWhatsNewIdentity {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: DocumentSaveFeedback.legacyPreferenceKey)
        defaults.synchronize()
        reloadFromDefaults()
        Self.gracefullyTerminateAfterSettingsReset()
    }

    private func reloadFromDefaults() {
        applyFromDefaults()
    }

    private static func loadAcknowledgedWhatsNewIdentity(from defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: Keys.lastAcknowledgedWhatsNewIdentity) ?? ""
        if defaults.object(forKey: Keys.legacyHasShownWhatsNew) != nil {
            defaults.removeObject(forKey: Keys.legacyHasShownWhatsNew)
        }
        return stored
    }

    private func applyFromDefaults() {
        pesterMeWithSipping = defaults.bool(forKey: Keys.pesterMeWithSipping)
        showNetworkNotices = defaults.bool(forKey: Keys.showNetworkNotices)
        upgradeChannel = defaults.string(forKey: Keys.upgradeChannel) ?? "Release"
        hideUpgradeAlerts = defaults.bool(forKey: Keys.hideUpgradeAlerts)
        deleteBackupOnStartup = defaults.bool(forKey: Keys.deleteBackupOnStartup)
        lastAcknowledgedWhatsNewIdentity = Self.loadAcknowledgedWhatsNewIdentity(from: defaults)
        entityTrackerAutoDeleteEnabled = defaults.bool(forKey: Keys.entityTrackerAutoDeleteEnabled)
        entityTrackerAutoDeleteScope = defaults.string(forKey: Keys.entityTrackerAutoDeleteScope) ?? "ephemerals"
        entityTrackerAutoDeleteTrigger = defaults.string(forKey: Keys.entityTrackerAutoDeleteTrigger) ?? "login"
        entityTrackerAutoDeleteLoupeActivities = defaults.bool(forKey: Keys.entityTrackerAutoDeleteLoupeActivities)
        playIndexingDoneSound = defaults.bool(forKey: Keys.playIndexingDoneSound)
        playDocumentSaveSound = defaults.bool(forKey: Keys.playDocumentSaveSound)
        playToolCycleSound = defaults.bool(forKey: Keys.playToolCycleSound)
        playDiffsplitterDoneSound = defaults.bool(forKey: Keys.playDiffsplitterDoneSound)
        diffsplitterNotifyWhenBackgrounded = defaults.bool(forKey: Keys.diffsplitterNotifyWhenBackgrounded)
        diffsplitterNotifyMinimumSeconds = DiffsplitterCompletionFeedback.preferredMinimumSeconds(
            defaults: defaults
        )
        diffsplitterStatusPriority = Self.loadDiffsplitterStatusPriority(from: defaults)
        diffsplitterIncludeHiddenFiles = DiffsplitterSettings.includeHiddenFiles(defaults: defaults)
        diffsplitterPreferDiskTempForLargeFiles = DiffsplitterSettings.preferDiskTempForLargeFiles(
            defaults: defaults
        )
        diffsplitterHexWindowLines = Double(DiffsplitterSettings.hexWindowLines(defaults: defaults))
        diffsplitterLargeFileHexConversionEnabled = DiffsplitterSettings.largeFileHexConversionEnabled(
            defaults: defaults
        )
        diffsplitterMaxTextMegabytes = Double(DiffsplitterSettings.maxTextMegabytes(defaults: defaults))
        diffsplitterMaxNestDepth = Double(DiffsplitterSettings.maxNestDepth(defaults: defaults))
        diffsplitterMaxEntries = Double(DiffsplitterSettings.maxEntries(defaults: defaults))
        showCLTNotices = defaults.bool(forKey: Keys.showCLTNotices)
        showLoupeApplyVerification = defaults.bool(forKey: Keys.showLoupeApplyVerification)
        animateEmptyDocumentBackgrounds = defaults.bool(forKey: Keys.animateEmptyDocumentBackgrounds)
    }

    private static func clamped(_ value: Double, range: ClosedRange<Int>) -> Double {
        min(max(value.rounded(), Double(range.lowerBound)), Double(range.upperBound))
    }

    private static func clampedContinuous(_ value: Double, range: ClosedRange<Int>) -> Double {
        min(max(value, Double(range.lowerBound)), Double(range.upperBound))
    }

    public func theThirdImpact() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleID)
        defaults.synchronize()
        Self.gracefullyTerminateAfterSettingsReset()
    }

    private static func gracefullyTerminateAfterSettingsReset() {
#if canImport(AppKit)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                exit(EXIT_SUCCESS)
            }
        }
#elseif canImport(UIKit)
        DispatchQueue.main.async {
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(EXIT_SUCCESS)
            }
        }
#endif
    }
}
