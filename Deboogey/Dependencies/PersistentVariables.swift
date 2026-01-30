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
        static let upgradeChannel = "upgradeChannel"
        static let hideUpgradeAlerts = "hideUpgradeAlerts"
        static let deleteBackupOnStartup = "deleteBackupOnStartup"
    }

    private let defaults: UserDefaults

    private static let registeredDefaults: [String: Any] = [
        Keys.pesterMeWithSipping: true,
        Keys.upgradeChannel: "Release",
        Keys.hideUpgradeAlerts: false,
        Keys.deleteBackupOnStartup: false
    ]

    @Published public var pesterMeWithSipping: Bool {
        didSet { defaults.set(pesterMeWithSipping, forKey: Keys.pesterMeWithSipping) }
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.defaults.register(defaults: Self.registeredDefaults)
        self.pesterMeWithSipping = self.defaults.bool(forKey: Keys.pesterMeWithSipping)
        self.upgradeChannel = self.defaults.string(forKey: Keys.upgradeChannel) ?? "Release"
        self.hideUpgradeAlerts = self.defaults.bool(forKey: Keys.hideUpgradeAlerts)
        self.deleteBackupOnStartup = self.defaults.bool(forKey: Keys.deleteBackupOnStartup)
    }
    
    public func theThirdImpact() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: bundleID)
        defaults.synchronize()

        NSApp.terminate(nil)
    }
}
