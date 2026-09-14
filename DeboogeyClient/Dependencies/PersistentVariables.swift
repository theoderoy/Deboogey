//
//  PersistentVariables.swift
//  DeboogeyClient
//
//  Created by Théo De Roy on 26/10/2025.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
import Combine

public final class PersistentVariables: ObservableObject {
    private enum Keys {
        static let pesterMeWithSipping = "pesterMeWithSipping"
        static let showNetworkNotices = "showNetworkNotices"
        static let upgradeChannel = "upgradeChannel"
        static let hideUpgradeAlerts = "hideUpgradeAlerts"
        static let deleteBackupOnStartup = "deleteBackupOnStartup"
        static let hasShownWhatsNew = "hasShownWhatsNew"
        static let entityTrackerAutoDeleteEnabled = "theoderoy.Deboogey.EntityTracker.autoDeleteEnabled"
        static let entityTrackerAutoDeleteScope = "theoderoy.Deboogey.EntityTracker.autoDeleteScope"
        static let entityTrackerAutoDeleteTrigger = "theoderoy.Deboogey.EntityTracker.autoDeleteTrigger"
        static let entityTrackerAutoDeleteLoupeActivities = "theoderoy.Deboogey.EntityTracker.autoDeleteLoupeActivities"
        static let playIndexingDoneSound = "theoderoy.Deboogey.Indexing.playCompletionSound"
        static let playToolCycleSound = "theoderoy.Deboogey.Tools.playCycleSound"
        static let playDiffsplitterDoneSound = "theoderoy.Deboogey.Diffsplitter.playCompletionSound"
        static let diffsplitterNotifyMinimumSeconds = "theoderoy.Deboogey.Diffsplitter.completionMinimumSeconds"
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
        Keys.hasShownWhatsNew: false,
        Keys.entityTrackerAutoDeleteEnabled: true,
        Keys.entityTrackerAutoDeleteScope: "ephemerals",
        Keys.entityTrackerAutoDeleteTrigger: "login",
        Keys.entityTrackerAutoDeleteLoupeActivities: true,
        Keys.playIndexingDoneSound: true,
        Keys.playToolCycleSound: true,
        Keys.playDiffsplitterDoneSound: true,
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
        Keys.showLoupeApplyVerification: true
    ]

    static func registerDefaults(in defaults: UserDefaults = .standard) {
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
    
    @Published public var hasShownWhatsNew: Bool {
        didSet { defaults.set(hasShownWhatsNew, forKey: Keys.hasShownWhatsNew) }
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

    @Published public var playToolCycleSound: Bool {
        didSet { defaults.set(playToolCycleSound, forKey: Keys.playToolCycleSound) }
    }

    @Published public var playDiffsplitterDoneSound: Bool {
        didSet { defaults.set(playDiffsplitterDoneSound, forKey: Keys.playDiffsplitterDoneSound) }
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.registerDefaults(in: self.defaults)
        self.pesterMeWithSipping = self.defaults.bool(forKey: Keys.pesterMeWithSipping)
        self.showNetworkNotices = self.defaults.bool(forKey: Keys.showNetworkNotices)
        self.upgradeChannel = self.defaults.string(forKey: Keys.upgradeChannel) ?? "Release"
        self.hideUpgradeAlerts = self.defaults.bool(forKey: Keys.hideUpgradeAlerts)
        self.deleteBackupOnStartup = self.defaults.bool(forKey: Keys.deleteBackupOnStartup)
        self.hasShownWhatsNew = self.defaults.bool(forKey: Keys.hasShownWhatsNew)
        self.entityTrackerAutoDeleteEnabled = self.defaults.bool(forKey: Keys.entityTrackerAutoDeleteEnabled)
        self.entityTrackerAutoDeleteScope = self.defaults.string(forKey: Keys.entityTrackerAutoDeleteScope) ?? "ephemerals"
        self.entityTrackerAutoDeleteTrigger = self.defaults.string(forKey: Keys.entityTrackerAutoDeleteTrigger) ?? "login"
        self.entityTrackerAutoDeleteLoupeActivities = self.defaults.bool(forKey: Keys.entityTrackerAutoDeleteLoupeActivities)
        self.playIndexingDoneSound = self.defaults.bool(forKey: Keys.playIndexingDoneSound)
        self.playToolCycleSound = self.defaults.bool(forKey: Keys.playToolCycleSound)
        self.playDiffsplitterDoneSound = self.defaults.bool(forKey: Keys.playDiffsplitterDoneSound)
        self.diffsplitterNotifyMinimumSeconds = DiffsplitterCompletionFeedback.preferredMinimumSeconds(
            defaults: self.defaults
        )
        self.diffsplitterStatusPriority = Self.loadDiffsplitterStatusPriority(from: self.defaults)
        self.diffsplitterIncludeHiddenFiles = DiffsplitterSettings.includeHiddenFiles(defaults: self.defaults)
        self.diffsplitterPreferDiskTempForLargeFiles = DiffsplitterSettings.preferDiskTempForLargeFiles(
            defaults: self.defaults
        )
        self.diffsplitterHexWindowLines = Double(DiffsplitterSettings.hexWindowLines(defaults: self.defaults))
        self.diffsplitterLargeFileHexConversionEnabled = DiffsplitterSettings.largeFileHexConversionEnabled(
            defaults: self.defaults
        )
        self.diffsplitterMaxTextMegabytes = Double(DiffsplitterSettings.maxTextMegabytes(defaults: self.defaults))
        self.diffsplitterMaxNestDepth = Double(DiffsplitterSettings.maxNestDepth(defaults: self.defaults))
        self.diffsplitterMaxEntries = Double(DiffsplitterSettings.maxEntries(defaults: self.defaults))
        self.showCLTNotices = self.defaults.bool(forKey: Keys.showCLTNotices)
        self.showLoupeApplyVerification = self.defaults.bool(forKey: Keys.showLoupeApplyVerification)
    }

    public func resetDiffsplitterStatusPriority() {
        diffsplitterStatusPriority = Self.defaultDiffsplitterStatusPriority
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

#if canImport(AppKit)
        NSApp.terminate(nil)
#endif
    }
}
