//
//  PersistentVariables.swift
//  Deboogey
//
//  Created by Théo De Roy on 26/10/2025.
//

import Foundation
import AppKit
import Combine

public final class PersistentVariables: ObservableObject {
    private enum Keys {
        static let pesterMeWithSipping = "pesterMeWithSipping"
        static let showNetworkNotices = "showNetworkNotices"
        static let upgradeChannel = "upgradeChannel"
        static let hideUpgradeAlerts = "hideUpgradeAlerts"
        static let deleteBackupOnStartup = "deleteBackupOnStartup"
        static let hasShownWhatsNew = "hasShownWhatsNew"
        static let entityTrackerAutoDeleteEnabled = "deboogey.entityTracker.autoDeleteEnabled"
        static let entityTrackerAutoDeleteScope = "deboogey.entityTracker.autoDeleteScope"
        static let entityTrackerAutoDeleteTrigger = "deboogey.entityTracker.autoDeleteTrigger"
        static let showCLTNotices = "showCLTNotices"
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
        Keys.showCLTNotices: true
    ]

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

    @Published public var showCLTNotices: Bool {
        didSet { defaults.set(showCLTNotices, forKey: Keys.showCLTNotices) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaults.register(defaults: Self.registeredDefaults)
        self.pesterMeWithSipping = self.defaults.bool(forKey: Keys.pesterMeWithSipping)
        self.showNetworkNotices = self.defaults.bool(forKey: Keys.showNetworkNotices)
        self.upgradeChannel = self.defaults.string(forKey: Keys.upgradeChannel) ?? "Release"
        self.hideUpgradeAlerts = self.defaults.bool(forKey: Keys.hideUpgradeAlerts)
        self.deleteBackupOnStartup = self.defaults.bool(forKey: Keys.deleteBackupOnStartup)
        self.hasShownWhatsNew = self.defaults.bool(forKey: Keys.hasShownWhatsNew)
        self.entityTrackerAutoDeleteEnabled = self.defaults.bool(forKey: Keys.entityTrackerAutoDeleteEnabled)
        self.entityTrackerAutoDeleteScope = self.defaults.string(forKey: Keys.entityTrackerAutoDeleteScope) ?? "ephemerals"
        self.entityTrackerAutoDeleteTrigger = self.defaults.string(forKey: Keys.entityTrackerAutoDeleteTrigger) ?? "login"
        self.showCLTNotices = self.defaults.bool(forKey: Keys.showCLTNotices)
    }
    
    public func theThirdImpact() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleID)
        defaults.synchronize()

        NSApp.terminate(nil)
    }
}
